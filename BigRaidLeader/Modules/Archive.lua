-- BIG RAID LEADER - 세션 보관 (아카이브)
-- 오래된 공격대 세션의 기록(경매/입찰/낙찰/거래/장부/정산/분배/보고서/전리품/진행)을
-- 하나의 직렬화 문자열 + 체크섬으로 묶어 보관한다. 보관된 기록은 목록/계산에서 빠지므로
-- 저장 파일이 가벼워지고 화면이 빨라진다. 언제든 원래 ID 그대로 복원할 수 있다.
-- 다른 세션과 연결된 기록(교차 연결)이 있거나 미수금/미지급이 남은 세션은 보관하지 않는다.
local _, BRL = ...
local U, DB, Money = BRL.Util, BRL.DB, BRL.Money

local Archive = BRL:NewModule("Archive")
BRL.Archive = Archive

local function store()
    BRL.db.archives = BRL.db.archives or {}
    return BRL.db.archives
end

function Archive:List()
    local out = {}
    for _, a in pairs(store()) do out[#out + 1] = a end
    table.sort(out, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
    return out
end

function Archive:Get(sessionId) return store()[sessionId] end

-- 세션에 속한 레코드 수집. 반환: records{table={id=rec}}, problems{문자열}
function Archive:Collect(sessionId)
    local records, problems = {}, {}
    local function put(name, rec)
        records[name] = records[name] or {}
        records[name][rec.id] = rec
    end
    local function has(name, id) return records[name] and records[name][id] ~= nil end
    local session = DB:Get("sessions", sessionId)
    if not session then return nil, { "세션 없음" } end
    put("sessions", session)
    for _, name in ipairs({ "auctions", "awards", "trades", "ledger", "settlements", "reports", "lootRecords" }) do
        for _, rec in pairs(DB:T(name)) do
            if rec.sessionId == sessionId then put(name, rec) end
        end
    end
    for _, bid in pairs(DB:T("bids")) do
        if has("auctions", bid.auctionId) then put("bids", bid) end
    end
    for _, ob in pairs(DB:T("payouts")) do
        if has("settlements", ob.settlementId) then put("payouts", ob) end
    end
    -- 연결 기록: 양쪽 끝이 모두 이 세션 안에 있어야 함
    for _, a in pairs(DB:T("auctionAllocations")) do
        local inAward = has("awards", a.awardId)
        local inTrade = a.tradeId == nil or has("trades", a.tradeId)
        if inAward and inTrade then
            put("auctionAllocations", a)
        elseif inAward or (a.tradeId and has("trades", a.tradeId)) then
            -- 취소된 연결이라도 한쪽만 보관하면 기록이 깨지므로 세션 보관을 보류
            problems[#problems + 1] = "다른 세션 거래와 연결된 수금 기록 (" .. a.id .. ")"
        end
    end
    for _, a in pairs(DB:T("payoutAllocations")) do
        local inOb = has("payouts", a.obligationId)
        local inTrade = a.tradeId == nil or has("trades", a.tradeId)
        if inOb and inTrade then
            put("payoutAllocations", a)
        elseif inOb or (a.tradeId and has("trades", a.tradeId)) then
            problems[#problems + 1] = "다른 세션 거래와 연결된 분배 지급 (" .. a.id .. ")"
        end
    end
    for _, e in pairs(DB:T("ledger")) do
        if e.tradeId then
            local inLedger, inTrade = has("ledger", e.id), has("trades", e.tradeId)
            if inLedger ~= inTrade then problems[#problems + 1] = "다른 세션과 걸친 장부 항목 (" .. e.id .. ")" end
        end
    end
    return records, problems
end

-- 보관 가능 여부. 반환: ok, 사유
function Archive:CanArchive(sessionId, opts)
    opts = opts or {}
    local s = DB:Get("sessions", sessionId)
    if not s then return false, "세션 없음" end
    if store()[sessionId] then return false, "이미 보관됨" end
    if BRL.db.activeSessionId == sessionId then return false, "현재 활성 세션은 보관할 수 없습니다" end
    if s.owner and s.owner ~= BRL.playerKey then return false, "다른 캐릭터가 만든 세션입니다" end
    if s.status ~= "closed" and not opts.allowOpen then return false, "종료되지 않은 세션입니다 (먼저 세션 종료)" end
    local active = BRL.Auctions:GetActive()
    if active and active.sessionId == sessionId then return false, "진행 중인 경매가 있습니다" end
    local cur = BRL.TradeTracker:GetCurrent()
    if cur then return false, "거래가 진행 중입니다" end
    if not opts.force then
        local sum = BRL.Ledger:Summary(sessionId)
        if sum.outstanding > 0 then return false, "미수금이 남아 있습니다 (" .. Money.Format(sum.outstanding) .. ")" end
        local st = BRL.Settlement:ForSession(sessionId)
        if st and st.status ~= "draft" then
            local pay = BRL.Settlement:PaymentState(st.id)
            if pay.unpaid > 0 then return false, "분배 미지급이 남아 있습니다 (" .. Money.Format(pay.unpaid) .. ")" end
        end
    end
    local _, problems = self:Collect(sessionId)
    if #problems > 0 then return false, "교차 연결: " .. problems[1] .. (#problems > 1 and (" 외 " .. (#problems - 1) .. "건") or "") end
    return true
end

-- 보관 목록 표시용 요약 (구매자 기록 포함: 보관 후에도 구매자 통계에 반영)
local function summarize(records)
    local sum = { awarded = 0, total = 0, trades = 0, buyers = {} }
    for _, aw in pairs(records.awards or {}) do
        if aw.status == "active" then
            sum.awarded = sum.awarded + 1
            sum.total = sum.total + (aw.amount or 0)
            local b = sum.buyers[aw.winnerKey]
            if not b then
                b = { name = aw.winnerName, count = 0, total = 0, items = {} }
                sum.buyers[aw.winnerKey] = b
            end
            b.count = b.count + 1
            b.total = b.total + (aw.amount or 0)
            b.items[#b.items + 1] = { name = U.StripColors(U.ItemNameFromLink(aw.itemLink) or aw.itemName or "?"), amount = aw.amount, at = aw.awardedAt }
        end
    end
    for _ in pairs(records.trades or {}) do sum.trades = sum.trades + 1 end
    for _, st in pairs(records.settlements or {}) do
        if st.result then
            sum.distributed = st.result.distributed
            sum.headcount = st.result.headcount
            sum.perPerson = st.result.perPerson
        end
        sum.settlement = st.status
    end
    return sum
end

function Archive:ArchiveSession(sessionId, opts)
    if not BRL.Perm:Require("finance.edit") then return nil, "권한 없음" end
    local ok, why = self:CanArchive(sessionId, opts)
    if not ok then return nil, why end
    local records = self:Collect(sessionId)
    local session = records.sessions[sessionId]
    local progress = BRL.db.progress and BRL.db.progress[sessionId]
    local payload = BRL.Serializer.Serialize({ version = BRL.VERSION, schema = DB.SCHEMA_VERSION, records = records, progress = progress })
    local counts, n = {}, 0
    for name, t in pairs(records) do
        counts[name] = U.Count(t)
        n = n + counts[name]
    end
    local entry = {
        id = sessionId, name = session.name, raidKey = session.raidKey, startedAt = session.startedAt, closedAt = session.closedAt,
        archivedAt = U.Now(), counts = counts, recordCount = n, size = #payload, checksum = U.Checksum(payload), data = payload,
        summary = summarize(records), version = BRL.VERSION, schema = DB.SCHEMA_VERSION,
    }
    -- 직렬화 결과 검증 후에만 원본 제거
    local back = BRL.Serializer.Deserialize(payload, 16 * 1024 * 1024)
    if type(back) ~= "table" or type(back.records) ~= "table" then return nil, "직렬화 검증 실패 - 보관 중단" end
    store()[sessionId] = entry
    for name, t in pairs(records) do
        local live = DB:T(name)
        for id in pairs(t) do live[id] = nil end
    end
    if records.trades then
        local keep = {}
        for _, id in ipairs(BRL.db.tradeOrder or {}) do if not records.trades[id] then keep[#keep + 1] = id end end
        BRL.db.tradeOrder = keep
    end
    if BRL.db.progress then BRL.db.progress[sessionId] = nil end
    DB:Audit("archive.create", "session", sessionId, { records = n, size = entry.size })
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "archive")
    return entry
end

function Archive:Verify(sessionId)
    local a = store()[sessionId]
    if not a then return false, "보관 기록 없음" end
    if U.Checksum(a.data or "") ~= a.checksum then return false, "체크섬 불일치" end
    local obj, err = BRL.Serializer.Deserialize(a.data, 16 * 1024 * 1024)
    if type(obj) ~= "table" or type(obj.records) ~= "table" then return false, err or "구조 오류" end
    return true, obj
end

function Archive:Restore(sessionId)
    if not BRL.Perm:Require("finance.edit") then return false, "권한 없음" end
    local ok, obj = self:Verify(sessionId)
    if not ok then return false, obj end
    -- ID 충돌 검사 (복원은 원래 ID 그대로)
    for name, t in pairs(obj.records) do
        if not DB.TABLES[name] then return false, "알 수 없는 테이블: " .. tostring(name) end
        local live = DB:T(name)
        for id in pairs(t) do
            if live[id] then return false, "ID 충돌로 복원 중단: " .. name .. " " .. tostring(id) end
        end
    end
    local restoredTrades = {}
    for name, t in pairs(obj.records) do
        local live = DB:T(name)
        for id, rec in pairs(t) do
            live[id] = rec
            if name == "trades" then restoredTrades[#restoredTrades + 1] = rec end
        end
    end
    if #restoredTrades > 0 then
        local order = BRL.db.tradeOrder or {}
        for _, tr in ipairs(restoredTrades) do order[#order + 1] = tr.id end
        local trades = DB:T("trades")
        table.sort(order, function(a, b)
            local ta, tb = trades[a], trades[b]
            local xa, xb = ta and ta.at or 0, tb and tb.at or 0
            if xa ~= xb then return xa < xb end
            return a < b
        end)
        BRL.db.tradeOrder = order
    end
    if obj.progress then
        BRL.db.progress = BRL.db.progress or {}
        BRL.db.progress[sessionId] = obj.progress
    end
    store()[sessionId] = nil
    DB:Audit("archive.restore", "session", sessionId, {})
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "archive")
    return true
end

-- 보관 기록 완전 삭제 (되돌릴 수 없음 - UI 에서 확인 후 호출)
function Archive:Delete(sessionId)
    if not BRL.Perm:Require("finance.edit") then return false end
    if not store()[sessionId] then return false end
    store()[sessionId] = nil
    DB:Audit("archive.delete", "session", sessionId, {})
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "archive")
    return true
end

-- 보관 기록 내보내기 문자열
function Archive:Export(sessionId)
    local a = store()[sessionId]
    if not a then return nil end
    return BRL.Serializer.Export("archive", a)
end

-- N일 이상 지난 종료 세션 일괄 보관. 반환: 보관 수, 건너뛴 목록{name, reason}
function Archive:Candidates(days)
    days = days or BRL.acct.archive.days or 30
    local limit = U.Now() - days * 86400
    local out = {}
    for _, s in pairs(DB:T("sessions")) do
        local t = s.closedAt or s.startedAt or 0
        if s.status == "closed" and t <= limit and BRL.db.activeSessionId ~= s.id then out[#out + 1] = s end
    end
    table.sort(out, function(a, b) return (a.startedAt or 0) < (b.startedAt or 0) end)
    return out
end

function Archive:ArchiveOld(days)
    if not BRL.Perm:Require("finance.edit") then return 0, {} end
    BRL.Migration:CreateBackup("세션 보관 전 자동 백업")
    local done, skipped = 0, {}
    for _, s in ipairs(self:Candidates(days)) do
        local ok, why = self:ArchiveSession(s.id)
        if ok then done = done + 1 else skipped[#skipped + 1] = { name = s.name, reason = why } end
    end
    return done, skipped
end

-- 접속 시 자동 보관 (설정에서 켠 경우에만, 그룹 밖에서만)
function Archive:OnEnable()
    if not (BRL.acct.archive and BRL.acct.archive.auto) then return end
    BRL.API.After(10, function()
        if BRL.API.IsInGroup() then return end
        local n = #self:Candidates()
        if n == 0 then return end
        local done, skipped = self:ArchiveOld()
        if done > 0 or #skipped > 0 then
            BRL:Print("오래된 세션 %d개를 보관했습니다%s.", done, #skipped > 0 and (" (보관 불가 " .. #skipped .. "개)") or "")
        end
    end)
end
