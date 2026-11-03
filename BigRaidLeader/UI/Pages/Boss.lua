-- BIG RAID LEADER - 보스 공략 화면 (공략 / 배치도 / 타임라인 / 진행)
local _, BRL = ...
local T, W, L, U = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local BP, P = BRL.BossPlans, BRL.RaidProgress

local FIELD_LABELS = {
    summary = "개요", tank = "탱커 주의사항", healer = "힐러 주의사항", dps = "딜러 주의사항",
    formation = "추천 진형", notes = "공략 메모",
}

local function listText(list)
    if type(list) ~= "table" or #list == 0 then return T.Color("muted", "-") end
    local out = {}
    for _, v in ipairs(list) do out[#out + 1] = type(v) == "table" and (v.name or v.text or "?") or tostring(v) end
    return table.concat(out, ", ")
end

local function build(page)
    UI:PageHeader(page, L.MENU_BOSS, "공략 데이터 · 전술 배치도 · 전투 타임라인 · 진행 관리")
    page.phase = 1
    local raidItems = {}
    for _, r in ipairs(BRL.Data.RaidList()) do raidItems[#raidItems + 1] = { value = r.key, text = r.name .. " (" .. r.size .. "인)" } end
    page.raidDrop = W.Dropdown(page, 210, raidItems, function(v) page.raidKey = v page.bossKey = nil UI:RequestRefresh() end)
    page.raidDrop:SetPoint("TOPLEFT", 4, -28)
    page.bossList = W.List(page, {
        columns = {
            { title = "보스", width = 0, render = function(b)
                local prog = P:Boss(b.key)
                local mark = prog.kills > 0 and "|cff5cf272✔|r " or ""
                local cur = P:GetCurrentBoss() == b.key and "|cffffd100▶|r " or ""
                return cur .. mark .. b.name .. (b.verified == false and " |cff9e9a8f?|r" or "")
            end },
            { title = "시도", width = 34, align = "CENTER", render = function(b) local p = P:Boss(b.key) return p.attempts > 0 and p.attempts or "" end },
        },
        onClick = function(b) page.bossKey = b.key UI:RequestRefresh() end,
        tooltip = function(b) return b.name, { b.verified == false and "미확인 정보 (편집 가능)" or "확인됨", b.nameEn or "" } end,
    })
    page.bossList:SetPoint("TOPLEFT", 4, -56)
    page.bossList:SetSize(220, 470)
    local bl = CreateFrame("Frame", nil, page)
    bl:SetPoint("TOPLEFT", 4, -532)
    bl:SetSize(220, 26)
    local fb = W.Flow(bl, 0, 1, 4)
    fb:Add(W.Button(bl, "보스 추가", 70, 22, function()
        D.Input("보스 추가", { { key = "name", label = "보스 이름", type = "text", required = true } }, function(v)
            local key = BP:AddBoss(page.raidKey or "CUSTOM", v.name)
            if key then page.bossKey = key end
            return key ~= nil
        end)
    end, { perm = "raid.plan" }))
    fb:Add(W.Button(bl, "현재 보스", 70, 22, function() if page.bossKey then P:SetCurrentBoss(page.bossKey) end end, { perm = "raid.command" }))
    fb:Add(W.Button(bl, "삭제", 50, 22, function()
        if page.bossKey then D.Confirm("사용자 보스를 삭제할까요?", function() BP:RemoveBoss(page.bossKey) page.bossKey = nil end, { danger = true }) end
    end, { perm = "raid.plan" }))

    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", 234, -28)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    page.right = right
    page.bossTitle = W.Label(right, "", 15, "goldBright")
    page.bossTitle:SetPoint("TOPLEFT", 0, 0)
    page.panels = {}
    page.tabs = W.Tabs(right, {
        { key = "plan", text = "공략", width = 70 }, { key = "layout", text = "배치도", width = 70 },
        { key = "timeline", text = "타임라인", width = 80 }, { key = "progress", text = "진행", width = 60 },
    }, function(key)
        page.tab = key
        for k, p in pairs(page.panels) do if k == key then p:Show() else p:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPRIGHT", 0, 2)
    local function panel(key)
        local p = CreateFrame("Frame", nil, right)
        p:SetPoint("TOPLEFT", 0, -28)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = p
        return p
    end

    -- 공략
    local pp = panel("plan")
    pp.text = W.TextArea(pp, 640, 470, { readOnly = true })
    pp.text:SetPoint("TOPLEFT", 0, 0)
    local _, f1 = UI.BottomBar(pp, 0)
    f1:Add(W.Button(f1.parent, "항목 편집", 80, 24, function()
        if not page.bossKey then return end
        local items = {}
        for _, k in ipairs({ "summary", "tank", "healer", "dps", "formation", "notes" }) do items[#items + 1] = { value = k, text = FIELD_LABELS[k] } end
        items[#items + 1] = { value = "dangers", text = "주요 위험 요소 (쉼표 구분)" }
        items[#items + 1] = { value = "interrupts", text = "차단 기술 (쉼표 구분)" }
        items[#items + 1] = { value = "dispels", text = "해제 대상 (쉼표 구분)" }
        items[#items + 1] = { value = "cc", text = "군중제어 대상 (쉼표 구분)" }
        items[#items + 1] = { value = "loot", text = "전리품 목록 (쉼표 구분)" }
        D.Select("편집할 항목", items, function(field)
            local plan = BP:Get(page.bossKey)
            local isList = type(plan[field]) == "table"
            local cur = isList and table.concat(U.Map(plan[field], function(v) return type(v) == "table" and (v.name or v.text) or tostring(v) end), ", ") or (plan[field] or "")
            D.Input(plan.name .. " - 편집", { { key = "value", label = "내용", type = "multiline", height = 140, default = cur } }, function(v)
                if isList then
                    local list = {}
                    for _, part in ipairs(U.Split((v.value:gsub("\n", ",")), ",")) do
                        part = U.Trim(part)
                        if part ~= "" then list[#list + 1] = part end
                    end
                    return BP:Set(page.bossKey, field, list)
                end
                return BP:Set(page.bossKey, field, v.value)
            end)
        end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(f1.parent, "기술 추가", 76, 24, function()
        if not page.bossKey then return end
        D.Input("주요 기술 추가", {
            { key = "name", label = "기술 이름", type = "text", required = true },
            { key = "text", label = "설명", type = "text" },
        }, function(v) return BP:AddListItem(page.bossKey, "abilities", { name = v.name, text = v.text }) end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(f1.parent, "단계 추가", 76, 24, function()
        if not page.bossKey then return end
        D.Input("전투 단계 추가", {
            { key = "name", label = "단계 이름", type = "text", required = true },
            { key = "text", label = "공략", type = "multiline" },
        }, function(v) return BP:AddListItem(page.bossKey, "phases", { name = v.name, text = v.text }) end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(f1.parent, "이름 변경", 76, 24, function()
        if not page.bossKey then return end
        D.Input("보스 이름 변경", { { key = "name", label = "이름", type = "text", default = BP:Get(page.bossKey).name, required = true } },
            function(v) return BP:Set(page.bossKey, "name", v.name) end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(f1.parent, "기본값 복원", 84, 24, function()
        if page.bossKey then D.Confirm("편집 내용을 지우고 기본 데이터로 되돌릴까요?", function() BP:ResetToDefault(page.bossKey) end, { danger = true }) end
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(f1.parent, "공략 안내 출력", 100, 24, function() if page.bossKey then A.SendLines(BP:BriefingLines(page.bossKey), "공략 안내") end end))

    -- 배치도
    local pl = panel("layout")
    pl.phaseDrop = W.Dropdown(pl, 180, function()
        local items = {}
        local plan = page.bossKey and BP:Get(page.bossKey)
        local n = math.max(3, plan and #(plan.phases or {}) or 1)
        for i = 1, n do
            local name = plan and plan.phases and plan.phases[i] and plan.phases[i].name or (i .. "단계")
            items[#items + 1] = { value = i, text = name }
        end
        return items
    end, function(v) page.phase = v UI:RequestRefresh() end)
    pl.phaseDrop:SetPoint("TOPLEFT", 0, 0)
    local canvas = W.Panel(pl, { 0.08, 0.1, 0.08, 1 }, T.colors.border)
    canvas:SetPoint("TOPLEFT", 0, -28)
    canvas:SetSize(460, 400)
    pl.canvas = canvas
    for i = 1, 2 do
        local v = canvas:CreateTexture(nil, "BACKGROUND")
        v:SetTexture(T.WHITE)
        v:SetVertexColor(1, 1, 1, 0.05)
        v:SetSize(1, 400)
        v:SetPoint("TOPLEFT", 460 * i / 3, 0)
        local h = canvas:CreateTexture(nil, "BACKGROUND")
        h:SetTexture(T.WHITE)
        h:SetVertexColor(1, 1, 1, 0.05)
        h:SetSize(460, 1)
        h:SetPoint("TOPLEFT", 0, -400 * i / 3)
    end
    pl.tokens = {}
    local function cursorNorm()
        local cx, cy = GetCursorPosition()
        local scale = canvas:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local x = (cx - (canvas:GetLeft() or 0)) / canvas:GetWidth()
        local y = ((canvas:GetTop() or 0) - cy) / canvas:GetHeight()
        return U.Clamp(x, 0, 1), U.Clamp(y, 0, 1)
    end
    pl.renderTokens = function()
        for _, t in ipairs(pl.tokens) do t:Hide() end
        if not page.bossKey then return end
        local layout = BP:GetLayout(page.bossKey, page.phase)
        for i, tok in ipairs(layout.tokens) do
            local b = pl.tokens[i]
            if not b then
                b = CreateFrame("Button", nil, canvas, "BackdropTemplate")
                b:SetSize(64, 18)
                b.text = W.Label(b, "", 10, "text", "CENTER")
                b.text:SetPoint("CENTER")
                b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                b:SetScript("OnMouseDown", function(self, button)
                    if button == "LeftButton" and BRL.Perm:Can("raid.plan") then self.dragging = true end
                    pl.selected = self.tokenId
                end)
                b:SetScript("OnMouseUp", function(self, button)
                    if self.dragging then
                        self.dragging = false
                        local x, y = cursorNorm()
                        BP:MoveToken(page.bossKey, page.phase, self.tokenId, x, y)
                    elseif button == "RightButton" then
                        BP:RemoveToken(page.bossKey, page.phase, self.tokenId)
                    end
                end)
                b:SetScript("OnUpdate", function(self)
                    if self.dragging then
                        local x, y = cursorNorm()
                        self:ClearAllPoints()
                        self:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
                    end
                end)
                W.SetTooltip(b, function(self) return self.tooltipText end, { "드래그: 이동 · 우클릭: 삭제" })
                pl.tokens[i] = b
            end
            local kindName, color = tok.kind, { 1, 1, 1 }
            for _, k in ipairs(BP.TOKEN_KINDS) do if k.key == tok.kind then kindName, color = k.name, k.color end end
            T.ApplyBackdrop(b, { color[1] * 0.35, color[2] * 0.35, color[3] * 0.35, 0.95 }, { color[1], color[2], color[3], 1 })
            b.text:SetText(tok.label ~= "" and tok.label or kindName)
            b.tokenId = tok.id
            b.tooltipText = kindName .. (tok.label ~= "" and (": " .. tok.label) or "")
            b:ClearAllPoints()
            b:SetPoint("CENTER", canvas, "TOPLEFT", tok.x * canvas:GetWidth(), -tok.y * canvas:GetHeight())
            b:Show()
        end
    end
    local side = CreateFrame("Frame", nil, pl)
    side:SetPoint("TOPLEFT", 470, -28)
    side:SetSize(170, 400)
    local kindItems = {}
    for _, k in ipairs(BP.TOKEN_KINDS) do kindItems[#kindItems + 1] = { value = k.key, text = k.name } end
    pl.kind = W.Dropdown(side, 170, kindItems)
    pl.kind:SetPoint("TOPLEFT", 0, 0)
    pl.kind:SetValue("tank", true)
    pl.label = W.EditBox(side, 170, 22, { placeholder = "표시 이름 (예: MT, 1파티, 홍길동)" })
    pl.label:SetPoint("TOPLEFT", 0, -28)
    local sb = {
        { "배치 추가 (중앙)", function() if page.bossKey then BP:AddToken(page.bossKey, page.phase, pl.kind:GetValue(), pl.label:GetText(), 0.5, 0.5) end end },
        { "파티별 배치 추가", function()
            if not page.bossKey then return end
            for g = 1, 8 do
                if (BRL.Roster:Counts().byGroup[g] or 0) > 0 then BP:AddToken(page.bossKey, page.phase, "group", g .. "파티", 0.1 + (g - 1) * 0.11, 0.9) end
            end
        end },
        { "기본 진형 적용", function() if page.bossKey then BP:ApplyLayoutTemplate(page.bossKey, page.phase, 1) end end },
        { "산개 진형 적용", function() if page.bossKey then BP:ApplyLayoutTemplate(page.bossKey, page.phase, 2) end end },
        { "이전 단계 복사", function() if page.bossKey and page.phase > 1 then BP:CopyLayout(page.bossKey, page.phase - 1, page.phase) end end },
        { "배치 초기화", function() if page.bossKey then D.Confirm("이 단계의 배치를 모두 지울까요?", function() BP:ClearLayout(page.bossKey, page.phase) end) end end },
        { "배치도 공유(채팅)", function() if page.bossKey then A.SendLines(BP:LayoutLines(page.bossKey, page.phase), "배치도 출력") end end },
    }
    for i, s in ipairs(sb) do
        local b = W.Button(side, s[1], 170, 24, s[2], { perm = i < 7 and "raid.plan" or nil })
        b:SetPoint("TOPLEFT", 0, -60 - (i - 1) * 30)
    end
    local hint = W.Paragraph(side, "배치도는 9구역(북서~남동) 위치로 채팅 공유됩니다. 위쪽 = 북쪽(보스 방향 권장).", 170, 11)
    hint:SetPoint("TOPLEFT", 0, -280)
    T.SetTextColor(hint, "muted")

    -- 타임라인
    local pt = panel("timeline")
    pt.timer = W.Label(pt, "", 14, "goldBright")
    pt.timer:SetPoint("TOPLEFT", 0, 0)
    pt.list = W.List(pt, {
        columns = {
            { title = "시각", width = 60, align = "CENTER", render = function(e) return U.FormatDuration(e.t) end },
            { title = "종류", width = 70, render = function(e) return ({ phase = "단계", cd = "생존기", swap = "탱커 교대", note = "지침" })[e.kind] or e.kind end },
            { title = "내용", width = 0, render = function(e)
                local up = BP.timer and BP.timer.bossKey == page.bossKey
                if up and BP:Elapsed() > e.t + 1 then return T.Color("muted", e.text) end
                return e.text
            end },
        },
    })
    pt.list:SetPoint("TOPLEFT", 0, -24)
    pt.list:SetSize(640, 330)
    pt.upcoming = W.Paragraph(pt, "", 640, 12)
    pt.upcoming:SetPoint("TOPLEFT", 0, -362)
    local _, ft = UI.BottomBar(pt, 0)
    ft:Add(W.Button(ft.parent, "타이머 시작", 86, 24, function() if page.bossKey then BP:StartTimer(page.bossKey) end end, { kind = "primary" }))
    ft:Add(W.Button(ft.parent, "다음 단계", 76, 24, function() BP:NextPhase() end))
    ft:Add(W.Button(ft.parent, "정지", 50, 24, function() BP:StopTimer() end))
    ft:Add(W.Button(ft.parent, "초기화", 60, 24, function() BP:ResetTimer() end))
    ft:Add(W.Button(ft.parent, "항목 추가", 76, 24, function()
        if not page.bossKey then return end
        D.Input("타임라인 항목 추가", {
            { key = "t", label = "시각(초)", type = "number", required = true },
            { key = "kind", label = "종류", type = "dropdown", default = "note", items = {
                { value = "note", text = "지침" }, { value = "phase", text = "단계" }, { value = "cd", text = "생존기" }, { value = "swap", text = "탱커 교대" } } },
            { key = "text", label = "내용", type = "text", required = true },
        }, function(v) return BP:AddTimelineEvent(page.bossKey, v.t, v.text, v.kind) end)
    end, { perm = "raid.plan" }))
    ft:Add(W.Button(ft.parent, "항목 삭제", 76, 24, function()
        local e = pt.list:GetSelected()
        if e and page.bossKey then BP:RemoveTimelineEvent(page.bossKey, e.index) end
    end, { perm = "raid.plan" }))
    local tnote = W.Label(ft.parent, "수동 진행 · 전투 시작 이벤트 시 자동 시작 · 알림은 화면에만 표시", 11, "muted")
    ft:Add(tnote, 300)

    -- 진행
    local pg = panel("progress")
    pg.info = W.Paragraph(pg, "", 640, 12)
    pg.info:SetPoint("TOPLEFT", 0, 0)
    pg.retry = W.TextArea(pg, 640, 90)
    pg.retry:SetPoint("TOPLEFT", 0, -150)
    local rl = W.Label(pg, "재시도 전략", 11, "gold")
    rl:SetPoint("BOTTOMLEFT", pg.retry, "TOPLEFT", 0, 2)
    pg.next = W.TextArea(pg, 640, 90)
    pg.next:SetPoint("TOPLEFT", 0, -262)
    local nl = W.Label(pg, "다음 시도 수정사항", 11, "gold")
    nl:SetPoint("BOTTOMLEFT", pg.next, "TOPLEFT", 0, 2)
    local _, fg = UI.BottomBar(pg, 0)
    fg:Add(W.Button(fg.parent, "시도 시작", 76, 24, function() if page.bossKey then P:StartAttempt(page.bossKey) end end, { perm = "raid.command" }))
    fg:Add(W.Button(fg.parent, "처치", 60, 24, function() if page.bossKey then P:EndAttempt(page.bossKey, true) end end, { kind = "primary", perm = "raid.command" }))
    fg:Add(W.Button(fg.parent, "전멸", 60, 24, function() if page.bossKey then P:EndAttempt(page.bossKey, false) end end, { perm = "raid.command" }))
    fg:Add(W.Button(fg.parent, "처치 표시 해제", 100, 24, function() if page.bossKey then P:MarkKilled(page.bossKey, false) end end, { perm = "raid.command" }))
    fg:Add(W.Button(fg.parent, "메모 저장", 76, 24, function()
        if not page.bossKey then return end
        P:SetText(page.bossKey, "retry", pg.retry:GetText())
        P:SetText(page.bossKey, "nextChanges", pg.next:GetText())
        BRL:Print("저장했습니다.")
    end, { perm = "raid.plan" }))
    fg:Add(W.Button(fg.parent, "기록 초기화", 84, 24, function()
        if page.bossKey then D.Confirm("이 보스의 진행 기록을 초기화할까요?", function() P:Reset(page.bossKey) end, { danger = true }) end
    end, { perm = "raid.command" }))
    page.tabs:Select("plan")
end

local function planText(plan)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    if plan.verified == false then add("※ 미확인 정보입니다. 실제 공략 후 내용을 확인/편집하세요.") add("") end
    add("[개요] " .. (plan.summary or ""))
    add("")
    add("[주요 기술]")
    for _, a in ipairs(plan.abilities or {}) do add(" - " .. (a.name or "?") .. ": " .. (a.text or "")) end
    if #(plan.abilities or {}) == 0 then add(" - (없음)") end
    add("")
    add("[전투 단계]")
    for _, p in ipairs(plan.phases or {}) do add(" - " .. (p.name or "?") .. ": " .. (p.text or "")) end
    add("")
    add("[탱커] " .. (plan.tank or ""))
    add("[힐러] " .. (plan.healer or ""))
    add("[딜러] " .. (plan.dps or ""))
    add("")
    add("[차단 기술] " .. U.StripColors(listText(plan.interrupts)))
    add("[해제 대상] " .. U.StripColors(listText(plan.dispels)))
    add("[군중제어 대상] " .. U.StripColors(listText(plan.cc)))
    add("[주요 위험 요소] " .. U.StripColors(listText(plan.dangers)))
    add("[추천 진형] " .. (plan.formation or ""))
    add("[공략 메모] " .. (plan.notes or ""))
    add("[전리품] " .. U.StripColors(listText(plan.loot)))
    return table.concat(lines, "\n")
end

local function refresh(page)
    local session = BRL.Session:GetActive()
    if not page.raidKey then page.raidKey = (session and session.raidKey) or "ONYXIAS_LAIR" end
    page.raidDrop:SetValue(page.raidKey, true)
    local bosses = BP:List(page.raidKey)
    if not page.bossKey and bosses[1] then page.bossKey = P:GetCurrentBoss() or bosses[1].key end
    page.bossList:SetData(bosses, true)
    local plan = page.bossKey and BP:Get(page.bossKey)
    page.bossTitle:SetText(plan and (plan.name .. (plan.verified == false and "  |cff9e9a8f(미확인)|r" or "")) or "보스를 선택하세요")
    if not plan then return end
    if page.tab == "plan" then
        page.panels.plan.text:SetText(planText(plan))
    elseif page.tab == "layout" then
        local pl = page.panels.layout
        pl.phaseDrop:SetValue(page.phase, true)
        pl.renderTokens()
    elseif page.tab == "timeline" then
        local pt = page.panels.timeline
        local events = {}
        for i, e in ipairs(plan.timeline or {}) do events[#events + 1] = { index = i, t = e.t, text = e.text, kind = e.kind } end
        pt.list:SetData(events, true)
        if BP.timer and BP.timer.bossKey == page.bossKey then
            pt.timer:SetText(string.format("경과 %s · %d단계", U.FormatDuration(BP:Elapsed()), BP.timer.phase))
            local up = {}
            for _, e in ipairs(BP:Upcoming(3)) do up[#up + 1] = string.format("%s 후: %s", U.FormatDuration(math.max(0, e.inSec)), e.text) end
            pt.upcoming:SetText(#up > 0 and ("다음: " .. table.concat(up, " / ")) or "")
        else
            pt.timer:SetText("타이머 정지")
            pt.upcoming:SetText("")
        end
    else
        local pg = page.panels.progress
        local prog = P:Boss(page.bossKey)
        local lines = {
            string.format("시도 %d회 · 전멸 %d회 · 처치 %d회%s", prog.attempts, prog.wipes, prog.kills, prog.inProgress and T.Color("yellow", " · 전투 중") or ""),
            "처치 시각: " .. (prog.killedAt and U.FormatDateTime(prog.killedAt) or "-") .. " · 처치 시간: " .. (prog.killTime and U.FormatDuration(prog.killTime) or "-"),
        }
        local recent = {}
        for i = #prog.durations, math.max(1, #prog.durations - 5), -1 do
            local d = prog.durations[i]
            recent[#recent + 1] = (d.success and "처치 " or "전멸 ") .. U.FormatDuration(d.d)
        end
        lines[#lines + 1] = "최근 전투: " .. (#recent > 0 and table.concat(recent, ", ") or "-")
        local sum = P:Summary(session and session.id)
        lines[#lines + 1] = string.format("공격대 진행률: %d/%d (%d%%) · 총 시도 %d · 총 전멸 %d", sum.killed, sum.total, sum.percent, sum.attempts, sum.wipes)
        pg.info:SetText(table.concat(lines, "\n"))
        if not pg.retry.edit:HasFocus() then pg.retry:SetText(prog.retry or "") end
        if not pg.next.edit:HasFocus() then pg.next:SetText(prog.nextChanges or "") end
    end
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("boss", { title = L.MENU_BOSS, order = 9, build = build, refresh = refresh })
