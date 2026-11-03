-- BIG RAID LEADER - 버프 관리자
-- 전투 중에는 오라 정보를 읽지 않는다. Secret Value 로 전달되면 "확인 불가"로 표시한다.
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Buffs = BRL:NewModule("Buffs")

Buffs.results = {}      -- [memberKey] = { unavailable=reason } | { buffs = { [key] = {present, remaining, via} }, camps = {..}, consumables = {..} }
Buffs.scannedAt = nil
Buffs.needsRecheck = false

local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "buffs") end

function Buffs:OnEnable()
    BRL.Events:Register("ENCOUNTER_END", self, function(_, _, _, _, _, _, success)
        if success == 0 or success == false then
            self.needsRecheck = true
            changed()
        end
    end)
end

local function idSet(list)
    local s = {}
    for _, id in ipairs(list or {}) do s[id] = true end
    return s
end

local function matchesKeywords(name, keywords)
    if type(name) ~= "string" then return false end
    for _, kw in ipairs(keywords or {}) do
        if name:find(kw, 1, true) then return true end
    end
    return false
end

-- 사용자 키워드 보완 (설정 > 버프 키워드)
function Buffs:Keywords(key, defaults)
    local custom = BRL.acct.buffs.keywords and BRL.acct.buffs.keywords[key]
    if custom and #custom > 0 then
        local merged = {}
        for _, k in ipairs(defaults or {}) do merged[#merged + 1] = k end
        for _, k in ipairs(custom) do merged[#merged + 1] = k end
        return merged
    end
    return defaults
end

function Buffs:Analyze(auras)
    local now = U.Clock()
    local res = { buffs = {}, camps = {}, consumables = {} }
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        local ids = idSet(b.spellIds)
        local kws = self:Keywords(b.key, b.keywords)
        for _, a in ipairs(auras) do
            if (a.spellId and ids[a.spellId]) or matchesKeywords(a.name, kws) then
                local remaining = a.expirationTime and a.expirationTime > 0 and (a.expirationTime - now) or nil
                res.buffs[b.key] = { present = true, remaining = remaining, via = "class", name = a.name }
                break
            end
        end
    end
    for _, c in ipairs(BRL.Data.CampFacilities) do
        local kws = self:Keywords(c.key, c.keywords)
        for _, a in ipairs(auras) do
            if matchesKeywords(a.name, kws) then
                local remaining = a.expirationTime and a.expirationTime > 0 and (a.expirationTime - now) or nil
                res.camps[c.key] = { present = true, remaining = remaining }
                break
            end
        end
    end
    for _, g in ipairs(BRL.Data.ConsumableGroups) do
        if not g.manual then
            local kws = self:Keywords(g.key, g.keywords)
            for _, a in ipairs(auras) do
                if matchesKeywords(a.name, kws) then
                    local remaining = a.expirationTime and a.expirationTime > 0 and (a.expirationTime - now) or nil
                    res.consumables[g.key] = { present = true, remaining = remaining }
                    break
                end
            end
        end
    end
    -- 야영지 효과가 직업 버프를 대체
    if BRL.acct.buffs.campReplacesClassBuff then
        for _, c in ipairs(BRL.Data.CampFacilities) do
            if res.camps[c.key] and c.replaces and not res.buffs[c.replaces] then
                res.buffs[c.replaces] = { present = true, remaining = res.camps[c.key].remaining, via = "camp" }
            end
        end
    end
    return res
end

function Buffs:Scan()
    if API.InCombat() then
        BRL:Print("전투 중에는 버프를 점검할 수 없습니다.")
        return false
    end
    local results = {}
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        if not m.online then
            results[m.key] = { unavailable = "offline" }
        else
            local auras, why = API.GetUnitBuffs(m.unit or "player")
            if not auras then results[m.key] = { unavailable = why or "unknown" }
            else results[m.key] = self:Analyze(auras) end
        end
    end
    self.results = results
    self.scannedAt = U.Now()
    self.needsRecheck = false
    changed()
    return true
end

function Buffs:RequiredList(bossKey)
    local req = {}
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        if BRL.acct.buffs.required[b.key] then req[#req + 1] = b end
    end
    local bossReq = bossKey and BRL.db.raidOps.bossBuffs and BRL.db.raidOps.bossBuffs[bossKey]
    if bossReq then
        for key in pairs(bossReq) do
            local b = BRL.Data.FindClassBuff(key)
            if b and not BRL.acct.buffs.required[key] then req[#req + 1] = b end
        end
    end
    return req
end

function Buffs:SetRequired(key, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    BRL.acct.buffs.required[key] = value and true or nil
    changed()
    return true
end

function Buffs:SetBossRequired(bossKey, key, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    BRL.db.raidOps.bossBuffs = BRL.db.raidOps.bossBuffs or {}
    BRL.db.raidOps.bossBuffs[bossKey] = BRL.db.raidOps.bossBuffs[bossKey] or {}
    BRL.db.raidOps.bossBuffs[bossKey][key] = value and true or nil
    changed()
    return true
end

-- 누락 버프: { [buffKey] = { memberKeys... } }, 확인 불가 인원 목록
function Buffs:Missing(bossKey)
    local missing, unknown = {}, {}
    local required = self:RequiredList(bossKey)
    for key, r in pairs(self.results) do
        if r.unavailable then
            if r.unavailable ~= "offline" then unknown[#unknown + 1] = key end
        else
            for _, b in ipairs(required) do
                if not (r.buffs[b.key] and r.buffs[b.key].present) then
                    missing[b.key] = missing[b.key] or {}
                    table.insert(missing[b.key], key)
                end
            end
        end
    end
    for _, list in pairs(missing) do table.sort(list) end
    return missing, unknown
end

-- 곧 만료되는 버프
function Buffs:Expiring()
    local limit = (BRL.acct.buffs.expireWarnMinutes or 5) * 60
    local out = {}
    for key, r in pairs(self.results) do
        if r.buffs then
            for bkey, b in pairs(r.buffs) do
                if b.remaining and b.remaining < limit then
                    out[#out + 1] = { key = key, buff = bkey, remaining = b.remaining }
                end
            end
        end
    end
    return out
end

-- 버프 담당자
function Buffs:GetProvider(buffKey) return BRL.db.raidOps.buffProviders[buffKey] end

function Buffs:SetProvider(buffKey, memberKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    BRL.db.raidOps.buffProviders[buffKey] = memberKey
    changed()
    return true
end

function Buffs:AutoAssignProviders()
    if not BRL.Perm:Require("raid.plan") then return 0 end
    local used, n = {}, 0
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        local cur = BRL.db.raidOps.buffProviders[b.key]
        if not cur or not BRL.Roster:IsMember(cur) then
            for _, m in ipairs(BRL.Roster:Sorted("name")) do
                if m.class == b.provider and not used[m.key .. b.group] then
                    BRL.db.raidOps.buffProviders[b.key] = m.key
                    used[m.key .. b.group] = true
                    n = n + 1
                    break
                end
            end
        end
    end
    changed()
    return n
end

-- 대체/중복 관계 설명
function Buffs:OverlapNotes()
    local out = {}
    for _, c in ipairs(BRL.Data.CampFacilities) do
        out[#out + 1] = string.format("%s(야영지) ↔ %s : 중복 적용 안 됨", c.name, c.replacesName)
    end
    out[#out + 1] = "왕의 축복 ↔ 상급 왕의 축복 : 같은 효과(중복 불가)"
    out[#out + 1] = "신의 권능: 인내 ↔ 인내의 기원 : 같은 효과(중복 불가)"
    return out
end

function Buffs:MissingLines(bossKey)
    local missing, unknown = self:Missing(bossKey)
    local lines = { "[BIG RAID LEADER 버프 점검]" }
    for _, b in ipairs(self:RequiredList(bossKey)) do
        local list = missing[b.key]
        if list and #list > 0 then
            local names = {}
            for _, k in ipairs(list) do names[#names + 1] = API.ShortName(k) end
            local prov = self:GetProvider(b.key)
            lines[#lines + 1] = string.format("%s 누락(%d): %s%s", b.name, #list, table.concat(names, ", "),
                prov and (" - 담당 " .. API.ShortName(prov)) or "")
        end
    end
    if #unknown > 0 then lines[#lines + 1] = "확인 불가: " .. #unknown .. "명" end
    if #lines == 1 then lines[#lines + 1] = "필수 버프 누락 없음" end
    return lines
end
