-- BIG RAID LEADER - 전리품 경매 화면 (골드 경매 / 낙찰·수금 / 구매자 기록)
local _, BRL = ...
local T, W, L, U, Money, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money, BRL.API
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local AU, Bids, P = BRL.Auctions, BRL.Bids, BRL.Payments

-- 낙찰 → 거래 선택 연결
function A.LinkAwardToTrade(aw)
    local st = P:AwardStatus(aw)
    if st.outstanding <= 0 then D.Message("이미 수금 연결이 끝난 낙찰입니다.") return end
    local items = {}
    local trades = BRL.TradeJournal:Query({})
    table.sort(trades, function(a, b)
        local am, bm = a.partnerKey == aw.winnerKey, b.partnerKey == aw.winnerKey
        if am ~= bm then return am end
        return (a.at or 0) > (b.at or 0)
    end)
    for _, tr in ipairs(trades) do
        if BRL.TradeJournal:IsCounted(tr) and (tr.purpose == "auction_payment" or tr.purpose == "unclassified") then
            local avail = P:TradeAvailableIn(tr)
            if avail > 0 then
                items[#items + 1] = {
                    value = tr.id,
                    text = (tr.partnerKey == aw.winnerKey and "|cff61db80★|r " or "|cff8f8f99(대리)|r ") .. (tr.partnerName or "?") .. " " .. U.FormatDateTime(tr.at),
                    sub = "미연결 " .. Money.Format(avail),
                }
            end
        end
    end
    if #items == 0 then D.Message("연결 가능한 완료 거래가 없습니다.\n(거래가 '확인 불가'이면 거래 로그에서 수동 확인 후 연결하세요. 누락된 거래는 수동 기록으로 추가할 수 있습니다.)") return end
    D.Select("수금 거래 선택 - " .. (aw.winnerName or "?"), items, function(tradeId)
        A.LinkTradeToAwardDirect(BRL.TradeJournal:Get(tradeId), aw)
    end, { description = "연결할 낙찰금 " .. Money.Format(st.outstanding) .. " · ★ = 낙찰자 본인 거래" })
end

function A.LinkTradeToAwardDirect(tr, aw)
    local st = P:AwardStatus(aw)
    local avail = P:TradeAvailableIn(tr)
    D.Input("연결 금액", { { key = "amount", label = "연결 금액", type = "money", default = math.min(avail, st.outstanding), required = true } }, function(v)
        local res, err = P:AllocateAuction(tr.id, aw.id, v.amount)
        if res then return true end
        if err == "overpay" then
            D.Confirm("낙찰금보다 큰 금액입니다. 초과 입금으로 기록할까요?", function()
                A.Report(P:AllocateAuction(tr.id, aw.id, v.amount, { allowOverpay = true }))
            end, { danger = true, title = "초과 입금 경고" })
            return true
        end
        return false, err
    end)
end

local function itemText(auc)
    return (auc.itemLink or auc.itemName or "?") .. ((auc.quantity or 1) > 1 and (" x" .. auc.quantity) or "")
end

local function build(page)
    UI:PageHeader(page, L.MENU_AUCTION, "골드 경매 · 낙찰/수금 · 구매자 기록")
    page.panels = {}
    page.tabs = W.Tabs(page, {
        { key = "auction", text = "골드 경매", width = 100 },
        { key = "awards", text = "낙찰·수금", width = 100 },
        { key = "buyers", text = "구매자 기록", width = 100 },
    }, function(key)
        page.tab = key
        for k, p in pairs(page.panels) do if k == key then p:Show() else p:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPLEFT", 4, -28)
    local function panel(key)
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -58)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = p
        return p
    end

    ---------------------------------------------------------------------
    -- 골드 경매
    ---------------------------------------------------------------------
    local pa = panel("auction")
    local cur = W.Panel(pa, T.colors.panel2, T.colors.border)
    cur:SetPoint("TOPLEFT", 4, 0)
    cur:SetSize(430, 150)
    pa.cur = cur
    cur.icon = cur:CreateTexture(nil, "ARTWORK")
    cur.icon:SetSize(40, 40)
    cur.icon:SetPoint("TOPLEFT", 10, -10)
    cur.item = W.Label(cur, "진행 중인 경매 없음", 14, "goldBright")
    cur.item:SetPoint("TOPLEFT", 58, -12)
    cur.item:SetPoint("RIGHT", -10, 0)
    cur.state = W.Label(cur, "", 11, "muted")
    cur.state:SetPoint("TOPLEFT", 58, -32)
    cur.high = W.Label(cur, "", 20, "green")
    cur.high:SetPoint("TOPLEFT", 10, -62)
    cur.bidder = W.Label(cur, "", 13, "text")
    cur.bidder:SetPoint("TOPLEFT", 10, -90)
    cur.nextMin = W.Label(cur, "", 12, "muted")
    cur.nextMin:SetPoint("TOPLEFT", 10, -112)
    cur.timer = W.Label(cur, "", 26, "yellow", "RIGHT")
    cur.timer:SetPoint("BOTTOMRIGHT", -12, 12)

    local ctl = CreateFrame("Frame", nil, pa)
    ctl:SetPoint("TOPLEFT", 4, -156)
    ctl:SetSize(430, 84)
    local fc = W.Flow(ctl, 0, 1, 4)
    local function active() return AU:GetActive() end
    local function pending() return AU:GetPendingConfirm((BRL.Session:GetActive() or {}).id)[1] end
    fc:Add(W.Button(ctl, "다음 경매 시작", 104, 24, function() local ok, err = AU:StartNext() if not ok then BRL:Print(tostring(err)) end end, { kind = "primary", perm = "finance.edit" }))
    pa.countBtn = fc:Add(W.Button(ctl, "카운트 " .. AU:CountSeconds() .. "초", 84, 24, function()
        local ok, err = AU:StartCount()
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "primary", perm = "finance.edit", tooltip = { "공격대 경보로 \"카운트 5, 4, 3, 2, 1\"을 공지하고 입찰을 마감합니다.", "카운트 중 새 입찰이 들어오면 자동 취소(설정)", "단축키: 키 설정 > 애드온 > 경매 카운트" } }))
    fc:Add(W.Button(ctl, "카운트 취소", 80, 24, function()
        local ok, err = AU:CancelCount(nil, "manual")
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "danger", perm = "finance.edit", tooltip = { "카운트를 멈추고 입찰을 계속 받습니다 (\"[카운트 취소] 입찰 계속\" 공지)." } }))
    fc:Add(W.Button(ctl, "+10초", 52, 24, function() local a = active() if a then AU:ExtendTime(a.id, 10) end end, { perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "입찰 마감", 70, 24, function() local a = active() if a then AU:End(a.id, "manual") end end, { perm = "finance.edit" }))
    fc:NewLine(28)
    fc:Add(W.Button(ctl, "낙찰 확정", 76, 24, function()
        local a = active() or pending()
        if not a then return end
        local bid = Bids:Get(a.highBidId)
        if not bid then BRL:Print("유효한 입찰이 없습니다.") return end
        D.Confirm(string.format("%s\n낙찰자: %s\n낙찰 금액: %s\n\n낙찰을 확정할까요? (실제 수금은 거래 연결 후 반영됩니다)", a.itemLink, bid.bidderName, Money.Format(bid.amount)), function()
            A.Report(AU:ConfirmAward(a.id))
        end, { title = "낙찰 확정" })
    end, { kind = "primary", perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "수동 입찰", 70, 24, function() local a = active() or pending() if a then A.ManualBid(a) end end, { perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "다른 입찰로 낙찰", 110, 24, function()
        local a = active() or pending()
        if not a then return end
        local items = {}
        for _, b in ipairs(Bids:History(a.id)) do
            if b.accepted and not b.retracted then items[#items + 1] = { value = b.id, text = b.bidderName, sub = Money.Format(b.amount) } end
        end
        D.Select("낙찰할 입찰 선택", items, function(bidId)
            if a.status == "active" then AU:End(a.id, "manual") end
            A.Report(AU:ConfirmAward(a.id, bidId))
        end)
    end, { perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "입찰 철회", 70, 24, function()
        local b = pa.bids:GetSelected()
        if b then D.Reason("입찰 철회", function(r) return Bids:Retract(b.id, r) end) end
    end, { perm = "finance.edit" }))
    fc:NewLine(28)
    fc:Add(W.Button(ctl, "유찰", 50, 24, function() local a = active() or pending() if a then AU:MarkUnsold(a.id) end end, { perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "경매 취소", 70, 24, function()
        local a = active() or pending()
        if a then D.Confirm("진행 중인 경매를 취소할까요?", function() AU:Cancel(a.id, "공대장 취소") end, { danger = true }) end
    end, { perm = "finance.edit" }))
    fc:Add(W.Button(ctl, "결과 공지", 70, 24, function() A.SendLines(AU:ResultLines((BRL.Session:GetActive() or {}).id), "경매 결과") end))
    pa.autoNext = W.CheckBox(ctl, "연속 경매", function(v)
        BRL.DB:SetSetting("auction.autoNext", v)
        if v then AU:ScheduleAutoNext() else AU:CancelAutoNext() end
    end, { "낙찰 확정/유찰 후 몇 초 뒤 다음 대기 경매를 자동으로 시작합니다.", "대기 시간: 설정 > 경매/정산 (기본 8초)", "전투 중에는 자동 시작하지 않습니다." })
    pa.autoNext:SetPoint("TOPLEFT", 206, -59)
    pa.autoNextStop = W.Button(ctl, "자동 시작 취소", 96, 24, function() AU:CancelAutoNext() end, { perm = "finance.edit" })
    pa.autoNextStop:SetPoint("TOPLEFT", 318, -57)

    local bh = W.Section(pa, "입찰 내역", 430)
    bh:SetPoint("TOPLEFT", 4, -246)
    pa.bids = W.List(pa, {
        columns = {
            { title = "시각", width = 50, render = function(b) return U.FormatClock(b.at) end },
            { title = "입찰자", width = 100, render = function(b) return b.bidderName end },
            { title = "금액", width = 110, align = "RIGHT", render = function(b) return Money.Format(b.amount) end },
            { title = "결과", width = 0, render = function(b)
                if b.retracted then return T.Color("muted", "철회") end
                if b.accepted then return T.Color("green", "유효") .. " |cff8f8f99" .. (b.source == "chat" and "채팅" or "수동") .. "|r" end
                return T.Color("red", b.rejectReason or "거부")
            end },
        },
        fontSize = 11,
    })
    pa.bids:SetPoint("TOPLEFT", 4, -268)
    pa.bids:SetPoint("BOTTOMLEFT", 4, 4)
    pa.bids:SetWidth(430)

    -- 대기열
    local qh = W.Section(pa, "경매 대기열")
    qh:SetPoint("TOPLEFT", 446, 0)
    pa.showAll = W.CheckBox(pa, "종료된 경매 포함", function() UI:RequestRefresh() end)
    pa.showAll:SetPoint("TOPRIGHT", -110, -2)
    pa.queue = W.List(pa, {
        columns = {
            { title = "#", width = 24, align = "CENTER", render = function(a) return a.status == "queued" and a.order or "" end },
            { title = "아이템", width = 0, render = itemText },
            { title = "시작가", width = 76, align = "RIGHT", render = function(a) return Money.Format(a.startPrice, { goldOnly = true }) end },
            { title = "증가", width = 60, align = "RIGHT", render = function(a) return Money.Format(a.minIncrement, { goldOnly = true }) end },
            { title = "상태", width = 70, render = function(a) return T.StatusText(a.status, BRL.Label("AUC_", a.status)) end },
        },
        onDoubleClick = function(a) if a.status == "queued" then AU:Start(a.id) end end,
        tooltip = function(a)
            local lines = { "시작가 " .. Money.Format(a.startPrice), "최소 증가 " .. Money.Format(a.minIncrement), "시간 " .. a.duration .. "초" }
            if a.buyout and a.buyout > 0 then lines[#lines + 1] = "즉시 낙찰 " .. Money.Format(a.buyout) end
            if a.relistOf then lines[#lines + 1] = "재경매" end
            lines[#lines + 1] = "더블클릭: 경매 시작"
            return a.itemName, lines
        end,
    })
    pa.queue:SetPoint("TOPLEFT", 446, -24)
    pa.queue:SetPoint("BOTTOMRIGHT", -4, 64)
    local qb = CreateFrame("Frame", nil, pa)
    qb:SetPoint("BOTTOMLEFT", 446, 32)
    qb:SetSize(440, 26)
    local fq = W.Flow(qb, 0, 1, 4)
    local function selQ() return pa.queue:GetSelected() end
    fq:Add(W.Button(qb, "아이템 등록", 84, 24, function() A.AddAuction() end, { kind = "primary", perm = "finance.edit", tooltip = { "Shift+클릭/드래그로 아이템 링크 입력" } }))
    fq:Add(W.Button(qb, "전리품 창에서", 92, 24, function()
        local loot = API.GetLootItems()
        if #loot == 0 then BRL:Print("열린 전리품 창이 없습니다.") return end
        local items = {}
        for _, it in ipairs(loot) do items[#items + 1] = { value = it.link, text = it.link, sub = BRL.Data.QualityName(it.quality) } end
        D.Select("전리품 창 아이템 등록", items, function(link) A.AddAuction(link) end)
    end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "▲", 28, 24, function() local a = selQ() if a then AU:Move(a.id, -1) end end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "▼", 28, 24, function() local a = selQ() if a then AU:Move(a.id, 1) end end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "시작", 44, 24, function() local a = selQ() if a then A.Report(AU:Start(a.id)) end end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "수정", 44, 24, function()
        local a = selQ()
        if not a then return end
        D.Input("경매 수정", {
            { key = "startPrice", label = "시작가", type = "money", default = a.startPrice },
            { key = "minIncrement", label = "최소 증가액", type = "money", default = a.minIncrement },
            { key = "buyout", label = "즉시 낙찰가", type = "money", default = a.buyout or 0 },
            { key = "duration", label = "시간(초)", type = "number", default = a.duration },
        }, function(v) return AU:Update(a.id, v) end)
    end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "취소", 44, 24, function() local a = selQ() if a then AU:Cancel(a.id, "대기열에서 취소") end end, { perm = "finance.edit" }))
    fq:Add(W.Button(qb, "재경매", 54, 24, function() local a = selQ() if a then A.Report(AU:Relist(a.id)) end end, { perm = "finance.edit" }))
    local qb2 = CreateFrame("Frame", nil, pa)
    qb2:SetPoint("BOTTOMLEFT", 446, 4)
    qb2:SetSize(440, 26)
    local fq2 = W.Flow(qb2, 0, 1, 4)
    pa.quickLink = fq2:Add(W.EditBox(qb2, 260, 24, { placeholder = "여기에 아이템 Shift+클릭/드래그 후 Enter", acceptItems = true, onEnter = function(t)
        if t and t ~= "" then A.AddAuction(t) end
        pa.quickLink:SetText("")
    end }))
    fq2:Add(W.Button(qb2, "경매 내보내기", 90, 24, function() D.CopyText("경매 기록 CSV", AU:ExportCSV((BRL.Session:GetActive() or {}).id)) end))

    ---------------------------------------------------------------------
    -- 낙찰·수금
    ---------------------------------------------------------------------
    local pw = panel("awards")
    pw.summary = W.Label(pw, "", 12, "gold")
    pw.summary:SetPoint("TOPLEFT", 4, 0)
    pw.list = W.List(pw, {
        columns = {
            { title = "아이템", width = 0, render = function(aw) return aw.itemLink or aw.itemName or "?" end },
            { title = "낙찰자", width = 96, render = function(aw) return BRL.Data.ColorName(aw.winnerName, aw.winnerClass) end },
            { title = "낙찰액", width = 92, align = "RIGHT", render = function(aw) return Money.Format(aw.amount, { goldOnly = aw.amount % 10000 == 0 }) end },
            { title = "수금", width = 92, align = "RIGHT", render = function(aw) return Money.Format(P:AwardStatus(aw).collected, { goldOnly = true }) end },
            { title = "상태", width = 74, render = function(aw) local st = P:AwardStatus(aw) return T.StatusText(st.status, BRL.Label("AWARD_", st.status)) end },
            { title = "전달", width = 40, align = "CENTER", render = function(aw) return aw.delivered and T.Color("green", "O") or T.Color("muted", "-") end },
        },
        onDoubleClick = function(aw) if aw.status == "active" then A.LinkAwardToTrade(aw) end end,
        tooltip = function(aw)
            local lines = { "낙찰 시각: " .. U.FormatDateTime(aw.awardedAt), "경매 ID: " .. tostring(aw.auctionId) }
            for _, a in ipairs(P:AllocationsForAward(aw.id)) do
                lines[#lines + 1] = string.format("%s %s (거래 %s)%s", a.kind == "refund" and "환불" or "입금", Money.Format(a.amount), tostring(a.tradeId), a.proxy and " 대리" or "")
            end
            if aw.cancelReason then lines[#lines + 1] = "취소 사유: " .. aw.cancelReason end
            lines[#lines + 1] = "더블클릭: 수금 거래 연결"
            return aw.itemName, lines
        end,
    })
    pw.list:SetPoint("TOPLEFT", 4, -22)
    pw.list:SetPoint("BOTTOMRIGHT", -4, 70)
    pw.showCancelled = W.CheckBox(pw, "취소된 낙찰 포함", function() UI:RequestRefresh() end)
    pw.showCancelled:SetPoint("TOPRIGHT", -120, -2)
    local function selAw() return pw.list:GetSelected() end
    local wb = CreateFrame("Frame", nil, pw)
    wb:SetPoint("BOTTOMLEFT", 4, 36)
    wb:SetSize(880, 26)
    local fw = W.Flow(wb, 0, 1, 4)
    fw:Add(W.Button(wb, "수금 거래 연결", 104, 24, function() local aw = selAw() if aw then A.LinkAwardToTrade(aw) end end, { kind = "primary", perm = "finance.edit" }))
    fw:Add(W.Button(wb, "연결 내역/해제", 104, 24, function()
        local aw = selAw()
        if not aw then return end
        local items = {}
        for _, a in ipairs(P:AllocationsForAward(aw.id)) do
            items[#items + 1] = { value = a.id, text = (a.kind == "refund" and "환불 " or "입금 ") .. Money.Format(a.amount) .. " · 거래 " .. tostring(a.tradeId), sub = U.FormatDateTime(a.at) }
        end
        if #items == 0 then D.Message("연결된 거래가 없습니다.") return end
        D.Select("연결 해제할 항목 선택", items, function(id)
            D.Reason("연결 해제", function(r) return P:UnlinkAuction(id, r) end)
        end, { description = "연결을 해제해도 거래 기록은 보존됩니다." })
    end, { perm = "finance.edit" }))
    fw:Add(W.Button(wb, "본인 낙찰금 기록", 110, 24, function()
        local aw = selAw()
        if not aw then
            for _, x in ipairs(AU:AwardsForPlayer(BRL.playerKey, (BRL.Session:GetActive() or {}).id)) do
                if BRL.Payments:AwardStatus(x).outstanding > 0 then aw = x break end
            end
        end
        if aw then A.PayAwardFromSelf(aw) else D.Message("기록할 공대장 본인 낙찰이 없습니다.") end
    end, { perm = "finance.edit", tooltip = { "공대장이 직접 낙찰받은 경우, 본인 지갑에서 낸 낙찰금을 거래 로그에 '본인 지급'으로 기록합니다." } }))
    fw:Add(W.Button(wb, "전달 표시", 70, 24, function() local aw = selAw() if aw then AU:SetDelivered(aw.id, not aw.delivered) end end, { perm = "finance.edit" }))
    fw:Add(W.Button(wb, "금액 수정", 70, 24, function() local aw = selAw() if aw then A.ChangeAwardAmount(aw) end end, { perm = "finance.edit" }))
    fw:Add(W.Button(wb, "낙찰 취소", 70, 24, function() local aw = selAw() if aw then A.CancelAward(aw) end end, { kind = "danger", perm = "finance.edit" }))
    fw:Add(W.Button(wb, "결과 공지", 70, 24, function() A.SendLines(AU:ResultLines((BRL.Session:GetActive() or {}).id), "경매 결과") end))
    pw.note = W.Paragraph(pw, "낙찰 금액은 수금 예정 금액입니다. 실제 수금은 '완료 확인'된 거래를 연결해야 반영됩니다. 자동 매칭은 제안만 하며, 금액이 같아도 자동 확정하지 않습니다.", 880, 11)
    pw.note:SetPoint("BOTTOMLEFT", 4, 8)
    T.SetTextColor(pw.note, "muted")

    ---------------------------------------------------------------------
    -- 구매자 기록 (모든 세션 + 보관된 세션)
    ---------------------------------------------------------------------
    local pb = panel("buyers")
    pb.search = W.EditBox(pb, 160, 22, { placeholder = "구매자 검색", onChange = function() UI:RequestRefresh() end })
    pb.search:SetPoint("TOPLEFT", 4, 0)
    pb.summary = W.Label(pb, "", 12, "gold")
    pb.summary:SetPoint("LEFT", pb.search, "RIGHT", 12, 0)
    pb.list = W.List(pb, {
        idKey = "key",
        columns = {
            { title = "구매자", width = 0, render = function(b) return BRL.Data.ColorName(b.name, b.class) end },
            { title = "구매", width = 50, align = "CENTER", render = function(b) return b.count end },
            { title = "총 구매액", width = 100, align = "RIGHT", render = function(b) return Money.Format(b.total, { goldOnly = true }) end },
            { title = "평균", width = 90, align = "RIGHT", render = function(b) return Money.Format(b.average, { goldOnly = true }) end },
            { title = "최고", width = 90, align = "RIGHT", render = function(b) return Money.Format(b.max, { goldOnly = true }) end },
            { title = "세션", width = 44, align = "CENTER", render = function(b) return b.sessions end },
            { title = "최근 구매", width = 86, render = function(b) return b.last > 0 and U.FormatDate(b.last) or "-" end },
        },
        onClick = function() UI:RequestRefresh() end,
    })
    pb.list:SetPoint("TOPLEFT", 4, -28)
    pb.list:SetSize(880, 250)
    pb.detail = W.Paragraph(pb, "", 880, 11)
    pb.detail:SetPoint("TOPLEFT", 4, -286)
    local bb = CreateFrame("Frame", nil, pb)
    bb:SetPoint("BOTTOMLEFT", 4, 8)
    bb:SetSize(880, 26)
    local fb = W.Flow(bb, 0, 1, 4)
    fb:Add(W.Button(bb, "구매 내역 복사", 100, 24, function()
        local lines = { "[BIG RAID LEADER 구매자 기록]" }
        for _, b in ipairs(BRL.Statistics:Buyers(pb.search:GetText())) do
            lines[#lines + 1] = string.format("%s: %d건 / 총 %s / 평균 %s / 최고 %s", b.name, b.count, Money.Format(b.total), Money.Format(b.average),
                Money.Format(b.max))
        end
        D.CopyText("구매자 기록", table.concat(lines, "\n"))
    end))

    page.tabs:Select("auction")
end

local function tick(page, auc, rem)
    if page.tab ~= "auction" then return end
    local cur = page.panels.auction.cur
    if not auc and AU.autoNext then
        cur.timer:SetText(string.format("다음 %d초", AU:AutoNextRemaining() or 0))
        T.SetTextColor(cur.timer, "blue")
    end
    if auc and auc.status == "active" then
        if auc.countEndsClock then
            cur.timer:SetText(string.format("카운트 %d", math.ceil(rem or 0)))
            T.SetTextColor(cur.timer, "red")
        else
            cur.timer:SetText(string.format("%d초", math.ceil(rem or 0)))
            T.SetTextColor(cur.timer, (rem or 0) <= AU:CountSeconds() and "red" or "yellow")
        end
    end
end

local function refresh(page)
    local session = BRL.Session:GetActive()
    local sid = session and session.id
    if page.tab == "auction" then
        local pa = page.panels.auction
        local cur = pa.cur
        local a = AU:GetActive() or AU:GetPendingConfirm(sid)[1]
        if a then
            cur.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            cur.icon:Show()
            cur.item:SetText(itemText(a))
            pa.countBtn:SetText("카운트 " .. AU:CountSeconds() .. "초")
            cur.state:SetText(BRL.Label("AUC_", a.status) .. (a.countEndsClock and " · |cffff6161카운트 중|r" or "") .. (a.endReason == "interrupted" and " (재접속으로 중단됨 - 확인 후 낙찰/유찰)" or "") ..
                (a.buyout and a.buyout > 0 and (" · 즉시 낙찰 " .. Money.Format(a.buyout)) or ""))
            cur.high:SetText(a.highAmount and Money.Format(a.highAmount) or ("시작가 " .. Money.Format(a.startPrice)))
            cur.bidder:SetText(a.highBidder and ("최고 입찰자: " .. API.ShortName(a.highBidder)) or "입찰 없음")
            cur.nextMin:SetText("다음 최소 입찰가: " .. Money.Format(AU:NextMinimum(a)) .. " · 최소 증가 " .. Money.Format(a.minIncrement))
            if a.status == "active" then
                if a.countEndsClock then
                    cur.timer:SetText(string.format("카운트 %d", math.ceil(AU:Remaining(a))))
                    T.SetTextColor(cur.timer, "red")
                else
                    cur.timer:SetText(string.format("%d초", math.ceil(AU:Remaining(a))))
                    T.SetTextColor(cur.timer, "yellow")
                end
            else
                cur.timer:SetText(T.Color("yellow", "확정 대기"))
            end
            pa.bids:SetData(Bids:History(a.id), true)
        else
            cur.icon:Hide()
            cur.item:SetText("진행 중인 경매 없음")
            cur.state:SetText(session and ("세션: " .. session.name) or "공격대 세션이 없습니다 (아이템 등록 시 자동 생성)")
            cur.high:SetText("")
            cur.bidder:SetText("")
            cur.nextMin:SetText("")
            cur.timer:SetText(AU.autoNext and string.format("다음 %d초", AU:AutoNextRemaining() or 0) or "")
            pa.bids:SetData({})
        end
        pa.autoNext:SetChecked(BRL.acct.auction.autoNext and true or false)
        if AU.autoNext then pa.autoNextStop:Show() else pa.autoNextStop:Hide() end
        local filter = pa.showAll:GetChecked() and nil or { queued = true, active = true, ended = true }
        pa.queue:SetData(sid and AU:List(sid, filter) or {}, true)
    elseif page.tab == "awards" then
        local pw = page.panels.awards
        pw.list:SetData(sid and AU:Awards(sid, pw.showCancelled:GetChecked()) or {}, true)
        if sid then
            local sum = BRL.Ledger:Summary(sid)
            pw.summary:SetText(string.format("낙찰 %d건 · 총 경매액 %s · 실제 수금 %s%s%s",
                sum.awardCount, Money.Format(sum.totalAwarded), Money.Format(sum.collected),
                sum.unallocatedAuctionIncome > 0 and (" · " .. T.Color("yellow", "미연결 수금 " .. Money.Format(sum.unallocatedAuctionIncome))) or "",
                sum.refundDue > 0 and (" · " .. T.Color("red", "환불 필요 " .. Money.Format(sum.refundDue))) or ""))
        else
            pw.summary:SetText("공격대 세션이 없습니다")
        end
    elseif page.tab == "buyers" then
        local pb = page.panels.buyers
        local list = BRL.Statistics:Buyers(pb.search:GetText())
        pb.list:SetData(list, true)
        local total = 0
        for _, b in ipairs(list) do total = total + b.total end
        pb.summary:SetText(string.format("구매자 %d명 · 총 %s (모든 세션)", #list, Money.Format(total, { goldOnly = true })))
        local b = pb.list:GetSelected()
        if b then
            local lines = { T.Color("goldBright", b.name) .. " 구매 내역 (최근순)" }
            for i, it in ipairs(b.items) do
                if i > 12 then lines[#lines + 1] = "… 외 " .. (#b.items - 12) .. "건" break end
                lines[#lines + 1] = string.format("%s  %s  %s  %s", it.at and U.FormatDate(it.at) or "-", it.name or "?", Money.Format(it.amount or 0),
                    T.Color("muted", it.session or ""))
            end
            pb.detail:SetText(table.concat(lines, "\n"))
        else
            pb.detail:SetText(T.Color("muted", "구매자를 선택하면 구매 내역이 표시됩니다."))
        end
    end
    UI:SetPermBanner(page, "finance.edit")
end

UI:RegisterPage("auction", { title = L.MENU_AUCTION, order = 10, build = build, refresh = refresh, tick = tick })
