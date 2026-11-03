-- BIG RAID LEADER - 스키마 마이그레이션 / 무결성 검증 / 백업·복구
local _, BRL = ...
local U, Money = BRL.Util, BRL.Money

local M = {}
BRL.Migration = M

M.MAX_BACKUPS = 5

-- 마이그레이션: [대상 버전] = function(db)
M.steps = {
    -- v1 -> v2: 레코드 키/ID 정합성, 거래 레코드 기본 필드 보정
    [2] = function(db)
        for name in pairs(BRL.DB.TABLES) do
            local t = db[name]
            if type(t) == "table" then
                for key, rec in pairs(t) do
                    if type(rec) == "table" and rec.id == nil then rec.id = key end
                end
            end
        end
        for _, tr in pairs(db.trades or {}) do
            tr.history = tr.history or {}
            tr.purpose = tr.purpose or "unclassified"
            tr.source = tr.source or "auto"
        end
    end,
}

function M:Run(db)
    local from = tonumber(db.schemaVersion) or 1
    local target = BRL.DB.SCHEMA_VERSION
    if from > target then
        BRL:Print("|cffff5555경고|r: 저장 데이터가 더 최신 버전(%d)에서 생성되었습니다. 애드온을 업데이트하세요. 데이터는 수정하지 않습니다.", from)
        BRL.readOnlyData = true
        return false
    end
    if from == target then return true end
    -- 마이그레이션 전 자동 백업
    self:CreateBackup("마이그레이션 전 자동 백업 (v" .. from .. ")")
    for v = from + 1, target do
        local step = self.steps[v]
        if step then
            local ok, err = pcall(step, db)
            if not ok then
                BRL:Error("Migration v" .. v, err)
                BRL.readOnlyData = true
                return false
            end
        end
        db.schemaVersion = v
    end
    BRL:Print("저장 데이터를 v%d → v%d 로 업데이트했습니다.", from, target)
    return true
end

---------------------------------------------------------------------------
-- 무결성 검증
---------------------------------------------------------------------------
local function issue(list, severity, message, entity)
    list[#list + 1] = { severity = severity, message = message, entity = entity }
end

local MONEY_FIELDS = {
    trades = { "playerMoney", "targetMoney" },
    awards = { "amount" },
    auctionAllocations = { "amount" },
    payouts = { "amount" },
    payoutAllocations = { "amount" },
    ledger = { "amount" },
    bids = { "amount" },
}

function M:Validate(db)
    db = db or BRL.db
    local issues = {}
    for name in pairs(BRL.DB.TABLES) do
        local t = db[name]
        if type(t) ~= "table" then
            issue(issues, "error", "테이블 누락: " .. name)
        else
            for key, rec in pairs(t) do
                if type(rec) ~= "table" then
                    issue(issues, "error", name .. " 레코드 형식 오류", key)
                else
                    if rec.id ~= key then issue(issues, "error", name .. " ID 불일치", key) end
                    for _, f in ipairs(MONEY_FIELDS[name] or {}) do
                        local v = rec[f]
                        if v ~= nil and not Money.IsValid(v) then
                            issue(issues, "error", string.format("%s.%s 금액 오류(정수 코퍼 아님/음수): %s", name, f, tostring(v)), key)
                        end
                    end
                end
            end
        end
    end
    -- 거래 순서 목록
    local seen = {}
    for _, id in ipairs(db.tradeOrder or {}) do
        if seen[id] then issue(issues, "warn", "거래 순서 목록 중복", id) end
        seen[id] = true
        if not (db.trades or {})[id] then issue(issues, "warn", "거래 순서 목록에 없는 거래", id) end
    end
    for id in pairs(db.trades or {}) do
        if not seen[id] then issue(issues, "warn", "거래 순서 목록 누락", id) end
    end
    -- 수금 연결
    local perTrade = {}
    local pairSeen = {}
    for id, a in pairs(db.auctionAllocations or {}) do
        if not a.voided then
            local tr = db.trades[a.tradeId]
            if a.tradeId and not tr then issue(issues, "error", "수금 연결: 거래 없음", id) end
            if not db.awards[a.awardId] then issue(issues, "error", "수금 연결: 낙찰 기록 없음", id) end
            if a.tradeId then
                perTrade[a.tradeId] = (perTrade[a.tradeId] or 0) + (a.amount or 0)
                local pk = a.tradeId .. "|" .. tostring(a.awardId)
                if pairSeen[pk] then issue(issues, "error", "동일 거래-낙찰 중복 연결", id) end
                pairSeen[pk] = true
            end
        end
    end
    for tradeId, sum in pairs(perTrade) do
        local tr = db.trades[tradeId]
        if tr and BRL.TradeJournal then
            local received = BRL.TradeJournal:Effective(tr).received
            if sum > received then issue(issues, "error", "거래 받은 금액보다 큰 수금 연결", tradeId) end
        end
    end
    -- 지급 연결
    local perTradeOut = {}
    for id, a in pairs(db.payoutAllocations or {}) do
        if not a.voided then
            if not db.payouts[a.obligationId] then issue(issues, "error", "지급 연결: 분배 의무 없음", id) end
            if a.tradeId then
                if not db.trades[a.tradeId] then issue(issues, "error", "지급 연결: 거래 없음", id) end
                perTradeOut[a.tradeId] = (perTradeOut[a.tradeId] or 0) + (a.amount or 0)
            end
        end
    end
    for tradeId, sum in pairs(perTradeOut) do
        local tr = db.trades[tradeId]
        if tr and BRL.TradeJournal then
            local given = BRL.TradeJournal:Effective(tr).given
            if sum > given then issue(issues, "error", "거래 지급 금액보다 큰 분배 연결", tradeId) end
        end
    end
    return issues
end

---------------------------------------------------------------------------
-- 백업 / 복구
---------------------------------------------------------------------------
local EXCLUDE = { backups = true, errorLog = true }

function M:Snapshot(db)
    db = db or BRL.db
    local snap = {}
    for k, v in pairs(db) do
        if not EXCLUDE[k] then snap[k] = v end
    end
    return snap
end

function M:CreateBackup(label)
    local db = BRL.db
    if not db then return nil end
    local payload = BRL.Serializer.Serialize(self:Snapshot(db))
    local b = {
        at = U.Now(), label = label or "수동 백업", size = #payload,
        checksum = U.Checksum(payload), data = payload, schema = db.schemaVersion, version = BRL.VERSION,
    }
    db.backups = db.backups or {}
    table.insert(db.backups, 1, b)
    while #db.backups > self.MAX_BACKUPS do table.remove(db.backups) end
    BRL.DB:Audit("backup.create", "backup", nil, { label = b.label, size = b.size })
    return b
end

function M:VerifyBackup(index)
    local b = BRL.db.backups and BRL.db.backups[index]
    if not b then return false, "백업 없음" end
    if U.Checksum(b.data or "") ~= b.checksum then return false, "체크섬 불일치" end
    local obj, err = BRL.Serializer.Deserialize(b.data)
    if not obj then return false, err end
    local issues = self:Validate(setmetatable(obj, nil))
    local errors = 0
    for _, i in ipairs(issues) do if i.severity == "error" then errors = errors + 1 end end
    return errors == 0, errors == 0 and "정상" or (errors .. "개 무결성 오류"), issues
end

function M:RestoreBackup(index)
    local db = BRL.db
    local b = db.backups and db.backups[index]
    if not b then return false, "백업 없음" end
    if U.Checksum(b.data or "") ~= b.checksum then return false, "체크섬 불일치 - 복구 중단" end
    local obj, err = BRL.Serializer.Deserialize(b.data)
    if not obj then return false, err end
    local backups = db.backups
    -- 현재 상태를 안전 백업으로 보관
    self:CreateBackup("복구 직전 자동 백업")
    for k in pairs(db) do
        if not EXCLUDE[k] then db[k] = nil end
    end
    for k, v in pairs(obj) do db[k] = v end
    db.backups = backups
    BRL.DB:Init()
    self:Run(db)
    BRL.DB:Audit("backup.restore", "backup", nil, { label = b.label, at = b.at })
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "all")
    return true
end

-- 하루 1회 자동 백업
function M:AutoBackup()
    local db = BRL.db
    local last = db.backups and db.backups[1]
    if not last or (U.Now() - (last.at or 0)) > 20 * 3600 then
        self:CreateBackup("자동 백업")
    end
end
