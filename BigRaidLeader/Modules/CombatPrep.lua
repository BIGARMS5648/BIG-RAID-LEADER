-- BIG RAID LEADER - 전투 준비 (도핑 점검)
-- [전투 준비] 버튼: 공대원 버프를 다시 읽어 음식 · 영약/비약 · 필수 직업 버프가 없는 사람을 알려준다.
-- 전투 중에는 오라를 읽지 않으며(전투 밖에서만 점검), Secret Value/오프라인은 "확인 불가"로 따로 표시한다.
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local CP = BRL:NewModule("CombatPrep")

CP.last = nil

CP.MODES = {
    { value = "flask_or_elixir", text = "영약 또는 비약" },
    { value = "flask", text = "영약 필수" },
    { value = "elixir", text = "비약 필수" },
    { value = "none", text = "점검 안 함" },
}

local UNAVAILABLE_LABEL = { offline = "오프라인", combat = "전투 중", secret = "확인 불가", unsupported = "확인 불가", unknown = "확인 불가", unscanned = "미점검" }
CP.UNAVAILABLE_LABEL = UNAVAILABLE_LABEL

local function cfg() return BRL.acct.consumables end

function CP:MainLabel()
    local mode = cfg().mainMode
    if mode == "flask" then return "영약" end
    if mode == "elixir" then return "비약" end
    return "영약/비약"
end

local function fmtMin(sec)
    if not sec then return "" end
    return math.max(0, math.floor(sec / 60)) .. "분"
end

-- 버프 점검 결과 한 명 평가
function CP:EvaluateMember(member, r, required)
    local c = cfg()
    local row = { key = member.key, member = member, missing = {}, expiring = {}, buffsMissing = {} }
    if not r then
        row.unavailable = "unscanned"
        return row
    end
    if r.unavailable then
        row.unavailable = r.unavailable
        return row
    end
    local cons = r.consumables or {}
    local warn = (BRL.acct.buffs.expireWarnMinutes or 5) * 60
    row.food = cons.FOOD
    row.flask = cons.FLASK
    row.elixirCount = cons.ELIXIR and cons.ELIXIR.count or 0
    row.elixir = cons.ELIXIR
    if c.requireFood then
        if not cons.FOOD then
            row.missing[#row.missing + 1] = "음식"
        elseif cons.FOOD.remaining and cons.FOOD.remaining < warn then
            row.expiring[#row.expiring + 1] = "음식 " .. fmtMin(cons.FOOD.remaining)
        end
    end
    local mode = c.mainMode
    local minE = math.max(1, tonumber(c.minElixirs) or 1)
    local mainOk, mainRemaining
    if mode == "flask" then
        mainOk = cons.FLASK ~= nil
        mainRemaining = cons.FLASK and cons.FLASK.remaining
    elseif mode == "elixir" then
        mainOk = row.elixirCount >= minE
        mainRemaining = cons.ELIXIR and cons.ELIXIR.remaining
    elseif mode == "flask_or_elixir" then
        mainOk = cons.FLASK ~= nil or row.elixirCount >= minE
        mainRemaining = (cons.FLASK and cons.FLASK.remaining) or (cons.ELIXIR and cons.ELIXIR.remaining)
    else
        mainOk = true
    end
    if not mainOk then
        local label = self:MainLabel()
        if mode ~= "flask" and row.elixirCount > 0 then label = label .. " (" .. row.elixirCount .. "/" .. minE .. ")" end
        row.missing[#row.missing + 1] = label
    elseif mode ~= "none" and mainRemaining and mainRemaining < warn then
        row.expiring[#row.expiring + 1] = self:MainLabel() .. " " .. fmtMin(mainRemaining)
    end
    if c.checkClassBuffs then
        for _, b in ipairs(required or {}) do
            if not (r.buffs[b.key] and r.buffs[b.key].present) then
                row.buffsMissing[#row.buffsMissing + 1] = b
            end
        end
    end
    if c.expiringAsMissing then
        for _, e in ipairs(row.expiring) do row.missing[#row.missing + 1] = e .. " 남음" end
    end
    row.ok = #row.missing == 0 and #row.buffsMissing == 0
    return row
end

-- 마지막 버프 점검 결과로 평가 (재검사하지 않음)
function CP:Evaluate(bossKey)
    local required = BRL.Buffs:RequiredList(bossKey)
    local res = { at = U.Now(), rows = {}, total = 0, checked = 0, okCount = 0,
        noFood = {}, noMain = {}, expiring = {}, unavailable = {}, buffMissing = {}, bossKey = bossKey }
    for _, m in ipairs(BRL.Roster:Sorted("group")) do
        local row = self:EvaluateMember(m, BRL.Buffs.results[m.key], required)
        res.rows[#res.rows + 1] = row
        res.total = res.total + 1
        if row.unavailable then
            res.unavailable[#res.unavailable + 1] = row
        else
            res.checked = res.checked + 1
            if row.ok then res.okCount = res.okCount + 1 end
            for _, x in ipairs(row.missing) do
                if x == "음식" then res.noFood[#res.noFood + 1] = row
                elseif not x:find("남음$") then res.noMain[#res.noMain + 1] = row end
            end
            if #row.expiring > 0 then res.expiring[#res.expiring + 1] = row end
            for _, b in ipairs(row.buffsMissing) do
                res.buffMissing[b.key] = res.buffMissing[b.key] or { buff = b, rows = {} }
                table.insert(res.buffMissing[b.key].rows, row)
            end
        end
    end
    return res
end

-- [전투 준비] 실행: 버프 재검사 → 도핑 평가 → (설정 시) 준비 확인/공지 → 결과 창
function CP:Run(opts)
    opts = opts or {}
    if API.InCombat() then
        BRL:Print("전투 중에는 도핑을 점검할 수 없습니다. 전투 종료 후 다시 누르세요.")
        return nil, "combat"
    end
    BRL.Buffs:Scan()
    local bossKey = opts.bossKey or (BRL.RaidProgress and BRL.RaidProgress:GetCurrentBoss())
    local res = self:Evaluate(bossKey)
    self.last = res
    local c = cfg()
    if c.withReadyCheck and API.IsInGroup() and BRL.Perm:Can("raid.command") then BRL.Readiness:Start() end
    if c.autoAnnounce and API.IsInGroup() and BRL.Perm:Can("raid.command") then BRL.ChatOut:SendLines(self:Lines(res)) end
    if opts.silent or not BRL.PrepReport then -- 결과 창을 띄우면 채팅 요약은 생략 (중복)
        BRL:Print("전투 준비 점검: 도핑 완료 %d/%d · 음식 없음 %d · %s 없음 %d%s", res.okCount, res.checked, #res.noFood, self:MainLabel(),
            #res.noMain, #res.unavailable > 0 and (" · 확인 불가 " .. #res.unavailable) or "")
    end
    BRL.Events:Fire(BRL.Events.MSG.READY_CHANGED)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "prep")
    if not opts.silent and BRL.PrepReport then BRL.PrepReport:Show(res) end
    return res
end

local function names(rows, extra)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.member.short .. (extra and extra(r) or "") end
    return table.concat(out, ", ")
end

function CP:Lines(res)
    res = res or self.last
    if not res then return { "[BIG RAID LEADER 전투 준비] 점검 기록 없음" } end
    local lines = { string.format("[BIG RAID LEADER 전투 준비] 도핑 완료 %d/%d", res.okCount, res.checked) }
    if #res.noFood > 0 then lines[#lines + 1] = string.format("음식 없음(%d): %s", #res.noFood, names(res.noFood)) end
    if #res.noMain > 0 then lines[#lines + 1] = string.format("%s 없음(%d): %s", self:MainLabel(), #res.noMain, names(res.noMain)) end
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        local m = res.buffMissing[b.key]
        if m then lines[#lines + 1] = string.format("%s 없음(%d): %s", b.name, #m.rows, names(m.rows)) end
    end
    if #res.expiring > 0 then
        lines[#lines + 1] = "곧 만료: " .. names(res.expiring, function(r) return "(" .. table.concat(r.expiring, ", ") .. ")" end)
    end
    local unk = {}
    for _, r in ipairs(res.unavailable) do
        if r.unavailable ~= "offline" then unk[#unk + 1] = r end
    end
    if #unk > 0 then lines[#lines + 1] = string.format("확인 불가(%d): %s", #unk, names(unk)) end
    if #lines == 1 then lines[#lines + 1] = "전원 도핑 완료 - 전투 준비 끝!" end
    return lines
end

-- 누락자에게 개별 귓속말
function CP:WhisperMissing(res)
    res = res or self.last
    if not res then return 0 end
    if not BRL.Perm:Require("raid.command") then return 0 end
    local n = 0
    for _, row in ipairs(res.rows) do
        if not row.unavailable and not row.ok and row.key ~= BRL.playerKey then
            local need = {}
            for _, x in ipairs(row.missing) do need[#need + 1] = x end
            for _, b in ipairs(row.buffsMissing) do need[#need + 1] = b.name end
            BRL.ChatOut:Send("[BRL 전투 준비] 필요: " .. table.concat(need, ", "), "WHISPER", row.key)
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- 풀링 판정: 준비 확인 · 사망/부재 · 도핑 · 역할을 종합해 "풀링 가능/주의/보류"
---------------------------------------------------------------------------
CP.VERDICT = {
    go = { label = "풀링 가능", color = "green" },
    caution = { label = "주의 후 풀링", color = "yellow" },
    stop = { label = "풀링 보류", color = "red" },
}
local RANK = { go = 1, caution = 2, stop = 3 }

function CP:PullCheck()
    local level, reasons = "go", {}
    local function bump(l, text)
        if RANK[l] > RANK[level] then level = l end
        -- 보류 사유를 앞쪽에 둔다
        if l == "stop" then table.insert(reasons, 1, text) else reasons[#reasons + 1] = text end
    end
    if API.InCombat() then
        local v = self.VERDICT.stop
        return { verdict = "stop", label = "전투 중", color = v.color, reasons = { "전투 중입니다" } }
    end
    local inGroup = API.IsInGroup()
    if not inGroup then bump("caution", "그룹이 아닙니다") end
    local rs = BRL.Readiness:Summary()
    if inGroup then
        if rs.dead > 0 then bump("stop", "사망 " .. rs.dead .. "명") end
        if rs.offline > 0 then bump("caution", "오프라인 " .. rs.offline .. "명") end
        if rs.absent > 0 then bump("caution", "다른 지역 " .. rs.absent .. "명") end
        if not rs.checked then
            bump("caution", "준비 확인 미실시")
        elseif rs.active then
            bump("caution", "준비 확인 진행 중")
        else
            if rs.notready > 0 then bump("stop", "준비 안 됨 " .. rs.notready .. "명") end
            if rs.noresponse > 0 then bump("caution", "준비 확인 무응답 " .. rs.noresponse .. "명") end
            local age = U.Now() - (BRL.Readiness.check.finishedAt or BRL.Readiness.check.startedAt or 0)
            if age > 300 then bump("caution", "준비 확인 " .. math.floor(age / 60) .. "분 지남") end
        end
        local _, counts = BRL.Roster:Warnings()
        -- 역할은 직업 기본값으로 추정하므로 보류가 아닌 주의로만 알린다
        if (counts.TANK or 0) == 0 then bump("caution", "탱커 미지정 (역할 화면)") end
        if (counts.HEALER or 0) == 0 then bump("caution", "힐러 없음") end
    end
    local last = self.last
    if not last then
        bump("caution", "도핑 점검 안 함 ([전투 준비])")
    else
        local age = U.Now() - (last.at or 0)
        if age > 600 then bump("caution", "도핑 점검 " .. math.floor(age / 60) .. "분 지남") end
        local miss = {}
        for _, r in ipairs(last.noFood) do miss[r.key] = true end
        for _, r in ipairs(last.noMain) do miss[r.key] = true end
        local n = U.Count(miss)
        if n > 0 then bump("caution", "도핑 누락 " .. n .. "명") end
        local bm = 0
        for _ in pairs(last.buffMissing) do bm = bm + 1 end
        if bm > 0 then bump("caution", "필수 버프 누락 " .. bm .. "종") end
    end
    if BRL.Buffs.needsRecheck then bump("caution", "전멸 후 재점검 필요") end
    if rs.lowDurability > 0 then bump("caution", "내 장비 내구도 낮음") end
    local v = self.VERDICT[level]
    return { verdict = level, label = v.label, color = v.color, reasons = reasons }
end

function CP:PullCheckLines(pc)
    pc = pc or self:PullCheck()
    local lines = { "[BIG RAID LEADER 풀링 판정] " .. pc.label }
    if #pc.reasons > 0 then lines[#lines + 1] = table.concat(pc.reasons, " · ") end
    return lines
end

---------------------------------------------------------------------------
-- 전멸 복구: 우두머리 전투 실패 → 전투 종료 후 사망자 · 영혼석 · 재버프 · 도핑 점검
---------------------------------------------------------------------------
function CP:OnEnable()
    BRL.Events:Register("ENCOUNTER_END", self, function(_, _, encounterID, encounterName, _, _, success)
        if success == 1 or success == true then self.pendingWipe = nil return end
        local key = BRL.BossPlans and BRL.BossPlans:ResolveEncounter(encounterID, encounterName)
        self.pendingWipe = { bossKey = key, name = API.Safe(encounterName, nil), clock = U.Clock() }
        if not API.InCombat() then self:ScheduleWipeRecovery() end
    end)
    BRL.Events:Register("PLAYER_REGEN_ENABLED", self, function()
        if self.pendingWipe then self:ScheduleWipeRecovery() end
    end)
end

function CP:ScheduleWipeRecovery()
    if BRL.acct.consumables.wipeRecovery == false then self.pendingWipe = nil return end
    local wipe = self.pendingWipe
    if not wipe or wipe.scheduled then return end
    wipe.scheduled = true
    -- 전투 종료 직후 사망/오라 정보가 갱신될 시간을 둔다
    API.After(1.5, function()
        if self.pendingWipe ~= wipe then return end
        self.pendingWipe = nil
        if API.InCombat() then return end
        self:WipeRecovery(wipe.bossKey, { name = wipe.name })
    end)
end

function CP:WipeRecovery(bossKey, opts)
    opts = opts or {}
    if API.InCombat() then return nil, "combat" end
    BRL.Roster:Refresh()
    BRL.Buffs:Scan()
    local res = self:Evaluate(bossKey or (BRL.RaidProgress and BRL.RaidProgress:GetCurrentBoss()))
    local wipe = { dead = {}, soulstones = {}, deadWithStone = {}, rebuff = {}, name = opts.name }
    for _, m in ipairs(BRL.Roster:Sorted("group")) do
        local r = BRL.Buffs.results[m.key]
        local stone = r and r.soulstone
        if m.dead then
            wipe.dead[#wipe.dead + 1] = m
            if stone then wipe.deadWithStone[#wipe.deadWithStone + 1] = m end
        end
        if stone then wipe.soulstones[#wipe.soulstones + 1] = m end
    end
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        local mb = res.buffMissing[b.key]
        if mb then wipe.rebuff[#wipe.rebuff + 1] = { buff = b, count = #mb.rows, provider = BRL.Buffs:GetProvider(b.key) } end
    end
    res.wipe = wipe
    self.last = res
    if opts.silent or not BRL.PrepReport then
        BRL:Print("전멸 복구 점검: 사망 %d명 · 영혼석 %d명 · 재버프 필요 %d종 · 도핑 누락 %d명", #wipe.dead, #wipe.soulstones, #wipe.rebuff, #res.noFood + #res.noMain)
    end
    BRL.Events:Fire(BRL.Events.MSG.READY_CHANGED)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "prep")
    if not opts.silent and BRL.PrepReport then BRL.PrepReport:Show(res) end
    return res
end

function CP:WipeLines(res)
    res = res or self.last
    local w = res and res.wipe
    if not w then return { "[BIG RAID LEADER 전멸 복구] 기록 없음" } end
    local function list(ms)
        local out = {}
        for _, m in ipairs(ms) do out[#out + 1] = m.short end
        return table.concat(out, ", ")
    end
    local lines = { "[BIG RAID LEADER 전멸 복구]" .. (w.name and (" " .. w.name) or "") }
    lines[#lines + 1] = "사망 " .. #w.dead .. "명" .. (#w.dead > 0 and (": " .. list(w.dead)) or "")
    if #w.deadWithStone > 0 then lines[#lines + 1] = "영혼석 부활 가능: " .. list(w.deadWithStone) end
    local rb = {}
    for _, e in ipairs(w.rebuff) do rb[#rb + 1] = e.buff.name .. (e.provider and ("(" .. API.ShortName(e.provider) .. ")") or "") end
    if #rb > 0 then lines[#lines + 1] = "재버프 필요: " .. table.concat(rb, ", ") end
    if #res.noFood + #res.noMain > 0 then
        lines[#lines + 1] = string.format("도핑 누락: 음식 %d명 · %s %d명", #res.noFood, self:MainLabel(), #res.noMain)
    end
    lines[#lines + 1] = "부활 → 재버프 → 도핑 → 준비 확인 순서로 정비합니다."
    return lines
end

-- 특정 공대원의 마지막 도핑 상태 (준비 상태 화면용)
function CP:RowFor(key)
    if not self.last then return nil end
    for _, r in ipairs(self.last.rows) do if r.key == key then return r end end
    return nil
end
