-- BIG RAID LEADER - 현재 공대원 관리 (CurrentRaidMember)
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local R = BRL:NewModule("Roster")

R.members = {}
R.byKey = {}
R.lastCount = 0

-- 공격대 규모별 권장 역할 인원
R.ROLE_TARGETS = {
    [10] = { TANK = 2, HEALER = 2 },
    [20] = { TANK = 2, HEALER = 4 },
    [40] = { TANK = 3, HEALER = 8 },
}

function R:OnEnable()
    local function schedule()
        if self.pendingRefresh then return end
        self.pendingRefresh = true
        API.After(0.2, function() self.pendingRefresh = false self:Refresh() end)
    end
    BRL.Events:Register("GROUP_ROSTER_UPDATE", self, schedule)
    BRL.Events:Register("UNIT_CONNECTION", self, schedule)
    BRL.Events:Register("PLAYER_FLAGS_CHANGED", self, schedule)
    BRL.Events:Register("PLAYER_ENTERING_WORLD", self, schedule)
    BRL.Events:On(BRL.Events.MSG.ROLE_CHANGED, self, function() self:Refresh() end)
    self:Refresh()
end

function R:Refresh()
    local list = API.GetGroupRoster()
    if #list == 0 then
        -- 그룹이 아니면 본인만 표시 (사전 계획용)
        local key = BRL.playerKey
        local classLocal, class = API.UnitClass("player")
        list = { { key = key, name = key, short = API.ShortName(key), rank = 2, subgroup = 1, level = nil,
            classLocal = classLocal, class = class, online = true, dead = false, unit = "player", raidIndex = 0,
            isLeader = true, isAssistant = false, solo = true } }
    end
    local byKey = {}
    for _, m in ipairs(list) do
        m.role = BRL.Roles and BRL.Roles:GetMemberRole(m.key, m) or nil
        byKey[m.key] = m
    end
    local prev = self.lastCount
    self.members, self.byKey = list, byKey
    self.lastCount = #list
    BRL.Events:Fire(BRL.Events.MSG.ROSTER_CHANGED, #list, prev)
end

function R:GetMembers() return self.members end
function R:Get(key) return self.byKey[key] end
function R:IsMember(key) return self.byKey[key] ~= nil end

function R:Counts()
    local c = { total = #self.members, TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0, NONE = 0,
        online = 0, offline = 0, dead = 0, afk = 0, byGroup = {}, byClass = {} }
    for g = 1, 8 do c.byGroup[g] = 0 end
    for _, m in ipairs(self.members) do
        local role = m.role or "NONE"
        c[role] = (c[role] or 0) + 1
        if m.online then c.online = c.online + 1 else c.offline = c.offline + 1 end
        if m.dead then c.dead = c.dead + 1 end
        if m.afk then c.afk = c.afk + 1 end
        local g = m.subgroup or 1
        c.byGroup[g] = (c.byGroup[g] or 0) + 1
        if m.class then c.byClass[m.class] = (c.byClass[m.class] or 0) + 1 end
    end
    return c
end

function R:TargetSize()
    local s = BRL.Session and BRL.Session:GetActive()
    if s and s.size then return s.size end
    local n = #self.members
    if n <= 10 then return 10 elseif n <= 20 then return 20 end
    return 40
end

-- 부족한 역할 / 인원 경고
function R:Warnings(size)
    size = size or self:TargetSize()
    local c = self:Counts()
    local out = {}
    local target = self.ROLE_TARGETS[size] or self.ROLE_TARGETS[20]
    if c.TANK < target.TANK then out[#out + 1] = string.format("탱커 부족 (%d/%d)", c.TANK, target.TANK) end
    if c.HEALER < target.HEALER then out[#out + 1] = string.format("힐러 부족 (%d/%d)", c.HEALER, target.HEALER) end
    if c.total < size and not (self.members[1] and self.members[1].solo) then
        out[#out + 1] = string.format("공격대 인원 부족 (%d/%d)", c.total, size)
    end
    if c.NONE > 0 then out[#out + 1] = string.format("역할 미지정 %d명", c.NONE) end
    if c.offline > 0 then out[#out + 1] = string.format("오프라인 %d명", c.offline) end
    return out, c
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, MELEE = 3, RANGED = 4, NONE = 5 }

-- sortKey: name | class | role | group ; query: 이름 검색 ; filter: { role=, class=, group= }
function R:Sorted(sortKey, query, filter)
    local out = {}
    filter = filter or {}
    for _, m in ipairs(self.members) do
        local ok = U.MatchSearch(m.short or m.key, query)
        if ok and filter.role and (m.role or "NONE") ~= filter.role then ok = false end
        if ok and filter.class and m.class ~= filter.class then ok = false end
        if ok and filter.group and m.subgroup ~= filter.group then ok = false end
        if ok then out[#out + 1] = m end
    end
    local classOrder = {}
    for i, c in ipairs(BRL.Data.ClassOrder) do classOrder[c] = i end
    table.sort(out, function(a, b)
        local ka, kb
        if sortKey == "class" then ka, kb = classOrder[a.class or ""] or 99, classOrder[b.class or ""] or 99
        elseif sortKey == "role" then ka, kb = ROLE_ORDER[a.role or "NONE"], ROLE_ORDER[b.role or "NONE"]
        elseif sortKey == "group" then ka, kb = a.subgroup or 9, b.subgroup or 9
        else ka, kb = 0, 0 end
        if ka ~= kb then return ka < kb end
        return (a.short or a.key) < (b.short or b.key)
    end)
    return out
end

-- 파티 변경 (게임 파티 이동: 공대장/부공대장, 전투 중 불가)
function R:MoveToGroup(key, group)
    if not BRL.Perm:Require("raid.groups.apply") then return false end
    if not API.GuardCombat() then return false end
    local m = self.byKey[key]
    if not m or not m.raidIndex or m.raidIndex == 0 then return false, "공대원이 아닙니다" end
    if m.subgroup == group then return true end
    local c = self:Counts()
    if (c.byGroup[group] or 0) >= 5 then
        return false, group .. "파티가 가득 찼습니다. 파티 편성 화면에서 교체하세요."
    end
    return API.SetRaidSubgroup(m.raidIndex, group)
end
