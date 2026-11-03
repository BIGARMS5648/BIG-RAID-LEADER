-- BIG RAID LEADER - 역할 및 전술 임무 배정 (RoleAssignment)
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Roles = BRL:NewModule("Roles")

Roles.DUTIES = {
    { key = "MAIN_TANK", name = "메인 탱커", group = "tank" },
    { key = "OFF_TANK", name = "보조 탱커", group = "tank" },
    { key = "EXTRA_TANK", name = "추가 탱커", group = "tank" },
    { key = "TANK_HEALER", name = "탱커 전담 힐러", group = "heal" },
    { key = "PARTY_HEALER", name = "파티 담당 힐러", group = "heal" },
    { key = "RAID_HEALER", name = "전체 치유 담당", group = "heal" },
    { key = "INTERRUPT", name = "차단 담당", group = "util" },
    { key = "DISPEL", name = "해제 담당", group = "util" },
    { key = "CC", name = "군중제어 담당", group = "util" },
    { key = "ADD_KILLER", name = "특정 몬스터 처리", group = "util" },
    { key = "MECHANIC", name = "보스 기믹 담당", group = "util" },
    { key = "PULLER", name = "풀링 담당", group = "util" },
    { key = "SPECIAL", name = "특수 기술 담당", group = "util" },
}
Roles.ORDERS = {
    { key = "INTERRUPT", name = "차단 순서" },
    { key = "DISPEL", name = "해제 순서" },
    { key = "TANKSWAP", name = "탱커 교대 순서" },
    { key = "COOLDOWN", name = "생존기 사용 순서" },
    { key = "MECHANIC", name = "특수 기믹 수행 순서" },
}
-- 동시에 맡기 어려운 임무 조합 (중복 배정 경고)
Roles.CONFLICTS = {
    { "MAIN_TANK", "OFF_TANK" }, { "MAIN_TANK", "TANK_HEALER" }, { "MAIN_TANK", "RAID_HEALER" },
    { "OFF_TANK", "TANK_HEALER" }, { "TANK_HEALER", "RAID_HEALER" }, { "MAIN_TANK", "PULLER" },
}

local function ops() return BRL.db.raidOps end
local function changed()
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "roles")
end

function Roles:DutyName(key)
    for _, d in ipairs(self.DUTIES) do if d.key == key then return d.name end end
    return key
end

function Roles:OrderName(key)
    for _, d in ipairs(self.ORDERS) do if d.key == key then return d.name end end
    return key
end

---------------------------------------------------------------------------
-- 전투 역할 (탱커/힐러/근접/원거리)
---------------------------------------------------------------------------
local MELEE_DPS = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true }

function Roles:GuessRole(member)
    local class = member and member.class
    local assigned = member and member.combatRole
    if assigned == "TANK" then return "TANK" end
    if assigned == "HEALER" then return "HEALER" end
    if assigned == "DAMAGER" then
        if class == "HUNTER" or class == "MAGE" or class == "WARLOCK" or class == "PRIEST" then return "RANGED" end
        return MELEE_DPS[class] and "MELEE" or "RANGED"
    end
    local c = class and BRL.Data.Classes[class]
    return c and c.defaultRole or nil
end

function Roles:GetMemberRole(key, member)
    local stored = ops().memberRoles[key]
    if stored then return stored end
    member = member or (BRL.Roster and BRL.Roster:Get(key))
    return self:GuessRole(member)
end

function Roles:IsRoleAssigned(key)
    return ops().memberRoles[key] ~= nil
end

function Roles:SetMemberRole(key, role)
    if not BRL.Perm:Require("raid.plan") then return false end
    if role ~= nil and not U.Contains(BRL.Data.Roles, role) then return false end
    ops().memberRoles[key] = role
    if BRL.Roster then BRL.Roster:Refresh() end
    changed()
    return true
end

---------------------------------------------------------------------------
-- 전술 임무
---------------------------------------------------------------------------
local function planFor(planKey, create)
    planKey = planKey or "default"
    local a = ops().assignments
    if not a[planKey] and create then a[planKey] = {} end
    return a[planKey]
end

function Roles:GetAssignees(planKey, duty)
    local plan = planFor(planKey)
    return plan and plan[duty] or {}
end

function Roles:Assign(planKey, duty, key, note)
    if not BRL.Perm:Require("raid.plan") then return false end
    key = API.NormalizeName(key)
    if not key then return false, "이름 오류" end
    local plan = planFor(planKey, true)
    plan[duty] = plan[duty] or {}
    for _, e in ipairs(plan[duty]) do
        if e.key == key then e.note = note or e.note changed() return true end
    end
    table.insert(plan[duty], { key = key, note = note })
    changed()
    return true
end

function Roles:Unassign(planKey, duty, key)
    if not BRL.Perm:Require("raid.plan") then return false end
    local plan = planFor(planKey)
    if not plan or not plan[duty] then return false end
    for i = #plan[duty], 1, -1 do
        if plan[duty][i].key == key then table.remove(plan[duty], i) end
    end
    changed()
    return true
end

function Roles:ClearPlan(planKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    ops().assignments[planKey or "default"] = {}
    ops().orders[planKey or "default"] = {}
    changed()
    return true
end

---------------------------------------------------------------------------
-- 전술 순서표
---------------------------------------------------------------------------
local function ordersFor(planKey, create)
    planKey = planKey or "default"
    local o = ops().orders
    if not o[planKey] and create then o[planKey] = {} end
    return o[planKey]
end

function Roles:GetOrder(planKey, orderKey, backup)
    local o = ordersFor(planKey)
    if not o then return {} end
    local k = backup and (orderKey .. "_BACKUP") or orderKey
    return o[k] or {}
end

function Roles:SetOrder(planKey, orderKey, list, backup)
    if not BRL.Perm:Require("raid.plan") then return false end
    local o = ordersFor(planKey, true)
    o[backup and (orderKey .. "_BACKUP") or orderKey] = list
    changed()
    return true
end

function Roles:AddToOrder(planKey, orderKey, key, backup)
    local list = U.ShallowCopy(self:GetOrder(planKey, orderKey, backup))
    key = API.NormalizeName(key)
    if not key or U.Contains(list, key) then return false end
    list[#list + 1] = key
    return self:SetOrder(planKey, orderKey, list, backup)
end

function Roles:RemoveFromOrder(planKey, orderKey, index, backup)
    local list = U.ShallowCopy(self:GetOrder(planKey, orderKey, backup))
    if not list[index] then return false end
    table.remove(list, index)
    return self:SetOrder(planKey, orderKey, list, backup)
end

function Roles:MoveInOrder(planKey, orderKey, index, delta, backup)
    local list = U.ShallowCopy(self:GetOrder(planKey, orderKey, backup))
    local j = index + delta
    if not list[index] or not list[j] then return false end
    list[index], list[j] = list[j], list[index]
    return self:SetOrder(planKey, orderKey, list, backup)
end

-- 담당자 교체: 모든 임무/순서표에서 oldKey → newKey
function Roles:ReplaceMember(planKey, oldKey, newKey)
    if not BRL.Perm:Require("raid.plan") then return 0 end
    newKey = API.NormalizeName(newKey)
    if not newKey then return 0 end
    local n = 0
    for _, list in pairs(planFor(planKey, true)) do
        for _, e in ipairs(list) do if e.key == oldKey then e.key = newKey n = n + 1 end end
    end
    for _, list in pairs(ordersFor(planKey, true)) do
        for i, k in ipairs(list) do if k == oldKey then list[i] = newKey n = n + 1 end end
    end
    changed()
    return n
end

-- 특정 공대원의 임무 목록
function Roles:DutiesFor(planKey, key)
    local out = {}
    for _, d in ipairs(self.DUTIES) do
        for _, e in ipairs(self:GetAssignees(planKey, d.key)) do
            if e.key == key then out[#out + 1] = d.name .. (e.note and e.note ~= "" and (" (" .. e.note .. ")") or "") end
        end
    end
    for _, o in ipairs(self.ORDERS) do
        for i, k in ipairs(self:GetOrder(planKey, o.key)) do
            if k == key then out[#out + 1] = o.name .. " " .. i .. "번" end
        end
        for i, k in ipairs(self:GetOrder(planKey, o.key, true)) do
            if k == key then out[#out + 1] = o.name .. " 예비 " .. i .. "번" end
        end
    end
    return out
end

-- 검증: 중복 배정 / 공대원 아님 / 핵심 임무 비어 있음
function Roles:Validate(planKey)
    local warnings = {}
    local dutiesByMember = {}
    for _, d in ipairs(self.DUTIES) do
        for _, e in ipairs(self:GetAssignees(planKey, d.key)) do
            dutiesByMember[e.key] = dutiesByMember[e.key] or {}
            dutiesByMember[e.key][d.key] = true
            if BRL.Roster and API.IsInGroup() and not BRL.Roster:IsMember(e.key) then
                warnings[#warnings + 1] = API.ShortName(e.key) .. ": 현재 공대원이 아님 (" .. d.name .. ")"
            end
        end
    end
    for key, set in pairs(dutiesByMember) do
        for _, pair in ipairs(self.CONFLICTS) do
            if set[pair[1]] and set[pair[2]] then
                warnings[#warnings + 1] = string.format("%s: '%s'와 '%s' 중복 배정", API.ShortName(key), self:DutyName(pair[1]), self:DutyName(pair[2]))
            end
        end
    end
    if #self:GetAssignees(planKey, "MAIN_TANK") == 0 then warnings[#warnings + 1] = "메인 탱커 미지정" end
    if #self:GetAssignees(planKey, "MAIN_TANK") > 1 then warnings[#warnings + 1] = "메인 탱커가 2명 이상입니다" end
    return warnings
end

-- 공유용 텍스트
function Roles:OutputLines(planKey, title)
    local lines = { "[BIG RAID LEADER 임무] " .. (title or "") }
    for _, d in ipairs(self.DUTIES) do
        local list = self:GetAssignees(planKey, d.key)
        if #list > 0 then
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = API.ShortName(e.key) .. (e.note and e.note ~= "" and ("(" .. e.note .. ")") or "") end
            lines[#lines + 1] = d.name .. ": " .. table.concat(names, ", ")
        end
    end
    for _, o in ipairs(self.ORDERS) do
        local list = self:GetOrder(planKey, o.key)
        if #list > 0 then
            local names = {}
            for i, k in ipairs(list) do names[#names + 1] = i .. "." .. API.ShortName(k) end
            local backup = self:GetOrder(planKey, o.key, true)
            local b = {}
            for _, k in ipairs(backup) do b[#b + 1] = API.ShortName(k) end
            lines[#lines + 1] = o.name .. ": " .. table.concat(names, " → ") .. (#b > 0 and (" / 예비: " .. table.concat(b, ", ")) or "")
        end
    end
    return lines
end

-- 전술표 템플릿 저장/불러오기
function Roles:SaveTemplate(name, planKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    ops().roleTemplates = ops().roleTemplates or {}
    ops().roleTemplates[name] = {
        assignments = U.DeepCopy(planFor(planKey) or {}), orders = U.DeepCopy(ordersFor(planKey) or {}), at = U.Now(),
    }
    return true
end

function Roles:LoadTemplate(name, planKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    local t = ops().roleTemplates and ops().roleTemplates[name]
    if not t then return false end
    ops().assignments[planKey or "default"] = U.DeepCopy(t.assignments)
    ops().orders[planKey or "default"] = U.DeepCopy(t.orders)
    changed()
    return true
end

function Roles:Templates()
    return U.Keys(ops().roleTemplates or {})
end

