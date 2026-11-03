-- BIG RAID LEADER - 공격대 모집 화면
local _, BRL = ...
local T, W, L, U = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util
local UI, D = BRL.UI, BRL.Dialogs

local function channelItems()
    local items = { { value = "GUILD", text = "길드" }, { value = "SAY", text = "일반 대화" }, { value = "YELL", text = "외치기" } }
    for _, c in ipairs(BRL.API.GetChannels()) do
        items[#items + 1] = { value = "CHANNEL:" .. c.id, text = c.id .. ". " .. c.name }
    end
    return items
end

local function build(page)
    UI:PageHeader(page, L.MENU_RECRUIT, "모집 공고 · 지원자 대기열")
    local R = BRL.Recruitment
    local flow = W.Flow(page, 4, 30, 6)
    flow:AddLabel("공격대", 46)
    local raidItems = {}
    for _, r in ipairs(BRL.Data.RaidList()) do raidItems[#raidItems + 1] = { value = r.key, text = r.name .. " (" .. r.size .. "인)" } end
    page.raid = flow:Add(W.Dropdown(page, 180, raidItems, function(v) R:SetField("raidKey", v) end))
    flow:AddLabel("템플릿", 46)
    page.template = flow:Add(W.Dropdown(page, 150, function()
        local items = {}
        for _, n in ipairs(R:Templates()) do items[#items + 1] = { value = n, text = n } end
        if #items == 0 then items[1] = { value = false, text = "(저장된 템플릿 없음)" } end
        return items
    end, function(v) if v then R:LoadTemplate(v) end end, { placeholder = "템플릿 불러오기" }))
    flow:Add(W.Button(page, "템플릿 저장", 90, 22, function()
        D.Input("모집 템플릿 저장", { { key = "name", label = "이름", type = "text", required = true, default = R:GetCurrent().name } },
            function(v) return R:SaveTemplate(v.name) end)
    end, { perm = "raid.plan" }))

    local s1 = W.Section(page, "모집 문구")
    s1:SetPoint("TOPLEFT", 4, -62)
    page.message = W.TextArea(page, 420, 60, { onCommit = function(text) R:SetField("message", (text:gsub("\n", " "))) end })
    page.message:SetPoint("TOPLEFT", 4, -84)
    local hint = W.Label(page, "치환: {raid} {size} {have} {need} {roles} {note}", 11, "muted")
    hint:SetPoint("TOPLEFT", 4, -148)
    page.preview = W.Paragraph(page, "", 420, 12)
    page.preview:SetPoint("TOPLEFT", 4, -166)
    T.SetTextColor(page.preview, "yellow")

    local s2 = W.Section(page, "역할별 / 직업별 모집 정원")
    s2:SetPoint("TOPLEFT", 4, -212)
    page.roleEdits = {}
    for i, role in ipairs(BRL.Data.Roles) do
        local lbl = W.Label(page, BRL.Label("CR_", role), 12, "muted")
        lbl:SetPoint("TOPLEFT", 4 + (i - 1) * 105, -238)
        local eb = W.EditBox(page, 36, 22, { numeric = true, onCommit = function(text) R:SetQuota("role", role, text) end })
        eb:SetPoint("TOPLEFT", 64 + (i - 1) * 105, -234)
        page.roleEdits[role] = eb
    end
    page.classEdits = {}
    for i, class in ipairs(BRL.Data.ClassOrder) do
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        local lbl = W.Label(page, BRL.Data.ColorName(BRL.Data.ClassName(class), class), 12)
        lbl:SetPoint("TOPLEFT", 4 + col * 84, -268 - row * 28)
        local eb = W.EditBox(page, 30, 22, { numeric = true, onCommit = function(text) R:SetQuota("class", class, text) end })
        eb:SetPoint("TOPLEFT", 54 + col * 84, -264 - row * 28)
        page.classEdits[class] = eb
    end

    local s3 = W.Section(page, "전송 (버튼 클릭 시에만 전송)")
    s3:SetPoint("TOPLEFT", 4, -330)
    local f2 = W.Flow(page, 4, 354, 6)
    page.channel = f2:Add(W.Dropdown(page, 150, channelItems, nil, { placeholder = "채널 선택" }))
    page.channel:SetValue("GUILD", true)
    f2:Add(W.Button(page, "모집 문구 전송", 120, 24, function()
        page.channel:SetItems(channelItems())
        R:Send(page.channel:GetValue() or "GUILD")
    end, { kind = "primary", perm = "raid.invite" }))
    f2:Add(W.Button(page, "모집 종료 공지", 110, 24, function()
        D.Confirm("모집을 종료하고 선택한 채널에 마감 공지를 보낼까요?", function() R:CloseNotice(page.channel:GetValue()) end)
    end, { perm = "raid.invite" }))
    page.activeBtn = f2:Add(W.Button(page, "", 100, 24, function() R:SetActive(not R:IsActive()) end))
    page.refill = W.Label(page, "", 12, "red")
    page.refill:SetPoint("TOPLEFT", 4, -386)
    local note = W.Paragraph(page, "· 공개 채널/일반/외치기 전송은 게임 정책상 클릭할 때마다 1회만 전송됩니다.\n· 모집 진행 중에만 귓속말 지원자를 자동으로 대기열에 추가합니다.", 420, 11)
    note:SetPoint("TOPLEFT", 4, -408)
    T.SetTextColor(note, "muted")

    -- 오른쪽: 진행 상황 + 지원자
    local s4 = W.Section(page, "모집 진행 상황")
    s4:SetPoint("TOPLEFT", 440, -62)
    page.progress = W.Paragraph(page, "", 440, 12)
    page.progress:SetPoint("TOPLEFT", 440, -84)
    local s5 = W.Section(page, "지원자 대기열")
    s5:SetPoint("TOPLEFT", 440, -170)
    page.list = W.List(page, {
        columns = {
            { title = "이름", width = 110, render = function(a) return BRL.Data.ColorName(a.name, a.class) .. (a.inGroup and " |cff9e9a8f(공대원)|r" or "") end },
            { title = "직업/역할", width = 90, render = function(a) return (a.class and BRL.Data.ClassName(a.class) or "?") .. "/" .. (a.role and BRL.Label("CR_", a.role) or "?") end },
            { title = "상태", width = 60, render = function(a)
                local labels = { pending = "대기", approved = "승인", rejected = "거절", hold = "보류" }
                local colors = { pending = "yellow", approved = "green", rejected = "muted", hold = "blue" }
                return T.Color(colors[a.status] or "white", labels[a.status] or a.status) .. ((a.count or 1) > 1 and (" x" .. a.count) or "")
            end },
            { title = "메시지", width = 0, render = function(a) return a.msg or "" end },
        },
        tooltip = function(a) return a.name, { a.msg or "", "지원 시각: " .. U.FormatDateTime(a.at), a.duplicate and "중복 지원" or nil } end,
        emptyText = "지원자가 없습니다",
    })
    page.list:SetPoint("TOPLEFT", 440, -194)
    page.list:SetPoint("BOTTOMRIGHT", -4, 40)
    local f3 = W.Flow(page, 440, 0, 6)
    local function sel() return page.list:GetSelected() end
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("BOTTOMLEFT", 440, 6)
    bar:SetSize(450, 26)
    f3.parent = bar
    f3.x, f3.y, f3.cursor = 0, 0, 0
    f3:Add(W.Button(bar, "승인(초대)", 84, 24, function() local a = sel() if a then R:Approve(a.key, true) end end, { kind = "primary", perm = "raid.invite" }))
    f3:Add(W.Button(bar, "거절", 60, 24, function() local a = sel() if a then R:Reject(a.key, true) end end, { perm = "raid.invite" }))
    f3:Add(W.Button(bar, "보류", 60, 24, function() local a = sel() if a then R:Hold(a.key) end end, { perm = "raid.invite" }))
    f3:Add(W.Button(bar, "삭제", 60, 24, function() local a = sel() if a then R:Remove(a.key) end end))
    f3:Add(W.Button(bar, "직접 추가", 76, 24, function()
        D.Input("지원자 직접 추가", {
            { key = "name", label = "이름", type = "text", required = true },
            { key = "msg", label = "메모", type = "text" },
        }, function(v) return R:AddApplicant(v.name, v.msg) ~= nil end)
    end))
    f3:Add(W.Button(bar, "전체 정리", 76, 24, function() D.Confirm("지원자 목록을 모두 지울까요?", function() R:ClearApplicants() end) end))
end

local function refresh(page)
    local R = BRL.Recruitment
    local cur = R:GetCurrent()
    page.raid:SetValue(cur.raidKey, true)
    if not page.message.edit.hasFocus then page.message:SetText(cur.message or "") end
    for role, eb in pairs(page.roleEdits) do if not eb.edit.hasFocus then eb:SetText(tostring(cur.roleQuotas[role] or "")) end end
    for class, eb in pairs(page.classEdits) do if not eb.edit.hasFocus then eb:SetText(tostring(cur.classQuotas[class] or "")) end end
    page.preview:SetText("미리보기: " .. R:BuildMessage())
    page.activeBtn:SetText(R:IsActive() and "지원 접수: 켜짐" or "지원 접수: 꺼짐")
    page.refill:SetText(R.refillSuggested and "공대원 이탈 감지 - 재모집이 필요합니다" or "")
    local p = R:Progress()
    local lines = { string.format("현재 인원 %d / %d (빈자리 %d)", p.have, p.size, p.open) }
    local roleParts = {}
    for _, role in ipairs(BRL.Data.Roles) do
        local r = p.roles[role]
        if r.quota > 0 then
            roleParts[#roleParts + 1] = BRL.Label("CR_", role) .. " " .. (r.need > 0 and T.Color("red", r.have .. "/" .. r.quota) or T.Color("green", r.have .. "/" .. r.quota))
        end
    end
    lines[#lines + 1] = table.concat(roleParts, "   ")
    if #p.missingClasses > 0 then
        local cl = {}
        for _, c in ipairs(p.missingClasses) do cl[#cl + 1] = BRL.Data.ColorName(BRL.Data.ClassName(c.class), c.class) .. " " .. c.need end
        lines[#lines + 1] = "부족한 직업: " .. table.concat(cl, ", ")
    end
    lines[#lines + 1] = "부족: " .. R:NeedText()
    page.progress:SetText(table.concat(lines, "\n"))
    page.list:SetData(R:Applicants(), true)
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("recruit", { title = L.MENU_RECRUIT, order = 2, build = build, refresh = refresh })
