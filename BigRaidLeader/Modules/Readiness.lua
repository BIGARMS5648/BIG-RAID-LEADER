-- BIG RAID LEADER - 공격대 준비 확인
-- API로 확인할 수 없는 항목(마법부여, 저항 장비, 시약 등)은 수동 확인 대상으로 표시한다.
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Ready = BRL:NewModule("Readiness")

Ready.check = { active = false, results = {}, startedAt = nil }

local function changed() BRL.Events:Fire(BRL.Events.MSG.READY_CHANGED) end

function Ready:OnEnable()
    BRL.Events:Register("READY_CHECK", self, "OnReadyCheck")
    BRL.Events:Register("READY_CHECK_CONFIRM", self, "OnReadyConfirm")
    BRL.Events:Register("READY_CHECK_FINISHED", self, "OnReadyFinished")
end

function Ready:Start()
    if not BRL.Perm:Require("raid.command") then return false end
    if not API.IsInGroup() then BRL:Print("파티/공격대에서만 준비 확인을 할 수 있습니다.") return false end
    return API.DoReadyCheck()
end

function Ready:OnReadyCheck(_, initiator, timeLeft)
    self.check = { active = true, results = {}, startedAt = U.Now(), initiator = API.Safe(initiator, nil), timeLeft = API.Safe(timeLeft, 30) }
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        self.check.results[m.key] = m.online and "waiting" or "offline"
    end
    local leaderKey = self.check.initiator and API.NormalizeName(self.check.initiator)
    if leaderKey then self.check.results[leaderKey] = "ready" end
    changed()
end

function Ready:OnReadyConfirm(_, unit, isReady)
    local key = API.UnitKey(unit)
    if not key then return end
    if API.IsSecret(isReady) then
        self.check.results[key] = "unknown"
    else
        self.check.results[key] = isReady and "ready" or "notready"
    end
    changed()
end

function Ready:OnReadyFinished()
    for key, st in pairs(self.check.results) do
        if st == "waiting" then self.check.results[key] = "noresponse" end
    end
    self.check.active = false
    self.check.finishedAt = U.Now()
    changed()
end

local STATUS_LABEL = {
    ready = "준비 완료", notready = "준비 안 됨", waiting = "응답 대기", noresponse = "미응답",
    offline = "오프라인", unknown = "확인 불가",
}
Ready.STATUS_LABEL = STATUS_LABEL

-- 공대원별 상태 행
function Ready:Rows()
    local rows = {}
    local myZone = API.GetCurrentZone()
    local minDur = BRL.acct.readiness.minDurability or 50
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        local row = { member = m, key = m.key }
        row.ready = self.check.results[m.key]
        if not m.online then row.ready = "offline" end
        row.dead = m.dead
        row.inInstance = (m.zone == nil) or (myZone ~= nil and m.zone == myZone)
        -- 내구도는 게임 API로 본인 것만 확인 가능
        if m.key == BRL.playerKey then row.durability = API.GetOwnDurability() end
        row.lowDurability = row.durability ~= nil and row.durability < minDur
        rows[#rows + 1] = row
    end
    return rows
end

function Ready:Summary()
    local s = { ready = 0, notready = 0, noresponse = 0, waiting = 0, offline = 0, dead = 0, absent = 0, lowDurability = 0, total = 0 }
    for _, row in ipairs(self:Rows()) do
        s.total = s.total + 1
        local st = row.ready
        if st and s[st] then s[st] = s[st] + 1 end
        if row.dead then s.dead = s.dead + 1 end
        if not row.inInstance then s.absent = s.absent + 1 end
        if row.lowDurability then s.lowDurability = s.lowDurability + 1 end
    end
    s.active = self.check.active
    s.checked = self.check.startedAt ~= nil
    return s
end

function Ready:OutputLines()
    local groups = { notready = {}, noresponse = {}, offline = {}, dead = {}, absent = {}, lowDurability = {} }
    for _, row in ipairs(self:Rows()) do
        local n = row.member.short
        if row.ready == "notready" then table.insert(groups.notready, n) end
        if row.ready == "noresponse" then table.insert(groups.noresponse, n) end
        if row.ready == "offline" then table.insert(groups.offline, n) end
        if row.dead then table.insert(groups.dead, n) end
        if not row.inInstance then table.insert(groups.absent, n) end
        if row.lowDurability then table.insert(groups.lowDurability, n) end
    end
    local lines = { "[BIG RAID LEADER 준비 상태]" }
    local labels = { notready = "준비 안 됨", noresponse = "미응답", offline = "오프라인", dead = "사망", absent = "인스턴스 미입장", lowDurability = "내구도 낮음" }
    for _, k in ipairs({ "notready", "noresponse", "offline", "dead", "absent", "lowDurability" }) do
        if #groups[k] > 0 then lines[#lines + 1] = labels[k] .. ": " .. table.concat(groups[k], ", ") end
    end
    if #lines == 1 then lines[#lines + 1] = "전원 준비 완료" end
    return lines
end
