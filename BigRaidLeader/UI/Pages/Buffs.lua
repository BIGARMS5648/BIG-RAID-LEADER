-- BIG RAID LEADER - 버프 및 야영지 화면
local _, BRL = ...
local T, W, L, U, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.API
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local B, C = BRL.Buffs, BRL.Campsites

local function short(name)
    return (name:gsub("%(.*%)", ""))
end

local function build(page)
    UI:PageHeader(page, L.MENU_BUFFS, "직업 버프 · 도핑 · 포에버 야영지 효과")
    page.bossKey = nil
    page.tabs = W.Tabs(page, {
        { key = "buffs", text = "버프 점검", width = 100 },
        { key = "camps", text = "야영지 효과", width = 100 },
        { key = "setup", text = "필수 버프/담당자", width = 130 },
    }, function(key) page.tab = key
        for k, panel in pairs(page.panels) do if k == key then panel:Show() else panel:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPLEFT", 4, -28)
    page.bossDrop = W.Dropdown(page, 220, UI.PlanItems, function(v) page.bossKey = (v ~= "default") and v or nil UI:RequestRefresh() end)
    page.bossDrop:SetPoint("TOPRIGHT", -4, -28)
    page.bossDrop:SetValue("default", true)
    W.SetTooltip(page.bossDrop, "보스별 체크리스트", { "보스를 선택하면 해당 보스의 추가 필수 버프/야영지 효과를 함께 점검합니다." })
    page.panels = {}
    local function panel(key)
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -58)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = p
        return p
    end

    -- 버프 점검
    local pb = panel("buffs")
    pb.info = W.Label(pb, "", 12, "gold")
    pb.info:SetPoint("TOPLEFT", 4, 0)
    local cols = { { title = "공대원", width = 110, render = function(row) return BRL.Data.ColorName(row.member.short, row.member.class) end } }
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        cols[#cols + 1] = { title = U.Utf8Truncate(short(b.name), 9), width = 0, align = "CENTER", render = function(row)
            local r = row.result
            if not r then return T.Color("muted", "?") end
            if r.unavailable then return T.Color("muted", r.unavailable == "offline" and "off" or "확인불가") end
            local x = r.buffs[b.key]
            if x and x.present then
                local warn = x.remaining and x.remaining < (BRL.acct.buffs.expireWarnMinutes or 5) * 60
                return T.Color(warn and "yellow" or "green", x.via == "camp" and "야영" or "O")
            end
            return row.required[b.key] and T.Color("red", "X") or T.Color("muted", "-")
        end }
    end
    for _, g in ipairs(BRL.Data.ConsumableGroups) do
        if not g.manual then
            cols[#cols + 1] = { title = U.Utf8Truncate(g.name, 6), width = 44, align = "CENTER", render = function(row)
                local r = row.result
                if not r or r.unavailable then return T.Color("muted", "?") end
                return r.consumables[g.key] and T.Color("green", "O") or T.Color("muted", "-")
            end }
        end
    end
    pb.list = W.List(pb, { columns = cols, fontSize = 11 })
    pb.list:SetPoint("TOPLEFT", 4, -20)
    pb.list:SetPoint("BOTTOMRIGHT", -4, 96)
    pb.missing = W.Paragraph(pb, "", 880, 12)
    pb.missing:SetPoint("BOTTOMLEFT", 4, 36)
    local _, f = UI.BottomBar(pb)
    f:Add(W.Button(f.parent, "버프 점검(재검사)", 120, 24, function() B:Scan() C:Verify() end, { kind = "primary" }))
    f:Add(W.Button(f.parent, "누락 버프 채팅 출력", 140, 24, function() A.SendLines(B:MissingLines(page.bossKey), "누락 버프 출력") end))
    f:Add(W.Button(f.parent, "중복/대체 관계", 110, 24, function() D.CopyText("버프 중복/대체 관계", table.concat(B:OverlapNotes(), "\n")) end))

    -- 야영지
    local pc = panel("camps")
    pc.info = W.Paragraph(pc, "야영지(캠핑) 시설 효과는 대응하는 직업 버프와 중복 적용되지 않습니다. 이 화면은 버프 확인과 전술 준비만 담당합니다. (한글 시설명은 비공식 번역)", 880, 11)
    pc.info:SetPoint("TOPLEFT", 4, 0)
    T.SetTextColor(pc.info, "muted")
    pc.list = W.List(pc, {
        columns = {
            { title = "시설", width = 120, render = function(row) return row.facility.name .. " |cff9e9a8f" .. row.facility.nameEn .. "|r" end },
            { title = "효과", width = 150, render = function(row) return row.facility.effect end },
            { title = "대체 버프", width = 120, render = function(row) return row.facility.replacesName end },
            { title = "보스 필요", width = 64, align = "CENTER", render = function(row) return row.required and T.Color("yellow", "필요") or "" end },
            { title = "준비", width = 56, align = "CENTER", render = function(row) return row.status.prepared and T.Color("green", "준비됨") or T.Color("muted", "-") end },
            { title = "담당자", width = 100, render = function(row) return row.status.assignee and API.ShortName(row.status.assignee) or "-" end },
            { title = "확인 결과", width = 0, render = function(row)
                local st = row.status
                if not st.scanned then return T.Color("muted", "미점검") end
                return st.appliedCount > 0 and T.Color("green", st.appliedCount .. "명 적용") or T.Color("red", "적용 인원 없음")
            end },
        },
        onDoubleClick = function(row) C:Set(row.facility.key, "prepared", not row.status.prepared) end,
    })
    pc.list:SetPoint("TOPLEFT", 4, -34)
    pc.list:SetPoint("BOTTOMRIGHT", -4, 40)
    local _, f2 = UI.BottomBar(pc)
    local function selCamp() return pc.list:GetSelected() end
    f2:Add(W.Button(f2.parent, "준비 여부 전환", 110, 24, function() local r = selCamp() if r then C:Set(r.facility.key, "prepared", not r.status.prepared) end end, { perm = "raid.command" }))
    f2:Add(W.Button(f2.parent, "담당자 지정", 90, 24, function()
        local r = selCamp()
        if not r then return end
        D.Select(r.facility.name .. " 담당자", A.MemberItems(true), function(key) C:SetAssignee(r.facility.key, key or nil) end)
    end, { perm = "raid.plan" }))
    f2:Add(W.Button(f2.parent, "보스 필요 전환", 110, 24, function()
        local r = selCamp()
        if not r or not page.bossKey then BRL:Print("오른쪽 위에서 보스를 선택하세요.") return end
        C:SetBossRequirement(page.bossKey, r.facility.key, not r.required)
    end, { perm = "raid.plan" }))
    f2:Add(W.Button(f2.parent, "효과 확인(버프 점검)", 140, 24, function() B:Scan() C:Verify() end, { kind = "primary" }))
    f2:Add(W.Button(f2.parent, "채팅 출력", 80, 24, function() A.SendLines(C:OutputLines(page.bossKey), "야영지 효과 출력") end))

    -- 필수 버프 / 담당자
    local ps = panel("setup")
    ps.list = W.List(ps, {
        columns = {
            { title = "버프", width = 160, render = function(b) return b.name end },
            { title = "제공 직업", width = 90, render = function(b) return BRL.Data.ColorName(BRL.Data.ClassName(b.provider), b.provider) end },
            { title = "필수(공통)", width = 76, align = "CENTER", render = function(b) return BRL.acct.buffs.required[b.key] and T.Color("green", "필수") or T.Color("muted", "-") end },
            { title = "보스 필수", width = 76, align = "CENTER", render = function(b)
                local req = page.bossKey and BRL.db.raidOps.bossBuffs and BRL.db.raidOps.bossBuffs[page.bossKey]
                return req and req[b.key] and T.Color("yellow", "필수") or T.Color("muted", "-")
            end },
            { title = "담당자", width = 0, render = function(b)
                local p = B:GetProvider(b.key)
                return p and API.ShortName(p) or T.Color("muted", "미지정")
            end },
        },
        onDoubleClick = function(b) B:SetRequired(b.key, not BRL.acct.buffs.required[b.key]) end,
    })
    ps.list:SetPoint("TOPLEFT", 4, 0)
    ps.list:SetPoint("BOTTOMRIGHT", -4, 40)
    local _, f3 = UI.BottomBar(ps)
    local function selBuff() return ps.list:GetSelected() end
    f3:Add(W.Button(f3.parent, "공통 필수 전환", 110, 24, function() local b = selBuff() if b then B:SetRequired(b.key, not BRL.acct.buffs.required[b.key]) end end, { perm = "raid.plan" }))
    f3:Add(W.Button(f3.parent, "보스 필수 전환", 110, 24, function()
        local b = selBuff()
        if not b or not page.bossKey then BRL:Print("오른쪽 위에서 보스를 선택하세요.") return end
        local req = BRL.db.raidOps.bossBuffs and BRL.db.raidOps.bossBuffs[page.bossKey]
        B:SetBossRequired(page.bossKey, b.key, not (req and req[b.key]))
    end, { perm = "raid.plan" }))
    f3:Add(W.Button(f3.parent, "담당자 지정", 90, 24, function()
        local b = selBuff()
        if not b then return end
        D.Select(b.name .. " 담당자", A.MemberItems(true), function(key) B:SetProvider(b.key, key or nil) end)
    end, { perm = "raid.plan" }))
    f3:Add(W.Button(f3.parent, "담당자 자동 지정", 120, 24, function() BRL:Print("%d개 버프 담당자 지정", B:AutoAssignProviders()) end, { perm = "raid.plan" }))
    page.tabs:Select("buffs")
end

local function refresh(page)
    page.bossDrop:SetItems(UI.PlanItems())
    if page.tab == "buffs" then
        local pb = page.panels.buffs
        local required = {}
        for _, b in ipairs(B:RequiredList(page.bossKey)) do required[b.key] = true end
        local rows = {}
        for _, m in ipairs(BRL.Roster:Sorted("group")) do rows[#rows + 1] = { member = m, result = B.results[m.key], required = required } end
        pb.list:SetData(rows, true)
        local scanned = B.scannedAt and ("마지막 점검 " .. U.FormatClock(B.scannedAt)) or "아직 점검하지 않았습니다"
        pb.info:SetText(scanned .. (API.InCombat() and T.Color("red", "  · 전투 중: 점검 불가") or "") ..
            (B.needsRecheck and T.Color("yellow", "  · 전멸 후 재도핑 점검 필요") or ""))
        local missing, unknown = B:Missing(page.bossKey)
        local parts = {}
        for _, b in ipairs(B:RequiredList(page.bossKey)) do
            local list = missing[b.key]
            if list and #list > 0 then parts[#parts + 1] = T.Color("red", short(b.name) .. " " .. #list .. "명") end
        end
        local expiring = B:Expiring()
        if #expiring > 0 then parts[#parts + 1] = T.Color("yellow", "곧 만료 " .. #expiring .. "건") end
        if #unknown > 0 then parts[#parts + 1] = T.Color("muted", "확인 불가 " .. #unknown .. "명") end
        pb.missing:SetText(#parts > 0 and ("누락: " .. table.concat(parts, " · ")) or (B.scannedAt and T.Color("green", "필수 버프 누락 없음") or ""))
    elseif page.tab == "camps" then
        page.panels.camps.list:SetData(C:Checklist(page.bossKey), true)
    else
        page.panels.setup.list:SetData(BRL.Data.ClassBuffs, true)
    end
end

UI:RegisterPage("buffs", { title = L.MENU_BUFFS, order = 7, build = build, refresh = refresh })
