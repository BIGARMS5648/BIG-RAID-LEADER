-- BIG RAID LEADER - 보스 공략 / 전술 배치도 / 전투 타임라인 (BossPlan)
-- 기본 데이터(Data/Bosses.lua) 위에 공대장이 편집한 내용(db.bossPlans)을 덮어쓴다.
-- 타임라인은 공대장의 수동 시작/단계 진행 기준이며 전투 정보를 임의로 읽어 자동 판단하지 않는다.
local _, BRL = ...
local DB = BRL.DB
local U, API = BRL.Util, BRL.API

local BP = BRL:NewModule("BossPlans")

BP.TOKEN_KINDS = {
    { key = "tank", name = "탱커", color = { 0.3, 0.6, 1 } },
    { key = "healer", name = "힐러", color = { 0.3, 1, 0.4 } },
    { key = "melee", name = "근접", color = { 1, 0.5, 0.2 } },
    { key = "ranged", name = "원거리", color = { 0.9, 0.3, 0.9 } },
    { key = "group", name = "파티", color = { 0.9, 0.9, 0.3 } },
    { key = "player", name = "공대원", color = { 1, 1, 1 } },
    { key = "boss", name = "보스", color = { 0.9, 0.1, 0.1 } },
    { key = "danger", name = "위험 구역", color = { 1, 0.1, 0.1 } },
    { key = "zone", name = "담당 구역", color = { 0.4, 0.8, 0.8 } },
    { key = "move", name = "이동 경로", color = { 1, 1, 0.6 } },
    { key = "marker", name = "징표", color = { 1, 0.85, 0.3 } },
}

BP.timer = nil

local function plans() return BRL.db.bossPlans end
local function changed(key) BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "boss", key) end

function BP:OnEnable()
    BRL.Events:Register("ENCOUNTER_START", self, "OnEncounterStart")
    BRL.Events:Register("ENCOUNTER_END", self, "OnEncounterEnd")
end

-- 병합된 보스 계획
function BP:Get(bossKey)
    local base = BRL.Data.Bosses[bossKey]
    local user = plans()[bossKey]
    if not base and not user then return nil end
    local merged = U.DeepCopy(base or {})
    for k, v in pairs(user or {}) do merged[k] = U.DeepCopy(v) end
    merged.key = bossKey
    merged.edited = user ~= nil
    return merged
end

function BP:List(raidKey)
    local out = {}
    for _, b in ipairs(BRL.Data.BossesForRaid(raidKey)) do out[#out + 1] = self:Get(b.key) end
    for key, p in pairs(plans()) do
        if p.custom and p.raid == raidKey then out[#out + 1] = self:Get(key) end
    end
    table.sort(out, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return out
end

function BP:Set(bossKey, field, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    plans()[bossKey] = plans()[bossKey] or {}
    plans()[bossKey][field] = U.DeepCopy(value)
    if field == "name" then plans()[bossKey].verified = true end
    changed(bossKey)
    return true
end

function BP:ResetToDefault(bossKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    local p = plans()[bossKey]
    if p and p.custom then return false, "사용자 보스는 초기화할 수 없습니다" end
    plans()[bossKey] = nil
    changed(bossKey)
    return true
end

function BP:AddBoss(raidKey, name)
    if not BRL.Perm:Require("raid.plan") then return nil end
    name = U.Trim(name or "")
    if name == "" then return nil end
    local key = "CUSTOM_" .. BRL.NewId("B")
    local count = #self:List(raidKey)
    plans()[key] = {
        custom = true, raid = raidKey, order = count + 1, name = name, verified = true,
        summary = "", abilities = {}, phases = { { name = "1단계", text = "" } }, tank = "", healer = "", dps = "",
        interrupts = {}, dispels = {}, cc = {}, dangers = {}, formation = "", notes = "", loot = {}, timeline = {},
    }
    changed(key)
    return key
end

function BP:RemoveBoss(bossKey)
    if not BRL.Perm:Require("raid.plan") then return false end
    local p = plans()[bossKey]
    if not p or not p.custom then return false end
    plans()[bossKey] = nil
    changed(bossKey)
    return true
end

-- 기술/단계 편집
function BP:AddListItem(bossKey, field, item)
    local plan = self:Get(bossKey)
    if not plan then return false end
    local list = plan[field] or {}
    list[#list + 1] = item
    return self:Set(bossKey, field, list)
end

function BP:RemoveListItem(bossKey, field, index)
    local plan = self:Get(bossKey)
    if not plan or not plan[field] or not plan[field][index] then return false end
    local list = plan[field]
    table.remove(list, index)
    return self:Set(bossKey, field, list)
end

---------------------------------------------------------------------------
-- 전술 배치도 (좌표 0~1 정규화)
---------------------------------------------------------------------------
function BP:GetLayout(bossKey, phase)
    local plan = self:Get(bossKey)
    phase = phase or 1
    local layouts = plan and plan.layouts or {}
    return layouts[phase] or { tokens = {} }
end

local function saveLayout(self, bossKey, phase, layout)
    local plan = self:Get(bossKey)
    local layouts = plan and plan.layouts or {}
    layouts[phase or 1] = layout
    return self:Set(bossKey, "layouts", layouts)
end

function BP:AddToken(bossKey, phase, kind, label, x, y)
    local layout = self:GetLayout(bossKey, phase)
    local tok = { id = BRL.NewId("TK"), kind = kind, label = label or "", x = U.Clamp(x or 0.5, 0, 1), y = U.Clamp(y or 0.5, 0, 1) }
    table.insert(layout.tokens, tok)
    if saveLayout(self, bossKey, phase, layout) then return tok end
    return nil
end

function BP:MoveToken(bossKey, phase, tokenId, x, y)
    local layout = self:GetLayout(bossKey, phase)
    for _, t in ipairs(layout.tokens) do
        if t.id == tokenId then
            t.x, t.y = U.Clamp(x, 0, 1), U.Clamp(y, 0, 1)
            return saveLayout(self, bossKey, phase, layout)
        end
    end
    return false
end

function BP:UpdateToken(bossKey, phase, tokenId, fields)
    local layout = self:GetLayout(bossKey, phase)
    for _, t in ipairs(layout.tokens) do
        if t.id == tokenId then
            for k, v in pairs(fields) do t[k] = v end
            return saveLayout(self, bossKey, phase, layout)
        end
    end
    return false
end

function BP:RemoveToken(bossKey, phase, tokenId)
    local layout = self:GetLayout(bossKey, phase)
    for i, t in ipairs(layout.tokens) do
        if t.id == tokenId then
            table.remove(layout.tokens, i)
            return saveLayout(self, bossKey, phase, layout)
        end
    end
    return false
end

function BP:ClearLayout(bossKey, phase)
    return saveLayout(self, bossKey, phase, { tokens = {} })
end

function BP:CopyLayout(bossKey, fromPhase, toPhase)
    local layout = U.DeepCopy(self:GetLayout(bossKey, fromPhase))
    for _, t in ipairs(layout.tokens) do t.id = BRL.NewId("TK") end
    return saveLayout(self, bossKey, toPhase, layout)
end

-- 배치도 템플릿 (기본 진형)
BP.LAYOUT_TEMPLATES = {
    {
        name = "기본 진형 (탱커 정면/근접 후방/원거리 반원)",
        tokens = {
            { kind = "boss", label = "보스", x = 0.5, y = 0.3 }, { kind = "tank", label = "MT", x = 0.5, y = 0.18 },
            { kind = "melee", label = "근접", x = 0.5, y = 0.42 }, { kind = "healer", label = "힐러", x = 0.35, y = 0.65 },
            { kind = "healer", label = "힐러", x = 0.65, y = 0.65 }, { kind = "ranged", label = "원거리", x = 0.5, y = 0.8 },
        },
    },
    {
        name = "산개 진형",
        tokens = {
            { kind = "boss", label = "보스", x = 0.5, y = 0.5 }, { kind = "tank", label = "MT", x = 0.5, y = 0.38 },
            { kind = "ranged", label = "원거리", x = 0.15, y = 0.8 }, { kind = "ranged", label = "원거리", x = 0.85, y = 0.8 },
            { kind = "healer", label = "힐러", x = 0.3, y = 0.9 }, { kind = "healer", label = "힐러", x = 0.7, y = 0.9 },
            { kind = "melee", label = "근접", x = 0.6, y = 0.55 },
        },
    },
}

function BP:ApplyLayoutTemplate(bossKey, phase, index)
    local tpl = self.LAYOUT_TEMPLATES[index]
    if not tpl then return false end
    local layout = { tokens = {} }
    for _, t in ipairs(tpl.tokens) do
        layout.tokens[#layout.tokens + 1] = { id = BRL.NewId("TK"), kind = t.kind, label = t.label, x = t.x, y = t.y }
    end
    return saveLayout(self, bossKey, phase, layout)
end

local AREAS = {
    { "북서", "북", "북동" }, { "서", "중앙", "동" }, { "남서", "남", "남동" },
}

-- 공유용 텍스트 (9구역 기준 위치 설명)
function BP:LayoutLines(bossKey, phase)
    local plan = self:Get(bossKey)
    local layout = self:GetLayout(bossKey, phase)
    local phaseName = plan and plan.phases and plan.phases[phase or 1] and plan.phases[phase or 1].name or ((phase or 1) .. "단계")
    local lines = { "[" .. (plan and plan.name or "?") .. " 배치도 - " .. phaseName .. "]" }
    local byArea = {}
    for _, t in ipairs(layout.tokens) do
        local col = math.min(3, math.floor(t.x * 3) + 1)
        local row = math.min(3, math.floor(t.y * 3) + 1)
        local area = AREAS[row][col]
        byArea[area] = byArea[area] or {}
        local kindName = t.kind
        for _, k in ipairs(self.TOKEN_KINDS) do if k.key == t.kind then kindName = k.name end end
        table.insert(byArea[area], (t.label ~= "" and t.label or kindName))
    end
    for _, row in ipairs(AREAS) do
        for _, area in ipairs(row) do
            if byArea[area] then lines[#lines + 1] = area .. ": " .. table.concat(byArea[area], ", ") end
        end
    end
    if #lines == 1 then lines[#lines + 1] = "배치 정보 없음" end
    return lines
end

---------------------------------------------------------------------------
-- 전투 타임라인 (수동)
---------------------------------------------------------------------------
function BP:AddTimelineEvent(bossKey, t, text, kind)
    local plan = self:Get(bossKey)
    if not plan then return false end
    local list = plan.timeline or {}
    list[#list + 1] = { t = math.max(0, math.floor(tonumber(t) or 0)), text = text or "", kind = kind or "note" }
    table.sort(list, function(a, b) return a.t < b.t end)
    return self:Set(bossKey, "timeline", list)
end

function BP:RemoveTimelineEvent(bossKey, index)
    return self:RemoveListItem(bossKey, "timeline", index)
end

function BP:StartTimer(bossKey)
    self.timer = { bossKey = bossKey, startClock = U.Clock(), phase = 1, phaseStart = U.Clock(), announced = {} }
    if not self.ticker then
        self.ticker = API.NewTicker(0.5, function() self:Tick() end)
    end
    BRL.Events:Fire(BRL.Events.MSG.PROGRESS_CHANGED)
end

function BP:StopTimer()
    self.timer = nil
    if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
    self.ticker = nil
    BRL.Events:Fire(BRL.Events.MSG.PROGRESS_CHANGED)
end

function BP:ResetTimer()
    if self.timer then self:StartTimer(self.timer.bossKey) end
end

function BP:NextPhase()
    if not self.timer then return end
    self.timer.phase = self.timer.phase + 1
    self.timer.phaseStart = U.Clock()
    BRL.Events:Fire(BRL.Events.MSG.PROGRESS_CHANGED)
end

function BP:Elapsed()
    if not self.timer then return 0 end
    return U.Clock() - self.timer.startClock
end

function BP:Upcoming(count)
    if not self.timer then return {} end
    local plan = self:Get(self.timer.bossKey)
    local elapsed = self:Elapsed()
    local out = {}
    for i, e in ipairs(plan and plan.timeline or {}) do
        if e.t + 1 >= elapsed then
            out[#out + 1] = { index = i, t = e.t, text = e.text, kind = e.kind, inSec = e.t - elapsed }
            if #out >= (count or 5) then break end
        end
    end
    return out
end

function BP:Tick()
    if not self.timer then return end
    local plan = self:Get(self.timer.bossKey)
    local elapsed = self:Elapsed()
    for i, e in ipairs(plan and plan.timeline or {}) do
        if not self.timer.announced[i] and elapsed >= e.t - 3 and elapsed < e.t + 1 then
            self.timer.announced[i] = true
            -- 채팅 잠금 중일 수 있으므로 화면 알림만 사용
            API.ScreenAlert("[" .. U.FormatDuration(e.t) .. "] " .. (e.text or ""))
        end
    end
    BRL.Events:Fire(BRL.Events.MSG.PROGRESS_CHANGED)
end

---------------------------------------------------------------------------
-- 우두머리 전투 이벤트 → 보스 식별 (이름 자동 갱신)
---------------------------------------------------------------------------
function BP:ResolveEncounter(encounterID, encounterName)
    encounterID = API.Safe(encounterID, nil)
    encounterName = API.Safe(encounterName, nil)
    local session = BRL.Session:GetActive()
    local raidKey = session and session.raidKey
    -- 1) 이미 매핑된 encounterID
    for key, p in pairs(plans()) do
        if encounterID and p.encounterId == encounterID then return key end
    end
    -- 2) 이름 일치
    if encounterName then
        for key, b in pairs(BRL.Data.Bosses) do
            local plan = self:Get(key)
            if plan.name == encounterName or b.nameEn == encounterName then return key end
        end
    end
    -- 3) 현재 선택된 보스가 미확인이면 매핑
    local cur = BRL.RaidProgress and BRL.RaidProgress:GetCurrentBoss()
    if cur then
        local plan = self:Get(cur)
        if plan and not plan.encounterId and (raidKey == nil or plan.raid == raidKey) then
            plans()[cur] = plans()[cur] or {}
            plans()[cur].encounterId = encounterID
            if encounterName and plan.verified == false then
                plans()[cur].name = encounterName
                plans()[cur].verified = true
                BRL:Print("우두머리 이름을 게임 정보로 갱신했습니다: %s", encounterName)
            end
            changed(cur)
            return cur
        end
    end
    return nil
end

function BP:OnEncounterStart(_, encounterID, encounterName)
    local key = self:ResolveEncounter(encounterID, encounterName)
    if key then
        if BRL.RaidProgress then BRL.RaidProgress:StartAttempt(key, true) end
        local plan = self:Get(key)
        if plan and plan.timeline and #plan.timeline > 0 then self:StartTimer(key) end
    end
end

function BP:OnEncounterEnd(_, encounterID, encounterName, _, _, success)
    local key = self:ResolveEncounter(encounterID, encounterName)
    if key and BRL.RaidProgress then
        BRL.RaidProgress:EndAttempt(key, success == 1 or success == true, true)
    end
    self:StopTimer()
end

---------------------------------------------------------------------------
-- 보스 준비 적용: 현재 보스 지정 + 보스 편성 템플릿 불러오기 + 전술표/징표/메모/필수 버프 화면이
-- 이 보스를 따라가도록 활성 전술표 지정. 실제 파티 이동은 공대장 확인 후(UI) Groups:Apply 로 한다.
---------------------------------------------------------------------------
function BP:GroupTemplateName(bossKey)
    local p = self:Get(bossKey)
    local templates = BRL.db.raidOps.groupTemplates
    for _, name in ipairs({ "보스:" .. bossKey, p and ("보스:" .. p.name) or nil }) do
        if name and templates[name] then return name end
    end
    return nil
end

function BP:SaveGroupTemplate(bossKey)
    local p = self:Get(bossKey)
    if not p then return false end
    return BRL.Groups:SaveTemplate("보스:" .. p.name), "보스:" .. p.name
end

function BP:ActivePlanKey()
    return BRL.db.raidOps.activePlanKey or "default"
end

function BP:SetActivePlan(planKey)
    local ops = BRL.db.raidOps
    ops.activePlanKey = planKey or "default"
    ops.activePlanVersion = (ops.activePlanVersion or 0) + 1
end

function BP:ApplyPrep(bossKey)
    if not BRL.Perm:Require("raid.plan") then return nil, "권한 없음" end
    local p = self:Get(bossKey)
    if not p then return nil, "보스 정보 없음" end
    local res = { bossKey = bossKey, name = p.name }
    BRL.RaidProgress:SetCurrentBoss(bossKey)
    self:SetActivePlan(bossKey)
    local tpl = self:GroupTemplateName(bossKey)
    if tpl and BRL.Groups:LoadTemplate(tpl) then res.groupTemplate = tpl end
    local assigned = 0
    for _, d in ipairs(BRL.Roles.DUTIES) do assigned = assigned + #BRL.Roles:GetAssignees(bossKey, d.key) end
    res.duties = assigned
    res.markers = U.Count(BRL.Command:GetMarkerPlan(bossKey))
    res.required = #BRL.Buffs:RequiredList(bossKey)
    res.warnings = BRL.Roles:Validate(bossKey)
    DB:Audit("boss.prep", "boss", bossKey, { groupTemplate = res.groupTemplate })
    changed(bossKey)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "plan")
    return res
end

function BP:PrepLines(res)
    local lines = { "[" .. res.name .. " 준비 적용]" }
    lines[#lines + 1] = res.groupTemplate and ("편성: '" .. res.groupTemplate .. "' 불러옴 (실제 파티 적용은 확인 후)") or "편성: 보스 편성 템플릿 없음 (편성 화면에서 '보스:" .. res.name .. "' 이름으로 저장하면 자동으로 불러옵니다)"
    lines[#lines + 1] = string.format("전술 임무 %d건 · 징표 규칙 %d개 · 필수 버프 %d종", res.duties, res.markers, res.required)
    for _, w in ipairs(res.warnings or {}) do lines[#lines + 1] = "확인: " .. w end
    return lines
end

---------------------------------------------------------------------------
-- 브리핑
---------------------------------------------------------------------------
function BP:BriefingLines(bossKey)
    local p = self:Get(bossKey)
    if not p then return { "공략 정보 없음" } end
    local lines = { "[" .. p.name .. " 공략]" .. (p.verified == false and " (미확인 정보)" or "") }
    if p.summary and p.summary ~= "" then lines[#lines + 1] = p.summary end
    if p.tank and p.tank ~= "" then lines[#lines + 1] = "탱커: " .. p.tank end
    if p.healer and p.healer ~= "" then lines[#lines + 1] = "힐러: " .. p.healer end
    if p.dps and p.dps ~= "" then lines[#lines + 1] = "딜러: " .. p.dps end
    if p.dangers and #p.dangers > 0 then lines[#lines + 1] = "주의: " .. table.concat(p.dangers, ", ") end
    if p.formation and p.formation ~= "" then lines[#lines + 1] = "진형: " .. p.formation end
    return lines
end

