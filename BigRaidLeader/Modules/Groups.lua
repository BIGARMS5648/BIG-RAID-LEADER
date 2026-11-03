-- BIG RAID LEADER - 파티 편성 (RaidGroupLayout)
-- 편성안은 먼저 "계획"으로 만들고, 공대장 확인 후 실제 공격대에 반영한다 (전투 중 불가).
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Groups = BRL:NewModule("Groups")

Groups.MAX_GROUPS = 8
Groups.GROUP_SIZE = 5

local function ops() return BRL.db.raidOps end
local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "groups") end

local function emptyPlan()
    local p = { groups = {} }
    for g = 1, Groups.MAX_GROUPS do p.groups[g] = {} end
    return p
end

function Groups:GetPlan()
    local p = ops().groupPlan
    if not p then
        p = self:FromCurrent(true)
        ops().groupPlan = p
    end
    for g = 1, self.MAX_GROUPS do p.groups[g] = p.groups[g] or {} end
    return p
end

function Groups:SetPlan(plan)
    ops().groupPlan = plan
    changed()
end

-- 현재 공격대 편성 복사
function Groups:FromCurrent(noSave)
    local p = emptyPlan()
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        local g = U.Clamp(m.subgroup or 1, 1, self.MAX_GROUPS)
        if #p.groups[g] < self.GROUP_SIZE then table.insert(p.groups[g], m.key) end
    end
    if not noSave then self:SetPlan(p) end
    return p
end

function Groups:Reset()
    if not BRL.Perm:Require("raid.plan") then return false end
    self:SetPlan(emptyPlan())
    return true
end

function Groups:Locate(key, plan)
    plan = plan or self:GetPlan()
    for g = 1, self.MAX_GROUPS do
        for i, k in ipairs(plan.groups[g]) do
            if k == key then return g, i end
        end
    end
    return nil
end

function Groups:Unassigned()
    local plan = self:GetPlan()
    local out = {}
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        if not self:Locate(m.key, plan) then out[#out + 1] = m.key end
    end
    return out
end

-- 계획 내 이동. target 파티가 가득 찼고 swapWith 가 없으면 실패
function Groups:Move(key, toGroup, swapWith)
    if not BRL.Perm:Require("raid.plan") then return false end
    local plan = self:GetPlan()
    if toGroup < 1 or toGroup > self.MAX_GROUPS then return false end
    local fromG, fromI = self:Locate(key, plan)
    if fromG == toGroup and not swapWith then return true end
    local target = plan.groups[toGroup]
    if swapWith then
        local sg, si = self:Locate(swapWith, plan)
        if sg and fromG then
            plan.groups[fromG][fromI], plan.groups[sg][si] = swapWith, key
            changed()
            return true
        elseif sg and not fromG then
            plan.groups[sg][si] = key
            changed()
            return true
        end
    end
    if #target >= self.GROUP_SIZE then return false, toGroup .. "파티가 가득 찼습니다" end
    if fromG then table.remove(plan.groups[fromG], fromI) end
    table.insert(target, key)
    changed()
    return true
end

function Groups:Remove(key)
    if not BRL.Perm:Require("raid.plan") then return false end
    local plan = self:GetPlan()
    local g, i = self:Locate(key, plan)
    if g then table.remove(plan.groups[g], i) changed() end
    return true
end

function Groups:IsPinned(key) return ops().pinned[key] and true or false end

function Groups:SetPinned(key, pinned)
    if not BRL.Perm:Require("raid.plan") then return false end
    ops().pinned[key] = pinned and true or nil
    changed()
    return true
end

---------------------------------------------------------------------------
-- 자동 편성 제안 (적용하지 않고 계획만 반환)
---------------------------------------------------------------------------
-- opts: { includeOffline = bool }
function Groups:AutoSuggest(opts)
    opts = opts or {}
    local members = {}
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        if m.online or opts.includeOffline then members[#members + 1] = m end
    end
    local n = #members
    local numGroups = math.max(1, math.min(self.MAX_GROUPS, math.ceil(n / self.GROUP_SIZE)))
    local plan = emptyPlan()
    local current = self:GetPlan()
    local info = {}
    for g = 1, numGroups do info[g] = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0, classes = {} } end
    local placed = {}
    local function place(m, g)
        table.insert(plan.groups[g], m.key)
        local role = m.role or "RANGED"
        info[g][role] = (info[g][role] or 0) + 1
        info[g].classes[m.class or "?"] = (info[g].classes[m.class or "?"] or 0) + 1
        placed[m.key] = true
    end
    -- 1) 고정 인원은 현재 계획의 파티 유지
    for _, m in ipairs(members) do
        if self:IsPinned(m.key) then
            local g = self:Locate(m.key, current)
            if g and g <= numGroups and #plan.groups[g] < self.GROUP_SIZE then place(m, g) end
        end
    end
    -- 2) 역할 우선순위대로 점수가 가장 높은 파티에 배치
    local order = { TANK = 1, HEALER = 2, MELEE = 3, RANGED = 4 }
    local rest = {}
    for _, m in ipairs(members) do if not placed[m.key] then rest[#rest + 1] = m end end
    table.sort(rest, function(a, b)
        local ra, rb = order[a.role or "RANGED"] or 5, order[b.role or "RANGED"] or 5
        if ra ~= rb then return ra < rb end
        if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
        return a.key < b.key
    end)
    for _, m in ipairs(rest) do
        local best, bestScore
        for g = 1, numGroups do
            if #plan.groups[g] < self.GROUP_SIZE then
                local gi = info[g]
                local role = m.role or "RANGED"
                local score = 0
                if role == "TANK" then score = score - gi.TANK * 30
                elseif role == "HEALER" then score = score - gi.HEALER * 20
                elseif role == "MELEE" then score = score + gi.MELEE * 3 - gi.RANGED * 2 + gi.TANK * 1
                elseif role == "RANGED" then score = score + gi.RANGED * 3 - gi.MELEE * 2 end
                -- 직업 시너지 (필수 버프 공급원 분산)
                if m.class == "SHAMAN" then score = score + gi.MELEE * 2 - (gi.classes.SHAMAN or 0) * 8 end
                if m.class == "PALADIN" then score = score - (gi.classes.PALADIN or 0) * 4 end
                if m.class == "DRUID" and role ~= "HEALER" then score = score - (gi.classes.DRUID or 0) * 4 end
                if m.class == "HUNTER" then score = score + (gi.classes.HUNTER or 0) * 2 end
                if m.class == "WARRIOR" and role == "MELEE" then score = score - (gi.classes.WARRIOR or 0) * 1 end
                -- 균등 채우기
                score = score - #plan.groups[g] * 0.5
                if not bestScore or score > bestScore then best, bestScore = g, score end
            end
        end
        if best then place(m, best) end
    end
    return plan
end

---------------------------------------------------------------------------
-- 실제 공격대에 반영 (단계별, 전투 시작 시 중단)
---------------------------------------------------------------------------
function Groups:Apply(plan)
    if not BRL.Perm:Require("raid.groups.apply") then return false end
    if not API.GuardCombat() then return false end
    if not API.IsInRaid() then BRL:Print("공격대 상태에서만 파티 이동을 적용할 수 있습니다.") return false end
    self.applying = { plan = plan or self:GetPlan(), steps = 0, attempts = {} }
    self:ApplyStep()
    return true
end

function Groups:IsApplying() return self.applying ~= nil end

function Groups:CancelApply()
    self.applying = nil
end

function Groups:ApplyStep()
    local job = self.applying
    if not job then return end
    if API.InCombat() then
        BRL:Print("전투가 시작되어 편성 적용을 중단했습니다. 전투 후 다시 적용하세요.")
        self.applying = nil
        return
    end
    job.steps = job.steps + 1
    if job.steps > 120 then
        BRL:Print("편성 적용을 완료하지 못했습니다 (최대 단계 초과).")
        self.applying = nil
        return
    end
    local roster = API.GetGroupRoster()
    local cur, counts = {}, {}
    for g = 1, self.MAX_GROUPS do counts[g] = 0 end
    for _, m in ipairs(roster) do
        cur[m.key] = m
        counts[m.subgroup] = (counts[m.subgroup] or 0) + 1
    end
    local desired = {}
    for g = 1, self.MAX_GROUPS do
        for _, key in ipairs(job.plan.groups[g] or {}) do desired[key] = g end
    end
    for g = 1, self.MAX_GROUPS do
        for _, key in ipairs(job.plan.groups[g] or {}) do
            local m = cur[key]
            if m and m.subgroup ~= g then
                local tries = job.attempts[key] or 0
                if tries < 3 then
                    job.attempts[key] = tries + 1
                    if counts[g] < self.GROUP_SIZE then
                        API.SetRaidSubgroup(m.raidIndex, g)
                    else
                        local swap
                        for _, other in ipairs(roster) do
                            if other.subgroup == g and desired[other.key] ~= g then swap = other break end
                        end
                        if swap then API.SwapRaidSubgroup(m.raidIndex, swap.raidIndex) end
                    end
                    API.After(0.3, function() self:ApplyStep() end)
                    return
                end
            end
        end
    end
    BRL:Print("파티 편성 적용 완료")
    self.applying = nil
    if BRL.Roster then BRL.Roster:Refresh() end
end

---------------------------------------------------------------------------
-- 템플릿 / 출력
---------------------------------------------------------------------------
function Groups:SaveTemplate(name)
    if not BRL.Perm:Require("raid.plan") then return false end
    name = U.Trim(name or "")
    if name == "" then return false end
    ops().groupTemplates[name] = { plan = U.DeepCopy(self:GetPlan()), at = U.Now() }
    return true
end

function Groups:LoadTemplate(name)
    if not BRL.Perm:Require("raid.plan") then return false end
    local t = ops().groupTemplates[name]
    if not t then return false end
    self:SetPlan(U.DeepCopy(t.plan))
    return true
end

function Groups:DeleteTemplate(name)
    if not BRL.Perm:Require("raid.plan") then return false end
    ops().groupTemplates[name] = nil
    return true
end

function Groups:Templates() return U.Keys(ops().groupTemplates) end

function Groups:OutputLines(plan)
    plan = plan or self:GetPlan()
    local lines = { "[BIG RAID LEADER 파티 편성]" }
    for g = 1, self.MAX_GROUPS do
        local names = {}
        for _, key in ipairs(plan.groups[g]) do names[#names + 1] = API.ShortName(key) end
        if #names > 0 then lines[#lines + 1] = g .. "파티: " .. table.concat(names, ", ") end
    end
    return lines
end

-- 계획의 파티별 역할 구성 요약
function Groups:Composition(plan)
    plan = plan or self:GetPlan()
    local out = {}
    for g = 1, self.MAX_GROUPS do
        local c = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0, total = #plan.groups[g] }
        for _, key in ipairs(plan.groups[g]) do
            local role = BRL.Roles:GetMemberRole(key) or "RANGED"
            c[role] = (c[role] or 0) + 1
        end
        out[g] = c
    end
    return out
end
