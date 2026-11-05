-- BIG RAID LEADER - 거래 완료 직후 목적 분류 창 (최소 클릭으로 경매/분배 연결)
local _, BRL = ...
local T, W, Money, API = BRL.Theme, BRL.Widgets, BRL.Money, BRL.API

local TP = BRL:NewModule("TradePopup")

function TP:OnEnable()
    BRL.Events:On(BRL.Events.MSG.SELF_AWARD, self, function(_, award)
        if not award then return end
        if API.InCombat() then
            BRL:Print("공대장 본인 낙찰: 전투 후 [전리품 경매 > 낙찰·수금]의 '본인 낙찰금 기록'으로 거래 로그에 남기세요.")
            return
        end
        BRL.Dialogs.Confirm(string.format("공대장 본인 낙찰\n%s - %s\n\n본인 지갑에서 공대 금액으로 낸 것으로 거래 로그에 지금 기록할까요?\n(나중에 [낙찰·수금]의 '본인 낙찰금 기록'으로도 할 수 있습니다)",
            award.itemName or "?", Money.Format(award.amount)), function()
            local res, err = BRL.Payments:PayAwardFromSelf(award.id)
            if res then BRL:Print("본인 낙찰금 %s 기록 완료 (거래 로그: 본인 지급)", Money.Format(award.amount))
            else BRL:Print("본인 낙찰금 기록 실패: %s", tostring(err)) end
        end, { title = "본인 낙찰금 기록", acceptText = "지금 기록", cancelText = "나중에" })
    end)
    BRL.Events:On(BRL.Events.MSG.TRADE_RECORDED, self, function(_, tr)
        if tr and tr.source == "auto" and BRL.TradeJournal:IsCounted(tr) and tr.purpose == "unclassified"
            and BRL.acct.trade.completionPopup and not API.InCombat() then
            self:Show(tr)
        end
    end)
end

function TP:Create()
    if self.frame then return self.frame end
    local f = W.Panel(UIParent, nil, nil, "dialog")
    _G.BigRaidLeaderTradePopup = f
    f:SetSize(450, 206)
    f:SetPoint("TOP", 0, -200)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    f.title = W.Label(f, "거래 완료 - 목적을 선택하세요", 14, "goldBright", nil, true)
    f.title:SetPoint("TOPLEFT", 18, -16)
    f.body = W.Paragraph(f, "", 414, 12)
    f.body:SetPoint("TOPLEFT", 18, -40)
    f.suggest = W.Paragraph(f, "", 414, 11)
    f.suggest:SetPoint("TOPLEFT", 18, -88)
    T.SetTextColor(f.suggest, "yellow")
    local close = W.CloseButton(f, function() f:Hide() end, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.apply = W.Button(f, "제안대로 연결", 130, 24, function()
        local tr = f.trade
        if not tr then return end
        local n = BRL.Payments:ApplySuggestion(tr.id)
        BRL:Print("거래 연결 %d건 승인", n)
        f:Hide()
    end, { kind = "primary" })
    f.apply:SetPoint("BOTTOMLEFT", 18, 46)
    f.auction = W.Button(f, "경매금 수금", 100, 24, function()
        local tr = f.trade
        f:Hide()
        if tr then BRL.UIActions.LinkTradeToAward(tr) end
    end)
    f.auction:SetPoint("LEFT", f.apply, "RIGHT", 6, 0)
    f.payout = W.Button(f, "분배 지급", 90, 24, function()
        local tr = f.trade
        f:Hide()
        if tr then BRL.UIActions.LinkTradeToPayout(tr) end
    end)
    f.payout:SetPoint("LEFT", f.auction, "RIGHT", 6, 0)
    f.personal = W.Button(f, "개인 거래", 90, 24, function()
        local tr = f.trade
        if tr then BRL.TradeJournal:SetPurpose(tr.id, "personal", "거래 직후 분류") end
        f:Hide()
    end)
    f.personal:SetPoint("BOTTOMLEFT", 18, 16)
    f.income = W.Button(f, "기타 공대 수입", 110, 24, function()
        local tr = f.trade
        if tr then BRL.TradeJournal:SetPurpose(tr.id, "raid_income", "거래 직후 분류") end
        f:Hide()
    end)
    f.income:SetPoint("LEFT", f.personal, "RIGHT", 6, 0)
    f.expense = W.Button(f, "기타 공대 지출", 110, 24, function()
        local tr = f.trade
        if tr then BRL.TradeJournal:SetPurpose(tr.id, "raid_expense", "거래 직후 분류") end
        f:Hide()
    end)
    f.expense:SetPoint("LEFT", f.income, "RIGHT", 6, 0)
    f.later = W.Button(f, "나중에", 70, 24, function() f:Hide() end)
    f.later:SetPoint("BOTTOMRIGHT", -18, 16)
    self.frame = f
    return f
end

function TP:Show(tr)
    local f = self:Create()
    f.trade = tr
    local eff = BRL.TradeJournal:Effective(tr)
    local parts = { "상대: " .. BRL.Data.ColorName(tr.partnerName, tr.partnerClass) }
    if eff.received > 0 then parts[#parts + 1] = "받은 골드: " .. T.Color("green", Money.Format(eff.received)) end
    if eff.given > 0 then parts[#parts + 1] = "지급 골드: " .. T.Color("red", Money.Format(eff.given)) end
    local items = BRL.TradeJournal:ItemSummary(tr, 120)
    if items ~= "" then parts[#parts + 1] = "아이템: " .. items end
    f.body:SetText(table.concat(parts, "\n"))
    local sug = tr.suggestion
    if sug and sug.allocations and #sug.allocations > 0 then
        local lines = {}
        for _, s in ipairs(sug.allocations) do
            if s.awardId then
                local aw = BRL.Auctions:GetAward(s.awardId)
                lines[#lines + 1] = "제안: " .. (aw and (aw.itemName or "?") or "?") .. " 낙찰금 " .. Money.Format(s.amount) .. (s.exact and " (금액 일치)" or "")
            elseif s.obligationId then
                lines[#lines + 1] = "제안: 분배금 지급 " .. Money.Format(s.amount) .. (s.exact and " (금액 일치)" or "")
            end
        end
        f.suggest:SetText(table.concat(lines, "\n") .. "\n자동 확정하지 않습니다. 확인 후 승인하세요.")
        f.apply:Show()
    else
        f.suggest:SetText("")
        f.apply:Hide()
    end
    if eff.received > 0 then f.auction:Show() f.income:Show() else f.auction:Hide() f.income:Hide() end
    if eff.given > 0 then f.payout:Show() f.expense:Show() else f.payout:Hide() f.expense:Hide() end
    f:Show()
end
