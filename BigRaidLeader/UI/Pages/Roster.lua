-- BIG RAID LEADER - 공대원 관리 화면
local _, BRL = ...
local T, W, L = BRL.Theme, BRL.Widgets, BRL.L
local UI, D = BRL.UI, BRL.Dialogs

local function build(page)
    UI:PageHeader(page, L.MENU_ROSTER, "현재 공격대 구성원")
    page.sortKey = "group"
    local flow = W.Flow(page, 4, 30, 6)
    flow:AddLabel("검색", 30)
    page.search = flow:Add(W.EditBox(page, 140, 22, { placeholder = "캐릭터명", onChange = function() UI:RequestRefresh() end }))
    flow:AddLabel("정렬", 30)
    page.sort = flow:Add(W.Dropdown(page, 100, {
        { value = "group", text = "파티" }, { value = "class", text = "직업" }, { value = "role", text = "역할" }, { value = "name", text = "이름" },
    }, function(v) page.sortKey = v UI:RequestRefresh() end))
    page.sort:SetValue("group", true)
    flow:AddLabel("역할", 30)
    local roleItems = { { value = false, text = "전체" } }
    for _, r in ipairs(BRL.Data.Roles) do roleItems[#roleItems + 1] = { value = r, text = BRL.Label("CR_", r) } end
    roleItems[#roleItems + 1] = { value = "NONE", text = "미지정" }
    page.roleFilter = flow:Add(W.Dropdown(page, 100, roleItems, function() UI:RequestRefresh() end))
    page.roleFilter:SetValue(false, true)
    page.summary = W.Label(page, "", 12, "gold")
    page.summary:SetPoint("TOPLEFT", 4, -60)

    page.list = W.List(page, {
        columns = {
            { title = "파티", width = 40, align = "CENTER", render = function(m) return m.subgroup or "-" end, sort = true, key = "group" },
            { title = "캐릭터", width = 150, render = function(m)
                local mark = m.isLeader and "|cffffffff[공대장]|r " or (m.isAssistant and "|cff73b8ff[부공대장]|r " or "")
                return mark .. BRL.Data.ColorName(m.short, m.class)
            end, sort = true, key = "name" },
            { title = "직업", width = 80, render = function(m) return BRL.Data.ClassName(m.class) end, sort = true, key = "class" },
            { title = "레벨", width = 40, align = "CENTER", render = function(m) return m.level or "-" end },
            { title = "역할", width = 90, render = function(m)
                local assigned = BRL.Roles:IsRoleAssigned(m.key)
                return BRL.Label("CR_", m.role or "NONE") .. (assigned and "" or " |cff8f8f99(추정)|r")
            end, sort = true, key = "role" },
            { title = "상태", width = 140, render = function(m)
                local s = {}
                if not m.online then s[#s + 1] = T.Color("muted", "오프라인") else s[#s + 1] = T.Color("green", "접속") end
                if m.afk then s[#s + 1] = T.Color("yellow", "자리비움") end
                if m.dead then s[#s + 1] = T.Color("red", "사망") end
                return table.concat(s, " ")
            end },
            { title = "임무", width = 0, render = function(m) return table.concat(BRL.Roles:DutiesFor("default", m.key), ", ") end },
        },
        onSort = function(key) page.sortKey = key page.sort:SetValue(key, true) UI:RequestRefresh() end,
        onRightClick = function(m) page.contextMember(m) end,
        tooltip = function(m) return m.short, { "지역: " .. tostring(m.zone or "-"), "우클릭: 역할/파티 변경" } end,
    })
    page.list:SetPoint("TOPLEFT", 4, -82)
    page.list:SetPoint("BOTTOMRIGHT", -4, 70)
    page.warnings = W.Label(page, "", 12, "red")
    page.warnings:SetPoint("BOTTOMLEFT", 4, 40)
    page.warnings:SetPoint("RIGHT", -4, 0)

    local function sel() return page.list:GetSelected() end
    page.contextMember = function(m)
        local items = {}
        for _, r in ipairs(BRL.Data.Roles) do items[#items + 1] = { value = "role:" .. r, text = "역할: " .. BRL.Label("CR_", r) } end
        for g = 1, 8 do items[#items + 1] = { value = "group:" .. g, text = g .. "파티로 이동" } end
        D.Select(m.short .. " 관리", items, function(v)
            local kind, val = v:match("^(%a+):(.+)$")
            if kind == "role" then BRL.Roles:SetMemberRole(m.key, val)
            elseif kind == "group" then
                local ok, err = BRL.Roster:MoveToGroup(m.key, tonumber(val))
                if not ok and err then BRL:Print(err) end
            end
        end)
    end
    local _, f = UI.BottomBar(page)
    for _, r in ipairs(BRL.Data.Roles) do
        f:Add(W.Button(f.parent, BRL.Label("CR_", r), 74, 24, function()
            local m = sel()
            if m then BRL.Roles:SetMemberRole(m.key, r) end
        end, { perm = "raid.plan", tooltip = "선택한 공대원의 역할 지정" }))
    end
    f:Add(W.Button(f.parent, "파티 변경", 80, 24, function()
        local m = sel()
        if not m then return end
        local items = {}
        for g = 1, 8 do items[#items + 1] = { value = g, text = g .. "파티" } end
        D.Select("파티 변경 - " .. m.short, items, function(g)
            local ok, err = BRL.Roster:MoveToGroup(m.key, g)
            if not ok and err then BRL:Print(err) end
        end)
    end, { perm = "raid.groups.apply" }))
    f:Add(W.Button(f.parent, "역할 자동 추정 초기화", 140, 24, function()
        local m = sel()
        if m then BRL.Roles:SetMemberRole(m.key, nil) end
    end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "새로고침", 76, 24, function() BRL.Roster:Refresh() end))
end

local function refresh(page)
    local members = BRL.Roster:Sorted(page.sortKey, page.search:GetText(), { role = page.roleFilter:GetValue() or nil })
    page.list:SetData(members, true)
    local warnings, c = BRL.Roster:Warnings()
    page.summary:SetText(string.format("총 %d명 · 탱커 %d · 힐러 %d · 근접 %d · 원거리 %d · 접속 %d · 사망 %d",
        c.total, c.TANK, c.HEALER, c.MELEE, c.RANGED, c.online, c.dead))
    -- 중복 역할 배정 확인 (전술 임무)
    for _, w in ipairs(BRL.Roles:Validate("default")) do
        if w:find("중복") then warnings[#warnings + 1] = w end
    end
    page.warnings:SetText(table.concat(warnings, " · "))
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("roster", { title = L.MENU_ROSTER, order = 3, build = build, refresh = refresh })
