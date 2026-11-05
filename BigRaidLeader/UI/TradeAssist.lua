-- BIG RAID LEADER - 거래 창 옆 정보 패널
-- 거래 상대에게서 받을 낙찰금/줄 분배금과 현재 거래 창 금액을 실시간으로 비교해 보여준다.
-- [분배금 입력]은 내 골드 칸에 남은 분배금을 넣기만 하며, 거래 수락은 절대 자동으로 하지 않는다.
local _, BRL = ...
local T, W, Money, API, U = BRL.Theme, BRL.Widgets, BRL.Money, BRL.API, BRL.Util

local TA = BRL:NewModule("TradeAssist")

function TA:OnEnable()
    BRL.Events:On(BRL.Events.MSG.TRADE_STATE, self, function(_, sess) self:Update(sess) end)
    BRL.Events:Register("TRADE_CLOSED", self, function() if self.frame then self.frame:Hide() end end)
end

function TA:Enabled()
    return BRL.acct.trade.assistPanel ~= false
end

-- 표시용 정보 계산 (UI 와 분리: 테스트 가능)
function TA:Info(sess)
    if not sess then return nil end
    local key = sess.partnerKey
    local live = sess.live or {}
    local info = { partnerKey = key, partnerName = key and API.ShortName(key) or "알 수 없음", partnerClass = sess.partnerClass,
        offered = live.targetMoney or 0, given = live.playerMoney or 0, accepted = sess.playerAccepted, targetAccepted = sess.targetAccepted }
    info.awardDue, info.awardList = BRL.Payments:PendingAwardsFor(key)
    info.payout, info.payoutList = BRL.Payments:UnpaidPayoutFor(key)
    -- 상대가 넣은 골드 vs 받을 낙찰금
    if info.awardDue > 0 then
        if info.offered == 0 then info.offerState = "none"
        elseif info.offered == info.awardDue then info.offerState = "match"
        elseif info.offered < info.awardDue then info.offerState = "short"
        else info.offerState = "over" end
    end
    -- 준 골드 vs 미지급 분배금
    if info.payout > 0 then
        if info.given == 0 then info.giveState = "none"
        elseif info.given == info.payout then info.giveState = "match"
        elseif info.given < info.payout then info.giveState = "short"
        else info.giveState = "over" end
    end
    return info
end

function TA:Lines(info)
    local lines = {}
    if not info then return lines end
    lines[#lines + 1] = T.Color("goldBright", "거래 상대: ") .. BRL.Data.ColorName(info.partnerName, info.partnerClass)
    if info.awardDue > 0 then
        local items = {}
        for i, e in ipairs(info.awardList) do
            if i > 3 then items[#items + 1] = "외 " .. (#info.awardList - 3) .. "건" break end
            items[#items + 1] = U.StripColors(U.ItemNameFromLink(e.award.itemLink) or e.award.itemName or "?")
        end
        lines[#lines + 1] = "받을 낙찰금: " .. T.Color("gold", Money.Format(info.awardDue)) .. T.Color("muted", " (" .. table.concat(items, ", ") .. ")")
        local st = info.offerState
        local diff = info.offered - info.awardDue
        lines[#lines + 1] = "상대가 넣은 골드: " .. Money.Format(info.offered) .. "  " ..
            (st == "match" and T.Color("green", "✔ 낙찰금과 일치")
            or st == "short" and T.Color("yellow", "부족 " .. Money.Format(-diff))
            or st == "over" and T.Color("red", "초과 " .. Money.Format(diff))
            or T.Color("muted", "아직 없음"))
    else
        lines[#lines + 1] = "받을 낙찰금: " .. T.Color("muted", "없음") .. (info.offered > 0 and ("  · 상대가 넣은 골드 " .. Money.Format(info.offered)) or "")
    end
    if info.payout > 0 then
        local st = info.giveState
        local diff = info.given - info.payout
        lines[#lines + 1] = "미지급 분배금: " .. T.Color("blue", Money.Format(info.payout)) .. "  · 내가 넣은 골드 " .. Money.Format(info.given) .. "  " ..
            (st == "match" and T.Color("green", "✔ 일치")
            or st == "short" and T.Color("yellow", "부족 " .. Money.Format(-diff))
            or st == "over" and T.Color("red", "초과 " .. Money.Format(diff))
            or "")
    end
    if info.awardDue > 0 and info.payout > 0 then
        lines[#lines + 1] = T.Color("yellow", "받을 낙찰금과 줄 분배금이 모두 있습니다. 상계하지 말고 각각 거래로 처리하세요.")
    end
    lines[#lines + 1] = T.Color("muted", "거래 수락은 직접 눌러 주세요. 애드온은 자동 수락하지 않습니다.")
    return lines
end

-- 내 골드 칸에 남은 분배금 입력
function TA:FillPayout()
    local sess = BRL.TradeTracker.current
    if not sess then return false, "거래 창이 열려 있지 않습니다" end
    local info = self:Info(sess)
    if not info or info.payout <= 0 then return false, "이 상대에게 남은 분배금이 없습니다" end
    if info.payout > (API.GetMoney() or 0) then return false, "보유 골드가 부족합니다" end
    local ok, err = API.SetTradeMoney(info.payout)
    if not ok then
        return false, (err or "입력 실패") .. " - 골드 칸에 " .. Money.Format(info.payout) .. " 를 직접 입력하세요"
    end
    BRL:Print("분배금 %s 을 거래 창에 입력했습니다. 금액을 확인한 뒤 직접 수락하세요.", Money.Format(info.payout))
    return true
end

function TA:Create()
    if self.frame then return self.frame end
    local f = W.Panel(UIParent, nil, nil, "panel")
    _G.BigRaidLeaderTradeAssist = f
    f:SetSize(330, 150)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:Hide()
    f.title = W.Label(f, "BIG RAID LEADER 거래 정보", 12, "gold")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.body = W.Paragraph(f, "", 310, 11)
    f.body:SetPoint("TOPLEFT", 10, -26)
    f.fill = W.Button(f, "분배금 입력", 90, 22, function()
        local ok, err = self:FillPayout()
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "primary", perm = "finance.edit", tooltip = { "남은 분배금을 내 골드 칸에 입력합니다.", "거래 수락은 직접 눌러야 합니다." } })
    f.fill:SetPoint("BOTTOMLEFT", 10, 8)
    f.open = W.Button(f, "거래 로그", 70, 22, function() if BRL.UI then BRL.UI:Open("trades") end end)
    f.open:SetPoint("LEFT", f.fill, "RIGHT", 6, 0)
    local close = W.CloseButton(f, function() f:Hide() f.dismissed = BRL.TradeTracker.current and BRL.TradeTracker.current.id end, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    self.frame = f
    return f
end

function TA:Anchor(f)
    f:ClearAllPoints()
    local tf = API.GetTradeFrame()
    if tf and tf:IsShown() then
        f:SetPoint("TOPLEFT", tf, "TOPRIGHT", 6, 0)
    else
        f:SetPoint("LEFT", UIParent, "CENTER", 220, 80)
    end
end

function TA:Update(sess)
    sess = sess or BRL.TradeTracker.current
    if not sess or sess.finalized or not self:Enabled() or not BRL.Perm:IsOperator() then
        if self.frame then self.frame:Hide() end
        return
    end
    local f = self:Create()
    if f.dismissed == sess.id then return end
    f.dismissed = nil
    local info = self:Info(sess)
    self.lastInfo = info
    local lines = self:Lines(info)
    f.body:SetText(table.concat(lines, "\n"))
    -- 긴 줄은 접혀서 여러 줄이 되므로 실제 글자 높이로 창 높이를 맞춤 (버튼과 겹침 방지)
    local bh = math.max(#lines * 14, f.body:GetStringHeight() or 0)
    f:SetHeight(26 + bh + 6 + 30)
    if info.payout > 0 then f.fill:Show() else f.fill:Hide() end
    self:Anchor(f)
    f:Show()
end
