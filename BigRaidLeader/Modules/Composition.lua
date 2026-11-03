-- BIG RAID LEADER - 공격대 구성 분석 / 추천 직업
-- 현재 공대원(+선택: 승인/대기 지원자)의 직업·역할로 공격대 버프, 파티 버프, 보스 약화, 공격대 생존기,
-- 유틸리티 확보 상태를 계산하고, 부족한 것을 가장 많이 채우는 직업을 추천한다.
-- 직업×역할 집계만으로 계산하므로 40인 기준 남은 자리 전체 추천(탐욕 계획)도 즉시 계산된다.
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Comp = BRL:NewModule("Composition")

local ROLES = { "TANK", "HEALER", "MELEE", "RANGED" }
local ROLE_WEIGHT = { TANK = 4, HEALER = 4, MELEE = 1.5, RANGED = 1.5 }
local CLASS_TARGET_WEIGHT = 0.4

Comp.STATUS_LABEL = { ok = "확보", partial = "부족", missing = "없음", camp = "야영지 대체", na = "해당 없음", unavailable = "직업 제한" }

local function cfg() return BRL.acct.composition end
local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "composition") end

function Comp:SizeKey(size)
    size = tonumber(size) or 20
    if size <= 10 then return 10 end
    if size <= 20 then return 20 end
    return 40
end

function Comp:CategoryName(key)
    for _, c in ipairs(BRL.Data.SynergyCategories) do if c.key == key then return c.name end end
    return key
end

---------------------------------------------------------------------------
-- 목표 구성 / 설정
---------------------------------------------------------------------------
function Comp:Target(size)
    local k = self:SizeKey(size)
    if self.targetCache and self.targetCache[k] then return self.targetCache[k] end
    local base = BRL.Data.TargetComposition[k]
    local user = cfg().targets[k]
    return {
        classes = (user and user.classes) or base.classes,
        roles = (user and user.roles) or base.roles,
        edited = user ~= nil,
    }
end

function Comp:SetTargetClasses(size, classes)
    if not BRL.Perm:Require("raid.plan") then return false end
    local k = self:SizeKey(size)
    local t = cfg().targets[k] or {}
    t.classes = U.DeepCopy(classes)
    t.roles = t.roles or U.DeepCopy(BRL.Data.TargetComposition[k].roles)
    cfg().targets[k] = t
    changed()
    return true
end

function Comp:SetTargetRoles(size, roles)
    if not BRL.Perm:Require("raid.plan") then return false end
    local k = self:SizeKey(size)
    local t = cfg().targets[k] or {}
    t.roles = U.DeepCopy(roles)
    t.classes = t.classes or U.DeepCopy(BRL.Data.TargetComposition[k].classes)
    cfg().targets[k] = t
    changed()
    return true
end

function Comp:ResetTarget(size)
    if not BRL.Perm:Require("raid.plan") then return false end
    cfg().targets[self:SizeKey(size)] = nil
    changed()
    return true
end

function Comp:IsExcluded(class) return cfg().excluded[class] and true or false end

function Comp:SetExcluded(class, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    cfg().excluded[class] = value and true or nil
    changed()
    return true
end

function Comp:SetIncludeMode(mode)
    cfg().include = mode
    changed()
end

---------------------------------------------------------------------------
-- 대상 인원 수집
---------------------------------------------------------------------------
-- mode: "roster" | "approved" (+승인 지원자) | "all" (+대기/보류 지원자)
function Comp:Members(mode)
    mode = mode or cfg().include or "approved"
    local out, seen = {}, {}
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        if m.class then
            out[#out + 1] = { key = m.key, name = m.short, class = m.class, role = m.role or BRL.Roles:GuessRole(m), subgroup = m.subgroup, source = "roster" }
            seen[m.key] = true
        end
    end
    if mode == "approved" or mode == "all" then
        for _, a in ipairs(BRL.Recruitment:Applicants()) do
            local ok = a.status == "approved" or (mode == "all" and (a.status == "pending" or a.status == "hold"))
            if ok and a.class and not seen[a.key] then
                local c = BRL.Data.Classes[a.class]
                out[#out + 1] = { key = a.key, name = a.name, class = a.class, role = a.role or (c and c.defaultRole), source = "applicant" }
                seen[a.key] = true
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- 집계 상태 (직업×역할 수)
---------------------------------------------------------------------------
local function newState()
    local s = { cr = {}, class = {}, role = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0 }, total = 0 }
    for _, c in ipairs(BRL.Data.ClassOrder) do
        s.cr[c] = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0 }
        s.class[c] = 0
    end
    return s
end

local function addToState(s, class, role, n)
    n = n or 1
    if not s.cr[class] then
        s.cr[class] = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0 }
        s.class[class] = 0
    end
    role = role or (BRL.Data.Classes[class] and BRL.Data.Classes[class].defaultRole) or "RANGED"
    s.cr[class][role] = (s.cr[class][role] or 0) + n
    s.class[class] = s.class[class] + n
    s.role[role] = (s.role[role] or 0) + n
    s.total = s.total + n
end
Comp.AddToState = addToState

function Comp:StateFromMembers(members)
    local s = newState()
    for _, m in ipairs(members) do addToState(s, m.class, m.role) end
    return s
end

local function countProviders(s, syn, excluded)
    local n = 0
    for _, p in ipairs(syn.providers) do
        if not (excluded and excluded[p.class]) then
            local cr = s.cr[p.class]
            if cr then
                if p.roles then
                    for _, r in ipairs(p.roles) do n = n + (cr[r] or 0) end
                else
                    n = n + (s.class[p.class] or 0)
                end
            end
        end
    end
    return n
end

local function countBeneficiaries(s, benefit)
    if not benefit then return 0 end
    local n = 0
    local inRoles = {}
    for _, r in ipairs(benefit.roles or {}) do
        inRoles[r] = true
        n = n + (s.role[r] or 0)
    end
    for _, c in ipairs(benefit.notClasses or {}) do
        local cr = s.cr[c]
        if cr then for r in pairs(inRoles) do n = n - (cr[r] or 0) end end
    end
    for _, c in ipairs(benefit.classes or {}) do
        local cr = s.cr[c]
        if cr then for _, r in ipairs(ROLES) do if not inRoles[r] then n = n + (cr[r] or 0) end end end
    end
    return math.max(0, n)
end

local function campPrepared(key)
    if not key or not BRL.Campsites then return false end
    local flags = Comp.campFlags
    if flags then return flags[key] and true or false end
    local st = BRL.Campsites:Status(key)
    return st and (st.prepared or st.verified) and true or false
end

-- 분석 1회 동안 야영지 준비 상태를 고정 (반복 평가 시 조회 비용 절감)
function Comp:SnapshotCamps()
    local flags = {}
    for _, c in ipairs(BRL.Data.CampFacilities) do
        local st = BRL.Campsites and BRL.Campsites:Status(c.key)
        flags[c.key] = st and (st.prepared or st.verified) and true or false
    end
    return flags
end

local function allExcluded(syn, excluded)
    for _, p in ipairs(syn.providers) do
        if not excluded[p.class] then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- 평가
---------------------------------------------------------------------------
-- shareGroup(같은 제공자를 나눠 쓰는 파티 버프)은 중요도 높은 항목부터 제공자를 배정
function Comp:EvalOrder()
    if self.order and self.orderSource == BRL.Data.Synergies then return self.order end
    local order = {}
    for i, syn in ipairs(BRL.Data.Synergies) do order[#order + 1] = { i = i, syn = syn } end
    table.sort(order, function(a, b)
        if (a.syn.shareGroup ~= nil) ~= (b.syn.shareGroup ~= nil) then return a.syn.shareGroup ~= nil end
        if a.syn.weight ~= b.syn.weight then return a.syn.weight > b.syn.weight end
        return a.i < b.i
    end)
    self.order, self.orderSource = order, BRL.Data.Synergies
    return order
end
-- 반환: { items = {...}, score, sizeKey, size, roleRows, classRows }
-- 시너지 하나 평가 (테이블 생성 없이 값만 반환): have, need, status, coverage, beneficiaries
local function evalSyn(state, syn, k, maxParties, excluded, shared)
    local need, benef
    if syn.category == "partybuff" then
        benef = countBeneficiaries(state, syn.benefit)
        need = benef > 0 and math.min(maxParties, math.max(1, math.ceil(benef / 4))) or 0
    else
        need = (syn.need and syn.need[k]) or 1
        if syn.campReduce then
            for _, campKey in ipairs(syn.campReduce) do
                if campPrepared(campKey) then need = need - 1 end
            end
        end
        if need < 1 then need = 1 end
    end
    local have = countProviders(state, syn, excluded)
    if syn.shareGroup then
        local used = shared[syn.shareGroup] or 0
        local avail = have - used
        if avail < 0 then avail = 0 end
        shared[syn.shareGroup] = used + math.min(avail, need)
        have = avail
    end
    if need == 0 then return have, need, "na", 1, benef end
    if allExcluded(syn, excluded) then return have, need, "unavailable", 1, benef end
    if have >= need then return have, need, "ok", 1, benef end
    if syn.camp and campPrepared(syn.camp) then return have, need, "camp", 1, benef end
    return have, need, (have > 0 and "partial" or "missing"), have / need, benef
end

local function goalScore(self, state, k, excluded)
    local score = 0
    local target = self:Target(k)
    for _, r in ipairs(ROLES) do
        local t = target.roles[r] or 0
        if t > 0 then score = score + ROLE_WEIGHT[r] * math.min(state.role[r] or 0, t) / t end
    end
    for _, c in ipairs(BRL.Data.ClassOrder) do
        local t = excluded[c] and 0 or (target.classes[c] or 0)
        if t > 0 then score = score + CLASS_TARGET_WEIGHT * math.min(state.class[c] or 0, t) / t end
    end
    return score, target
end

-- 점수만 계산 (추천 후보 비교용 빠른 경로)
function Comp:Score(state, size)
    local k = self:SizeKey(size)
    local maxParties = math.ceil((tonumber(size) or k) / 5)
    local excluded = cfg().excluded
    local shared, score = {}, 0
    for _, e in ipairs(self:EvalOrder()) do
        local _, _, _, coverage = evalSyn(state, e.syn, k, maxParties, excluded, shared)
        score = score + e.syn.weight * coverage
    end
    return score + goalScore(self, state, k, excluded)
end

-- 반환: { items = {...}, score, sizeKey, size, roleRows, classRows }
function Comp:Evaluate(state, size)
    local k = self:SizeKey(size)
    local maxParties = math.ceil((tonumber(size) or k) / 5)
    local excluded = cfg().excluded
    local items, score = {}, 0
    local shared = {}
    local byIndex = {}
    for _, e in ipairs(self:EvalOrder()) do
        local syn = e.syn
        local have, need, status, coverage, benef = evalSyn(state, syn, k, maxParties, excluded, shared)
        byIndex[e.i] = { syn = syn, category = syn.category, have = have, need = need, status = status, coverage = coverage, beneficiaries = benef }
        score = score + syn.weight * coverage
    end
    for i = 1, #BRL.Data.Synergies do items[#items + 1] = byIndex[i] end
    local goal, target = goalScore(self, state, k, excluded)
    score = score + goal
    local roleRows = {}
    for _, r in ipairs(ROLES) do roleRows[#roleRows + 1] = { role = r, have = state.role[r] or 0, target = target.roles[r] or 0 } end
    local classRows = {}
    for _, c in ipairs(BRL.Data.ClassOrder) do
        classRows[#classRows + 1] = { class = c, have = state.class[c] or 0, target = excluded[c] and 0 or (target.classes[c] or 0), excluded = excluded[c] and true or false }
    end
    return { items = items, score = score, sizeKey = k, size = tonumber(size) or k, roleRows = roleRows, classRows = classRows, total = state.total }
end

local function copyState(s)
    local n = { cr = {}, class = {}, role = {}, total = s.total }
    for c, t in pairs(s.cr) do n.cr[c] = { TANK = t.TANK, HEALER = t.HEALER, MELEE = t.MELEE, RANGED = t.RANGED } end
    for c, v in pairs(s.class) do n.class[c] = v end
    for r, v in pairs(s.role) do n.role[r] = v end
    return n
end

-- 직업별 최적 역할과 추가 시 이득
-- fast=true: 이유 목록 없이 순위만 (남은 자리 계획용)
function Comp:Recommend(state, size, limit, fast)
    local base = fast and { score = self:Score(state, size) } or self:Evaluate(state, size)
    local excluded = cfg().excluded
    local results = {}
    for _, class in ipairs(BRL.Data.ClassOrder) do
        if not excluded[class] then
            local best
            for _, role in ipairs(BRL.Data.Classes[class].roles) do
                addToState(state, class, role, 1)
                local gain = self:Score(state, size) - base.score
                addToState(state, class, role, -1)
                if not best or gain > best.gain + 1e-9 then best = { class = class, role = role, gain = gain } end
            end
            if best and best.gain > 1e-6 and fast then
                results[#results + 1] = best
            elseif best and best.gain > 1e-6 then
                addToState(state, best.class, best.role, 1)
                best.eval = self:Evaluate(state, size)
                addToState(state, best.class, best.role, -1)
                -- 이유: 확보 상태가 좋아지는 항목
                local reasons = {}
                for i, it in ipairs(base.items) do
                    local after = best.eval.items[i]
                    if it.status ~= "ok" and it.status ~= "camp" and it.status ~= "na" and after.have > it.have then
                        reasons[#reasons + 1] = { syn = it.syn, before = it.status, after = after.status, weight = it.syn.weight }
                    end
                end
                table.sort(reasons, function(a, b) return a.weight > b.weight end)
                best.reasons = reasons
                best.eval = nil
                results[#results + 1] = best
            end
        end
    end
    table.sort(results, function(a, b)
        if math.abs(a.gain - b.gain) > 1e-9 then return a.gain > b.gain end
        return (BRL.Data.Classes[a.class].order or 0) < (BRL.Data.Classes[b.class].order or 0)
    end)
    if limit then while #results > limit do table.remove(results) end end
    return results, base
end

-- 남은 자리를 채우는 추천 구성안 (탐욕적 계획)
function Comp:Plan(state, size)
    local open = math.max(0, (tonumber(size) or 20) - state.total)
    local s = copyState(state)
    local adds, byClass, byRole = {}, {}, {}
    for _ = 1, open do
        local rec = self:Recommend(s, size, 1, true)
        local pick = rec[1]
        if not pick then
            -- 이득이 없으면 목표 구성 대비 가장 부족한 직업
            local target = self:Target(size)
            local bestC, bestGap
            for _, c in ipairs(BRL.Data.ClassOrder) do
                if not cfg().excluded[c] then
                    local gap = (target.classes[c] or 0) - (s.class[c] or 0)
                    if not bestGap or gap > bestGap then bestC, bestGap = c, gap end
                end
            end
            if not bestC then break end
            pick = { class = bestC, role = BRL.Data.Classes[bestC].defaultRole, gain = 0, reasons = {} }
        end
        addToState(s, pick.class, pick.role)
        adds[#adds + 1] = pick
        local key = pick.class .. "|" .. pick.role
        byClass[pick.class] = (byClass[pick.class] or 0) + 1
        byRole[key] = (byRole[key] or 0) + 1
    end
    return { open = open, adds = adds, byClass = byClass, byRole = byRole, final = self:Evaluate(s, size) }
end

---------------------------------------------------------------------------
-- 통합 분석 (화면/채팅용)
---------------------------------------------------------------------------
-- 같은 입력이면 이전 결과 재사용 (화면 갱신마다 재계산하지 않음)
function Comp:CacheKey(size, mode, members)
    local parts = { tostring(size), tostring(mode or cfg().include) }
    local list = {}
    for _, m in ipairs(members) do list[#list + 1] = m.class .. ":" .. tostring(m.role) .. ":" .. tostring(m.subgroup) end
    table.sort(list)
    parts[#parts + 1] = table.concat(list, ",")
    parts[#parts + 1] = table.concat(U.Keys(cfg().excluded), ",")
    parts[#parts + 1] = BRL.Serializer.Serialize(cfg().targets)
    for _, c in ipairs(BRL.Data.CampFacilities) do parts[#parts + 1] = campPrepared(c.key) and "1" or "0" end
    parts[#parts + 1] = API.IsInRaid() and "R" or "-"
    return table.concat(parts, "|")
end

function Comp:Analyze(size, mode)
    size = tonumber(size) or (BRL.Recruitment and BRL.Recruitment:GetCurrent().size) or 20
    local members = self:Members(mode)
    local key = self:CacheKey(size, mode, members)
    if self.cache and self.cache.key == key then return self.cache.result end
    local result = self:Compute(size, members)
    self.cache = { key = key, result = result }
    return result
end

function Comp:Compute(size, members)
    self.campFlags = self:SnapshotCamps()
    self.targetCache = {}
    for _, k in ipairs({ 10, 20, 40 }) do self.targetCache[k] = self:Target(k) end
    local ok, result = pcall(self.ComputeInner, self, size, members)
    self.campFlags, self.targetCache = nil, nil
    if not ok then error(result, 0) end
    return result
end

function Comp:ComputeInner(size, members)
    local state = self:StateFromMembers(members)
    local recs, eval = self:Recommend(state, size)
    local plan = self:Plan(state, size)
    local missing = { raidbuff = {}, partybuff = {}, debuff = {}, cooldown = {}, utility = {} }
    for _, it in ipairs(eval.items) do
        if it.status == "missing" or it.status == "partial" then
            table.insert(missing[it.category], it)
        end
    end
    return {
        size = size, sizeKey = eval.sizeKey, members = members, state = state, eval = eval,
        recommendations = recs, plan = plan, missing = missing, partyGaps = self:PartyGaps(members),
    }
end

-- 현재 파티 배치에서 파티 버프가 빠진 파티 (공격대 상태에서만)
function Comp:PartyGaps(members)
    local gaps = {}
    if not API.IsInRaid() then return gaps end
    local groups = {}
    for _, m in ipairs(members) do
        if m.source == "roster" and m.subgroup then
            groups[m.subgroup] = groups[m.subgroup] or {}
            table.insert(groups[m.subgroup], m)
        end
    end
    local excluded = cfg().excluded
    for g, list in pairs(groups) do
        local s = self:StateFromMembers(list)
        for _, syn in ipairs(BRL.Data.Synergies) do
            if syn.category == "partybuff" and syn.weight >= 2 and countBeneficiaries(s, syn.benefit) > 0
                and countProviders(s, syn, excluded) == 0 and not (syn.camp and campPrepared(syn.camp)) then
                gaps[#gaps + 1] = { group = g, syn = syn }
            end
        end
    end
    table.sort(gaps, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.syn.weight > b.syn.weight
    end)
    return gaps
end

function Comp:ProviderText(syn)
    local parts = {}
    for _, p in ipairs(syn.providers) do
        local s = BRL.Data.ClassName(p.class)
        if p.roles then
            local r = {}
            for _, x in ipairs(p.roles) do r[#r + 1] = BRL.Label("CR_", x) end
            s = s .. "(" .. table.concat(r, "/") .. ")"
        end
        if p.talent then s = s .. "*" end
        parts[#parts + 1] = s
    end
    return table.concat(parts, ", ")
end

local function shortRole(role)
    return ({ TANK = "탱커", HEALER = "힐러", MELEE = "근딜", RANGED = "원딜" })[role] or role
end
Comp.ShortRole = shortRole

function Comp:RecommendText(rec, maxReasons)
    local names = {}
    for i, r in ipairs(rec.reasons or {}) do
        if i > (maxReasons or 3) then break end
        names[#names + 1] = (r.syn.name:gsub("%s*%(.*%)", ""))
    end
    return BRL.Data.ClassName(rec.class) .. "(" .. shortRole(rec.role) .. ")" .. (#names > 0 and (": " .. table.concat(names, ", ")) or "")
end

-- 모집 문구 {recommend} 치환용: 상위 n개 직업
function Comp:ShortRecommendation(n)
    local a = self:Analyze()
    local parts = {}
    for i, r in ipairs(a.recommendations) do
        if i > (n or 3) then break end
        parts[#parts + 1] = BRL.Data.ClassName(r.class) .. "(" .. shortRole(r.role) .. ")"
    end
    return #parts > 0 and table.concat(parts, ", ") or "전 직업"
end

function Comp:Lines(a)
    a = a or self:Analyze()
    local lines = { string.format("[BIG RAID LEADER 구성 분석] %d인 기준 (현재 %d명)", a.size, a.state.total) }
    -- 채팅은 중요도 2 이상만 이름으로, 나머지는 개수로 (전체 목록은 구성 분석 화면)
    local function list(cat, label)
        local names, minor = {}, 0
        for _, it in ipairs(a.missing[cat]) do
            if it.syn.weight >= 2 then
                names[#names + 1] = (it.syn.name:gsub("%s*%(.*%)", "")) .. (it.status == "partial" and (" " .. it.have .. "/" .. it.need) or "")
            else
                minor = minor + 1
            end
        end
        if #names > 0 then
            lines[#lines + 1] = label .. ": " .. table.concat(names, ", ") .. (minor > 0 and (" (그 외 " .. minor .. "개)") or "")
        end
    end
    list("raidbuff", "없는 공격대 버프")
    list("partybuff", "부족한 파티 버프")
    list("cooldown", "부족한 공격대 생존기")
    list("debuff", "없는 보스 약화")
    list("utility", "부족한 유틸리티")
    local recs = {}
    for i, r in ipairs(a.recommendations) do
        if i > 4 then break end
        recs[#recs + 1] = self:RecommendText(r, 2)
    end
    if #recs > 0 then lines[#lines + 1] = "추천 추가 직업: " .. table.concat(recs, " / ") end
    if a.plan.open > 0 then
        local parts = {}
        for _, c in ipairs(BRL.Data.ClassOrder) do
            if a.plan.byClass[c] then parts[#parts + 1] = BRL.Data.ClassName(c) .. " " .. a.plan.byClass[c] end
        end
        lines[#lines + 1] = string.format("남은 %d자리 추천: %s", a.plan.open, table.concat(parts, ", "))
    end
    if #lines == 1 then lines[#lines + 1] = "핵심 시너지 모두 확보" end
    return lines
end

-- 추천 계획을 모집 정원에 반영 (직업별 정원 = 현재 + 추천 추가 인원, 역할 정원 = 목표 구성)
function Comp:ApplyToRecruitment(size, mode)
    if not BRL.Perm:Require("raid.plan") then return false end
    local a = self:Analyze(size, mode)
    local R = BRL.Recruitment
    for _, c in ipairs(BRL.Data.ClassOrder) do
        local add = a.plan.byClass[c] or 0
        R:SetQuota("class", c, add > 0 and ((a.state.class[c] or 0) + add) or 0)
    end
    local target = self:Target(a.size)
    for _, r in ipairs(ROLES) do R:SetQuota("role", r, target.roles[r] or 0) end
    return true, a
end
