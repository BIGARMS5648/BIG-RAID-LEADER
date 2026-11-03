-- BIG RAID LEADER - 파티 편성 화면 (8개 파티 × 5명, 클릭/드래그 앤 드롭)
local _, BRL = ...
local T, W, L, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.API
local UI, D = BRL.UI, BRL.Dialogs

local G = BRL.Groups

local function slotText(key)
    if not key then return T.Color("muted", "(빈 자리)") end
    local m = BRL.Roster:Get(key)
    local class = m and m.class
    local role = BRL.Roles:GetMemberRole(key, m)
    local roleTag = role and ({ TANK = "탱", HEALER = "힐", MELEE = "근", RANGED = "원" })[role] or "?"
    local pin = G:IsPinned(key) and "|cffffd100*|r" or ""
    local offline = m and not m.online and " |cff9e9a8f(off)|r" or (not m and " |cff9e9a8f(부재)|r" or "")
    return pin .. "[" .. roleTag .. "] " .. BRL.Data.ColorName(API.ShortName(key), class) .. offline
end

local function build(page)
    UI:PageHeader(page, L.MENU_GROUPS, "클릭으로 선택 후 다른 자리 클릭 = 이동/교체 · 드래그 앤 드롭 지원")
    page.selectedKey = nil
    page.boxes = {}
    local boxW, boxH, slotH = 212, 124, 22
    for g = 1, 8 do
        local col = (g - 1) % 4
        local row = math.floor((g - 1) / 4)
        local box = W.Panel(page, T.colors.panel2, T.colors.borderDim)
        box:SetSize(boxW, boxH)
        box:SetPoint("TOPLEFT", 4 + col * (boxW + 8), -30 - row * (boxH + 8))
        box.title = W.Label(box, g .. "파티", 12, "goldBright")
        box.title:SetPoint("TOPLEFT", 6, -4)
        box.comp = W.Label(box, "", 10, "muted", "RIGHT")
        box.comp:SetPoint("TOPRIGHT", -6, -5)
        box.slots = {}
        for i = 1, 5 do
            local s = CreateFrame("Button", nil, box, "BackdropTemplate")
            s:SetSize(boxW - 10, slotH - 2)
            s:SetPoint("TOPLEFT", 5, -20 - (i - 1) * slotH)
            T.ApplyBackdrop(s, T.colors.input, T.colors.borderDim)
            s.label = W.Label(s, "", 11)
            s.label:SetPoint("LEFT", 4, 0)
            s.label:SetPoint("RIGHT", -4, 0)
            s.group, s.index = g, i
            s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            s:RegisterForDrag("LeftButton")
            s:SetScript("OnClick", function(self, button) page.onSlotClick(self, button) end)
            s:SetScript("OnDragStart", function(self)
                if self.key then page.dragKey = self.key page.selectedKey = self.key page.Render() end
            end)
            -- WoW 는 마우스를 뗀 이벤트를 드래그를 시작한 프레임으로 보내므로, 커서 아래 슬롯을 찾아 놓는다
            s:SetScript("OnDragStop", function()
                if not page.dragKey then return end
                for gg = 1, 8 do
                    for _, target in ipairs(page.boxes[gg].slots) do
                        if target:IsMouseOver() then page.onDrop(target) return end
                    end
                end
                page.dragKey = nil
                page.Render()
            end)
            box.slots[i] = s
        end
        page.boxes[g] = box
    end
    -- 미배치 인원
    local un = W.Section(page, "미배치 인원 (클릭 후 빈 자리 클릭)")
    un:SetPoint("TOPLEFT", 4, -30 - 2 * (boxH + 8))
    page.unassigned = W.List(page, {
        noHeader = true,
        columns = { { title = "", width = 0, render = function(key) return slotText(key) end } },
        onClick = function(key) page.selectedKey = key page.Render() end,
    })
    page.unassigned:SetPoint("TOPLEFT", 4, -54 - 2 * (boxH + 8))
    page.unassigned:SetSize(300, 140)
    page.info = W.Paragraph(page, "", 560, 12)
    page.info:SetPoint("TOPLEFT", 320, -54 - 2 * (boxH + 8))

    page.onSlotClick = function(slot, button)
        if button == "RightButton" then
            if slot.key then
                local key = slot.key
                D.Select(API.ShortName(key), {
                    { value = "pin", text = G:IsPinned(key) and "고정 해제" or "고정 (자동 편성 시 유지)" },
                    { value = "remove", text = "편성에서 제외" },
                }, function(v)
                    if v == "pin" then G:SetPinned(key, not G:IsPinned(key)) elseif v == "remove" then G:Remove(key) end
                end)
            end
            return
        end
        if page.selectedKey and page.selectedKey ~= slot.key then
            local ok, err = G:Move(page.selectedKey, slot.group, slot.key)
            if not ok and err then BRL:Print(err) end
            page.selectedKey = nil
        else
            page.selectedKey = slot.key
        end
        page.Render()
    end
    page.onDrop = function(slot)
        local key = page.dragKey
        page.dragKey = nil
        if key and key ~= slot.key then
            local ok, err = G:Move(key, slot.group, slot.key)
            if not ok and err then BRL:Print(err) end
        end
        page.selectedKey = nil
        page.Render()
    end
    page.Render = function()
        local plan = page.preview or G:GetPlan()
        local comp = G:Composition(plan)
        for g = 1, 8 do
            local box = page.boxes[g]
            local c = comp[g]
            box.comp:SetText(string.format("탱%d 힐%d 근%d 원%d", c.TANK, c.HEALER, c.MELEE, c.RANGED))
            for i = 1, 5 do
                local s = box.slots[i]
                local key = plan.groups[g][i]
                s.key = key
                s.label:SetText(slotText(key))
                local border = (key and key == page.selectedKey) and T.colors.goldBright or T.colors.borderDim
                T.ApplyBackdrop(s, T.colors.input, border)
            end
        end
        page.unassigned:SetData(G:Unassigned())
    end

    local _, f = UI.BottomBar(page)
    f:Add(W.Button(f.parent, "현재 편성 복사", 106, 24, function() G:FromCurrent() page.preview = nil end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "자동 편성 제안", 106, 24, function()
        page.preview = G:AutoSuggest()
        page.Render()
        page.info:SetText(T.Color("yellow", "자동 편성 제안을 표시 중입니다. [제안 채택]을 눌러야 계획에 반영됩니다."))
    end, { perm = "raid.plan", tooltip = { "탱커/힐러 분산, 근접·원거리 묶음, 직업 시너지, 고정 인원을 고려한 제안" } }))
    f:Add(W.Button(f.parent, "제안 채택", 76, 24, function()
        if page.preview then G:SetPlan(page.preview) page.preview = nil end
    end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "초기화", 64, 24, function() D.Confirm("편성 계획을 비울까요?", function() G:Reset() page.preview = nil end) end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "공격대에 적용", 106, 24, function()
        D.Confirm("현재 편성 계획대로 실제 파티를 이동할까요?\n(전투 중에는 실행되지 않으며, 전투 시작 시 중단됩니다)", function()
            G:Apply(page.preview or G:GetPlan())
        end)
    end, { kind = "primary", perm = "raid.groups.apply" }))
    f:Add(W.Button(f.parent, "채팅 출력", 76, 24, function() BRL.UIActions.SendLines(G:OutputLines(page.preview), "파티 편성 출력") end))
    page.templateDrop = f:Add(W.Dropdown(f.parent, 130, function()
        local items = {}
        for _, n in ipairs(G:Templates()) do items[#items + 1] = { value = n, text = n } end
        if #items == 0 then items[1] = { value = false, text = "(없음)" } end
        return items
    end, function(v) if v then G:LoadTemplate(v) page.preview = nil end end, { placeholder = "템플릿 불러오기" }))
    f:Add(W.Button(f.parent, "템플릿 저장", 86, 24, function()
        D.Input("편성 템플릿 저장", { { key = "name", label = "이름", type = "text", required = true, placeholder = "예: 오닉시아 기본 / 보스:HYJAL_SUMMIT_1" } },
            function(v) return G:SaveTemplate(v.name) end)
    end, { perm = "raid.plan" }))
end

local function refresh(page)
    page.Render()
    local lines = {}
    if G:IsApplying() then lines[#lines + 1] = T.Color("yellow", "공격대에 편성 적용 중...") end
    if API.InCombat() then lines[#lines + 1] = T.Color("red", "전투 중: 실제 파티 이동은 전투 후 가능합니다.") end
    lines[#lines + 1] = "우클릭: 고정(*)/제외 · 고정 인원은 자동 편성 시 현재 파티를 유지합니다."
    lines[#lines + 1] = "보스별 특수 배치는 '보스:<보스키>' 이름으로 템플릿을 저장해 사용하세요."
    if not page.preview then page.info:SetText(table.concat(lines, "\n")) end
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("groups", { title = L.MENU_GROUPS, order = 4, build = build, refresh = refresh })
