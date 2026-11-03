-- BIG RAID LEADER - 거래 로그 화면
local _, BRL = ...
local T, W, L, U, Money = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local J, P = BRL.TradeJournal, BRL.Payments

local function linkText(tr)
    local links = P:LinksForTrade(tr.id)
    local parts = {}
    for _, a in ipairs(links.awards) do
        local aw = BRL.Auctions:GetAward(a.awardId)
        parts[#parts + 1] = (a.kind == "refund" and "환불:" or "") .. (aw and U.StripColors(aw.itemName or "?") or "?")
    end
    if #links.payouts > 0 then parts[#parts + 1] = "분배 " .. #links.payouts .. "명" end
    if #parts == 0 and tr.suggestion then return T.Color("yellow", "연결 제안 있음") end
    return table.concat(parts, ", ")
end

local function build(page)
    UI:PageHeader(page, L.MENU_TRADES, "거래 자동 기록 · 완료 검증 · 목적 분류")
    page.filter = {}
    local flow = W.Flow(page, 4, 28, 5)
    page.group = flow:Add(W.Dropdown(page, 130, {
        { value = false, text = "전체 거래" }, { value = "raid", text = "골드팟 관련" }, { value = "personal", text = "개인 거래" },
        { value = "unverified", text = "확인 불가(미확인)" }, { value = "unclassified", text = "미분류 완료 거래" }, { value = "cancelled", text = "취소된 거래" },
    }, function() UI:RequestRefresh() end))
    page.group:SetValue(false, true)
    page.direction = flow:Add(W.Dropdown(page, 90, {
        { value = false, text = "입출금" }, { value = "in", text = "입금" }, { value = "out", text = "출금" },
    }, function() UI:RequestRefresh() end))
    page.direction:SetValue(false, true)
    page.kind = flow:Add(W.Dropdown(page, 100, {
        { value = false, text = "골드/아이템" }, { value = "gold", text = "골드 거래" }, { value = "item", text = "아이템 거래" },
    }, function() UI:RequestRefresh() end))
    page.kind:SetValue(false, true)
    page.period = flow:Add(W.Dropdown(page, 100, {
        { value = false, text = "전체 기간" }, { value = 1, text = "오늘" }, { value = 7, text = "최근 7일" }, { value = 30, text = "최근 30일" },
        { value = "session", text = "현재 세션" },
    }, function() UI:RequestRefresh() end))
    page.period:SetValue(false, true)
    page.partner = flow:Add(W.EditBox(page, 110, 22, { placeholder = "거래 상대", onChange = function() UI:RequestRefresh() end }))
    page.search = flow:Add(W.EditBox(page, 120, 22, { placeholder = "메모/아이템 검색", onChange = function() UI:RequestRefresh() end }))
    page.showVoided = W.CheckBox(page, "취소 기록", function() UI:RequestRefresh() end)
    page.showVoided:SetPoint("TOPRIGHT", -70, -31)

    page.list = W.List(page, {
        idKey = "id",
        columns = {
            { title = "시각", width = 86, render = function(tr) return date("%m-%d %H:%M", tr.at) end },
            { title = "거래 상대", width = 100, render = function(tr) return BRL.Data.ColorName(tr.partnerName, tr.partnerClass) end },
            { title = "받은 골드", width = 92, align = "RIGHT", render = function(tr)
                local e = J:Effective(tr)
                return e.received > 0 and T.Color("green", Money.Format(e.received, { goldOnly = e.received % 10000 == 0 })) or ""
            end },
            { title = "지급 골드", width = 92, align = "RIGHT", render = function(tr)
                local e = J:Effective(tr)
                return e.given > 0 and T.Color("red", Money.Format(e.given, { goldOnly = e.given % 10000 == 0 })) or ""
            end },
            { title = "아이템", width = 0, render = function(tr) return J:ItemSummary(tr, 90) end },
            { title = "거래 목적", width = 104, render = function(tr) return J:PurposeLabel(tr.purpose) end },
            { title = "연결", width = 96, render = linkText },
            { title = "상태", width = 84, render = function(tr) return T.StatusText(tr.voided and "cancelled" or tr.status, J:StatusLabel(tr)) end },
        },
        onDoubleClick = function(tr) A.TradeDetail(tr) end,
        onRightClick = function(tr) page.context(tr) end,
        tooltip = function(tr)
            local lines = { "상태: " .. J:StatusLabel(tr) .. " (" .. tostring(tr.verification) .. ")", "목적: " .. J:PurposeLabel(tr.purpose) }
            if tr.note then lines[#lines + 1] = "메모: " .. tr.note end
            if tr.adjusted then lines[#lines + 1] = "수동 조정: " .. tostring(tr.adjusted.reason) end
            lines[#lines + 1] = "더블클릭: 상세 · 우클릭: 작업 메뉴"
            return tr.partnerName, lines
        end,
    })
    page.list:SetPoint("TOPLEFT", 4, -56)
    page.list:SetPoint("BOTTOMRIGHT", -4, 70)
    page.summary = W.Label(page, "", 12, "gold")
    page.summary:SetPoint("BOTTOMLEFT", 4, 42)

    page.context = function(tr)
        local items = {
            { value = "detail", text = "상세 보기 / 수정 이력" },
            { value = "purpose", text = "거래 목적 변경" },
        }
        local e = J:Effective(tr)
        if J:IsCounted(tr) and e.net > 0 then items[#items + 1] = { value = "award", text = "경매금 수금으로 연결" } end
        if J:IsCounted(tr) and e.net < 0 then
            items[#items + 1] = { value = "payout", text = "분배 지급으로 연결" }
            items[#items + 1] = { value = "refund", text = "경매금 환불로 연결" }
        end
        if tr.suggestion then items[#items + 1] = { value = "suggest", text = "|cffffd100연결 제안 승인|r" } end
        if tr.status == "unverified" or tr.status == "cancelled" then items[#items + 1] = { value = "confirm", text = "수동 확인 (완료로 인정)" } end
        if tr.status == "unverified" then items[#items + 1] = { value = "markcancel", text = "취소로 표시" } end
        items[#items + 1] = { value = "adjust", text = "금액 정정 (수동 조정)" }
        items[#items + 1] = { value = "note", text = "메모" }
        if tr.voided then items[#items + 1] = { value = "restore", text = "기록 복원" } else items[#items + 1] = { value = "void", text = "기록 취소" } end
        D.Select((tr.partnerName or "?") .. " 거래 작업", items, function(v)
            if v == "detail" then A.TradeDetail(tr)
            elseif v == "purpose" then A.ChangePurpose(tr)
            elseif v == "award" then A.LinkTradeToAward(tr)
            elseif v == "payout" then A.LinkTradeToPayout(tr)
            elseif v == "refund" then A.LinkRefund(tr)
            elseif v == "suggest" then BRL:Print("연결 %d건 승인", P:ApplySuggestion(tr.id))
            elseif v == "confirm" then A.ConfirmTrade(tr)
            elseif v == "markcancel" then D.Reason("취소로 표시", function(r) return J:MarkCancelled(tr.id, r) end)
            elseif v == "adjust" then A.AdjustTrade(tr)
            elseif v == "note" then D.Input("메모", { { key = "note", label = "메모", type = "text", default = tr.note } }, function(x) return J:SetNote(tr.id, x.note) end)
            elseif v == "restore" then D.Reason("기록 복원", function(r) return J:Restore(tr.id, r) end)
            elseif v == "void" then A.VoidTrade(tr) end
        end)
    end

    local function sel() return page.list:GetSelected() end
    local _, f = UI.BottomBar(page)
    f:Add(W.Button(f.parent, "작업 메뉴", 76, 24, function() local tr = sel() if tr then page.context(tr) end end))
    f:Add(W.Button(f.parent, "경매금 연결", 86, 24, function() local tr = sel() if tr then A.LinkTradeToAward(tr) end end, { kind = "primary", perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "분배 지급 연결", 100, 24, function() local tr = sel() if tr then A.LinkTradeToPayout(tr) end end, { perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "목적 변경", 76, 24, function() local tr = sel() if tr then A.ChangePurpose(tr) end end))
    f:Add(W.Button(f.parent, "개인 거래로", 84, 24, function() local tr = sel() if tr then A.Report(J:SetPurpose(tr.id, "personal", "개인 거래 분류")) end end))
    f:Add(W.Button(f.parent, "수동 기록 추가", 100, 24, function() A.AddManualTrade() end))
    f:Add(W.Button(f.parent, "내보내기(CSV)", 96, 24, function() D.CopyText("거래 로그 CSV", J:ExportCSV(page.lastList)) end))
end

local function refresh(page)
    local f = {
        group = page.group:GetValue() or nil, direction = page.direction:GetValue() or nil, kind = page.kind:GetValue() or nil,
        partner = page.partner:GetText(), search = page.search:GetText(), includeVoided = page.showVoided:GetChecked(),
    }
    local period = page.period:GetValue()
    if period == "session" then
        local s = BRL.Session:GetActive()
        f.sessionId = s and s.id or "__none"
    elseif period then
        f.from = U.Now() - period * 86400
    end
    local list = J:Query(f)
    page.lastList = list
    page.list:SetData(list, true)
    local inSum, outSum, unverified = 0, 0, 0
    for _, tr in ipairs(list) do
        if J:IsCounted(tr) then
            local e = J:Effective(tr)
            inSum, outSum = inSum + e.received, outSum + e.given
        elseif tr.status == "unverified" then
            unverified = unverified + 1
        end
    end
    page.summary:SetText(string.format("%d건 · 확정 입금 %s · 확정 출금 %s%s · 진행 중 거래: %s", #list, Money.Format(inSum), Money.Format(outSum),
        unverified > 0 and (" · " .. T.Color("yellow", "확인 불가 " .. unverified .. "건(합산 제외)")) or "",
        BRL.TradeTracker:GetCurrent() and T.Color("yellow", "있음") or "없음"))
end

UI:RegisterPage("trades", { title = L.MENU_TRADES, order = 11, build = build, refresh = refresh })
