-- BIG RAID LEADER - 역할 및 전술 임무 배정 화면
local _, BRL = ...
local T, W, L, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.API
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local R = BRL.Roles

local function build(page)
    UI:PageHeader(page, L.MENU_ROLES, "실제 전투 임무 배정 · 전술 순서표")
    page.planKey = "default"
    page.orderKey = "INTERRUPT"
    local flow = W.Flow(page, 4, 30, 6)
    flow:AddLabel("전술표", 44)
    page.plan = flow:Add(W.Dropdown(page, 220, UI.PlanItems, function(v) page.planKey = v UI:RequestRefresh() end))
    page.plan:SetValue("default", true)

    local s1 = W.Section(page, "전술 임무")
    s1:SetPoint("TOPLEFT", 4, -62)
    page.duties = W.List(page, {
        columns = {
            { title = "임무", width = 120, render = function(d) return d.name end },
            { title = "담당자", width = 0, render = function(d)
                local names = {}
                for _, e in ipairs(R:GetAssignees(page.planKey, d.key)) do
                    local m = BRL.Roster:Get(e.key)
                    names[#names + 1] = BRL.Data.ColorName(API.ShortName(e.key), m and m.class) .. (e.note and e.note ~= "" and ("(" .. e.note .. ")") or "")
                end
                return #names > 0 and table.concat(names, ", ") or T.Color("muted", "-")
            end },
        },
        onDoubleClick = function(d) page.addAssignee(d) end,
    })
    page.duties:SetPoint("TOPLEFT", 4, -84)
    page.duties:SetSize(470, 300)
    local bar1 = CreateFrame("Frame", nil, page)
    bar1:SetPoint("TOPLEFT", 4, -390)
    bar1:SetSize(470, 26)
    local f1 = W.Flow(bar1, 0, 1, 6)
    page.addAssignee = function(d)
        d = d or page.duties:GetSelected()
        if not d then BRL:Print("임무를 선택하세요.") return end
        D.Input(d.name .. " 담당자 추가", {
            { key = "member", label = "공대원", type = "dropdown", items = A.MemberItems() },
            { key = "name", label = "또는 이름 입력", type = "text" },
            { key = "note", label = "메모(대상/위치)", type = "text", placeholder = "예: 해골 / 왼쪽 쫄" },
        }, function(v)
            local key = v.member or (v.name ~= "" and v.name)
            if not key then return false, "공대원을 선택하세요" end
            return R:Assign(page.planKey, d.key, key, v.note ~= "" and v.note or nil)
        end)
    end
    f1:Add(W.Button(bar1, "담당자 추가", 90, 24, function() page.addAssignee() end, { kind = "primary", perm = "raid.plan" }))
    f1:Add(W.Button(bar1, "담당자 제거", 90, 24, function()
        local d = page.duties:GetSelected()
        if not d then return end
        local items = {}
        for _, e in ipairs(R:GetAssignees(page.planKey, d.key)) do items[#items + 1] = { value = e.key, text = API.ShortName(e.key) } end
        D.Select("제거할 담당자", items, function(key) R:Unassign(page.planKey, d.key, key) end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(bar1, "담당자 교체", 90, 24, function()
        D.Input("담당자 교체 (모든 임무/순서표)", {
            { key = "old", label = "기존 담당자", type = "dropdown", items = A.MemberItems() },
            { key = "new", label = "새 담당자", type = "dropdown", items = A.MemberItems() },
        }, function(v)
            if not v.old or not v.new then return false, "두 명을 모두 선택하세요" end
            local n = R:ReplaceMember(page.planKey, v.old, v.new)
            BRL:Print("%d개 항목 교체", n)
            return true
        end)
    end, { perm = "raid.plan" }))
    f1:Add(W.Button(bar1, "전체 초기화", 84, 24, function()
        D.Confirm("이 전술표의 임무/순서를 모두 지울까요?", function() R:ClearPlan(page.planKey) end, { danger = true })
    end, { perm = "raid.plan" }))

    -- 순서표
    local s2 = W.Section(page, "전술 순서표")
    s2:SetPoint("TOPLEFT", 490, -62)
    local orderItems = {}
    for _, o in ipairs(R.ORDERS) do orderItems[#orderItems + 1] = { value = o.key, text = o.name } end
    page.orderDrop = W.Dropdown(page, 180, orderItems, function(v) page.orderKey = v UI:RequestRefresh() end)
    page.orderDrop:SetPoint("TOPLEFT", 490, -84)
    page.orderDrop:SetValue("INTERRUPT", true)
    local function orderList(backup)
        return W.List(page, {
            columns = {
                { title = backup and "예비" or "순서", width = 40, align = "CENTER", render = function(e) return e.i end },
                { title = backup and "예비 담당자" or "담당자", width = 0, render = function(e)
                    local m = BRL.Roster:Get(e.key)
                    return BRL.Data.ColorName(API.ShortName(e.key), m and m.class)
                end },
            },
        })
    end
    page.orderList = orderList(false)
    page.orderList:SetPoint("TOPLEFT", 490, -112)
    page.orderList:SetSize(190, 220)
    page.backupList = orderList(true)
    page.backupList:SetPoint("TOPLEFT", 690, -112)
    page.backupList:SetSize(190, 220)
    local function orderButtons(x, backup, list)
        local bar = CreateFrame("Frame", nil, page)
        bar:SetPoint("TOPLEFT", x, -338)
        bar:SetSize(190, 52)
        local f = W.Flow(bar, 0, 1, 4)
        f:Add(W.Button(bar, "추가", 44, 22, function()
            D.Select("추가할 공대원", A.MemberItems(), function(key) R:AddToOrder(page.planKey, page.orderKey, key, backup) end)
        end, { perm = "raid.plan" }))
        f:Add(W.Button(bar, "▲", 30, 22, function()
            local e = list:GetSelected()
            if e then R:MoveInOrder(page.planKey, page.orderKey, e.i, -1, backup) end
        end, { perm = "raid.plan" }))
        f:Add(W.Button(bar, "▼", 30, 22, function()
            local e = list:GetSelected()
            if e then R:MoveInOrder(page.planKey, page.orderKey, e.i, 1, backup) end
        end, { perm = "raid.plan" }))
        f:Add(W.Button(bar, "제거", 44, 22, function()
            local e = list:GetSelected()
            if e then R:RemoveFromOrder(page.planKey, page.orderKey, e.i, backup) end
        end, { perm = "raid.plan" }))
    end
    orderButtons(490, false, page.orderList)
    orderButtons(690, true, page.backupList)

    page.validation = W.Paragraph(page, "", 870, 12)
    page.validation:SetPoint("TOPLEFT", 4, -424)

    local _, f = UI.BottomBar(page)
    f:Add(W.Button(f.parent, "전술표 채팅 출력", 120, 24, function()
        local title = ""
        for _, it in ipairs(UI.PlanItems()) do if it.value == page.planKey then title = it.text end end
        A.SendLines(R:OutputLines(page.planKey, title), "전술표 출력")
    end))
    f:Add(W.Dropdown(f.parent, 140, function()
        local items = {}
        for _, n in ipairs(R:Templates()) do items[#items + 1] = { value = n, text = n } end
        if #items == 0 then items[1] = { value = false, text = "(없음)" } end
        return items
    end, function(v) if v then R:LoadTemplate(v, page.planKey) end end, { placeholder = "전술표 불러오기" }))
    f:Add(W.Button(f.parent, "공유", 50, 24, function() A.ShareMenu("roles", page.planKey, "전술표") end))
    f:Add(W.Button(f.parent, "전술표 저장", 90, 24, function()
        D.Input("전술표 저장", { { key = "name", label = "이름", type = "text", required = true } }, function(v) return R:SaveTemplate(v.name, page.planKey) end)
    end, { perm = "raid.plan" }))
end

local function refresh(page)
    page.plan:SetItems(UI.PlanItems())
    UI.FollowActivePlan(page, function(key) page.planKey = key page.plan:SetValue(key, true) end)
    page.duties:SetData(R.DUTIES, true)
    local function entries(backup)
        local out = {}
        for i, k in ipairs(R:GetOrder(page.planKey, page.orderKey, backup)) do out[#out + 1] = { i = i, key = k } end
        return out
    end
    page.orderList:SetData(entries(false))
    page.backupList:SetData(entries(true))
    local warnings = R:Validate(page.planKey)
    page.validation:SetText(#warnings > 0 and (T.Color("yellow", "확인 필요: ") .. table.concat(warnings, " · ")) or T.Color("green", "배정 검증: 문제 없음"))
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("roles", { title = L.MENU_ROLES, order = 5, build = build, refresh = refresh })
