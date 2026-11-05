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

local function buildRecruit(page, host)
    local R = BRL.Recruitment
    local flow = W.Flow(host, 4, 30, 6)
    flow:AddLabel("공격대", 46)
    local raidItems = {}
    for _, r in ipairs(BRL.Data.RaidList()) do raidItems[#raidItems + 1] = { value = r.key, text = r.name .. " (" .. r.size .. "인)" } end
    page.raid = flow:Add(W.Dropdown(host, 180, raidItems, function(v) R:SetField("raidKey", v) end))
    flow:AddLabel("템플릿", 46)
    page.template = flow:Add(W.Dropdown(host, 150, function()
        local items = {}
        for _, n in ipairs(R:Templates()) do items[#items + 1] = { value = n, text = n } end
        if #items == 0 then items[1] = { value = false, text = "(저장된 템플릿 없음)" } end
        return items
    end, function(v) if v then R:LoadTemplate(v) end end, { placeholder = "템플릿 불러오기" }))
    flow:Add(W.Button(host, "템플릿 저장", 90, 22, function()
        D.Input("모집 템플릿 저장", { { key = "name", label = "이름", type = "text", required = true, default = R:GetCurrent().name } },
            function(v) return R:SaveTemplate(v.name) end)
    end, { perm = "raid.plan" }))

    local s1 = W.Section(host, "모집 문구", 420)
    s1:SetPoint("TOPLEFT", 4, -62)
    page.message = W.TextArea(host, 420, 60, { onCommit = function(text) R:SetField("message", (text:gsub("\n", " "))) end })
    page.message:SetPoint("TOPLEFT", 4, -84)
    local hint = W.Label(host, "치환: {raid} {size} {have} {need} {recommend} {roles} {note}", 11, "muted")
    hint:SetPoint("TOPLEFT", 4, -148)
    page.preview = W.Paragraph(host, "", 420, 12)
    page.preview:SetPoint("TOPLEFT", 4, -166)
    T.SetTextColor(page.preview, "yellow")

    local s2 = W.Section(host, "역할별 / 직업별 모집 정원", 420)
    s2:SetPoint("TOPLEFT", 4, -212)
    page.roleEdits = {}
    -- 역할 이름 길이가 달라서(원거리 딜러 등) 실제 글자 폭을 재서 차례로 배치
    local rx = 4
    for _, role in ipairs(BRL.Data.Roles) do
        local lbl = W.Label(host, BRL.Label("CR_", role), 12, "muted")
        lbl:SetPoint("TOPLEFT", rx, -238)
        rx = rx + math.ceil(lbl:GetStringWidth() or 60) + 6
        local eb = W.EditBox(host, 36, 22, { numeric = true, onCommit = function(text) R:SetQuota("role", role, text) end })
        eb:SetPoint("TOPLEFT", rx, -234)
        rx = rx + 36 + 16
        page.roleEdits[role] = eb
    end
    page.classEdits = {}
    for i, class in ipairs(BRL.Data.ClassOrder) do
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        local lbl = W.Label(host, BRL.Data.ColorName(BRL.Data.ClassName(class), class), 12)
        lbl:SetPoint("TOPLEFT", 4 + col * 84, -268 - row * 28)
        local eb = W.EditBox(host, 26, 22, { numeric = true, onCommit = function(text) R:SetQuota("class", class, text) end })
        eb:SetPoint("TOPLEFT", 60 + col * 84, -264 - row * 28)
        page.classEdits[class] = eb
    end

    local s3 = W.Section(host, "전송 (버튼 클릭 시에만 전송)", 420)
    s3:SetPoint("TOPLEFT", 4, -330)
    local f2 = W.Flow(host, 4, 354, 6)
    page.channel = f2:Add(W.Dropdown(host, 150, channelItems, nil, { placeholder = "채널 선택" }))
    page.channel:SetValue("GUILD", true)
    f2:Add(W.Button(host, "모집 문구 전송", 120, 24, function()
        page.channel:SetItems(channelItems())
        R:Send(page.channel:GetValue() or "GUILD")
    end, { kind = "primary", perm = "raid.invite" }))
    f2:Add(W.Button(host, "모집 종료 공지", 110, 24, function()
        D.Confirm("모집을 종료하고 선택한 채널에 마감 공지를 보낼까요?", function() R:CloseNotice(page.channel:GetValue()) end)
    end, { perm = "raid.invite" }))
    -- 지원 접수 켜기/끄기: 오른쪽 지원자 대기열 제목 줄 끝
    page.activeBtn = W.Button(host, "", 110, 22, function() R:SetActive(not R:IsActive()) end,
        { tooltip = { "켜 두면 모집 문구를 보고 귓속말한 지원자를 대기열에 자동으로 추가합니다." } })
    page.activeBtn:SetPoint("TOPRIGHT", -4, -166)
    page.refill = W.Label(host, "", 12, "red")
    page.refill:SetPoint("TOPLEFT", 4, -386)
    local note = W.Paragraph(host, "· 공개 채널/일반/외치기 전송은 게임 정책상 클릭할 때마다 1회만 전송됩니다.\n· 모집 진행 중에만 귓속말 지원자를 자동으로 대기열에 추가합니다.", 420, 11)
    note:SetPoint("TOPLEFT", 4, -408)
    T.SetTextColor(note, "muted")

    -- 오른쪽: 진행 상황 + 지원자
    local s4 = W.Section(host, "모집 진행 상황")
    s4:SetPoint("TOPLEFT", 440, -62)
    page.progress = W.Paragraph(host, "", 440, 12)
    page.progress:SetPoint("TOPLEFT", 440, -84)
    local s5 = W.Section(host, "지원자 대기열")
    s5:SetPoint("TOPLEFT", 440, -170)
    page.list = W.List(host, {
        columns = {
            { title = "이름", width = 110, render = function(a) return BRL.Data.ColorName(a.name, a.class) .. (a.inGroup and " |cff879699(공대원)|r" or "") end },
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
    local function sel() return page.list:GetSelected() end
    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("BOTTOMLEFT", 440, 6)
    bar:SetSize(450, 26)
    local f3 = W.Flow(bar, 0, 1, 6)
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

local function refreshRecruit(page)
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
    local a = BRL.Composition:Analyze(cur.size)
    local recs = {}
    for i, r in ipairs(a.recommendations) do
        if i > 3 then break end
        recs[#recs + 1] = BRL.Data.ColorName(BRL.Data.ClassName(r.class), r.class) .. "(" .. BRL.Composition.ShortRole(r.role) .. ")"
    end
    lines[#lines + 1] = T.Color("gold", "추천 추가 직업: ") .. (#recs > 0 and table.concat(recs, ", ") or "없음 (핵심 시너지 확보)") .. T.Color("muted", "  → [구성 분석] 탭")
    page.progress:SetText(table.concat(lines, "\n"))
    page.list:SetData(R:Applicants(), true)
end

---------------------------------------------------------------------------
-- 구성 분석 탭 (시너지 버프 · 파티 버프 · 공격대 생존기 · 추천 직업)
---------------------------------------------------------------------------
local Comp = BRL.Composition

local STATUS_COLOR = { ok = "green", partial = "yellow", missing = "red", camp = "blue", na = "muted", unavailable = "muted" }

local function buildAnalysis(page, host)
    page.aSize = nil
    page.aFilter = false
    local flow = W.Flow(host, 4, 30, 6)
    flow:AddLabel("기준 인원", 56)
    page.aSizeDrop = flow:Add(W.Dropdown(host, 90, {
        { value = 10, text = "10인" }, { value = 20, text = "20인" }, { value = 40, text = "40인" },
    }, function(v) page.aSize = v UI:RequestRefresh() end))
    flow:AddLabel("포함", 30)
    page.aMode = flow:Add(W.Dropdown(host, 170, {
        { value = "roster", text = "현재 공대원만" }, { value = "approved", text = "공대원 + 승인한 지원자" },
        { value = "all", text = "공대원 + 모든 지원자" },
    }, function(v) Comp:SetIncludeMode(v) UI:RequestRefresh() end))
    flow:AddLabel("분류", 30)
    local catItems = { { value = false, text = "전체" } }
    for _, c in ipairs(BRL.Data.SynergyCategories) do catItems[#catItems + 1] = { value = c.key, text = c.name } end
    page.aCat = flow:Add(W.Dropdown(host, 120, catItems, function(v) page.aFilter = v UI:RequestRefresh() end))
    page.aCat:SetValue(false, true)
    page.aOnlyMissing = W.CheckBox(host, "부족한 것만", function() UI:RequestRefresh() end)
    page.aOnlyMissing:SetPoint("TOPLEFT", flow.cursor + 4, -33)

    page.aSummary = W.Label(host, "", 12, "gold")
    page.aSummary:SetPoint("TOPLEFT", 4, -60)
    page.aList = W.List(host, {
        columns = {
            { title = "분류", width = 76, render = function(it) return Comp:CategoryName(it.category) end },
            { title = "시너지 / 생존기", width = 0, render = function(it) return it.syn.name end },
            { title = "현재/필요", width = 62, align = "CENTER", render = function(it)
                if it.status == "na" then return T.Color("muted", "-") end
                return it.have .. "/" .. it.need
            end },
            { title = "상태", width = 70, render = function(it) return T.Color(STATUS_COLOR[it.status] or "white", Comp.STATUS_LABEL[it.status] or it.status) end },
        },
        tooltip = function(it)
            local lines = { "제공: " .. Comp:ProviderText(it.syn) }
            if it.syn.category == "partybuff" then lines[#lines + 1] = "수혜 인원 " .. (it.beneficiaries or 0) .. "명 → 필요 파티 " .. it.need end
            if it.syn.camp then
                local c = BRL.Data.FindCamp(it.syn.camp)
                lines[#lines + 1] = "야영지 대체: " .. (c and c.name or it.syn.camp)
            end
            if it.syn.note then lines[#lines + 1] = it.syn.note end
            lines[#lines + 1] = "* = 특성(전문화) 필요 · 오리지널 기준"
            return it.syn.name, lines
        end,
    })
    page.aList:SetPoint("TOPLEFT", 4, -80)
    page.aList:SetPoint("BOTTOMLEFT", 4, 40)
    page.aList:SetWidth(470)

    local s1 = W.Section(host, "추천 추가 직업 (추가 시 확보되는 시너지)")
    s1:SetPoint("TOPLEFT", 486, -58)
    page.aRecs = W.List(host, {
        columns = {
            { title = "#", width = 22, align = "CENTER", render = function(r) return r.rank end },
            { title = "직업", width = 96, render = function(r) return BRL.Data.ColorName(BRL.Data.ClassName(r.class), r.class) .. " " .. Comp.ShortRole(r.role) end },
            { title = "추가 시 확보", width = 0, render = function(r)
                local names = {}
                for i, x in ipairs(r.reasons) do
                    if i > 3 then names[#names + 1] = "외 " .. (#r.reasons - 3) break end
                    names[#names + 1] = (x.syn.name:gsub("%s*%(.*%)", ""))
                end
                return #names > 0 and table.concat(names, ", ") or T.Color("muted", "목표 구성/역할 보충")
            end },
        },
        tooltip = function(r)
            local lines = {}
            for _, x in ipairs(r.reasons) do
                lines[#lines + 1] = x.syn.name .. ": " .. (Comp.STATUS_LABEL[x.before] or x.before) .. " → " .. (Comp.STATUS_LABEL[x.after] or x.after)
            end
            lines[#lines + 1] = string.format("구성 점수 +%.2f", r.gain)
            return BRL.Data.ClassName(r.class) .. " (" .. BRL.Label("CR_", r.role) .. ")", lines
        end,
        emptyText = "추천할 직업이 없습니다 (핵심 시너지 확보)",
    })
    page.aRecs:SetPoint("TOPLEFT", 486, -80)
    page.aRecs:SetSize(400, 170)
    local s2 = W.Section(host, "남은 자리 추천 구성안")
    s2:SetPoint("TOPLEFT", 486, -258)
    page.aPlan = W.Paragraph(host, "", 400, 12)
    page.aPlan:SetPoint("TOPLEFT", 486, -280)
    local s3 = W.Section(host, "직업 / 역할 (현재 / 목표)")
    s3:SetPoint("TOPLEFT", 486, -340)
    page.aTarget = W.Paragraph(host, "", 400, 11)
    page.aTarget:SetPoint("TOPLEFT", 486, -362)
    page.aGaps = W.Paragraph(host, "", 400, 11)
    page.aGaps:SetPoint("TOPLEFT", 486, -436)

    local _, f = UI.BottomBar(host)
    f:Add(W.Button(f.parent, "추천을 모집 정원에 반영", 160, 24, function()
        local ok = Comp:ApplyToRecruitment(page.aSize, BRL.acct.composition.include)
        if ok then BRL:Print("추천 구성안을 직업/역할 모집 정원에 반영했습니다. [모집 공고] 탭에서 확인하세요.") end
    end, { kind = "primary", perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "분석 결과 출력", 110, 24, function()
        BRL.UIActions.SendLines(Comp:Lines(Comp:Analyze(page.aSize)), "구성 분석 출력")
    end))
    f:Add(W.Button(f.parent, "사용 불가 직업", 100, 24, function()
        local items = {}
        for _, c in ipairs(BRL.Data.ClassOrder) do
            items[#items + 1] = { value = c, text = (Comp:IsExcluded(c) and "|cffff6b6b[제외]|r " or "") .. BRL.Data.ColorName(BRL.Data.ClassName(c), c) }
        end
        D.Select("추천에서 제외할 직업 (선택 시 전환)", items, function(c) Comp:SetExcluded(c, not Comp:IsExcluded(c)) end,
            { description = "진영/서버 사정으로 모집할 수 없는 직업을 제외하면 그 직업만 제공하는 시너지는 '직업 제한'으로 표시됩니다." })
    end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "목표 구성 편집", 100, 24, function()
        local size = page.aSize or BRL.Recruitment:GetCurrent().size
        local target = Comp:Target(size)
        local fields = {}
        for _, c in ipairs(BRL.Data.ClassOrder) do
            fields[#fields + 1] = { key = c, label = BRL.Data.ClassName(c), type = "number", default = target.classes[c] or 0 }
        end
        D.Input(Comp:SizeKey(size) .. "인 목표 직업 구성", fields, function(v)
            local classes, total = {}, 0
            for _, c in ipairs(BRL.Data.ClassOrder) do
                classes[c] = math.max(0, math.floor(v[c] or 0))
                total = total + classes[c]
            end
            local ok = Comp:SetTargetClasses(size, classes)
            if ok then BRL:Print("목표 구성 저장 (합계 %d명)", total) end
            return ok
        end, { description = "기본값은 오리지널 공격대 메타 기준입니다. 추천 순위와 남은 자리 구성안에 반영됩니다." })
    end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "목표 역할 편집", 100, 24, function()
        local size = page.aSize or BRL.Recruitment:GetCurrent().size
        local target = Comp:Target(size)
        local fields = {}
        for _, r in ipairs(BRL.Data.Roles) do fields[#fields + 1] = { key = r, label = BRL.Label("CR_", r), type = "number", default = target.roles[r] or 0 } end
        D.Input(Comp:SizeKey(size) .. "인 목표 역할 구성", fields, function(v)
            local roles = {}
            for _, r in ipairs(BRL.Data.Roles) do roles[r] = math.max(0, math.floor(v[r] or 0)) end
            return Comp:SetTargetRoles(size, roles)
        end)
    end, { perm = "raid.plan" }))
    f:Add(W.Button(f.parent, "기본값", 60, 24, function()
        D.Confirm("목표 직업/역할 구성을 기본값으로 되돌릴까요?", function() Comp:ResetTarget(page.aSize or BRL.Recruitment:GetCurrent().size) end)
    end, { perm = "raid.plan" }))
end

local function refreshAnalysis(page)
    local size = page.aSize or BRL.Recruitment:GetCurrent().size
    page.aSizeDrop:SetValue(Comp:SizeKey(size), true)
    page.aMode:SetValue(BRL.acct.composition.include, true)
    local a = Comp:Analyze(size)
    local rows = {}
    local counts = { missing = 0, partial = 0 }
    for _, it in ipairs(a.eval.items) do
        if counts[it.status] then counts[it.status] = counts[it.status] + 1 end
        local show = (not page.aFilter or it.category == page.aFilter)
        if show and page.aOnlyMissing:GetChecked() then show = it.status == "missing" or it.status == "partial" end
        if show then rows[#rows + 1] = it end
    end
    page.aList:SetData(rows, true)
    local applicants = 0
    for _, m in ipairs(a.members) do if m.source == "applicant" then applicants = applicants + 1 end end
    page.aSummary:SetText(string.format("%d인 기준 · 분석 인원 %d명%s · 없음 %s · 부족 %s",
        a.size, a.state.total, applicants > 0 and (" (지원자 " .. applicants .. "명 포함)") or "",
        T.Color(counts.missing > 0 and "red" or "green", tostring(counts.missing)),
        T.Color(counts.partial > 0 and "yellow" or "green", tostring(counts.partial))))
    local recs = {}
    for i, r in ipairs(a.recommendations) do
        if i > 9 then break end
        local x = U.ShallowCopy(r)
        x.rank = i
        recs[#recs + 1] = x
    end
    page.aRecs:SetData(recs)
    -- 남은 자리 구성안
    if a.plan.open > 0 then
        local parts = {}
        for _, c in ipairs(BRL.Data.ClassOrder) do
            local roles = {}
            for _, r in ipairs(BRL.Data.Roles) do
                local n = a.plan.byRole[c .. "|" .. r]
                if n then roles[#roles + 1] = Comp.ShortRole(r) .. n end
            end
            if a.plan.byClass[c] then
                parts[#parts + 1] = BRL.Data.ColorName(BRL.Data.ClassName(c), c) .. " " .. a.plan.byClass[c] .. "(" .. table.concat(roles, "/") .. ")"
            end
        end
        local still = 0
        for _, it in ipairs(a.plan.final.items) do if it.status == "missing" or it.status == "partial" then still = still + 1 end end
        page.aPlan:SetText(string.format("남은 %d자리: %s\n채운 뒤에도 부족한 항목: %d개", a.plan.open, table.concat(parts, ", "), still))
    else
        page.aPlan:SetText(T.Color("muted", "남은 자리가 없습니다. 교체가 필요하면 위 추천 순위를 참고하세요."))
    end
    local cl, rl = {}, {}
    for _, row in ipairs(a.eval.classRows) do
        if row.target > 0 or row.have > 0 then
            local color = row.excluded and "muted" or (row.have < row.target and "red" or "green")
            cl[#cl + 1] = BRL.Data.ClassName(row.class) .. " " .. T.Color(color, row.have .. "/" .. row.target)
        end
    end
    for _, row in ipairs(a.eval.roleRows) do
        rl[#rl + 1] = BRL.Label("CR_", row.role) .. " " .. T.Color(row.have < row.target and "red" or "green", row.have .. "/" .. row.target)
    end
    page.aTarget:SetText(table.concat(cl, "  ") .. "\n" .. table.concat(rl, "  "))
    if #a.partyGaps > 0 then
        local g = {}
        for i, gap in ipairs(a.partyGaps) do
            if i > 8 then g[#g + 1] = "…" break end
            g[#g + 1] = gap.group .. "파티 " .. (gap.syn.name:gsub("%s*%(.*%)", ""))
        end
        page.aGaps:SetText(T.Color("yellow", "현재 파티 배치에서 빠진 파티 버프 (파티 편성으로 조정): ") .. table.concat(g, ", "))
    else
        page.aGaps:SetText("")
    end
end

local function build(page)
    UI:PageHeader(page, L.MENU_RECRUIT)
    page.panels = {}
    page.tabs = W.Tabs(page, {
        { key = "recruit", text = "모집 공고", width = 100 },
        { key = "analysis", text = "구성 분석 (추천 직업)", width = 150 },
    }, function(key)
        page.tab = key
        for k, p in pairs(page.panels) do if k == key then p:Show() else p:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPLEFT", 4, 0)
    for _, key in ipairs({ "recruit", "analysis" }) do
        local host = CreateFrame("Frame", nil, page)
        host:SetPoint("TOPLEFT", 0, -10)
        host:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = host
    end
    buildRecruit(page, page.panels.recruit)
    buildAnalysis(page, page.panels.analysis)
    page.tabs:Select("recruit")
end

local function refresh(page)
    if page.tab == "analysis" then refreshAnalysis(page) else refreshRecruit(page) end
    UI:SetPermBanner(page, "raid.plan")
end

UI:RegisterPage("recruit", { title = L.MENU_RECRUIT, order = 2, build = build, refresh = refresh })
