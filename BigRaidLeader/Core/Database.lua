-- BIG RAID LEADER - SavedVariables (BigRaidLeaderDB)
-- 계정 공통 설정(account), 캐릭터별 설정(characters[키]), 레코드 테이블, 감사 로그.
local _, BRL = ...
local U = BRL.Util

local DB = {}
BRL.DB = DB

DB.SCHEMA_VERSION = 2

-- 레코드 테이블 이름 -> ID 접두사
DB.TABLES = {
    sessions = "RS",            -- RaidSession
    auctions = "AU",            -- Auction
    bids = "BD",                -- Bid
    awards = "AW",              -- Award
    trades = "TR",              -- TradeTransaction (+ TradeItem 목록 내장)
    ledger = "LE",              -- LedgerEntry
    auctionAllocations = "AP",  -- AuctionPaymentAllocation
    payouts = "PO",             -- PayoutObligation
    payoutAllocations = "PA",   -- PayoutAllocation
    settlements = "ST",         -- Settlement
    reports = "RP",             -- SettlementReport
    lootRecords = "LR",         -- 기타 전리품 분배 기록
}

DB.ACCOUNT_DEFAULTS = {
    debug = false,
    minimap = { hide = false, angle = 215 },
    trade = {
        autoRecord = true,          -- 거래 자동 기록
        notifyScreen = true,        -- 화면 알림
        notifyChat = true,          -- 채팅창 기록 출력
        whisperPartner = false,     -- 거래 결과 귓속말 (기본 비활성)
        completionPopup = true,     -- 거래 직후 목적 분류 창
        suggestLinks = true,        -- 경매/분배 연결 제안
        closeGraceSeconds = 3,      -- 거래 창 닫힘 후 완료 신호 대기 시간
        assistPanel = true,         -- 거래 창 옆 정보 패널 (미납 낙찰금/미지급 분배금 비교)
    },
    auction = {
        defaultDuration = 30,
        startPrice = 100 * 10000,
        minIncrement = 50 * 10000,
        chatBids = true,
        bidChannels = { RAID = true, RAID_LEADER = true, RAID_WARNING = false, PARTY = true, PARTY_LEADER = true, WHISPER = true },
        requireGroupMember = true,
        announceChannel = "RAID_WARNING",
        announceBids = true,
        countdownAnnounce = true,
        countdownFrom = 5,          -- 카운트 초 (수동 카운트 / 마감 카운트다운)
        cancelCountOnBid = true,    -- 카운트 중 새 입찰이 들어오면 카운트 취소
        antiSnipeSeconds = 0,       -- 막판 입찰 시 연장(초), 0=사용 안 함
        autoConfirmAward = false,   -- 종료 시 자동 낙찰 확정 (기본: 공대장 확인)
        autoNext = false,           -- 연속 경매: 낙찰/유찰 후 다음 대기 경매 자동 시작
        autoNextDelay = 8,          -- 연속 경매 대기 초
        bidLimitOutstanding = 0,    -- 미납 낙찰금이 이 금액 이상이면 입찰 제한 (코퍼, 0=사용 안 함)
        policyAcknowledged = false,
    },
    settlement = {
        rounding = 1,               -- 1=코퍼, 100=실버, 10000=골드
        remainderMode = "keep",     -- keep(잔돈 보관) | carry(다음 정산 이월) | leader(공대장 지급)
    },
    chat = { reportChannel = "RAID" },
    archive = { days = 30, auto = false },  -- 세션 보관: N일 지난 종료 세션, 접속 시 자동 보관(기본 끔)
    buffs = { campReplacesClassBuff = true, expireWarnMinutes = 5, required = {} },
    readiness = { minDurability = 50 },
    command = { pullSeconds = 10, breakMinutes = 5 },
    composition = { excluded = {}, include = "approved", targets = {} },
    consumables = {
        requireFood = true,             -- 음식 버프 필수
        mainMode = "flask_or_elixir",   -- flask_or_elixir | flask | elixir | none
        minElixirs = 1,                 -- 비약 기준일 때 최소 비약 수
        checkClassBuffs = true,         -- 필수 직업 버프도 함께 점검
        expiringAsMissing = false,      -- 곧 만료되는 도핑도 누락으로 알림
        autoAnnounce = false,           -- 전투 준비 시 공격대 채팅 자동 공지
        withReadyCheck = false,         -- 전투 준비 시 준비 확인 함께 실행
    },
}

DB.CHAR_DEFAULTS = {
    ui = { scale = 1.0, width = 1080, height = 700, point = nil, lastPage = "dashboard" },
    carryover = 0,         -- 이월 잔돈 (코퍼)
    privateNotes = "",
}

DB.ROOT_DEFAULTS = {
    schemaVersion = DB.SCHEMA_VERSION,
    nextId = 0,
    account = {},
    characters = {},
    activeSessionId = nil,
    tradeOrder = {},
    activeTrade = nil,
    audit = {},
    raidOps = {
        groupTemplates = {}, groupPlan = nil, pinned = {},
        memberRoles = {}, assignments = {}, orders = {},
        markerTemplates = {}, notes = {}, savedCommands = {},
        recruitment = { templates = {}, current = nil, applicants = {} },
        readyManual = {}, campStatus = {}, buffProviders = {},
    },
    bossPlans = {},
    progress = {},
    loot = { dkp = { pools = { default = {} } }, epgp = { standings = {}, baseGP = 100 }, priorities = {} },
    backups = {},
    errorLog = {},
    archives = {},       -- 보관된 세션 (직렬화 문자열 + 체크섬)
    tradeTraces = {},    -- 최근 거래 이벤트 추적 (최대 10건)
}

local function ensureTables(db)
    for name in pairs(DB.TABLES) do
        if type(db[name]) ~= "table" then db[name] = {} end
    end
end

function DB:Init()
    if type(_G.BigRaidLeaderDB) ~= "table" then _G.BigRaidLeaderDB = {} end
    local db = _G.BigRaidLeaderDB
    local isNew = db.schemaVersion == nil and next(db) == nil
    U.ApplyDefaults(db, DB.ROOT_DEFAULTS)
    ensureTables(db)
    U.ApplyDefaults(db.account, DB.ACCOUNT_DEFAULTS)
    BRL.db = db
    BRL.acct = db.account

    local key = BRL.API.GetPlayerKey() or "Unknown"
    BRL.playerKey = key
    db.characters[key] = db.characters[key] or {}
    U.ApplyDefaults(db.characters[key], DB.CHAR_DEFAULTS)
    BRL.char = db.characters[key]

    if isNew then db.schemaVersion = DB.SCHEMA_VERSION end
    return db
end

-- 플레이어 키가 로그인 후에야 확정되는 경우 재바인딩
function DB:RebindCharacter()
    local key = BRL.API.GetPlayerKey()
    if key and key ~= BRL.playerKey then
        BRL.playerKey = key
        BRL.db.characters[key] = BRL.db.characters[key] or {}
        U.ApplyDefaults(BRL.db.characters[key], DB.CHAR_DEFAULTS)
        BRL.char = BRL.db.characters[key]
    end
end

function DB:T(name)
    local t = BRL.db[name]
    if not t then
        t = {}
        BRL.db[name] = t
    end
    return t
end

function DB:Get(name, id)
    if not id then return nil end
    return self:T(name)[id]
end

function DB:Insert(name, rec)
    local t = self:T(name)
    rec.id = rec.id or BRL.NewId(DB.TABLES[name] or "ID")
    -- 극히 드문 ID 충돌 방지
    while t[rec.id] and t[rec.id] ~= rec do rec.id = BRL.NewId(DB.TABLES[name] or "ID") end
    rec.createdAt = rec.createdAt or U.Now()
    rec.createdBy = rec.createdBy or BRL.playerKey
    t[rec.id] = rec
    return rec
end

-- 정렬된 목록. filter(rec) -> bool
function DB:List(name, filter, sortKey, desc)
    local out = {}
    for _, rec in pairs(self:T(name)) do
        if not filter or filter(rec) then out[#out + 1] = rec end
    end
    sortKey = sortKey or "createdAt"
    table.sort(out, function(a, b)
        local av, bv = a[sortKey] or 0, b[sortKey] or 0
        if av == bv then
            if desc then return tostring(a.id) > tostring(b.id) end
            return tostring(a.id) < tostring(b.id)
        end
        if desc then return av > bv end
        return av < bv
    end)
    return out
end

-- 수정 이력 기록 (레코드 내장)
function DB:AddHistory(rec, field, old, new, reason)
    rec.history = rec.history or {}
    table.insert(rec.history, {
        at = U.Now(), by = BRL.playerKey, field = field,
        old = U.DeepCopy(old), new = U.DeepCopy(new), reason = reason,
    })
    rec.updatedAt = U.Now()
end

-- 감사 로그 (AuditEvent)
function DB:Audit(action, entityType, entityId, details)
    local db = BRL.db
    if not db then return end
    local role = BRL.Perm and BRL.Perm:GetRole() or "?"
    local ev = {
        id = BRL.NewId("EV"), at = U.Now(), by = BRL.playerKey, role = role,
        action = action, entityType = entityType, entityId = entityId,
        details = details and U.DeepCopy(details) or nil,
    }
    table.insert(db.audit, ev)
    -- 감사 로그는 과도하게 커지면 오래된 비금융 항목부터 정리 (금융 항목은 보존)
    if #db.audit > 20000 then
        local kept = {}
        local drop = #db.audit - 15000
        for _, e in ipairs(db.audit) do
            local financial = e.entityType == "trade" or e.entityType == "award" or e.entityType == "ledger"
                or e.entityType == "settlement" or e.entityType == "allocation" or e.entityType == "payout"
            if drop > 0 and not financial then
                drop = drop - 1
            else
                kept[#kept + 1] = e
            end
        end
        db.audit = kept
    end
    return ev
end

function DB:AuditFor(entityId)
    local out = {}
    for _, e in ipairs(BRL.db.audit) do
        if e.entityId == entityId then out[#out + 1] = e end
    end
    return out
end

-- 설정 값 경로 접근 ("auction.defaultDuration")
function DB:GetSetting(path)
    local cur = BRL.acct
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end

function DB:SetSetting(path, value)
    local parts = U.Split(path, ".")
    local cur = BRL.acct
    for i = 1, #parts - 1 do
        cur[parts[i]] = cur[parts[i]] or {}
        cur = cur[parts[i]]
    end
    cur[parts[#parts]] = value
    BRL.Events:Fire(BRL.Events.MSG.SETTINGS_CHANGED, path, value)
end
