-- BIG RAID LEADER - 거래 기록 장부 (TradeTransaction / TradeItem)
-- 원본 거래 기록은 절대 삭제하지 않는다. 수정은 adjusted 필드와 수정 이력으로 남긴다.
local _, BRL = ...
local U, API, DB, Money, L = BRL.Util, BRL.API, BRL.DB, BRL.Money, BRL.L

local J = BRL:NewModule("TradeJournal")

J.PURPOSES = { "auction_payment", "payout", "personal", "raid_expense", "raid_income", "refund", "unclassified" }
J.RAID_PURPOSES = { auction_payment = true, payout = true, raid_expense = true, raid_income = true, refund = true }
J.STATUSES = { "open", "completed", "cancelled", "unverified", "manual" }

local function fire(rec)
    BRL.Events:Fire(BRL.Events.MSG.TRADE_RECORDED, rec)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "trades")
end

local function copyItems(items)
    local out = {}
    for _, it in ipairs(items or {}) do
        out[#out + 1] = { name = it.name, link = it.link, count = it.count or 1, quality = it.quality, icon = it.icon }
    end
    return out
end

local function activeSessionIdFor()
    local s = BRL.Session and BRL.Session:GetActive()
    if s and s.status == "open" and s.owner == BRL.playerKey then return s.id end
    return nil
end

---------------------------------------------------------------------------
-- 조회 헬퍼
---------------------------------------------------------------------------
function J:Get(id) return DB:Get("trades", id) end

-- 실효 금액 (수동 조정 반영). 원본은 playerMoney/targetMoney 에 그대로 보존.
function J:Effective(tr)
    local given = tr.playerMoney or 0
    local received = tr.targetMoney or 0
    if tr.adjusted then
        given = tr.adjusted.playerMoney or given
        received = tr.adjusted.targetMoney or received
    end
    return { given = given, received = received, net = received - given }
end

-- 확정 금액으로 합산 가능한 거래인가 (완료 확인 / 수동 확인, 기록 취소 아님)
function J:IsCounted(tr)
    if not tr or tr.voided then return false end
    return tr.status == "completed" or tr.status == "manual"
end

function J:StatusLabel(tr)
    if tr.voided then return L.TRADE_voided end
    local base = tr.source == "self" and L.TRADE_self or BRL.Label("TRADE_", tr.status)
    if tr.adjusted then return base .. "·" .. L.TRADE_adjusted end
    return base
end

function J:PurposeLabel(p) return BRL.Label("PURPOSE_", p or "unclassified") end

function J:HasItems(tr)
    return #(tr.playerItems or {}) > 0 or #(tr.targetItems or {}) > 0
end

function J:ItemSummary(tr, maxLen)
    local parts = {}
    for _, it in ipairs(tr.targetItems or {}) do
        parts[#parts + 1] = "+" .. (it.link or it.name or "?") .. ((it.count or 1) > 1 and ("x" .. it.count) or "")
    end
    for _, it in ipairs(tr.playerItems or {}) do
        parts[#parts + 1] = "-" .. (it.link or it.name or "?") .. ((it.count or 1) > 1 and ("x" .. it.count) or "")
    end
    local s = table.concat(parts, " ")
    if maxLen and #s > maxLen then s = U.Utf8Truncate(s, maxLen) .. "…" end
    return s
end

---------------------------------------------------------------------------
-- 기록 생성
---------------------------------------------------------------------------
function J:RecordFromTracker(sess, snap, status, verification, extra)
    snap = snap or {}
    local t = DB:T("trades")
    if t[sess.id] then return t[sess.id] end -- 동일 거래 세션 이중 기록 방지 (멱등)
    local rec = DB:Insert("trades", {
        id = sess.id,
        at = U.Now(),
        openedAt = sess.openedAt,
        partnerKey = sess.partnerKey,
        partnerName = sess.partnerKey and API.ShortName(sess.partnerKey) or "알 수 없음",
        partnerGuid = sess.partnerGuid,
        partnerClass = sess.partnerClass,
        playerMoney = Money.IsValid(snap.playerMoney) and snap.playerMoney or 0,
        targetMoney = Money.IsValid(snap.targetMoney) and snap.targetMoney or 0,
        playerItems = copyItems(snap.playerItems),
        targetItems = copyItems(snap.targetItems),
        status = status,
        verification = verification,
        source = "auto",
        purpose = "unclassified",
        sessionId = activeSessionIdFor(),
        moneyDelta = extra and extra.moneyDelta or nil,
        finalizeReason = extra and extra.reason or nil,
        cancelReason = extra and type(extra.cancelReason) == "string" and extra.cancelReason or nil,
        eventTrace = sess.events,
        history = {},
    })
    table.insert(BRL.db.tradeOrder, rec.id)
    DB:Audit("trade.record", "trade", rec.id, { status = status, verification = verification,
        given = rec.playerMoney, received = rec.targetMoney, partner = rec.partnerKey })
    if self:IsCounted(rec) then
        self:AutoDetectDelivery(rec)
        self:SuggestPurpose(rec)
    end
    self:Notify(rec)
    fire(rec)
    return rec
end

-- 수동 거래 기록 (누락된 거래 추가). fields: partner, given, received, purpose, note, at, items
-- 공대장 본인 지급 기록 (본인 낙찰 등: 거래 상대 없이 본인 지갑 → 공대 금액)
-- fields: received(코퍼), purpose, sessionId, note, targetItems
function J:AddSelf(fields)
    fields = fields or {}
    local received = fields.received or 0
    if not Money.IsValid(received) or received <= 0 then return nil, "금액 오류" end
    local purpose = fields.purpose or "auction_payment"
    local session = fields.sessionId and BRL.Session:Get(fields.sessionId)
    if session then
        local ok, why = BRL.Perm:CanEditSession(session)
        if not ok then return nil, why end
    elseif not BRL.Perm:Require("finance.edit") then
        return nil, L.LEADER_ONLY
    end
    local rec = DB:Insert("trades", {
        at = U.Now(),
        partnerKey = BRL.playerKey,
        partnerName = API.ShortName(BRL.playerKey) .. " (본인)",
        playerMoney = 0,
        targetMoney = received,
        playerItems = {},
        targetItems = copyItems(fields.targetItems),
        status = "manual",
        verification = "self",
        source = "self",
        purpose = purpose,
        sessionId = fields.sessionId or activeSessionIdFor(),
        note = fields.note or "공대장 본인 지급",
        history = {},
    })
    table.insert(BRL.db.tradeOrder, rec.id)
    DB:Audit("trade.self.add", "trade", rec.id, { received = received, purpose = purpose, note = rec.note })
    BRL.Ledger:SyncTrade(rec)
    fire(rec)
    return rec
end

function J:AddManual(fields)
    if not BRL.Perm:Require("trade.own") then return nil, "권한 없음" end
    fields = fields or {}
    local given = fields.given or 0
    local received = fields.received or 0
    if not Money.IsValid(given) or not Money.IsValid(received) then return nil, "금액 오류" end
    if given == 0 and received == 0 and not (fields.items and #fields.items > 0) then
        return nil, "금액 또는 아이템이 필요합니다"
    end
    local note = U.Trim(fields.note or "")
    if note == "" then return nil, "수동 기록 사유를 입력하세요" end
    local partner = API.NormalizeName(fields.partner)
    if not partner then return nil, "거래 상대를 입력하세요" end
    local purpose = fields.purpose or "unclassified"
    if self.RAID_PURPOSES[purpose] and not BRL.Perm:Require("finance.edit") then return nil, "권한 없음" end
    local rec = DB:Insert("trades", {
        at = fields.at or U.Now(),
        partnerKey = partner,
        partnerName = API.ShortName(partner),
        playerMoney = given,
        targetMoney = received,
        playerItems = copyItems(fields.playerItems),
        targetItems = copyItems(fields.targetItems),
        status = "manual",
        verification = "manual",
        source = "manual",
        purpose = purpose,
        sessionId = fields.sessionId or activeSessionIdFor(),
        note = note,
        history = {},
    })
    table.insert(BRL.db.tradeOrder, rec.id)
    DB:Audit("trade.manual.add", "trade", rec.id, { given = given, received = received, partner = partner, note = note })
    BRL.Ledger:SyncTrade(rec)
    fire(rec)
    return rec
end

---------------------------------------------------------------------------
-- 수정 (원본 보존 + 이력)
---------------------------------------------------------------------------
local function requireFor(tr, purpose)
    local needsFinance = J.RAID_PURPOSES[purpose or tr.purpose] or J.RAID_PURPOSES[tr.purpose]
    if needsFinance then
        local session = tr.sessionId and BRL.Session:Get(tr.sessionId)
        if session then
            local ok, why = BRL.Perm:CanEditSession(session)
            if not ok then return false, why end
        elseif not BRL.Perm:Can("finance.edit") then
            return false, L.LEADER_ONLY
        end
    elseif not BRL.Perm:Can("trade.own") then
        return false, L.NO_PERMISSION
    end
    return true
end

function J:SetPurpose(id, purpose, reason, opts)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if not U.Contains(self.PURPOSES, purpose) then return false, "알 수 없는 목적" end
    if tr.purpose == purpose then return true end
    local ok, why = requireFor(tr, purpose)
    if not ok then return false, why end
    -- 연결된 수금/지급이 있으면 목적 변경 전 연결 해제 필요
    if BRL.Payments:HasActiveLinks(id) and not (opts and opts.keepLinks) then
        return false, "연결된 경매 수금/분배 지급이 있습니다. 먼저 연결을 해제하세요."
    end
    DB:AddHistory(tr, "purpose", tr.purpose, purpose, reason)
    DB:Audit("trade.purpose", "trade", id, { old = tr.purpose, new = purpose, reason = reason })
    tr.purpose = purpose
    if self.RAID_PURPOSES[purpose] and not tr.sessionId then tr.sessionId = activeSessionIdFor() end
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

function J:SetSession(id, sessionId, reason)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if tr.sessionId == sessionId then return true end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    DB:AddHistory(tr, "sessionId", tr.sessionId, sessionId, reason)
    tr.sessionId = sessionId
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

-- 금액 정정 (수동 조정). 원본 금액은 그대로 보존된다.
function J:Adjust(id, given, received, reason)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if not Money.IsValid(given) or not Money.IsValid(received) then return false, "금액 오류" end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "정정 사유를 입력하세요" end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    local eff = self:Effective(tr)
    -- 이미 연결된 금액보다 작게 줄일 수 없음
    local inUse, outUse = BRL.Payments:AllocatedOnTrade(id)
    if received - given < inUse and inUse > 0 then return false, "이미 경매금으로 연결된 금액보다 작게 정정할 수 없습니다" end
    if given - received < outUse and outUse > 0 then return false, "이미 분배 지급으로 연결된 금액보다 작게 정정할 수 없습니다" end
    local old = { playerMoney = eff.given, targetMoney = eff.received }
    tr.adjusted = { playerMoney = given, targetMoney = received, reason = reason, at = U.Now(), by = BRL.playerKey }
    DB:AddHistory(tr, "money", old, { playerMoney = given, targetMoney = received }, reason)
    DB:Audit("trade.adjust", "trade", id, { old = old, new = tr.adjusted, reason = reason })
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

-- 확인 불가 거래를 공대장이 직접 확인 (수동 확인)
function J:ConfirmManually(id, reason)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if tr.status ~= "unverified" and tr.status ~= "cancelled" then return false, "확인 불가/취소 상태의 거래만 수동 확인할 수 있습니다" end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "확인 사유를 입력하세요" end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    DB:AddHistory(tr, "status", tr.status, "manual", reason)
    DB:Audit("trade.confirm", "trade", id, { old = tr.status, reason = reason })
    tr.status = "manual"
    tr.verification = "manual"
    BRL.Ledger:SyncTrade(tr)
    self:AutoDetectDelivery(tr)
    fire(tr)
    return true
end

function J:MarkCancelled(id, reason)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if tr.status ~= "unverified" then return false, "확인 불가 상태의 거래만 취소로 표시할 수 있습니다" end
    if BRL.Payments:HasActiveLinks(id) then return false, "연결을 먼저 해제하세요" end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    DB:AddHistory(tr, "status", tr.status, "cancelled", reason)
    DB:Audit("trade.mark_cancelled", "trade", id, { reason = reason })
    tr.status = "cancelled"
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

-- 늦게 도착한 완료 메시지로 확인 불가 → 완료 확인
function J:UpgradeToCompleted(id, why)
    local tr = self:Get(id)
    if not tr or tr.status ~= "unverified" then return false end
    DB:AddHistory(tr, "status", tr.status, "completed", why)
    DB:Audit("trade.upgrade", "trade", id, { why = why })
    tr.status = "completed"
    tr.verification = "message_late"
    BRL.Ledger:SyncTrade(tr)
    self:AutoDetectDelivery(tr)
    self:SuggestPurpose(tr)
    self:Notify(tr)
    fire(tr)
    return true
end

function J:Void(id, reason)
    local tr = self:Get(id)
    if not tr then return false, "거래 없음" end
    if tr.voided then return true end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "취소 사유를 입력하세요" end
    if BRL.Payments:HasActiveLinks(id) then return false, "연결된 수금/지급을 먼저 해제하세요" end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    tr.voided = true
    tr.voidReason = reason
    DB:AddHistory(tr, "voided", false, true, reason)
    DB:Audit("trade.void", "trade", id, { reason = reason })
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

function J:Restore(id, reason)
    local tr = self:Get(id)
    if not tr or not tr.voided then return false, "취소된 기록이 아닙니다" end
    local ok, why = requireFor(tr)
    if not ok then return false, why end
    tr.voided = false
    DB:AddHistory(tr, "voided", true, false, reason)
    DB:Audit("trade.restore", "trade", id, { reason = reason })
    BRL.Ledger:SyncTrade(tr)
    fire(tr)
    return true
end

function J:SetNote(id, note)
    local tr = self:Get(id)
    if not tr then return false end
    DB:AddHistory(tr, "note", tr.note, note)
    tr.note = note
    fire(tr)
    return true
end

---------------------------------------------------------------------------
-- 자동 제안 (확정은 공대장이 승인)
---------------------------------------------------------------------------
function J:SuggestPurpose(tr)
    if not BRL.acct.trade.suggestLinks then return end
    local eff = self:Effective(tr)
    tr.suggestion = nil
    if not tr.partnerKey then return end
    if eff.net > 0 then
        local sug = BRL.Payments:SuggestAuctionAllocations(tr)
        if #sug > 0 then tr.suggestion = { purpose = "auction_payment", allocations = sug } return end
    elseif eff.net < 0 then
        local sug = BRL.Payments:SuggestPayoutAllocations(tr)
        if #sug > 0 then tr.suggestion = { purpose = "payout", allocations = sug } return end
    end
end

-- 거래에 낙찰 아이템이 포함되어 낙찰자에게 전달되었는지 감지 (아이템 전달 여부)
function J:AutoDetectDelivery(tr)
    if not tr.partnerKey or #(tr.playerItems or {}) == 0 then return end
    for _, aw in pairs(DB:T("awards")) do
        if aw.status == "active" and not aw.delivered and aw.winnerKey == tr.partnerKey and aw.itemLink then
            local awId = U.ItemIdFromLink(aw.itemLink)
            for _, it in ipairs(tr.playerItems) do
                if (it.link and it.link == aw.itemLink) or (awId and U.ItemIdFromLink(it.link) == awId) then
                    aw.delivered = true
                    aw.deliveredTradeId = tr.id
                    aw.deliveredAt = tr.at
                    DB:Audit("award.delivered", "award", aw.id, { tradeId = tr.id })
                    break
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- 알림
---------------------------------------------------------------------------
function J:Notify(tr)
    local cfg = BRL.acct.trade
    if tr.status ~= "completed" then
        if tr.status == "unverified" and cfg.notifyChat then
            BRL:Print("|cffffaa00거래 결과 확인 불가|r: %s (받음 %s / 줌 %s) - 거래 로그에서 확인하세요.",
                tr.partnerName or "?", Money.Format(tr.targetMoney), Money.Format(tr.playerMoney))
        end
        return
    end
    local eff = self:Effective(tr)
    if cfg.notifyChat then
        local parts = { "|cff55ff55[거래 완료]|r", tr.partnerName or "?" }
        if eff.received > 0 then parts[#parts + 1] = "받은 골드 " .. Money.Format(eff.received) end
        if eff.given > 0 then parts[#parts + 1] = "지급 골드 " .. Money.Format(eff.given) end
        local items = self:ItemSummary(tr, 200)
        if items ~= "" then parts[#parts + 1] = items end
        BRL:Print(table.concat(parts, " | "))
    end
    if cfg.notifyScreen then
        API.ScreenAlert(string.format("거래 완료: %s %s", tr.partnerName or "?",
            eff.received > 0 and ("+" .. Money.Format(eff.received, { goldOnly = eff.received >= 10000 })) or
            (eff.given > 0 and ("-" .. Money.Format(eff.given, { goldOnly = eff.given >= 10000 })) or "")))
    end
    if cfg.whisperPartner and tr.partnerKey then
        for _, line in ipairs(self:BuildWhisper(tr)) do
            BRL.ChatOut:Send(line, "WHISPER", tr.partnerKey)
        end
    end
end

function J:BuildWhisper(tr)
    local eff = self:Effective(tr)
    local lines = { "[BIG RAID LEADER 거래 완료]", "상대방: " .. (tr.partnerName or "?") }
    local items = {}
    for _, it in ipairs(tr.playerItems or {}) do items[#items + 1] = (it.link or it.name) .. ((it.count or 1) > 1 and (" x" .. it.count) or "") end
    for _, it in ipairs(tr.targetItems or {}) do items[#items + 1] = (it.link or it.name) .. ((it.count or 1) > 1 and (" x" .. it.count) or "") end
    if #items > 0 then lines[#lines + 1] = "아이템: " .. table.concat(items, ", ") end
    if eff.received > 0 then lines[#lines + 1] = "받은 골드: " .. Money.Format(eff.received) end
    if eff.given > 0 then lines[#lines + 1] = "지급 골드: " .. Money.Format(eff.given) end
    lines[#lines + 1] = "거래 시각: " .. U.FormatClock(tr.at)
    return lines
end

---------------------------------------------------------------------------
-- 검색 / 필터
---------------------------------------------------------------------------
-- filter: { from, to (timestamp), partner (text), direction ("in"|"out"), kind ("item"|"gold"),
--   group ("raid"|"personal"|"unverified"|"unclassified"), purpose, sessionId, status, includeVoided, includeCancelled }
function J:Query(filter)
    filter = filter or {}
    local out = {}
    local order = BRL.db.tradeOrder
    for i = #order, 1, -1 do
        local tr = DB:Get("trades", order[i])
        if tr and self:Match(tr, filter) then out[#out + 1] = tr end
    end
    return out
end

function J:Match(tr, f)
    if tr.voided and not f.includeVoided then return false end
    if tr.status == "cancelled" and not f.includeCancelled and f.group ~= "cancelled" then return false end
    if f.from and (tr.at or 0) < f.from then return false end
    if f.to and (tr.at or 0) > f.to then return false end
    if f.partner and f.partner ~= "" and not U.MatchSearch(tr.partnerKey or tr.partnerName, f.partner) then return false end
    local eff = self:Effective(tr)
    if f.direction == "in" and eff.received <= 0 then return false end
    if f.direction == "out" and eff.given <= 0 then return false end
    if f.kind == "item" and not self:HasItems(tr) then return false end
    if f.kind == "gold" and eff.given == 0 and eff.received == 0 then return false end
    if f.group == "raid" and not self.RAID_PURPOSES[tr.purpose] then return false end
    if f.group == "personal" and tr.purpose ~= "personal" then return false end
    if f.group == "unverified" and tr.status ~= "unverified" then return false end
    if f.group == "unclassified" and (tr.purpose ~= "unclassified" or not self:IsCounted(tr)) then return false end
    if f.group == "cancelled" and tr.status ~= "cancelled" then return false end
    if f.purpose and tr.purpose ~= f.purpose then return false end
    if f.sessionId and tr.sessionId ~= f.sessionId then return false end
    if f.status and tr.status ~= f.status then return false end
    if f.search and f.search ~= "" then
        local hay = (tr.partnerKey or "") .. " " .. (tr.note or "") .. " " .. self:ItemSummary(tr)
        if not U.MatchSearch(hay, f.search) then return false end
    end
    return true
end

-- 정산 대상 기간의 미분류 완료 거래 수
function J:CountUnclassified(sessionId)
    local n = 0
    for _, tr in pairs(DB:T("trades")) do
        if self:IsCounted(tr) and tr.purpose == "unclassified" and (not sessionId or tr.sessionId == sessionId or tr.sessionId == nil) then
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- 내보내기 (CSV)
---------------------------------------------------------------------------
local function csv(v)
    v = tostring(v == nil and "" or v)
    v = U.StripColors(v):gsub("|H.-|h(.-)|h", "%1")
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end
J.CSV = csv

function J:ExportCSV(list)
    list = list or self:Query({ includeVoided = true, includeCancelled = true })
    local lines = { "거래ID,날짜,시각,상대방,식별자,받은골드(코퍼),지급골드(코퍼),받은아이템,지급아이템,상태,검증,목적,연결경매,연결정산,기록방식,메모" }
    for _, tr in ipairs(list) do
        local eff = self:Effective(tr)
        local recvItems, giveItems = {}, {}
        for _, it in ipairs(tr.targetItems or {}) do recvItems[#recvItems + 1] = (it.name or "?") .. "x" .. (it.count or 1) end
        for _, it in ipairs(tr.playerItems or {}) do giveItems[#giveItems + 1] = (it.name or "?") .. "x" .. (it.count or 1) end
        local links = BRL.Payments:LinksForTrade(tr.id)
        local auctionIds, settleIds = {}, {}
        for _, a in ipairs(links.awards) do
            local aw = DB:Get("awards", a.awardId)
            auctionIds[#auctionIds + 1] = aw and aw.auctionId or a.awardId
        end
        for _, p in ipairs(links.payouts) do
            local ob = DB:Get("payouts", p.obligationId)
            settleIds[#settleIds + 1] = ob and ob.settlementId or "?"
        end
        lines[#lines + 1] = table.concat({
            csv(tr.id), csv(U.FormatDate(tr.at)), csv(U.FormatClock(tr.at)), csv(tr.partnerName), csv(tr.partnerKey),
            csv(eff.received), csv(eff.given), csv(table.concat(recvItems, ";")), csv(table.concat(giveItems, ";")),
            csv(self:StatusLabel(tr)), csv(tr.verification), csv(self:PurposeLabel(tr.purpose)),
            csv(table.concat(auctionIds, ";")), csv(table.concat(settleIds, ";")), csv(tr.source == "manual" and "수동" or (tr.source == "self" and "본인 지급" or "자동")), csv(tr.note),
        }, ",")
    end
    return table.concat(lines, "\n")
end
