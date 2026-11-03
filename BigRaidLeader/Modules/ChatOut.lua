-- BIG RAID LEADER - 채팅 출력 (대기열 / 속도 제한 / 채팅 잠금 대응 / 255바이트 분할)
-- 자동 채팅은 공격대/파티/귓속말/공격대 경보만 사용한다.
-- 공개 채널·일반·외치기는 사용자의 버튼 클릭 시점에 SendNow 로만 전송한다 (하드웨어 이벤트 필요).
local _, BRL = ...
local U, API, L = BRL.Util, BRL.API, BRL.L

local C = BRL:NewModule("ChatOut")

C.queue = {}
C.INTERVAL = 0.35
C.MAX_BYTES = 250
C.lastSend = 0
C.lockdownNotified = false

local QUEUEABLE = { RAID = true, PARTY = true, RAID_WARNING = true, WHISPER = true, GUILD = true, OFFICER = true, INSTANCE_CHAT = true }
C.QUEUEABLE = QUEUEABLE

function C:OnEnable()
    BRL.Events:Register("ADDON_RESTRICTION_STATE_CHANGED", self, function() self:Drain() end)
    BRL.Events:Register("PLAYER_REGEN_ENABLED", self, function() self:Drain() end)
    BRL.Events:Register("ENCOUNTER_END", self, function() API.After(1, function() self:Drain() end) end)
end

local function defaultGroupChannel()
    if API.IsInRaid() then return "RAID" end
    if API.IsInGroup() then return "PARTY" end
    return nil
end
C.DefaultGroupChannel = defaultGroupChannel

-- 대기열 전송 (자동 메시지용). 긴 메시지는 분할.
function C:Send(text, chatType, target)
    if not text or text == "" then return false end
    chatType = chatType or defaultGroupChannel()
    if not chatType then
        BRL:Print(text)
        return false, "nogroup"
    end
    if not QUEUEABLE[chatType] then
        return false, "requires_click"
    end
    for _, part in ipairs(U.SplitMessage(U.SanitizeChat(text), self.MAX_BYTES)) do
        self.queue[#self.queue + 1] = { text = part, chatType = chatType, target = target }
    end
    self:Drain()
    return true
end

function C:SendLines(lines, chatType, target)
    for _, line in ipairs(lines or {}) do self:Send(line, chatType, target) end
end

-- 즉시 전송 (버튼 클릭 핸들러에서 직접 호출: CHANNEL/SAY/YELL 가능)
function C:SendNow(text, chatType, target)
    local parts = U.SplitMessage(U.SanitizeChat(text), self.MAX_BYTES)
    for _, part in ipairs(parts) do
        local ok, why = API.SendChatRaw(part, chatType, target)
        if not ok then
            if why == "lockdown" then BRL:Print(L.CHAT_LOCKDOWN) else BRL:Print("메시지 전송 실패: %s", tostring(why)) end
            return false, why
        end
    end
    return true
end

function C:Drain()
    if #self.queue == 0 then return end
    if API.InChatLockdown() then
        if not self.lockdownNotified then
            self.lockdownNotified = true
            BRL:Print(L.CHAT_LOCKDOWN)
        end
        API.After(2, function() self:Drain() end)
        return
    end
    self.lockdownNotified = false
    local now = U.Clock()
    if now - self.lastSend < self.INTERVAL then
        self:Schedule()
        return
    end
    local item = table.remove(self.queue, 1)
    if item then
        local ok, why = API.SendChatRaw(item.text, item.chatType, item.target)
        self.lastSend = now
        if not ok then
            if why == "lockdown" then
                table.insert(self.queue, 1, item)
            elseif why == "nogroup" then
                BRL:Print(item.text)
            else
                BRL:Debug("채팅 전송 실패: " .. tostring(why))
            end
        end
    end
    if #self.queue > 0 then self:Schedule() end
end

-- 대기열 소진 예약 (예약 콜백 유실 대비: 일정 시간이 지나면 재예약 허용)
function C:Schedule()
    local now = U.Clock()
    if self.scheduled and (now - (self.scheduledAt or 0)) < 2 then return end
    self.scheduled = true
    self.scheduledAt = now
    API.After(self.INTERVAL, function() self.scheduled = false self:Drain() end)
end

function C:Clear()
    self.queue = {}
end

-- 공격대 경보(가능하면) 또는 공격대/파티
function C:Announce(text)
    local ch = BRL.acct.auction.announceChannel or "RAID_WARNING"
    if ch == "RAID_WARNING" and not (API.IsLeader() or API.IsAssistant()) then ch = nil end
    return self:Send(text, ch)
end
