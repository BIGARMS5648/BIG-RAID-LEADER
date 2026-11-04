-- BIG RAID LEADER - 전투 지휘 화면 (명령 / 징표 / 전술 메모)
local _, BRL = ...
local T, W, L, U, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.API
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local Cmd = BRL.Command

local function build(page)
    UI:PageHeader(page, L.MENU_COMMAND, "지휘 명령 · 공격대 징표 · 전술 메모")
    page.planKey = "default"
    page.panels = {}
    page.tabs = W.Tabs(page, {
        { key = "cmd", text = "지휘 명령", width = 100 },
        { key = "notes", text = "전술 메모", width = 100 },
    }, function(key)
        page.tab = key
        for k, p in pairs(page.panels) do if k == key then p:Show() else p:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPLEFT", 4, -28)
    page.planDrop = W.Dropdown(page, 220, UI.PlanItems, function(v) page.planKey = v UI:RequestRefresh() end)
    page.planDrop:SetPoint("TOPRIGHT", -4, -28)
    page.planDrop:SetValue("default", true)
    local function panel(key)
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -58)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = p
        return p
    end

    -- 지휘 명령
    local pc = panel("cmd")
    local s1 = W.Section(pc, "주요 명령 (공격대 경보 채널)")
    s1:SetPoint("TOPLEFT", 4, 0)
    -- 지휘 명령은 HUD 와 같은 목록(UIActions.COMMANDS)을 사용한다
    local function opts()
        return { pull = tonumber(pc.pullSec:GetText()), breakMin = tonumber(pc.breakMin:GetText()), bossKey = page.planKey }
    end
    local n = 0
    for _, c in ipairs(A.COMMANDS) do
        if c.label then
            n = n + 1
            local col = (n - 1) % 5
            local row = math.floor((n - 1) / 5)
            local b = W.Button(pc, c.label, 140, 34, function() c.run(opts()) end,
                { kind = c.primary and "primary" or "normal", perm = c.perm ~= false and "raid.command" or nil, size = 13 })
            b:SetPoint("TOPLEFT", 4 + col * 148, -24 - row * 40)
        end
    end
    W.Label(pc, "같은 명령은 공대장 HUD(/brl hud)에서도 실행할 수 있습니다.", 11, "muted"):SetPoint("TOPLEFT", 160, -2)
    local f1 = W.Flow(pc, 4, 112, 6)
    f1:AddLabel("풀링(초)", 54)
    pc.pullSec = f1:Add(W.EditBox(pc, 40, 22, { numeric = true }))
    pc.pullSec:SetText(tostring(BRL.acct.command.pullSeconds))
    f1:AddLabel("휴식(분)", 54)
    pc.breakMin = f1:Add(W.EditBox(pc, 40, 22, { numeric = true }))
    pc.breakMin:SetText(tostring(BRL.acct.command.breakMinutes))
    f1:Add(W.Button(pc, "풀링 판정", 76, 22, function() A.ShowPullCheck() end, { tooltip = { "준비 확인 · 사망/부재 · 도핑 · 역할을 종합해 풀링 가능 여부를 판정합니다." } }))
    f1:Add(W.Button(pc, "징표 바 열기/닫기", 120, 22, function() BRL.MarkerBar:Toggle() end,
        { tooltip = { "징표 지정은 게임 보호 정책상 징표 바 버튼(직접 클릭)으로만 할 수 있습니다.", "전투 중에는 열고 닫을 수 없으니 미리 열어 두세요." } }))
    pc.status = f1:Add(W.Label(pc, "", 12, "yellow"), 300)

    local s2 = W.Section(pc, "커스텀 공지")
    s2:SetPoint("TOPLEFT", 4, -146)
    local f2 = W.Flow(pc, 4, 170, 6)
    pc.custom = f2:Add(W.EditBox(pc, 430, 24, { placeholder = "공지 내용 ({rt8}=해골 등 징표 아이콘 사용 가능)", onEnter = function(t) Cmd:Custom(t, pc.channel:GetValue()) end }))
    pc.channel = f2:Add(W.Dropdown(pc, 120, {
        { value = "RAID_WARNING", text = "공격대 경보" }, { value = "RAID", text = "공격대" }, { value = "PARTY", text = "파티" }, { value = "GUILD", text = "길드" },
    }))
    pc.channel:SetValue("RAID_WARNING", true)
    f2:Add(W.Button(pc, "전송", 60, 24, function() Cmd:Custom(pc.custom:GetText(), pc.channel:GetValue()) end, { perm = "raid.command" }))
    f2:Add(W.Button(pc, "명령 저장", 80, 24, function()
        local text = pc.custom:GetText()
        D.Input("명령 저장", { { key = "name", label = "버튼 이름", type = "text", required = true } }, function(v)
            return Cmd:SaveCommand(v.name, text, pc.channel:GetValue())
        end)
    end, { perm = "raid.command" }))

    local s3 = W.Section(pc, "저장한 명령 (더블클릭 실행)")
    s3:SetPoint("TOPLEFT", 4, -204)
    pc.saved = W.List(pc, {
        columns = {
            { title = "이름", width = 140, key = "name" },
            { title = "채널", width = 90, render = function(c) return c.channel end },
            { title = "내용", width = 0, key = "text" },
        },
        onDoubleClick = function(c) for i, x in ipairs(Cmd:SavedCommands()) do if x == c then Cmd:RunCommand(i) end end end,
    })
    pc.saved:SetPoint("TOPLEFT", 4, -228)
    pc.saved:SetPoint("BOTTOMRIGHT", -4, 40)
    local _, f3 = UI.BottomBar(pc)
    f3:Add(W.Button(f3.parent, "실행", 60, 24, function()
        local c = pc.saved:GetSelected()
        if c then for i, x in ipairs(Cmd:SavedCommands()) do if x == c then Cmd:RunCommand(i) end end end
    end, { perm = "raid.command" }))
    f3:Add(W.Button(f3.parent, "삭제", 60, 24, function()
        local c = pc.saved:GetSelected()
        if c then for i, x in ipairs(Cmd:SavedCommands()) do if x == c then Cmd:DeleteCommand(i) end end end
    end, { perm = "raid.command" }))
    local hint = W.Label(f3.parent, "단축키: 게임 메뉴 > 키 설정 > 애드온 > BIG RAID LEADER (준비 확인/풀링/취소)", 11, "muted")
    f3:Add(hint, 460)

    -- 전술 메모
    local pn = panel("notes")
    page.noteCat = "shared"
    local catItems = { { value = "private", text = "공대장 개인 메모 (비공개)" } }
    for _, c in ipairs(Cmd.NOTE_CATEGORIES) do catItems[#catItems + 1] = { value = c.key, text = c.name } end
    pn.cat = W.Dropdown(pn, 220, catItems, function(v)
        page.noteCat = v
        pn.area:SetText(Cmd:GetNote(page.planKey, v))
        UI:RequestRefresh()
    end)
    pn.cat:SetPoint("TOPLEFT", 4, 0)
    pn.cat:SetValue("shared", true)
    pn.tpl = W.Dropdown(pn, 160, function()
        local items = {}
        for i, t in ipairs(Cmd.NOTE_TEMPLATES) do items[#items + 1] = { value = i, text = t.name } end
        return items
    end, function(i)
        local t = Cmd.NOTE_TEMPLATES[i]
        if t then pn.area:SetText((pn.area:GetText() ~= "" and (pn.area:GetText() .. "\n") or "") .. t.text) end
    end, { placeholder = "메모 템플릿 삽입" })
    pn.tpl:SetPoint("LEFT", pn.cat, "RIGHT", 8, 0)
    pn.area = W.TextArea(pn, 560, 400)
    pn.area:SetPoint("TOPLEFT", 4, -30)
    pn.preview = W.Paragraph(pn, "", 300, 12)
    pn.preview:SetPoint("TOPLEFT", 580, -30)
    local _, fn = UI.BottomBar(pn)
    fn:Add(W.Button(fn.parent, "저장", 70, 24, function()
        if Cmd:SetNote(page.planKey, page.noteCat, pn.area:GetText()) then BRL:Print("메모 저장") end
        UI:RequestRefresh()
    end, { kind = "primary" }))
    fn:Add(W.Button(fn.parent, "채팅 출력", 80, 24, function() A.SendLines(Cmd:NoteLines(page.planKey, page.noteCat), "전술 메모 출력") end))
    fn:Add(W.Button(fn.parent, "텍스트 복사", 84, 24, function() D.CopyText("전술 메모", pn.area:GetText()) end,
        { tooltip = { "디스코드/메모장에 붙여넣을 수 있게 복사합니다." } }))
    local tip = W.Label(fn.parent, "★ 또는 ! 로 시작하는 줄은 강조 표시됩니다.", 11, "muted")
    fn:Add(tip, 300)

    page.tabs:Select("cmd")
end

local function refresh(page)
    page.planDrop:SetItems(UI.PlanItems())
    UI.FollowActivePlan(page, function(key) page.planKey = key page.planDrop:SetValue(key, true) end)
    if page.tab == "cmd" then
        local pc = page.panels.cmd
        pc.saved:SetData(Cmd:SavedCommands(), true)
        local rem = Cmd:BreakRemaining()
        pc.status:SetText(rem and ("휴식 중: " .. U.FormatDuration(rem) .. " 남음") or (API.InCombat() and "전투 중: 풀링/준비 확인 불가" or ""))
    else
        local pn = page.panels.notes
        if not pn.area.edit:HasFocus() then pn.area:SetText(Cmd:GetNote(page.planKey, page.noteCat)) end
        pn.preview:SetText(T.Color("gold", "미리보기") .. "\n" .. Cmd:FormatNote(Cmd:GetNote(page.planKey, page.noteCat)))
    end
    UI:SetPermBanner(page, "raid.command")
end

UI:RegisterPage("command", { title = L.MENU_COMMAND, order = 8, build = build, refresh = refresh })
