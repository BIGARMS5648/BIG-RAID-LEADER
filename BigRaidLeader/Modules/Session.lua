-- BIG RAID LEADER - 공격대 세션 (RaidSession)
-- 경매·거래 연결·정산의 단위. 세션 소유자(생성 캐릭터)가 금융 장부의 최종 책임자.
local _, BRL = ...
local U, API, DB = BRL.Util, BRL.API, BRL.DB

local Session = BRL:NewModule("Session")

function Session:OnEnable()
    BRL.Events:Register("GROUP_ROSTER_UPDATE", self, function() self:TrackAttendance() end)
end

function Session:GetActive()
    local id = BRL.db.activeSessionId
    return id and DB:Get("sessions", id) or nil
end

function Session:Get(id)
    return DB:Get("sessions", id)
end

function Session:List()
    return DB:List("sessions", nil, "createdAt", true)
end

-- 새 세션 생성. opts: name, raidKey, size
function Session:Create(opts)
    if not BRL.Perm:Require("finance.edit") then return nil end
    opts = opts or {}
    local raidName = opts.raidKey and BRL.Data.Raids[opts.raidKey] and BRL.Data.Raids[opts.raidKey].name
    local s = DB:Insert("sessions", {
        name = (opts.name and opts.name ~= "") and opts.name or ((raidName or "공격대") .. " " .. U.FormatDate(U.Now())),
        raidKey = opts.raidKey,
        size = opts.size or (opts.raidKey and BRL.Data.Raids[opts.raidKey] and BRL.Data.Raids[opts.raidKey].size) or 20,
        owner = BRL.playerKey,
        status = "open",
        attendance = {},
        locked = false,
        startedAt = U.Now(),
    })
    BRL.db.activeSessionId = s.id
    DB:Audit("session.create", "session", s.id, { name = s.name })
    self:TrackAttendance()
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, s.id)
    return s
end

-- 활성 세션이 없으면 생성
function Session:Ensure(opts)
    local s = self:GetActive()
    if s and s.status == "open" then return s end
    return self:Create(opts)
end

function Session:SetActive(id)
    if id and not self:Get(id) then return false end
    BRL.db.activeSessionId = id
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, id)
    return true
end

function Session:Rename(id, name)
    local s = self:Get(id)
    if not s or not BRL.Perm:RequireSession(s) then return false end
    DB:AddHistory(s, "name", s.name, name)
    s.name = name
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, id)
    return true
end

function Session:SetRaid(id, raidKey)
    local s = self:Get(id)
    if not s or not BRL.Perm:RequireSession(s) then return false end
    s.raidKey = raidKey
    local raid = BRL.Data.Raids[raidKey]
    if raid then s.size = raid.size end
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, id)
    return true
end

function Session:Close(id)
    local s = self:Get(id)
    if not s or not BRL.Perm:RequireSession(s) then return false end
    s.status = "closed"
    s.closedAt = U.Now()
    DB:Audit("session.close", "session", s.id)
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, id)
    return true
end

function Session:Reopen(id)
    local s = self:Get(id)
    if not s then return false end
    if s.owner ~= BRL.playerKey then return false end
    s.status = "open"
    s.closedAt = nil
    DB:Audit("session.reopen", "session", s.id)
    BRL.Events:Fire(BRL.Events.MSG.SESSION_CHANGED, id)
    return true
end

-- 참가자 기록 (현재 그룹 구성원). 정산 분배 대상의 기본값이 된다.
function Session:TrackAttendance()
    local s = self:GetActive()
    if not s or s.status ~= "open" or s.owner ~= BRL.playerKey then return end
    local now = U.Now()
    for _, m in ipairs(API.GetGroupRoster()) do
        local a = s.attendance[m.key]
        if not a then
            a = { key = m.key, name = m.short, class = m.class, firstSeen = now }
            s.attendance[m.key] = a
        end
        a.lastSeen = now
        a.class = a.class or m.class
        a.subgroup = m.subgroup
        a.present = true
    end
    if not API.IsInGroup() then
        local me = BRL.playerKey
        if not s.attendance[me] then
            local _, class = API.UnitClass("player")
            s.attendance[me] = { key = me, name = API.ShortName(me), class = class, firstSeen = now, lastSeen = now, subgroup = 1 }
        end
    end
end

-- 수동 참가자 추가/제거
function Session:AddAttendee(id, key, info)
    local s = self:Get(id)
    if not s or not BRL.Perm:RequireSession(s) then return false end
    key = API.NormalizeName(key)
    if not key then return false end
    s.attendance[key] = s.attendance[key] or { key = key, firstSeen = U.Now() }
    local a = s.attendance[key]
    a.name = a.name or API.ShortName(key)
    a.class = (info and info.class) or a.class
    a.subgroup = (info and info.subgroup) or a.subgroup or 1
    a.lastSeen = U.Now()
    a.manual = true
    DB:Audit("session.attendee.add", "session", s.id, { key = key })
    return true
end

function Session:RemoveAttendee(id, key)
    local s = self:Get(id)
    if not s or not BRL.Perm:RequireSession(s) then return false end
    s.attendance[key] = nil
    DB:Audit("session.attendee.remove", "session", s.id, { key = key })
    return true
end

function Session:Attendees(id)
    local s = self:Get(id)
    if not s then return {} end
    return U.Values(s.attendance, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
end

function Session:CanEdit(id)
    return BRL.Perm:CanEditSession(self:Get(id))
end
