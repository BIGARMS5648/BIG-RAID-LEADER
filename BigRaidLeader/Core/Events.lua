-- BIG RAID LEADER - 이벤트 시스템
--  * 게임 이벤트: 하나의 프레임에서 수신 후 등록된 핸들러로 분배 (핸들러별 오류 격리)
--  * 내부 메시지 버스: 모듈 간 느슨한 결합 (UI 갱신 등)
local _, BRL = ...

local Events = {}
BRL.Events = Events

Events.handlers = {}      -- event -> { {owner, fn}, ... }
Events.messages = {}      -- message -> { {owner, fn}, ... }
Events.unsupported = {}   -- event -> true (클라이언트가 모르는 이벤트)
Events.registered = {}

local frame = CreateFrame("Frame", "BigRaidLeaderEventFrame")
Events.frame = frame

local function dispatch(list, name, ...)
    if not list then return end
    -- 반복 중 등록/해제 안전을 위해 복사
    local copy = {}
    for i, h in ipairs(list) do copy[i] = h end
    for _, h in ipairs(copy) do
        BRL.SafeCall(name, h.fn, h.owner, ...)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(Events.handlers[event], event, event, ...)
end)

-- 게임 이벤트 등록. handler(owner, event, ...)
function Events:Register(event, owner, handler)
    if type(handler) == "string" then
        local method = handler
        handler = function(o, ...) return o[method](o, ...) end
    end
    handler = handler or function(o, ...) return o[event](o, ...) end
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], { owner = owner, fn = handler })
    if not self.registered[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if ok then
            self.registered[event] = true
        else
            self.unsupported[event] = true
            BRL:Debug("지원되지 않는 이벤트: " .. event)
        end
    end
    return not self.unsupported[event]
end

function Events:Unregister(event, owner)
    local list = self.handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then table.remove(list, i) end
    end
    if #list == 0 and self.registered[event] then
        pcall(frame.UnregisterEvent, frame, event)
        self.registered[event] = nil
    end
end

function Events:IsSupported(event)
    return not self.unsupported[event]
end

-- 내부 메시지
function Events:On(message, owner, fn)
    self.messages[message] = self.messages[message] or {}
    table.insert(self.messages[message], { owner = owner, fn = fn })
end

function Events:Off(message, owner)
    local list = self.messages[message]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then table.remove(list, i) end
    end
end

function Events:Fire(message, ...)
    dispatch(self.messages[message], message, ...)
    if message ~= "ANY" then dispatch(self.messages["ANY"], "ANY", message, ...) end
end

-- 테스트/시뮬레이션용: 게임 이벤트를 직접 주입
function Events:Inject(event, ...)
    dispatch(self.handlers[event], event, event, ...)
end

-- 메시지 이름
Events.MSG = {
    DATA_CHANGED = "BRL_DATA_CHANGED",           -- (domain)
    ROSTER_CHANGED = "BRL_ROSTER_CHANGED",
    ROLE_CHANGED = "BRL_ROLE_CHANGED",            -- 내 권한 변경
    TRADE_RECORDED = "BRL_TRADE_RECORDED",        -- (trade)
    TRADE_STATE = "BRL_TRADE_STATE",              -- 진행 중 거래 상태 변경
    AUCTION_CHANGED = "BRL_AUCTION_CHANGED",
    AUCTION_TICK = "BRL_AUCTION_TICK",
    LEDGER_CHANGED = "BRL_LEDGER_CHANGED",
    SETTLEMENT_CHANGED = "BRL_SETTLEMENT_CHANGED",
    SESSION_CHANGED = "BRL_SESSION_CHANGED",
    READY_CHANGED = "BRL_READY_CHANGED",
    PROGRESS_CHANGED = "BRL_PROGRESS_CHANGED",
    COMBAT_CHANGED = "BRL_COMBAT_CHANGED",
    SYNC_RECEIVED = "BRL_SYNC_RECEIVED",
    SETTINGS_CHANGED = "BRL_SETTINGS_CHANGED",
}
