-- BIG RAID LEADER - 대시보드 (공격대 운영 상태 한눈에 보기)
local _, BRL = ...
local T, W, Money, L, API = BRL.Theme, BRL.Widgets, BRL.Money, BRL.L, BRL.API
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
    { key = "progress", label = "보스 진행", page = "stats" },
    { key = "auction", label = "경매 총액", page = "auction" },
    { key = "collected", label = "실제 수금액", page = "ledger" },
    { key = "outstanding", label = "미수금", page = "ledger" },
    { key = "distributable", label = "분배 가능 골드", page = "settlement" },
    { key = "unpaid", label = "미지급금", page = "settlement" },
    { key = "settle", label = "정산 진행 상태", page = "settlement" },
    { key = "balance", label = "장부 잔액", page = "ledger" },
    { key = "trades", label = "확인 필요 거래", page = "trades" },
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
    flow:Add(W.Button(page, "준비 확인", 96, 26, function() BRL.Command:ReadyCheck() end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "풀링 " .. BRL.acct.command.pullSeconds .. "초", 96, 26, function() BRL.UIActions.PullWithCheck() end, { perm = "raid.command",
        tooltip = { "풀링 판정이 '보류'면 사유를 보여주고 확인 후 시작합니다." } }))
    flow:Add(W.Button(page, "풀링 취소", 86, 26, function() BRL.Command:CancelPull() end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "전투 준비", 86, 26, function() BRL.CombatPrep:Run() end, { kind = "primary", tooltip = { "버프를 다시 읽어 음식/영약/비약/필수 버프가 없는 공대원을 알려줍니다." } }))
    flow:Add(W.Button(page, "다음 경매 시작", 110, 26, function()
        local ok, err = BRL.Auctions:StartNext()
        if not ok then BRL:Print(tostring(err)) end
    end, { perm = "finance.edit", kind = "primary" }))
    flow:Add(W.Button(page, "정산 열기", 86, 26, function() UI:Open("settlement") end))
    flow:Add(W.Button(page, "징표 바", 76, 26, function() BRL.MarkerBar:Toggle() end))
    flow:Add(W.Button(page, "새 세션", 76, 26, function() UI:PromptNewSession() end, { perm = "finance.edit" }))
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

-- 공대장 진행 현황 요약 줄 (대시보드/HUD 공용)
function UI.LiveSummary(session)
    local info = {}
    local auc = BRL.Auctions:GetActive()
    if auc then
        local remain = math.max(0, math.ceil((auc.endsClock or 0) - BRL.Util.Clock()))
        info[#info + 1] = string.format("경매: %s 최고 %s%s %s", BRL.Util.StripColors(auc.itemName or "?"),
            auc.highAmount and Money.Format(auc.highAmount) or "없음", auc.highBidder and (" (" .. API.ShortName(auc.highBidder) .. ")") or "",
            BRL.Auctions:IsCounting(auc) and T.Color("red", "카운트 " .. remain) or (remain .. "초"))
    else
        local queued = session and #BRL.Auctions:Queue(session.id) or 0
        info[#info + 1] = "경매: 진행 없음" .. (queued > 0 and (" · 대기 " .. queued .. "건") or "")
    end
    local rp = BRL.Recruitment:Progress()
    if BRL.Recruitment:IsActive() then
        info[#info + 1] = string.format("모집: 진행 중 %d/%d (부족 %d)", rp.have, rp.size, math.max(0, rp.size - rp.have))
    end
    local pc = BRL.CombatPrep.PullCheck and BRL.CombatPrep:PullCheck()
    if pc then info[#info + 1] = "풀링 판정: " .. T.Color(pc.color, pc.label) .. (pc.reasons[1] and (" - " .. pc.reasons[1]) or "") end
    local prep = BRL.CombatPrep.last
    if prep then
        info[#info + 1] = string.format("전투 준비(%s): 음식 누락 %d · %s 누락 %d", BRL.Util.FormatClock(prep.at), #prep.noFood, BRL.CombatPrep:MainLabel(), #prep.noMain)
    end
    if session then
        local st = BRL.Settlement:ForSession(session.id)
        if st and st.status ~= "draft" then
            local pay = BRL.Settlement:PaymentState(st.id)
            local done, total = 0, 0
            for _, row in ipairs(pay.rows) do
                total = total + 1
                if row.remaining == 0 then done = done + 1 end
            end
            info[#info + 1] = string.format("분배 지급: %d/%d명 완료 · 남은 %s", done, total, Money.Format(pay.unpaid))
        end
        local sum = BRL.Ledger:Summary(session.id)
        if sum.outstanding > 0 then
            local debtors = BRL.Payments:Debtors(session.id)
            info[#info + 1] = string.format("미수금: %s (%d명)", Money.Format(sum.outstanding), #debtors)
        end
    end
    local cur = BRL.TradeTracker:GetCurrent()
    if cur then info[#info + 1] = "거래 중: " .. (cur.partnerName or "?") end
    return info
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
        setTile(page, "outstanding", Money.Format(sum.outstanding, { goldOnly = true }), sum.outstanding > 0 and "red" or "green")
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
        for _, k in ipairs({ "auction", "collected", "outstanding", "distributable", "unpaid", "settle", "balance" }) do setTile(page, k, "-", "muted") end
        warnings[#warnings + 1] = "공격대 세션이 없습니다. 상단에서 새 세션을 만드세요."
    end
    local unverified = #BRL.TradeJournal:Query({ group = "unverified" })
    local unclassified = #BRL.TradeJournal:Query({ group = "unclassified" })
    setTile(page, "trades", unverified .. " 확인불가 / " .. unclassified .. " 미분류", (unverified + unclassified) > 0 and "yellow" or "green")
    local gparts = {}
    for g = 1, 8 do if (counts.byGroup[g] or 0) > 0 then gparts[#gparts + 1] = counts.byGroup[g] end end
    setTile(page, "groups", #gparts > 0 and table.concat(gparts, " · ") or "-")
    if BRL.Buffs.needsRecheck then warnings[#warnings + 1] = "전멸 후 재도핑 점검이 필요합니다 (버프 및 야영지)." end
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
    local prep = BRL.CombatPrep.last
    if prep and (#prep.noFood + #prep.noMain) > 0 then
        warnings[#warnings + 1] = string.format("도핑 누락 (%s): 음식 %d명, %s %d명", BRL.Util.FormatClock(prep.at), #prep.noFood, BRL.CombatPrep:MainLabel(), #prep.noMain)
    end
    if not BRL.acct.auction.policyAcknowledged then
        warnings[#warnings + 1] = "골드 경매 운영 전 지역별 정책을 확인하세요 (설정 > 정책 안내)."
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
