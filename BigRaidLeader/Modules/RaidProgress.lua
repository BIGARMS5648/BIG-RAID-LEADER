-- BIG RAID LEADER - 보스 진행 관리 (BossProgress)
-- ENCOUNTER_START/END 이벤트 + 공대장 수동 기록. 현재 공격대 세션 단위.
local _, BRL = ...
local U = BRL.Util

local P = BRL:NewModule("RaidProgress")

local function changed() BRL.Events:Fire(BRL.Events.MSG.PROGRESS_CHANGED) end

local function store(sessionId)
    sessionId = sessionId or (BRL.Session:GetActive() or {}).id or "default"
    local all = BRL.db.progress
    all[sessionId] = all[sessionId] or { bosses = {}, currentBoss = nil }
    return all[sessionId]
end

function P:Boss(bossKey, sessionId)
    local s = store(sessionId)
    s.bosses[bossKey] = s.bosses[bossKey] or { attempts = 0, wipes = 0, kills = 0, durations = {}, notes = "", retry = "", nextChanges = "" }
    return s.bosses[bossKey]
end

function P:GetCurrentBoss(sessionId) return store(sessionId).currentBoss end

function P:SetCurrentBoss(bossKey)
    store().currentBoss = bossKey
    changed()
end

function P:StartAttempt(bossKey, auto)
    if not auto and not BRL.Perm:Require("raid.command") then return false end
    local b = self:Boss(bossKey)
    if b.inProgress then return true end
    b.inProgress = true
    b.lastStart = U.Now()
    b.lastStartClock = U.Clock()
    b.attempts = b.attempts + 1
    store().currentBoss = bossKey
    changed()
    return true
end

function P:EndAttempt(bossKey, success, auto)
    if not auto and not BRL.Perm:Require("raid.command") then return false end
    local b = self:Boss(bossKey)
    if not b.inProgress then
        -- 시작 기록이 없으면 시도 1회로 간주
        b.attempts = b.attempts + 1
    end
    local duration = b.lastStartClock and math.floor(U.Clock() - b.lastStartClock) or nil
    b.inProgress = false
    if duration then table.insert(b.durations, { d = duration, success = success and true or false, at = U.Now() }) end
    if success then
        b.kills = b.kills + 1
        b.killedAt = b.killedAt or U.Now()
        b.killTime = duration or b.killTime
    else
        b.wipes = b.wipes + 1
    end
    changed()
    return true
end

function P:MarkKilled(bossKey, killed)
    if not BRL.Perm:Require("raid.command") then return false end
    local b = self:Boss(bossKey)
    if killed then
        if b.kills == 0 then b.kills = 1 b.killedAt = U.Now() end
    else
        b.kills = 0
        b.killedAt = nil
    end
    changed()
    return true
end

function P:SetText(bossKey, field, text)
    if not BRL.Perm:Require("raid.plan") then return false end
    if field ~= "notes" and field ~= "retry" and field ~= "nextChanges" then return false end
    self:Boss(bossKey)[field] = text
    changed()
    return true
end

function P:Reset(bossKey)
    if not BRL.Perm:Require("raid.command") then return false end
    store().bosses[bossKey] = nil
    changed()
    return true
end

-- 세션 진행 요약
function P:Summary(sessionId)
    local session = sessionId and BRL.Session:Get(sessionId) or BRL.Session:GetActive()
    local s = store(session and session.id)
    local raidKey = session and session.raidKey
    local bosses = raidKey and BRL.BossPlans:List(raidKey) or {}
    local res = { total = #bosses, killed = 0, attempts = 0, wipes = 0, rows = {} }
    for _, plan in ipairs(bosses) do
        local b = s.bosses[plan.key] or { attempts = 0, wipes = 0, kills = 0, durations = {} }
        local best
        for _, d in ipairs(b.durations or {}) do if d.success and (not best or d.d < best) then best = d.d end end
        res.rows[#res.rows + 1] = { plan = plan, progress = b, killed = (b.kills or 0) > 0, bestKill = best or b.killTime }
        if (b.kills or 0) > 0 then res.killed = res.killed + 1 end
        res.attempts = res.attempts + (b.attempts or 0)
        res.wipes = res.wipes + (b.wipes or 0)
    end
    -- 공략 목록 밖의 보스 기록
    for key, b in pairs(s.bosses) do
        local found = false
        for _, row in ipairs(res.rows) do if row.plan.key == key then found = true end end
        if not found then
            local plan = BRL.BossPlans:Get(key) or { key = key, name = key }
            res.rows[#res.rows + 1] = { plan = plan, progress = b, killed = (b.kills or 0) > 0, bestKill = b.killTime }
            res.attempts = res.attempts + (b.attempts or 0)
            res.wipes = res.wipes + (b.wipes or 0)
        end
    end
    res.percent = res.total > 0 and math.floor(res.killed / res.total * 100 + 0.5) or 0
    if session then
        res.elapsed = (session.closedAt or U.Now()) - (session.startedAt or session.createdAt or U.Now())
    end
    res.currentBoss = s.currentBoss
    return res
end
