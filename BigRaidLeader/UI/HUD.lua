-- BIG RAID LEADER - 공대장 HUD (작은 떠 있는 창)
-- 메인 창을 닫아 둔 채로 경매/카운트, 거래 상대 정보, 풀링 판정, 도핑, 미지급을 한눈에 보고
-- 카운트 · 카운트 취소 · 전투 준비 · 메인 창 버튼을 바로 누를 수 있다.
local _, BRL = ...
local T, W, Money, API, U = BRL.Theme, BRL.Widgets, BRL.Money, BRL.API, BRL.Util

local HUD = BRL:NewModule("HUD")

local function cfg() return BRL.acct.hud end

function HUD:OnEnable()
    local refresh = function() if self.frame and self.frame:IsShown() then self:Update() end end
    for _, msg in ipairs({ "AUCTION_CHANGED", "TRADE_STATE", "READY_CHANGED", "SETTLEMENT_CHANGED", "LEDGER_CHANGED", "SESSION_CHANGED", "ROLE_CHANGED" }) do
        BRL.Events:On(BRL.Events.MSG[msg], self, refresh)
    end
    BRL.Events:On(BRL.Events.MSG.DATA_CHANGED, self, refresh)
    if cfg().show then API.After(2, function() self:Show() end) end
end

-- 표시할 줄 (UI 와 분리: 테스트 가능)
function HUD:Lines()
    local lines = {}
    local session = BRL.Session:GetActive()
    local auc = BRL.Auctions:GetActive()
    if auc then
        local rem = math.max(0, math.ceil(BRL.Auctions:Remaining(auc)))
        lines[#lines + 1] = string.format("%s %s", U.StripColors(auc.itemName or "?"),
            BRL.Auctions:IsCounting(auc) and T.Color("red", "카운트 " .. rem) or T.Color("yellow", rem .. "초"))
        lines[#lines + 1] = "  최고 " .. (auc.highAmount and (T.Color("green", Money.Format(auc.highAmount)) .. " " .. API.ShortName(auc.highBidder)) or T.Color("muted", "입찰 없음"))
    elseif BRL.Auctions.autoNext then
        lines[#lines + 1] = T.Color("blue", "다음 경매 " .. (BRL.Auctions:AutoNextRemaining() or 0) .. "초 후")
    else
        local q = session and #BRL.Auctions:Queue(session.id) or 0
        lines[#lines + 1] = "경매 없음" .. (q > 0 and (" · 대기 " .. q) or "")
    end
    local tr = BRL.TradeTracker.current
    if tr then
        local info = BRL.TradeAssist:Info(tr)
        local parts = { "거래: " .. info.partnerName }
        if info.outstanding > 0 then parts[#parts + 1] = T.Color("red", "미납 " .. Money.Format(info.outstanding, { goldOnly = true })) end
        if info.payout > 0 then parts[#parts + 1] = T.Color("blue", "분배 " .. Money.Format(info.payout, { goldOnly = true })) end
        lines[#lines + 1] = table.concat(parts, " · ")
    end
    local pc = BRL.CombatPrep:PullCheck()
    lines[#lines + 1] = "풀링: " .. T.Color(pc.color, pc.label) .. (pc.reasons[1] and T.Color("muted", " " .. pc.reasons[1]) or "")
    local prep = BRL.CombatPrep.last
    if prep then
        lines[#lines + 1] = string.format("도핑 %d/%d · 음식 -%d · %s -%d", prep.okCount, prep.checked, #prep.noFood, BRL.CombatPrep:MainLabel(), #prep.noMain)
    end
    if session then
        local sum = BRL.Ledger:Summary(session.id)
        if sum.outstanding > 0 or sum.unpaid > 0 then
            lines[#lines + 1] = "미수 " .. T.Color("red", Money.Format(sum.outstanding, { goldOnly = true })) .. " · 미지급 " .. T.Color("yellow", Money.Format(sum.unpaid, { goldOnly = true }))
        end
    end
    return lines
end

function HUD:Create()
    if self.frame then return self.frame end
    local f = W.Panel(UIParent, T.colors.bg, T.colors.border)
    _G.BigRaidLeaderHUD = f
    f:SetSize(250, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) if not cfg().locked then fr:StartMoving() end end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        local point, _, rel, x, y = fr:GetPoint()
        cfg().point = { point, rel, x, y }
    end)
    local p = cfg().point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -220) end
    f:Hide()
    f.title = W.Label(f, "BIG RAID LEADER", 11, "gold")
    f.title:SetPoint("TOPLEFT", 8, -6)
    local close = W.Button(f, "X", 18, 16, function() self:Hide() end, { kind = "subtle" })
    close:SetPoint("TOPRIGHT", -4, -4)
    f.body = W.Paragraph(f, "", 236, 11)
    f.body:SetPoint("TOPLEFT", 8, -22)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", 6, 6)
    bar:SetSize(240, 22)
    local fl = W.Flow(bar, 0, 0, 3)
    fl:Add(W.Button(bar, "카운트", 50, 20, function()
        local ok, err = BRL.Auctions:StartCount()
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "primary", perm = "finance.edit", size = 11 }))
    fl:Add(W.Button(bar, "취소", 40, 20, function()
        local ok, err = BRL.Auctions:CancelCount(nil, "manual")
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "danger", perm = "finance.edit", size = 11 }))
    fl:Add(W.Button(bar, "전투 준비", 64, 20, function() BRL.CombatPrep:Run() end, { size = 11 }))
    fl:Add(W.Button(bar, "메인", 40, 20, function() if BRL.UI then BRL.UI:Toggle() end end, { size = 11 }))
    self.frame = f
    return f
end

function HUD:Update()
    local f = self.frame
    if not f then return end
    local lines = self:Lines()
    f.body:SetText(table.concat(lines, "\n"))
    f:SetHeight(22 + #lines * 14 + 34)
end

function HUD:Show()
    local f = self:Create()
    cfg().show = true
    f:Show()
    self:Update()
    if not self.ticker then
        self.ticker = API.NewTicker(0.5, function()
            if self.frame and self.frame:IsShown() then self:Update() end
        end)
    end
    W.RefreshPermissionButtons()
end

function HUD:Hide()
    cfg().show = false
    if self.frame then self.frame:Hide() end
    if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
    self.ticker = nil
end

function HUD:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function HUD:IsShown() return self.frame ~= nil and self.frame:IsShown() end
