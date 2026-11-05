-- BIG RAID LEADER - 대시보드 (공격대 운영 상태 한눈에 보기)
local _, BRL = ...
local T, W, Money, L = BRL.Theme, BRL.Widgets, BRL.Money, BRL.L
local UI = BRL.UI

local TILES = {
    { key = "raid", label = "공격대", page = "dashboard" },
    { key = "count", label = "공격대 인원", page = "roster" },
    { key = "tank", label = "탱커", page = "roles" },
    { key = "healer", label = "힐러", page = "roles" },
    { key = "dps", label = "딜러 (근접/원거리)", page = "roles" },
    { key = "missing", label = "부족한 역할", page = "recruit" },
    { key = "ready", label = "준비 확인", page = "ready" },
    { key = "boss", label = "현재 보스", page = "boss" },
    { key = "progress", label = "보스 진행", page = "boss" },
    { key = "auction", label = "경매 총액", page = "auction" },
    { key = "collected", label = "실제 수금액", page = "ledger" },
    { key = "distributable", label = "분배 가능 골드", page = "settlement" },
    { key = "unpaid", label = "미지급금", page = "settlement" },
    { key = "settle", label = "정산 진행 상태", page = "settlement" },
    { key = "balance", label = "장부 잔액", page = "ledger" },
    { key = "trades", label = "거래 확인불가/미분류", page = "trades" },
    { key = "groups", label = "파티별 인원", page = "groups" },
}

local function build(page)
    UI:PageHeader(page, L.MENU_DASHBOARD, "공격대 운영 현황")
    page.tiles = {}
    local cols = 6
    for i, t in ipairs(TILES) do
        local tile = W.StatTile(page, t.label, 142, 52)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        tile:SetPoint("TOPLEFT", 4 + col * 148, -30 - row * 58)
        tile:EnableMouse(true)
        tile:SetScript("OnMouseUp", function() UI:Open(t.page) end)
        W.SetTooltip(tile, t.label, { "클릭: 관련 화면으로 이동" })
        page.tiles[t.key] = tile
    end

    local y = 30 + 3 * 58 + 8
    local sec = W.Section(page, "빠른 실행")
    sec:SetPoint("TOPLEFT", 4, -y)
    local flow = W.Flow(page, 4, y + 22, 6)
    flow:Add(W.Button(page, "준비 확인", 80, 26, function() BRL.Command:ReadyCheck() end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "풀링 " .. BRL.acct.command.pullSeconds .. "초", 80, 26, function() BRL.UIActions.PullWithCheck() end, { perm = "raid.command",
        tooltip = { "풀링 판정이 '보류'면 사유를 보여주고 확인 후 시작합니다." } }))
    flow:Add(W.Button(page, "풀링 취소", 80, 26, function() BRL.Command:CancelPull() end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "전투 준비", 80, 26, function() BRL.CombatPrep:Run() end, { kind = "primary", tooltip = { "버프를 다시 읽어 음식/영약/비약/필수 버프가 없는 공대원을 알려줍니다." } }))
    flow:Add(W.Button(page, "다음 경매 시작", 104, 26, function()
        local ok, err = BRL.Auctions:StartNext()
        if not ok then BRL:Print(tostring(err)) end
    end, { perm = "finance.edit", kind = "primary" }))
    flow:Add(W.Button(page, "지난 세션", 80, 26, function() BRL.UIActions.SessionHistory() end,
        { tooltip = { "지난 공격대 세션 목록 (경매 총액 · 수금 · 정산 상태)", "선택하면 그 세션으로 전환합니다." } }))
    flow:Add(W.Button(page, "징표 바", 68, 26, function() BRL.MarkerBar:Toggle() end))
    flow:Add(W.Button(page, "새 세션", 68, 26, function() UI:PromptNewSession() end, { perm = "finance.edit" }))
    flow:Add(W.Button(page, "풀링 판정", 80, 26, function() BRL.UIActions.ShowPullCheck() end))
    flow:Add(W.Button(page, "HUD", 50, 26, function() BRL.HUD:Toggle() end, { tooltip = { "메인 창 없이 경매/거래/풀링 판정/도핑을 보여주는 작은 창 (/brl hud)" } }))

    y = y + 60
    local warn = W.Section(page, "주의 사항")
    warn:SetPoint("TOPLEFT", 4, -y)
    page.warnings = W.Paragraph(page, "", 520, 12)
    page.warnings:SetPoint("TOPLEFT", 4, -y - 22)

    local live = W.Section(page, "진행 현황")
    live:SetPoint("TOPLEFT", 540, -y)
    page.liveInfo = W.Paragraph(page, "", 340, 12)
    page.liveInfo:SetPoint("TOPLEFT", 540, -y - 22)
end

local function setTile(page, key, text, color)
    local t = page.tiles[key]
    if t then t:SetValue(text, color) end
end

local function refresh(page)
    local session = BRL.Session:GetActive()
    local warnings, counts = BRL.Roster:Warnings()
    local raid = session and session.raidKey and BRL.Data.Raids[session.raidKey]
    setTile(page, "raid", session and (raid and raid.name or session.name) or "세션 없음", session and "goldBright" or "muted")
    local size = BRL.Roster:TargetSize()
    setTile(page, "count", counts.total .. " / " .. size, counts.total >= size and "green" or "yellow")
    setTile(page, "tank", tostring(counts.TANK))
    setTile(page, "healer", tostring(counts.HEALER))
    setTile(page, "dps", counts.MELEE .. " / " .. counts.RANGED)
    local missing = {}
    for _, w in ipairs(warnings) do if w:find("부족") then missing[#missing + 1] = w:match("^(%S+)") end end
    setTile(page, "missing", #missing > 0 and table.concat(missing, ", ") or "없음", #missing > 0 and "red" or "green")
    local rs = BRL.Readiness:Summary()
    if rs.checked then
        setTile(page, "ready", rs.ready .. "/" .. rs.total .. (rs.active and " (진행)" or ""), (rs.ready == rs.total) and "green" or "yellow")
    else
        setTile(page, "ready", "미실시", "muted")
    end
    local prog = BRL.RaidProgress:Summary(session and session.id)
    local cur = prog.currentBoss and BRL.BossPlans:Get(prog.currentBoss)
    setTile(page, "boss", cur and cur.name or "-")
    setTile(page, "progress", prog.total > 0 and (prog.killed .. "/" .. prog.total .. " (" .. prog.percent .. "%)") or "-")
    if session then
        local sum = BRL.Ledger:Summary(session.id)
        setTile(page, "auction", Money.Format(sum.totalAwarded, { goldOnly = true }))
        setTile(page, "collected", Money.Format(sum.collected, { goldOnly = true }), "green")
        local st = BRL.Settlement:ForSession(session.id)
        if st then
            local r = st.result or BRL.Settlement:Compute(st, "confirmed")
            setTile(page, "distributable", Money.Format(math.max(0, r.distributable), { goldOnly = true }))
            setTile(page, "settle", BRL.Label("SETTLE_", st.status) .. " v" .. (st.version or 0), T.STATUS_COLOR[st.status] or "goldBright")
            for _, w in ipairs(r.warnings) do warnings[#warnings + 1] = w end
        else
            local est = sum.collected + sum.otherIncome
            setTile(page, "distributable", Money.Format(est, { goldOnly = true }))
            setTile(page, "settle", "미작성", "muted")
        end
        setTile(page, "unpaid", Money.Format(sum.unpaid, { goldOnly = true }), sum.unpaid > 0 and "red" or "green")
        setTile(page, "balance", Money.Format(sum.balance, { goldOnly = true }))
    else
        for _, k in ipairs({ "auction", "collected", "distributable", "unpaid", "settle", "balance" }) do setTile(page, k, "-", "muted") end
        warnings[#warnings + 1] = "공격대 세션이 없습니다. 상단에서 새 세션을 만드세요."
    end
    local unverified = #BRL.TradeJournal:Query({ group = "unverified" })
    local unclassified = #BRL.TradeJournal:Query({ group = "unclassified" })
    setTile(page, "trades", unverified .. " / " .. unclassified, (unverified + unclassified) > 0 and "yellow" or "green")
    local gparts = {}
    for g = 1, 8 do if (counts.byGroup[g] or 0) > 0 then gparts[#gparts + 1] = counts.byGroup[g] end end
    setTile(page, "groups", #gparts > 0 and table.concat(gparts, " · ") or "-")
    -- 도핑 누락 · 전멸 후 재점검은 오른쪽 "진행 현황"의 풀링 판정/전투 준비 줄에 표시 (중복 제거)
    -- 구성 분석: 없는 핵심 시너지 + 추천 직업
    local comp = BRL.Composition:Analyze(BRL.Roster:TargetSize())
    local core = {}
    for _, it in ipairs(comp.eval.items) do
        if it.syn.weight >= 3 and (it.status == "missing" or it.status == "partial") then core[#core + 1] = (it.syn.name:gsub("%s*%(.*%)", "")) end
    end
    if #core > 0 then
        local recs = {}
        for i, r in ipairs(comp.recommendations) do if i <= 3 then recs[#recs + 1] = BRL.Data.ClassName(r.class) end end
        warnings[#warnings + 1] = "부족한 핵심 시너지: " .. table.concat(core, ", ") .. (#recs > 0 and (" → 추천 직업: " .. table.concat(recs, ", ")) or "")
    end
    local lines = {}
    for i, w in ipairs(warnings) do
        if i > 10 then lines[#lines + 1] = "… 외 " .. (#warnings - 10) .. "건" break end
        lines[#lines + 1] = "• " .. w
    end
    page.warnings:SetText(#lines > 0 and table.concat(lines, "\n") or T.Color("green", "특이 사항 없음"))

    -- 진행 현황 (공대장 운영 요약)
    page.liveInfo:SetText(table.concat(BRL.UI.LiveSummary(session), "\n"))
end

UI:RegisterPage("dashboard", { title = L.MENU_DASHBOARD, order = 1, build = build, refresh = refresh })
