-- BIG RAID LEADER - 골드 통합 장부 (LedgerEntry)
-- 실제 골드 이동(완료 거래/수동 확인 기록)과 장부상 예정 금액(낙찰·분배 의무)을 분리한다.
--  * source=trade  : 공대 목적 거래에서 자동 생성 (거래와 1:1, 거래 변경 시 자동 갱신)
--  * source=manual : 공대장 수동 기록 (사유 필수)
--  * source=system : 공대장 본인 몫 지급 등 내부 처리
local _, BRL = ...
local U, DB, Money = BRL.Util, BRL.DB, BRL.Money

local Ledger = BRL:NewModule("Ledger")

Ledger.INCOME_CATEGORIES = { "auction_payment", "extra_auction", "other_income", "adjust_income" }
Ledger.EXPENSE_CATEGORIES = { "payout_member", "payout_leader", "operating", "other_expense", "adjust_expense", "refund" }
Ledger.MANUAL_INCOME = { "extra_auction", "other_income", "adjust_income" }
Ledger.MANUAL_EXPENSE = { "operating", "other_expense", "adjust_expense", "payout_leader" }

local PURPOSE_MAP = {
    auction_payment = { kind = "income", category = "auction_payment", sign = 1 },
    raid_income = { kind = "income", category = "other_income", sign = 1 },
    payout = { kind = "expense", category = "payout_member", sign = -1 },
    raid_expense = { kind = "expense", category = "other_expense", sign = -1 },
    refund = { kind = "expense", category = "refund", sign = -1 },
}

local function changed()
    BRL.Events:Fire(BRL.Events.MSG.LEDGER_CHANGED)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "ledger")
end

function Ledger:Get(id) return DB:Get("ledger", id) end

function Ledger:CategoryLabel(cat) return BRL.Label("LEDGER_", cat) end

function Ledger:EntryForTrade(tradeId)
    for _, e in pairs(DB:T("ledger")) do
        if e.tradeId == tradeId and e.source == "trade" then return e end
    end
    return nil
end

-- 거래 → 장부 동기화 (멱등)
function Ledger:SyncTrade(tr)
    if not tr then return end
    local entry = self:EntryForTrade(tr.id)
    local map = PURPOSE_MAP[tr.purpose]
    local counted = BRL.TradeJournal:IsCounted(tr)
    if not map or not counted then
        if entry and not entry.voided then
            entry.voided = true
            entry.voidReason = not counted and "거래 미확정/취소" or "공대 목적 아님"
            DB:AddHistory(entry, "voided", false, true, entry.voidReason)
            changed()
        end
        return
    end
    local eff = BRL.TradeJournal:Effective(tr)
    local amount = eff.net * map.sign
    if amount < 0 then amount = 0 end
    if not entry then
        entry = DB:Insert("ledger", {
            sessionId = tr.sessionId, kind = map.kind, category = map.category, amount = amount,
            tradeId = tr.id, source = "trade", at = tr.at or U.Now(), partnerKey = tr.partnerKey,
            note = BRL.TradeJournal:PurposeLabel(tr.purpose), voided = false, history = {},
        })
        DB:Audit("ledger.trade", "ledger", entry.id, { trade = tr.id, amount = amount, category = map.category })
    else
        local before = { kind = entry.kind, category = entry.category, amount = entry.amount, sessionId = entry.sessionId, voided = entry.voided }
        entry.kind, entry.category, entry.amount, entry.sessionId = map.kind, map.category, amount, tr.sessionId
        entry.voided = false
        entry.voidReason = nil
        if before.amount ~= amount or before.category ~= map.category or before.voided or before.sessionId ~= tr.sessionId then
            DB:AddHistory(entry, "sync", before, { kind = entry.kind, category = entry.category, amount = amount, sessionId = tr.sessionId }, "거래 변경 반영")
        end
    end
    changed()
    return entry
end

-- 수동 장부 기록
function Ledger:AddManual(sessionId, kind, category, amount, note)
    local session = sessionId and BRL.Session:Get(sessionId)
    local ok, why = BRL.Perm:CanEditSession(session)
    if not ok then return nil, why end
    if kind ~= "income" and kind ~= "expense" then return nil, "구분 오류" end
    local allowed = kind == "income" and self.MANUAL_INCOME or self.MANUAL_EXPENSE
    if not U.Contains(allowed, category) then return nil, "분류 오류" end
    if not Money.IsValid(amount) or amount <= 0 then return nil, "금액 오류" end
    note = U.Trim(note or "")
    if note == "" then return nil, "기록 사유를 입력하세요" end
    local e = DB:Insert("ledger", {
        sessionId = sessionId, kind = kind, category = category, amount = amount,
        source = "manual", at = U.Now(), note = note, voided = false, history = {},
    })
    DB:Audit("ledger.manual", "ledger", e.id, { kind = kind, category = category, amount = amount, note = note })
    changed()
    return e
end

function Ledger:AddSystem(sessionId, kind, category, amount, note, refs)
    local e = DB:Insert("ledger", {
        sessionId = sessionId, kind = kind, category = category, amount = amount,
        source = "system", at = U.Now(), note = note, voided = false, history = {}, refs = refs,
    })
    DB:Audit("ledger.system", "ledger", e.id, { kind = kind, category = category, amount = amount })
    changed()
    return e
end

function Ledger:VoidSystem(id, reason)
    local e = self:Get(id)
    if not e or e.source ~= "system" then return false end
    e.voided = true
    e.voidReason = reason
    DB:AddHistory(e, "voided", false, true, reason)
    changed()
    return true
end

function Ledger:EditManual(id, amount, note, reason)
    local e = self:Get(id)
    if not e or e.source ~= "manual" then return false, "수동 기록만 수정할 수 있습니다 (거래 기록은 거래 로그에서 정정)" end
    local ok, why = BRL.Perm:CanEditSession(e.sessionId and BRL.Session:Get(e.sessionId))
    if not ok then return false, why end
    if not Money.IsValid(amount) or amount <= 0 then return false, "금액 오류" end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "수정 사유를 입력하세요" end
    DB:AddHistory(e, "amount", e.amount, amount, reason)
    if note and note ~= e.note then DB:AddHistory(e, "note", e.note, note, reason) e.note = note end
    DB:Audit("ledger.edit", "ledger", id, { old = e.amount, new = amount, reason = reason })
    e.amount = amount
    changed()
    return true
end

function Ledger:VoidManual(id, reason)
    local e = self:Get(id)
    if not e or e.source ~= "manual" then return false, "수동 기록만 취소할 수 있습니다" end
    local ok, why = BRL.Perm:CanEditSession(e.sessionId and BRL.Session:Get(e.sessionId))
    if not ok then return false, why end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "취소 사유를 입력하세요" end
    e.voided = true
    e.voidReason = reason
    DB:AddHistory(e, "voided", false, true, reason)
    DB:Audit("ledger.void", "ledger", id, { reason = reason })
    changed()
    return true
end

function Ledger:RestoreManual(id, reason)
    local e = self:Get(id)
    if not e or e.source ~= "manual" or not e.voided then return false end
    local ok, why = BRL.Perm:CanEditSession(e.sessionId and BRL.Session:Get(e.sessionId))
    if not ok then return false, why end
    e.voided = false
    DB:AddHistory(e, "voided", true, false, reason)
    DB:Audit("ledger.restore", "ledger", id, { reason = reason })
    changed()
    return true
end

-- filter: { kind, category, source, includeVoided, search }
function Ledger:Entries(sessionId, filter)
    filter = filter or {}
    return DB:List("ledger", function(e)
        if sessionId and e.sessionId ~= sessionId then return false end
        if e.voided and not filter.includeVoided then return false end
        if filter.kind and e.kind ~= filter.kind then return false end
        if filter.category and e.category ~= filter.category then return false end
        if filter.source and e.source ~= filter.source then return false end
        if filter.search and filter.search ~= "" then
            if not U.MatchSearch((e.note or "") .. " " .. (e.partnerKey or "") .. " " .. self:CategoryLabel(e.category), filter.search) then return false end
        end
        return true
    end, "at", true)
end

-- 세션 장부 요약 (모든 금액 정수 코퍼)
function Ledger:Summary(sessionId)
    local s = {
        incomeByCat = {}, expenseByCat = {}, income = 0, expense = 0,
    }
    for _, e in pairs(DB:T("ledger")) do
        if e.sessionId == sessionId and not e.voided then
            if e.kind == "income" then
                s.incomeByCat[e.category] = (s.incomeByCat[e.category] or 0) + e.amount
                s.income = s.income + e.amount
            else
                s.expenseByCat[e.category] = (s.expenseByCat[e.category] or 0) + e.amount
                s.expense = s.expense + e.amount
            end
        end
    end
    local coll = BRL.Payments:SessionCollection(sessionId)
    s.totalAwarded = coll.total            -- 총 경매액 (예정)
    s.collected = coll.collected           -- 실제 수금액 (낙찰에 연결된 금액 - 환불)
    s.outstanding = coll.outstanding       -- 미수금
    s.overpaid = coll.overpaid
    s.refundDue = coll.refundDue
    s.awardCount, s.awardPaidCount = coll.count, coll.paidCount
    -- 낙찰에 연결되지 않은 경매금 수금 거래 금액
    local unallocated = 0
    for _, tr in pairs(DB:T("trades")) do
        if tr.sessionId == sessionId and tr.purpose == "auction_payment" and BRL.TradeJournal:IsCounted(tr) then
            unallocated = unallocated + BRL.Payments:TradeAvailableIn(tr)
        end
    end
    s.unallocatedAuctionIncome = unallocated
    s.otherIncome = s.income - (s.incomeByCat.auction_payment or 0)
    -- 분배 의무
    local planned, paid, unpaid = 0, 0, 0
    for _, st in pairs(DB:T("settlements")) do
        if st.sessionId == sessionId then
            for _, ob in pairs(DB:T("payouts")) do
                if ob.settlementId == st.id and not ob.voided then
                    local obs = BRL.Payments:ObligationStatus(ob)
                    planned = planned + ob.amount
                    paid = paid + math.min(obs.paid, ob.amount)
                    unpaid = unpaid + obs.remaining
                end
            end
        end
    end
    s.payoutPlanned, s.payoutPaid, s.unpaid = planned, paid, unpaid
    s.balance = s.income - s.expense
    -- 미연결 지급 거래
    local unallocOut = 0
    for _, tr in pairs(DB:T("trades")) do
        if tr.sessionId == sessionId and tr.purpose == "payout" and BRL.TradeJournal:IsCounted(tr) then
            unallocOut = unallocOut + BRL.Payments:TradeAvailableOut(tr)
        end
    end
    s.unallocatedPayout = unallocOut
    -- 미연결 환불 거래 / 수동 공대장 분배 기록
    local unallocRefund = 0
    for _, tr in pairs(DB:T("trades")) do
        if tr.sessionId == sessionId and tr.purpose == "refund" and BRL.TradeJournal:IsCounted(tr) then
            unallocRefund = unallocRefund + BRL.Payments:TradeAvailableOut(tr)
        end
    end
    s.unallocatedRefund = unallocRefund
    local manualLeader = 0
    for _, e in pairs(DB:T("ledger")) do
        if e.sessionId == sessionId and not e.voided and e.source == "manual" and e.category == "payout_leader" then
            manualLeader = manualLeader + e.amount
        end
    end
    s.manualPayoutLeader = manualLeader
    return s
end

function Ledger:ExportCSV(sessionId)
    local csv = BRL.TradeJournal.CSV
    local lines = { "장부ID,세션,일시,구분,분류,금액(코퍼),금액,출처,거래ID,상대,메모,취소" }
    for _, e in ipairs(self:Entries(sessionId, { includeVoided = true })) do
        lines[#lines + 1] = table.concat({
            csv(e.id), csv(e.sessionId), csv(U.FormatDateTime(e.at)), csv(e.kind == "income" and "수입" or "지출"),
            csv(self:CategoryLabel(e.category)), csv(e.amount), csv(Money.Format(e.amount)), csv(e.source),
            csv(e.tradeId), csv(e.partnerKey), csv(e.note), csv(e.voided and ("Y:" .. tostring(e.voidReason)) or ""),
        }, ",")
    end
    return table.concat(lines, "\n")
end

