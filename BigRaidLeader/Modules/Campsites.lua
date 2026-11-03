-- BIG RAID LEADER - 포에버 야영지 효과 관리 (버프 확인/전술 준비 전용)
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Camps = BRL:NewModule("Campsites")

local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "camps") end

local function store()
    local sid = (BRL.Session and BRL.Session:GetActive() or {}).id or "default"
    local all = BRL.db.raidOps.campStatus
    all[sid] = all[sid] or {}
    return all[sid]
end

function Camps:Status(key)
    local s = store()
    s[key] = s[key] or { prepared = false, verified = false }
    return s[key]
end

function Camps:Set(key, field, value)
    if not BRL.Perm:Require("raid.command") then return false end
    local st = self:Status(key)
    st[field] = value
    st.updatedAt = U.Now()
    changed()
    return true
end

function Camps:SetAssignee(key, memberKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    self:Status(key).assignee = memberKey
    changed()
    return true
end

-- 보스별 필요한 야영지 효과
function Camps:BossRequirements(bossKey)
    local all = BRL.db.raidOps.campBoss or {}
    return all[bossKey] or {}
end

function Camps:SetBossRequirement(bossKey, key, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    BRL.db.raidOps.campBoss = BRL.db.raidOps.campBoss or {}
    BRL.db.raidOps.campBoss[bossKey] = BRL.db.raidOps.campBoss[bossKey] or {}
    BRL.db.raidOps.campBoss[bossKey][key] = value and true or nil
    changed()
    return true
end

-- 버프 점검 결과로 효과 적용 인원 확인
function Camps:Verify()
    local counts = {}
    local scanned = 0
    for _, r in pairs(BRL.Buffs.results or {}) do
        if r.camps then
            scanned = scanned + 1
            for key in pairs(r.camps) do counts[key] = (counts[key] or 0) + 1 end
        end
    end
    for _, c in ipairs(BRL.Data.CampFacilities) do
        local st = self:Status(c.key)
        st.appliedCount = counts[c.key] or 0
        st.scanned = scanned
        st.verified = scanned > 0 and (counts[c.key] or 0) > 0
    end
    changed()
    return counts, scanned
end

function Camps:Checklist(bossKey)
    local req = bossKey and self:BossRequirements(bossKey) or {}
    local rows = {}
    for _, c in ipairs(BRL.Data.CampFacilities) do
        local st = self:Status(c.key)
        rows[#rows + 1] = {
            facility = c, status = st, required = req[c.key] and true or false,
        }
    end
    return rows
end

function Camps:OutputLines(bossKey)
    local lines = { "[BIG RAID LEADER 야영지 효과]" }
    for _, row in ipairs(self:Checklist(bossKey)) do
        local st = row.status
        if row.required or st.prepared or st.assignee then
            lines[#lines + 1] = string.format("%s(%s 대체): %s%s%s", row.facility.name, row.facility.replacesName,
                st.prepared and "준비됨" or "미준비",
                st.assignee and (" / 담당 " .. API.ShortName(st.assignee)) or "",
                st.appliedCount and (" / 적용 " .. st.appliedCount .. "명") or "")
        end
    end
    if #lines == 1 then lines[#lines + 1] = "등록된 야영지 효과 계획 없음" end
    return lines
end
