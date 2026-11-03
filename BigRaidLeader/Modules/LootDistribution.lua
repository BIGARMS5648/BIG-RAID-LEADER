-- BIG RAID LEADER - 기타 전리품 분배 (주사위 / DKP / EPGP / Loot Council / 우선순위 / 수동)
-- 모든 분배는 공대장이 직접 관리한다 (별도 전리품 관리자 직책 없음).
local _, BRL = ...
local U, API, DB = BRL.Util, BRL.API, BRL.DB

local LD = BRL:NewModule("LootDistribution")

LD.METHODS = {
    { key = "roll", name = "주사위" },
    { key = "dkp", name = "DKP" },
    { key = "epgp", name = "EPGP" },
    { key = "council", name = "Loot Council" },
    { key = "priority", name = "우선순위" },
    { key = "manual", name = "수동 분배" },
}

LD.activeRoll = nil

local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "loot") end

local function require()
    local session = BRL.Session:GetActive()
    local ok, why = BRL.Perm:CanEditSession(session)
    if not ok then BRL:Print("%s: %s", BRL.L.NO_PERMISSION, why or "") end
    return ok
end

function LD:OnEnable()
    BRL.Events:Register("CHAT_MSG_SYSTEM", self, "OnSystemMessage")
    self:BuildRollPattern()
end

function LD:MethodName(key)
    for _, m in ipairs(self.METHODS) do if m.key == key then return m.name end end
    return key
end

function LD:Get(id) return DB:Get("lootRecords", id) end

function LD:List(sessionId)
    return DB:List("lootRecords", function(r) return not sessionId or r.sessionId == sessionId end, "createdAt", true)
end

-- 아이템 등록 (중복 분배 확인)
function LD:Register(itemLink, method, opts)
    opts = opts or {}
    if not require() then return nil, "권한 없음" end
    if not itemLink or itemLink == "" then return nil, "아이템이 필요합니다" end
    local session = BRL.Session:Ensure({})
    if not session then return nil, "세션 없음" end
    if not opts.allowDuplicate then
        for _, r in pairs(DB:T("lootRecords")) do
            if r.sessionId == session.id and r.itemLink == itemLink and r.status ~= "cancelled" then
                return nil, "duplicate"
            end
        end
        for _, a in pairs(DB:T("awards")) do
            if a.sessionId == session.id and a.itemLink == itemLink and a.status == "active" then
                return nil, "duplicate_auction"
            end
        end
    end
    local name = API.GetItemInfo(itemLink)
    local rec = DB:Insert("lootRecords", {
        sessionId = session.id, itemLink = itemLink, itemName = name or U.ItemNameFromLink(itemLink),
        method = method or "manual", status = "open", candidates = {}, cost = 0, history = {},
    })
    DB:Audit("loot.register", "loot", rec.id, { item = itemLink, method = rec.method })
    changed()
    return rec
end

function LD:SetMethod(id, method)
    local r = self:Get(id)
    if not r or r.status ~= "open" or not require() then return false end
    DB:AddHistory(r, "method", r.method, method)
    r.method = method
    changed()
    return true
end

function LD:AddCandidate(id, key, data)
    local r = self:Get(id)
    if not r or r.status ~= "open" or not require() then return false end
    key = API.NormalizeName(key)
    if not key then return false end
    r.candidates[key] = r.candidates[key] or { key = key, name = API.ShortName(key), votes = 0 }
    for k, v in pairs(data or {}) do r.candidates[key][k] = v end
    changed()
    return true
end

function LD:RemoveCandidate(id, key)
    local r = self:Get(id)
    if not r or r.status ~= "open" or not require() then return false end
    r.candidates[key] = nil
    changed()
    return true
end

---------------------------------------------------------------------------
-- 주사위
---------------------------------------------------------------------------
function LD:BuildRollPattern()
    local fmt = _G.RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    -- 한국어 조사 표기(|1이;가;): 이름 뒤 조사는 이름 캡처 후 제거, 숫자 뒤 조사는 무시
    self.rollStripParticle = fmt:find("%%s|1") ~= nil
    local p = fmt:gsub("%%s|1[^;]*;[^;]*;", "%%s")
    p = p:gsub("|1[^;]*;[^;]*;", "\001")
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(%%S+)"):gsub("%%d", "(%%d+)")
    p = p:gsub("\001", ".-")
    self.rollPattern = "^" .. p .. "$"
end

function LD:ParseRoll(msg)
    if type(msg) ~= "string" or API.IsSecret(msg) then return nil end
    local name, roll, lo, hi = msg:match(self.rollPattern)
    if not name then return nil end
    if self.rollStripParticle then
        for _, suf in ipairs({ "이", "가" }) do
            if #name > #suf and name:sub(-#suf) == suf then name = name:sub(1, -#suf - 1) break end
        end
    end
    return name, tonumber(roll), tonumber(lo), tonumber(hi)
end

function LD:StartRoll(id, seconds)
    local r = self:Get(id)
    if not r or r.status ~= "open" or not require() then return false end
    r.method = "roll"
    for _, c in pairs(r.candidates) do c.roll = nil end
    self.activeRoll = { id = id, untilClock = U.Clock() + (seconds or 20) }
    BRL.ChatOut:Send(string.format("[주사위] %s - /주사위 (1-100) %d초", r.itemLink, seconds or 20))
    API.After(seconds or 20, function()
        if self.activeRoll and self.activeRoll.id == id then self:EndRoll(id) end
    end)
    changed()
    return true
end

function LD:OnSystemMessage(_, msg)
    local roll = self.activeRoll
    if not roll then return end
    local name, value, lo, hi = self:ParseRoll(msg)
    if not name or lo ~= 1 or hi ~= 100 then return end
    local r = self:Get(roll.id)
    if not r then return end
    local key = API.NormalizeName(name)
    r.candidates[key] = r.candidates[key] or { key = key, name = API.ShortName(key), votes = 0 }
    if r.candidates[key].roll == nil then -- 첫 주사위만 인정
        r.candidates[key].roll = value
        changed()
    end
end

function LD:EndRoll(id)
    local r = self:Get(id)
    self.activeRoll = nil
    if not r then return nil end
    local best, tie = nil, false
    for _, c in pairs(r.candidates) do
        if c.roll then
            if not best or c.roll > best.roll then best, tie = c, false
            elseif c.roll == best.roll then tie = true end
        end
    end
    r.suggestedWinner = best and best.key or nil
    r.tie = tie
    if best then
        BRL.ChatOut:Send(string.format("[주사위 결과] %s - 최고 %s (%d)%s", r.itemLink, best.name, best.roll, tie and " 동점 - 재굴림 필요" or ""))
    end
    changed()
    return best, tie
end

---------------------------------------------------------------------------
-- DKP
---------------------------------------------------------------------------
function LD:DKP(key, pool)
    local p = BRL.db.loot.dkp.pools[pool or "default"] or {}
    return p[key] or 0
end

function LD:AdjustDKP(key, delta, reason, pool)
    if not require() then return false end
    key = API.NormalizeName(key)
    pool = pool or "default"
    local pools = BRL.db.loot.dkp.pools
    pools[pool] = pools[pool] or {}
    local old = pools[pool][key] or 0
    pools[pool][key] = old + (tonumber(delta) or 0)
    DB:Audit("dkp.adjust", "dkp", key, { pool = pool, old = old, new = pools[pool][key], reason = reason })
    changed()
    return true
end

function LD:AwardRaidDKP(amount, reason, pool)
    if not require() then return 0 end
    local n = 0
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        self:AdjustDKP(m.key, amount, reason, pool)
        n = n + 1
    end
    return n
end

function LD:DKPStandings(pool)
    local list = {}
    for key, v in pairs(BRL.db.loot.dkp.pools[pool or "default"] or {}) do list[#list + 1] = { key = key, value = v } end
    table.sort(list, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.key < b.key end)
    return list
end

---------------------------------------------------------------------------
-- EPGP
---------------------------------------------------------------------------
function LD:EPGP(key)
    local s = BRL.db.loot.epgp.standings[key] or { ep = 0, gp = 0 }
    local base = BRL.db.loot.epgp.baseGP or 100
    local gp = math.max(base, s.gp or 0)
    return s.ep or 0, gp, (s.ep or 0) / gp
end

function LD:AddEP(key, amount, reason)
    if not require() then return false end
    key = API.NormalizeName(key)
    local st = BRL.db.loot.epgp.standings
    st[key] = st[key] or { ep = 0, gp = 0 }
    st[key].ep = (st[key].ep or 0) + (tonumber(amount) or 0)
    DB:Audit("epgp.ep", "epgp", key, { amount = amount, reason = reason })
    changed()
    return true
end

function LD:AddGP(key, amount, reason)
    if not require() then return false end
    key = API.NormalizeName(key)
    local st = BRL.db.loot.epgp.standings
    st[key] = st[key] or { ep = 0, gp = 0 }
    st[key].gp = (st[key].gp or 0) + (tonumber(amount) or 0)
    DB:Audit("epgp.gp", "epgp", key, { amount = amount, reason = reason })
    changed()
    return true
end

function LD:Decay(percent)
    if not require() then return false end
    percent = U.Clamp(tonumber(percent) or 0, 0, 100)
    for _, s in pairs(BRL.db.loot.epgp.standings) do
        s.ep = math.floor((s.ep or 0) * (100 - percent) / 100)
        s.gp = math.floor((s.gp or 0) * (100 - percent) / 100)
    end
    DB:Audit("epgp.decay", "epgp", nil, { percent = percent })
    changed()
    return true
end

function LD:EPGPStandings()
    local list = {}
    for key in pairs(BRL.db.loot.epgp.standings) do
        local ep, gp, pr = self:EPGP(key)
        list[#list + 1] = { key = key, ep = ep, gp = gp, pr = pr }
    end
    table.sort(list, function(a, b) if a.pr ~= b.pr then return a.pr > b.pr end return a.key < b.key end)
    return list
end

---------------------------------------------------------------------------
-- Loot Council / 우선순위
---------------------------------------------------------------------------
function LD:Vote(id, key, delta)
    local r = self:Get(id)
    if not r or r.status ~= "open" or not require() then return false end
    local c = r.candidates[key]
    if not c then return false end
    c.votes = math.max(0, (c.votes or 0) + (delta or 1))
    changed()
    return true
end

function LD:SetPriorityList(itemKey, list)
    if not require() then return false end
    BRL.db.loot.priorities[itemKey] = list
    changed()
    return true
end

function LD:PriorityList(itemKey) return BRL.db.loot.priorities[itemKey] or {} end

-- 방식별 추천 수령자
function LD:Suggest(id)
    local r = self:Get(id)
    if not r then return nil end
    local best, bestVal
    if r.method == "roll" then return r.suggestedWinner end
    if r.method == "priority" then
        local itemKey = tostring(U.ItemIdFromLink(r.itemLink) or r.itemName)
        for _, key in ipairs(self:PriorityList(itemKey)) do
            if r.candidates[key] then return key end
        end
        return nil
    end
    for key, c in pairs(r.candidates) do
        local v
        if r.method == "dkp" then v = c.bid or self:DKP(key)
        elseif r.method == "epgp" then local _, _, pr = self:EPGP(key) v = pr
        elseif r.method == "council" then v = c.votes or 0 end
        if v and (not bestVal or v > bestVal or (v == bestVal and key < best)) then best, bestVal = key, v end
    end
    return best
end

-- 수령자 결정. cost: DKP 차감 / EPGP GP 부과
function LD:Award(id, key, cost)
    local r = self:Get(id)
    if not r or not require() then return false, "권한 없음" end
    if r.status ~= "open" then return false, "이미 분배된 아이템입니다 (중복 분배 방지)" end
    key = API.NormalizeName(key)
    if not key then return false, "수령자 오류" end
    cost = tonumber(cost) or 0
    r.status = "awarded"
    r.winnerKey = key
    r.winnerName = API.ShortName(key)
    r.cost = cost
    r.awardedAt = U.Now()
    if r.method == "dkp" and cost > 0 then self:AdjustDKP(key, -cost, "아이템: " .. (r.itemName or "?")) end
    if r.method == "epgp" and cost > 0 then self:AddGP(key, cost, "아이템: " .. (r.itemName or "?")) end
    DB:AddHistory(r, "winner", nil, key)
    DB:Audit("loot.award", "loot", r.id, { winner = key, method = r.method, cost = cost })
    BRL.ChatOut:Send(string.format("[분배] %s → %s (%s%s)", r.itemLink, r.winnerName, self:MethodName(r.method), cost > 0 and (" " .. cost) or ""))
    changed()
    return true
end

function LD:Cancel(id, reason)
    local r = self:Get(id)
    if not r or not require() then return false end
    if r.status == "awarded" then
        if r.method == "dkp" and (r.cost or 0) > 0 then self:AdjustDKP(r.winnerKey, r.cost, "분배 취소 환원") end
        if r.method == "epgp" and (r.cost or 0) > 0 then self:AddGP(r.winnerKey, -r.cost, "분배 취소 환원") end
    end
    DB:AddHistory(r, "status", r.status, "cancelled", reason)
    r.status = "cancelled"
    r.cancelReason = reason
    DB:Audit("loot.cancel", "loot", r.id, { reason = reason })
    changed()
    return true
end

-- 수령자 변경 (분배 결과 수정)
function LD:Modify(id, newKey, reason)
    local r = self:Get(id)
    if not r or r.status ~= "awarded" or not require() then return false end
    local cost, method = r.cost, r.method
    if method == "dkp" and cost > 0 then self:AdjustDKP(r.winnerKey, cost, "분배 수정 환원") end
    if method == "epgp" and cost > 0 then self:AddGP(r.winnerKey, -cost, "분배 수정 환원") end
    DB:AddHistory(r, "winner", r.winnerKey, newKey, reason)
    r.status = "open"
    return self:Award(id, newKey, cost)
end
