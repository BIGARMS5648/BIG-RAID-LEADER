-- BIG RAID LEADER - 경매금 수금 / 분배금 지급 연결
-- AuctionPaymentAllocation : 완료된 거래(받은 골드) → 낙찰 (부분/합산/일괄/대리 입금, 환불)
-- PayoutAllocation         : 완료된 거래(지급 골드) → 분배 의무 (개인/파티 대표 지급)
-- 규칙
--  * 자동 매칭은 "제안"만 한다. 연결 확정은 공대장의 승인으로만 이루어진다.
--  * 같은 거래의 동일 금액을 두 번 연결할 수 없다 (거래별 연결 합계 ≤ 거래 금액).
--  * 같은 거래-낙찰(또는 거래-분배) 쌍은 한 번만 연결된다 (중복 연결 방지).
--  * 확정되지 않은 거래(확인 불가/취소/기록 취소)는 연결할 수 없다.
local _, BRL = ...
local U, DB, Money, L = BRL.Util, BRL.DB, BRL.Money, BRL.L

local P = BRL:NewModule("Payments")

local function changed()
    BRL.Events:Fire(BRL.Events.MSG.LEDGER_CHANGED)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "payments")
end

local function J() return BRL.TradeJournal end

local function checkSession(sessionId)
    local session = sessionId and BRL.Session:Get(sessionId)
    if session then
        local ok, why = BRL.Perm:CanEditSession(session)
        if not ok and session.locked and why and why:find("잠긴") then
            -- 정산 잠금은 금액 확정만 막는다. 수금/지급 기록은 계속 가능
            if BRL.Perm:Can("finance.edit") and session.owner == BRL.playerKey then return true end
        end
        return ok, why
    end
    if not BRL.Perm:Can("finance.edit") then return false, L.LEADER_ONLY end
    return true
end

---------------------------------------------------------------------------
-- 조회
---------------------------------------------------------------------------
function P:AuctionAllocations(filter)
    return DB:List("auctionAllocations", filter, "at")
end

function P:AllocationsForAward(awardId, includeVoided)
    return self:AuctionAllocations(function(a) return a.awardId == awardId and (includeVoided or not a.voided) end)
end

function P:PayoutAllocations(filter)
    return DB:List("payoutAllocations", filter, "at")
end

function P:AllocationsForObligation(obId, includeVoided)
    return self:PayoutAllocations(function(a) return a.obligationId == obId and (includeVoided or not a.voided) end)
end

-- 거래에 연결된 금액 (경매 수금 inUse, 분배 지급 outUse, 환불 refundUse)
function P:AllocatedOnTrade(tradeId)
    local inUse, outUse, refundUse = 0, 0, 0
    for _, a in pairs(DB:T("auctionAllocations")) do
        if a.tradeId == tradeId and not a.voided then
            if a.kind == "refund" then refundUse = refundUse + a.amount else inUse = inUse + a.amount end
        end
    end
    for _, a in pairs(DB:T("payoutAllocations")) do
        if a.tradeId == tradeId and not a.voided then outUse = outUse + a.amount end
    end
    return inUse, outUse + refundUse, refundUse
end

function P:HasActiveLinks(tradeId)
    local i, o = self:AllocatedOnTrade(tradeId)
    return (i + o) > 0
end

function P:LinksForTrade(tradeId)
    local res = { awards = {}, payouts = {} }
    for _, a in pairs(DB:T("auctionAllocations")) do
        if a.tradeId == tradeId and not a.voided then res.awards[#res.awards + 1] = a end
    end
    for _, a in pairs(DB:T("payoutAllocations")) do
        if a.tradeId == tradeId and not a.voided then res.payouts[#res.payouts + 1] = a end
    end
    return res
end

-- 거래에서 아직 연결되지 않은 받은 금액(순수령)
function P:TradeAvailableIn(tr)
    local eff = J():Effective(tr)
    local inUse = self:AllocatedOnTrade(tr.id)
    return math.max(0, eff.net - inUse)
end

-- 거래에서 아직 연결되지 않은 지급 금액(순지급)
function P:TradeAvailableOut(tr)
    local eff = J():Effective(tr)
    local _, outUse = self:AllocatedOnTrade(tr.id)
    return math.max(0, -eff.net - outUse)
end

-- 낙찰 수금 상태
function P:AwardStatus(aw)
    local paid, refunded = 0, 0
    for _, a in pairs(DB:T("auctionAllocations")) do
        if a.awardId == aw.id and not a.voided then
            if a.kind == "refund" then refunded = refunded + a.amount else paid = paid + a.amount end
        end
    end
    local collected = paid - refunded
    local res = { amount = aw.amount, paid = paid, refunded = refunded, collected = collected, outstanding = 0, overpaid = 0 }
    if aw.status == "cancelled" then
        res.refundDue = math.max(0, collected)
        res.status = (collected > 0) and "refund_due" or (refunded > 0 and "refunded" or "cancelled")
        return res
    end
    res.outstanding = math.max(0, aw.amount - collected)
    res.overpaid = math.max(0, collected - aw.amount)
    if collected <= 0 then res.status = "unpaid"
    elseif collected < aw.amount then res.status = "partial"
    elseif collected == aw.amount then res.status = "paid"
    else res.status = "overpaid" end
    return res
end

-- 분배 의무 지급 상태
function P:ObligationStatus(ob)
    local paid = 0
    for _, a in pairs(DB:T("payoutAllocations")) do
        if a.obligationId == ob.id and not a.voided then paid = paid + a.amount end
    end
    local res = { amount = ob.amount, paid = paid, remaining = math.max(0, ob.amount - paid), over = math.max(0, paid - ob.amount) }
    if ob.hold then res.status = "hold"
    elseif res.over > 0 or ob.needsCheck then res.status = "check"
    elseif paid <= 0 and ob.amount > 0 then res.status = "pending"
    elseif paid < ob.amount then res.status = "partial"
    else res.status = "paid" end
    return res
end

---------------------------------------------------------------------------
-- 제안 (자동 확정 없음)
---------------------------------------------------------------------------
-- 거래 상대의 수금 전 낙찰에 오래된 순서로 배분 제안
function P:SuggestAuctionAllocations(tr)
    local out = {}
    if not J():IsCounted(tr) or not tr.partnerKey then return out end
    local avail = self:TradeAvailableIn(tr)
    if avail <= 0 then return out end
    local awards = BRL.Auctions:AwardsForPlayer(tr.partnerKey)
    -- 정확히 일치하는 단일 낙찰 우선
    for _, aw in ipairs(awards) do
        local st = self:AwardStatus(aw)
        if st.outstanding == avail then
            out[1] = { awardId = aw.id, amount = avail, exact = true }
            return out
        end
    end
    for _, aw in ipairs(awards) do
        if avail <= 0 then break end
        local st = self:AwardStatus(aw)
        if st.outstanding > 0 then
            local amt = math.min(avail, st.outstanding)
            out[#out + 1] = { awardId = aw.id, amount = amt }
            avail = avail - amt
        end
    end
    if avail > 0 and #out > 0 then out.leftover = avail end
    return out
end

function P:SuggestPayoutAllocations(tr)
    local out = {}
    if not J():IsCounted(tr) or not tr.partnerKey then return out end
    local avail = self:TradeAvailableOut(tr)
    if avail <= 0 then return out end
    local obs = DB:List("payouts", function(o) return o.memberKey == tr.partnerKey and not o.voided end, "createdAt")
    for _, ob in ipairs(obs) do
        local st = self:ObligationStatus(ob)
        if st.remaining == avail and st.status ~= "hold" then
            out[1] = { obligationId = ob.id, amount = avail, exact = true }
            return out
        end
    end
    for _, ob in ipairs(obs) do
        if avail <= 0 then break end
        local st = self:ObligationStatus(ob)
        if st.remaining > 0 and st.status ~= "hold" then
            local amt = math.min(avail, st.remaining)
            out[#out + 1] = { obligationId = ob.id, amount = amt }
            avail = avail - amt
        end
    end
    return out
end

---------------------------------------------------------------------------
-- 경매금 수금 연결
---------------------------------------------------------------------------
-- opts: allowOverpay, note
function P:AllocateAuction(tradeId, awardId, amount, opts)
    opts = opts or {}
    local tr = J():Get(tradeId)
    local aw = DB:Get("awards", awardId)
    if not tr then return nil, "거래 없음" end
    if not aw then return nil, "낙찰 없음" end
    local ok, why = checkSession(aw.sessionId)
    if not ok then return nil, why end
    if not J():IsCounted(tr) then return nil, "완료가 확인되지 않은 거래는 연결할 수 없습니다 (" .. J():StatusLabel(tr) .. ")" end
    if aw.status ~= "active" then return nil, "취소된 낙찰에는 수금을 연결할 수 없습니다" end
    if tr.purpose ~= "auction_payment" and tr.purpose ~= "unclassified" then
        return nil, "거래 목적이 '" .. J():PurposeLabel(tr.purpose) .. "'입니다. 목적을 경매금 수금으로 변경하세요."
    end
    if not Money.IsValid(amount) or amount <= 0 then return nil, "연결 금액 오류" end
    for _, a in pairs(DB:T("auctionAllocations")) do
        if a.tradeId == tradeId and a.awardId == awardId and not a.voided and a.kind ~= "refund" then
            return nil, "이미 이 거래가 해당 낙찰에 연결되어 있습니다 (중복 연결 방지)"
        end
    end
    local avail = self:TradeAvailableIn(tr)
    if amount > avail then
        return nil, "거래의 미연결 금액(" .. Money.Format(avail) .. ")보다 큰 금액은 연결할 수 없습니다"
    end
    local st = self:AwardStatus(aw)
    if amount > st.outstanding and not opts.allowOverpay then
        return nil, "overpay", { outstanding = st.outstanding }
    end
    if tr.purpose == "unclassified" then
        J():SetPurpose(tradeId, "auction_payment", "경매금 연결", { keepLinks = true })
    end
    if tr.sessionId ~= aw.sessionId and not self:HasActiveLinks(tradeId) then
        J():SetSession(tradeId, aw.sessionId, "낙찰 세션으로 이동")
    end
    local alloc = DB:Insert("auctionAllocations", {
        tradeId = tradeId, awardId = awardId, amount = amount, kind = "payment",
        payerKey = tr.partnerKey, proxy = tr.partnerKey ~= aw.winnerKey,
        overpay = amount > st.outstanding, at = U.Now(), note = opts.note, voided = false,
    })
    DB:Audit("allocation.auction", "allocation", alloc.id, {
        trade = tradeId, award = awardId, amount = amount, proxy = alloc.proxy, overpay = alloc.overpay,
    })
    tr.suggestion = nil
    changed()
    return alloc
end

-- 제안 목록 일괄 승인
function P:ApplySuggestion(tradeId)
    local tr = J():Get(tradeId)
    if not tr or not tr.suggestion then return 0 end
    local n = 0
    local sug = tr.suggestion
    for _, s in ipairs(sug.allocations or {}) do
        local res
        if s.awardId then res = self:AllocateAuction(tradeId, s.awardId, s.amount)
        elseif s.obligationId then res = self:AllocatePayout(tradeId, s.obligationId, s.amount) end
        if res then n = n + 1 end
    end
    tr.suggestion = nil
    return n
end

-- 환불 연결 (취소된 낙찰의 수금액을 돌려준 거래)
function P:AllocateRefund(tradeId, awardId, amount, opts)
    opts = opts or {}
    local tr = J():Get(tradeId)
    local aw = DB:Get("awards", awardId)
    if not tr or not aw then return nil, "거래/낙찰 없음" end
    local ok, why = checkSession(aw.sessionId)
    if not ok then return nil, why end
    if not J():IsCounted(tr) then return nil, "완료가 확인되지 않은 거래입니다" end
    if tr.purpose ~= "refund" and tr.purpose ~= "unclassified" then return nil, "거래 목적을 경매금 환불로 변경하세요" end
    if not Money.IsValid(amount) or amount <= 0 then return nil, "금액 오류" end
    local avail = self:TradeAvailableOut(tr)
    if amount > avail then return nil, "거래의 미연결 지급 금액(" .. Money.Format(avail) .. ")을 초과합니다" end
    local st = self:AwardStatus(aw)
    if amount > st.collected and not opts.allowOverpay then return nil, "수금액보다 큰 환불입니다" end
    if tr.purpose == "unclassified" then J():SetPurpose(tradeId, "refund", "경매금 환불 연결", { keepLinks = true }) end
    local alloc = DB:Insert("auctionAllocations", {
        tradeId = tradeId, awardId = awardId, amount = amount, kind = "refund",
        payerKey = tr.partnerKey, at = U.Now(), note = opts.note, voided = false,
    })
    DB:Audit("allocation.refund", "allocation", alloc.id, { trade = tradeId, award = awardId, amount = amount })
    changed()
    return alloc
end

function P:UnlinkAuction(allocId, reason)
    local a = DB:Get("auctionAllocations", allocId)
    if not a or a.voided then return false, "연결 없음" end
    local aw = DB:Get("awards", a.awardId)
    local ok, why = checkSession(aw and aw.sessionId)
    if not ok then return false, why end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "해제 사유를 입력하세요" end
    a.voided = true
    a.voidReason = reason
    a.voidedAt = U.Now()
    DB:Audit("allocation.auction.unlink", "allocation", allocId, { reason = reason, amount = a.amount })
    changed()
    return true
end

-- 연결 금액 수정 = 기존 연결 해제 + 새 연결 (이력 보존)
function P:ModifyAuction(allocId, newAmount, reason)
    local a = DB:Get("auctionAllocations", allocId)
    if not a or a.voided then return nil, "연결 없음" end
    local ok, why = self:UnlinkAuction(allocId, reason)
    if not ok then return nil, why end
    local res, err = self:AllocateAuction(a.tradeId, a.awardId, newAmount, { allowOverpay = true, note = "수정: " .. tostring(reason) })
    if not res then
        a.voided = false
        a.voidReason = nil
        return nil, err
    end
    res.replaces = allocId
    return res
end

---------------------------------------------------------------------------
-- 분배금 지급 연결
---------------------------------------------------------------------------
-- opts: allowOverpay, note, proxy(파티 대표 수령)
function P:AllocatePayout(tradeId, obligationId, amount, opts)
    opts = opts or {}
    local tr = J():Get(tradeId)
    local ob = DB:Get("payouts", obligationId)
    if not tr then return nil, "거래 없음" end
    if not ob or ob.voided then return nil, "분배 의무 없음" end
    local st = DB:Get("settlements", ob.settlementId)
    local ok, why = checkSession(st and st.sessionId)
    if not ok then return nil, why end
    if not J():IsCounted(tr) then return nil, "완료가 확인되지 않은 거래는 연결할 수 없습니다 (" .. J():StatusLabel(tr) .. ")" end
    if tr.purpose ~= "payout" and tr.purpose ~= "unclassified" then
        return nil, "거래 목적이 '" .. J():PurposeLabel(tr.purpose) .. "'입니다. 목적을 공대원 골드 분배로 변경하세요."
    end
    if not Money.IsValid(amount) or amount <= 0 then return nil, "연결 금액 오류" end
    for _, a in pairs(DB:T("payoutAllocations")) do
        if a.tradeId == tradeId and a.obligationId == obligationId and not a.voided then
            return nil, "이미 이 거래가 해당 분배에 연결되어 있습니다 (중복 지급 방지)"
        end
    end
    local avail = self:TradeAvailableOut(tr)
    if amount > avail then
        return nil, "거래의 미연결 지급 금액(" .. Money.Format(avail) .. ")보다 큰 금액은 연결할 수 없습니다"
    end
    local obs = self:ObligationStatus(ob)
    if amount > obs.remaining and not opts.allowOverpay then
        return nil, "overpay", { remaining = obs.remaining }
    end
    local proxy = tr.partnerKey ~= ob.memberKey
    if proxy and not opts.proxy then
        return nil, "proxy", { recipient = tr.partnerKey, member = ob.memberKey }
    end
    if tr.purpose == "unclassified" then J():SetPurpose(tradeId, "payout", "분배 지급 연결", { keepLinks = true }) end
    if st and tr.sessionId ~= st.sessionId and not self:HasActiveLinks(tradeId) then
        J():SetSession(tradeId, st.sessionId, "정산 세션으로 이동")
    end
    local alloc = DB:Insert("payoutAllocations", {
        tradeId = tradeId, obligationId = obligationId, amount = amount, recipientKey = tr.partnerKey,
        proxy = proxy, overpay = amount > obs.remaining, at = U.Now(), note = opts.note, voided = false,
    })
    DB:Audit("allocation.payout", "allocation", alloc.id, { trade = tradeId, obligation = obligationId, amount = amount, proxy = proxy })
    tr.suggestion = nil
    changed()
    BRL.Events:Fire(BRL.Events.MSG.SETTLEMENT_CHANGED, ob.settlementId)
    return alloc
end

-- 공대장 본인 낙찰: 본인 지갑의 골드를 공대 금액으로 낸 것으로 기록 (거래 로그 "본인 지급" + 수금 연결)
-- amount 생략 시 남은 낙찰금 전액. opts: allowOverpay
function P:PayAwardFromSelf(awardId, amount, opts)
    opts = opts or {}
    local aw = DB:Get("awards", awardId)
    if not aw then return nil, "낙찰 없음" end
    if aw.winnerKey ~= BRL.playerKey then return nil, "공대장 본인이 낙찰받은 경우에만 본인 지급으로 기록할 수 있습니다" end
    if aw.status ~= "active" then return nil, "취소된 낙찰입니다" end
    local ok, why = checkSession(aw.sessionId)
    if not ok then return nil, why end
    local st = self:AwardStatus(aw)
    amount = amount or st.outstanding
    if not Money.IsValid(amount) or amount <= 0 then return nil, "기록할 낙찰금이 없습니다" end
    if amount > st.outstanding and not opts.allowOverpay then return nil, "overpay", { outstanding = st.outstanding } end
    local tr, err = J():AddSelf({
        received = amount, purpose = "auction_payment", sessionId = aw.sessionId,
        note = "공대장 본인 낙찰금 - " .. tostring(aw.itemName or "?"),
        targetItems = {},
    })
    if not tr then return nil, err end
    local alloc, aerr = self:AllocateAuction(tr.id, aw.id, amount, { allowOverpay = opts.allowOverpay, note = "본인 낙찰" })
    if not alloc then
        J():Void(tr.id, "본인 지급 연결 실패: " .. tostring(aerr))
        return nil, aerr
    end
    if not aw.delivered then
        aw.delivered = true
        aw.deliveredAt = U.Now()
        DB:Audit("award.delivered", "award", aw.id, { self = true })
    end
    return alloc, tr
end

-- 공대장 본인 몫/수수료: 거래 없이 지급 완료 처리 (장부에 공대장 분배 지출로 기록)
function P:PaySelf(obligationId)
    local ob = DB:Get("payouts", obligationId)
    if not ob or ob.voided then return nil, "분배 의무 없음" end
    if ob.memberKey ~= BRL.playerKey then return nil, "본인 몫만 거래 없이 지급 처리할 수 있습니다" end
    local st = DB:Get("settlements", ob.settlementId)
    local ok, why = checkSession(st and st.sessionId)
    if not ok then return nil, why end
    local obs = self:ObligationStatus(ob)
    if obs.remaining <= 0 then return nil, "남은 지급액이 없습니다" end
    local alloc = DB:Insert("payoutAllocations", {
        tradeId = nil, obligationId = obligationId, amount = obs.remaining, recipientKey = BRL.playerKey,
        kind = "self", at = U.Now(), voided = false,
    })
    local entry = BRL.Ledger:AddSystem(st and st.sessionId, "expense", "payout_leader", obs.remaining,
        "공대장 본인 몫 (" .. (ob.kind == "fee" and "수수료" or "분배") .. ")", { payoutAllocationId = alloc.id })
    alloc.ledgerEntryId = entry and entry.id
    DB:Audit("allocation.payout.self", "allocation", alloc.id, { obligation = obligationId, amount = alloc.amount })
    changed()
    BRL.Events:Fire(BRL.Events.MSG.SETTLEMENT_CHANGED, ob.settlementId)
    return alloc
end

function P:UnlinkPayout(allocId, reason)
    local a = DB:Get("payoutAllocations", allocId)
    if not a or a.voided then return false, "연결 없음" end
    local ob = DB:Get("payouts", a.obligationId)
    local st = ob and DB:Get("settlements", ob.settlementId)
    local ok, why = checkSession(st and st.sessionId)
    if not ok then return false, why end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "해제 사유를 입력하세요" end
    a.voided = true
    a.voidReason = reason
    a.voidedAt = U.Now()
    if a.ledgerEntryId then BRL.Ledger:VoidSystem(a.ledgerEntryId, reason) end
    DB:Audit("allocation.payout.unlink", "allocation", allocId, { reason = reason, amount = a.amount })
    changed()
    if ob then BRL.Events:Fire(BRL.Events.MSG.SETTLEMENT_CHANGED, ob.settlementId) end
    return true
end

function P:SetHold(obligationId, hold, reason)
    local ob = DB:Get("payouts", obligationId)
    if not ob then return false end
    local st = DB:Get("settlements", ob.settlementId)
    local ok, why = checkSession(st and st.sessionId)
    if not ok then return false, why end
    DB:AddHistory(ob, "hold", ob.hold, hold, reason)
    ob.hold = hold and true or false
    changed()
    BRL.Events:Fire(BRL.Events.MSG.SETTLEMENT_CHANGED, ob.settlementId)
    return true
end

function P:SetNeedsCheck(obligationId, flag, reason)
    local ob = DB:Get("payouts", obligationId)
    if not ob then return false end
    DB:AddHistory(ob, "needsCheck", ob.needsCheck, flag, reason)
    ob.needsCheck = flag and true or false
    changed()
    return true
end

---------------------------------------------------------------------------
-- 거래 창 정보 패널용: 이 상대에게서 받을 낙찰금 (수금 연결 전 낙찰)
---------------------------------------------------------------------------
function P:PendingAwardsFor(memberKey, sessionId)
    local total, list = 0, {}
    if not memberKey then return 0, list end
    for _, aw in pairs(DB:T("awards")) do
        if aw.status == "active" and aw.winnerKey == memberKey and (not sessionId or aw.sessionId == sessionId) then
            local st = self:AwardStatus(aw)
            if st.outstanding > 0 then
                total = total + st.outstanding
                list[#list + 1] = { award = aw, amount = st.outstanding }
            end
        end
    end
    table.sort(list, function(a, b) return (a.award.awardedAt or 0) < (b.award.awardedAt or 0) end)
    return total, list
end

-- 분배 미지급 (memberKey 에게 줘야 할 남은 금액)
function P:UnpaidPayoutFor(memberKey, sessionId)
    local total, list = 0, {}
    if not memberKey then return 0, list end
    local stOk = {}
    for _, st in pairs(DB:T("settlements")) do
        if st.status ~= "draft" and (not sessionId or st.sessionId == sessionId) then stOk[st.id] = true end
    end
    for _, ob in pairs(DB:T("payouts")) do
        if ob.memberKey == memberKey and not ob.voided and stOk[ob.settlementId] then
            local st = self:ObligationStatus(ob)
            if (st.remaining or 0) > 0 and not ob.hold then
                total = total + st.remaining
                list[#list + 1] = { ob = ob, remaining = st.remaining }
            end
        end
    end
    return total, list
end

---------------------------------------------------------------------------
-- 세션 요약용
---------------------------------------------------------------------------
function P:SessionCollection(sessionId)
    local total, collected, outstanding, overpaid, refundDue = 0, 0, 0, 0, 0
    local count, paidCount = 0, 0
    for _, aw in pairs(DB:T("awards")) do
        if aw.sessionId == sessionId then
            local st = self:AwardStatus(aw)
            if aw.status == "active" then
                total = total + aw.amount
                collected = collected + st.collected
                outstanding = outstanding + st.outstanding
                overpaid = overpaid + st.overpaid
                count = count + 1
                if st.outstanding == 0 then paidCount = paidCount + 1 end
            else
                -- 취소된 낙찰의 미환불 수금액: 실제 보유 중이지만 돌려줘야 할 골드 (분배 대상 아님)
                refundDue = refundDue + (st.refundDue or 0)
            end
        end
    end
    return { total = total, collected = collected, outstanding = outstanding, overpaid = overpaid,
        refundDue = refundDue, count = count, paidCount = paidCount }
end
