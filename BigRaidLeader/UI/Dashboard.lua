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
    flow:Add(W.Button(page, "풀링 " .. BRL.acct.command.pullSeconds .. "초", 96, 26, function() BRL.Command:Pull(BRL.acct.command.pullSeconds) end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "풀링 취소", 86, 26, function() BRL.Command:CancelPull() end, { perm = "raid.command" }))
    flow:Add(W.Button(page, "버프 점검", 86, 26, function() BRL.Buffs:Scan() UI:Open("buffs") end))
    flow:Add(W.Button(page, "다음 경매 시작", 110, 26, function()
        local ok, err = BRL.Auctions:StartNext()
        if not ok then BRL:Print(tostring(err)) end
    end, { perm = "finance.edit", kind = "primary" }))
    flow:Add(W.Button(page, "정산 열기", 86, 26, function() UI:Open("settlement") end))
    flow:Add(W.Button(page, "징표 바", 76, 26, function() BRL.MarkerBar:Toggle() end))
    flow:Add(W.Button(page, "새 세션", 76, 26, function() UI:PromptNewSession() end, { perm = "finance.edit" }))

    y = y + 60
    local warn = W.Section(page, "주의 사항")
    warn:SetPoint("TOPLEFT", 4, -y)
    page.warnings = W.Paragraph(page, "", 520, 12)
    page.warnings:SetPoint("TOPLEFT", 4, -y - 22)

    local member = W.Section(page, "내 정보 (공대원 화면)")
    member:SetPoint("TOPLEFT", 540, -y)
    page.memberInfo = W.Paragraph(page, "", 340, 12)
    page.memberInfo:SetPoint("TOPLEFT", 540, -y - 22)
    page.readyReport = W.Button(page, "준비 상태 보고", 120, 22, function()
        if BRL.Sync:SendReadyReport() then BRL:Print("공대장에게 준비 상태(내구도)를 보고했습니다.") else BRL:Print("보고할 공대장이 없습니다.") end
    end)
    page.readyReport:SetPoint("TOPLEFT", 540, -y - 200)
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
    if not BRL.acct.auction.policyAcknowledged then
        warnings[#warnings + 1] = "골드 경매 운영 전 지역별 정책을 확인하세요 (설정 > 정책 안내)."
    end
    local lines = {}
    for i, w in ipairs(warnings) do
        if i > 10 then lines[#lines + 1] = "… 외 " .. (#warnings - 10) .. "건" break end
        lines[#lines + 1] = "• " .. w
    end
    page.warnings:SetText(#lines > 0 and table.concat(lines, "\n") or T.Color("green", "특이 사항 없음"))

    -- 공대원 화면 (자신의 정보)
    local me = BRL.Roster:Get(BRL.playerKey)
    local R = BRL.Sync.received
    local info = {}
    info[#info + 1] = "내 파티: " .. (me and (me.subgroup .. "파티") or "-")
    local role = BRL.Roles:GetMemberRole(BRL.playerKey, me)
    info[#info + 1] = "내 역할: " .. BRL.Label("CR_", (R.roles and R.roles.role ~= "" and R.roles.role) or role or "NONE")
    local duties = BRL.Roles:DutiesFor("default", BRL.playerKey)
    local dutyText = (R.roles and R.roles.duties ~= "" and R.roles.duties) or (#duties > 0 and table.concat(duties, ", ")) or "-"
    info[#info + 1] = "내 임무: " .. dutyText
    if R.notices[1] then info[#info + 1] = "공지: " .. R.notices[1].text end
    if R.auction and R.auction.status == "active" then
        local remain = math.max(0, R.auction.remaining - (BRL.Util.Clock() - (R.auction.clock or 0)))
        info[#info + 1] = string.format("현재 경매: %s 최고 %s (%s) %d초", R.auction.item or "?", Money.Format(R.auction.high), R.auction.bidder or "-", remain)
    end
    if R.awards[1] then info[#info + 1] = "최근 낙찰: " .. (R.awards[1].item or "?") .. " → " .. (R.awards[1].winner or "?") .. " " .. Money.Format(R.awards[1].amount) end
    local payout = R.payout or BRL.char.lastPayout
    if payout then
        info[#info + 1] = "내 분배 예정액: " .. Money.Format(payout.amount) .. " (지급 " .. Money.Format(payout.paid) .. ", " .. BRL.Label("PAY_", payout.status) .. ")"
    end
    local mn = API.GetOwnDurability()
    if mn then info[#info + 1] = "내 장비 내구도(최저): " .. mn .. "%" end
    page.memberInfo:SetText(table.concat(info, "\n"))
end

UI:RegisterPage("dashboard", { title = L.MENU_DASHBOARD, order = 1, build = build, refresh = refresh })
