-- BIG RAID LEADER - 공대장 HUD (작은 떠 있는 창)
-- 메인 창을 닫아 둔 채로 진행 현황(경매/카운트, 거래 상대, 풀링 판정, 도핑, 미수·미지급)을 보고
-- 경매 카운트와 전투 지휘 명령(준비 확인, 풀링, 공격 중지, 후퇴, 재정비, 휴식, 공략 안내)을 바로 실행한다.
local _, BRL = ...
local T, W, Money, API, U = BRL.Theme, BRL.Widgets, BRL.Money, BRL.API, BRL.Util
local UI = BRL.UI

local HUD = BRL:NewModule("HUD")

local function cfg() return BRL.acct.hud end

---------------------------------------------------------------------------
-- 진행 현황 줄 (대시보드 "진행 현황"과 HUD 공용). compact = HUD 용 짧은 형식
---------------------------------------------------------------------------
function UI.LiveSummary(session, compact)
    local info = {}
    local auc = BRL.Auctions:GetActive()
    if auc then
        local remain = math.max(0, math.ceil(BRL.Auctions:Remaining(auc)))
        local t = BRL.Auctions:IsCounting(auc) and T.Color("red", "카운트 " .. remain) or T.Color("yellow", remain .. "초")
        local high = auc.highAmount and (T.Color("green", Money.Format(auc.highAmount)) .. " " .. API.ShortName(auc.highBidder)) or T.Color("muted", "입찰 없음")
        if compact then
            info[#info + 1] = U.StripColors(auc.itemName or "?") .. " " .. t
            info[#info + 1] = "  최고 " .. high
        else
            info[#info + 1] = "경매: " .. U.StripColors(auc.itemName or "?") .. " 최고 " .. high .. " " .. t
        end
    elseif BRL.Auctions.autoNext then
        info[#info + 1] = T.Color("blue", "다음 경매 " .. (BRL.Auctions:AutoNextRemaining() or 0) .. "초 후 시작")
    else
        local queued = session and #BRL.Auctions:Queue(session.id) or 0
        info[#info + 1] = (compact and "경매 없음" or "경매: 진행 없음") .. (queued > 0 and (" · 대기 " .. queued .. "건") or "")
    end
    local tr = BRL.TradeTracker.current
    if tr and BRL.TradeAssist then
        local ti = BRL.TradeAssist:Info(tr)
        local parts = { "거래: " .. ti.partnerName }
        if ti.outstanding > 0 then parts[#parts + 1] = T.Color("red", "미납 " .. Money.Format(ti.outstanding, { goldOnly = true })) end
        if ti.payout > 0 then parts[#parts + 1] = T.Color("blue", "분배 " .. Money.Format(ti.payout, { goldOnly = true })) end
        info[#info + 1] = table.concat(parts, " · ")
    end
    if not compact and BRL.Recruitment:IsActive() then
        local rp = BRL.Recruitment:Progress()
        info[#info + 1] = string.format("모집: 진행 중 %d/%d (부족 %d)", rp.have, rp.size, math.max(0, rp.size - rp.have))
    end
    local brk = BRL.Command:BreakRemaining()
    if brk then info[#info + 1] = T.Color("blue", "휴식 중: " .. U.FormatDuration(brk) .. " 남음") end
    local pc = BRL.CombatPrep:PullCheck()
    info[#info + 1] = (compact and "풀링: " or "풀링 판정: ") .. T.Color(pc.color, pc.label) .. (pc.reasons[1] and T.Color("muted", " " .. pc.reasons[1]) or "")
    local prep = BRL.CombatPrep.last
    if prep then
        if compact then
            info[#info + 1] = string.format("도핑 %d/%d · 음식 -%d · %s -%d", prep.okCount, prep.checked, #prep.noFood, BRL.CombatPrep:MainLabel(), #prep.noMain)
        else
            info[#info + 1] = string.format("전투 준비(%s): 음식 누락 %d · %s 누락 %d", U.FormatClock(prep.at), #prep.noFood, BRL.CombatPrep:MainLabel(), #prep.noMain)
        end
    end
    if session then
        local sum = BRL.Ledger:Summary(session.id)
        if compact then
            if sum.outstanding > 0 or sum.unpaid > 0 then
                info[#info + 1] = "미수 " .. T.Color("red", Money.Format(sum.outstanding, { goldOnly = true })) .. " · 미지급 " .. T.Color("yellow", Money.Format(sum.unpaid, { goldOnly = true }))
            end
        else
            local st = BRL.Settlement:ForSession(session.id)
            if st and st.status ~= "draft" then
                local pay = BRL.Settlement:PaymentState(st.id)
                local done = 0
                for _, row in ipairs(pay.rows) do if row.remaining == 0 then done = done + 1 end end
                info[#info + 1] = string.format("분배 지급: %d/%d명 완료 · 남은 %s", done, #pay.rows, Money.Format(pay.unpaid))
            end
            if sum.outstanding > 0 then
                info[#info + 1] = string.format("미수금: %s (%d명)", Money.Format(sum.outstanding), #BRL.Payments:Debtors(session.id))
            end
        end
    end
    return info
end

function HUD:OnEnable()
    local refresh = function() if self.frame and self.frame:IsShown() then self:Update() end end
    for _, msg in ipairs({ "AUCTION_CHANGED", "TRADE_STATE", "READY_CHANGED", "SETTLEMENT_CHANGED", "LEDGER_CHANGED", "SESSION_CHANGED", "ROLE_CHANGED", "DATA_CHANGED" }) do
        BRL.Events:On(BRL.Events.MSG[msg], self, refresh)
    end
    if cfg().show then API.After(2, function() self:Show() end) end
end

function HUD:Lines()
    return UI.LiveSummary(BRL.Session:GetActive(), true)
end

-- HUD 지휘 명령 배치 (UIActions.COMMANDS 의 key)
HUD.COMMAND_ROWS = {
    { "ready", "pull", "cancelpull", "pullcheck" },
    { "stop", "retreat", "regroup", "briefing" },
    { "prep", "break" },
}

local BW, BH, GAP = 64, 20, 2

function HUD:Create()
    if self.frame then return self.frame end
    local f = W.Panel(UIParent, T.colors.bg, T.colors.border)
    _G.BigRaidLeaderHUD = f
    f:SetSize(BW * 4 + GAP * 3 + 12, 120)
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
    f.cmdToggle = W.Button(f, "지휘 ▾", 52, 16, function()
        cfg().commands = cfg().commands == false
        self:Layout()
    end, { kind = "subtle", size = 10, tooltip = { "지휘 명령 버튼 펼치기/접기" } })
    f.cmdToggle:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.body = W.Paragraph(f, "", BW * 4 + GAP * 3, 11)
    f.body:SetPoint("TOPLEFT", 6, -22)

    -- 경매 줄: 카운트 / 카운트 취소 / 메인 창
    f.auctionRow = CreateFrame("Frame", nil, f)
    f.auctionRow:SetSize(BW * 4 + GAP * 3, BH)
    local x = 0
    local function addAuction(text, fn, opts)
        local b = W.Button(f.auctionRow, text, BW, BH, fn, opts)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + BW + GAP
        return b
    end
    addAuction("카운트", function()
        local ok, err = BRL.Auctions:StartCount()
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "primary", perm = "finance.edit", size = 11 })
    addAuction("카운트 취소", function()
        local ok, err = BRL.Auctions:CancelCount(nil, "manual")
        if not ok then BRL:Print(tostring(err)) end
    end, { kind = "danger", perm = "finance.edit", size = 11 })
    addAuction("다음 경매", function()
        local ok, err = BRL.Auctions:StartNext()
        if not ok then BRL:Print(tostring(err)) end
    end, { perm = "finance.edit", size = 11 })
    addAuction("메인 창", function() if UI then UI:Toggle() end end, { size = 11 })

    -- 지휘 명령 줄 (전투 지휘 화면과 같은 목록)
    f.cmdRows = {}
    f.cmdButtons = {}
    local byKey = {}
    for _, c in ipairs(BRL.UIActions.COMMANDS) do byKey[c.key] = c end
    for r, keys in ipairs(self.COMMAND_ROWS) do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(BW * 4 + GAP * 3, BH)
        for i, key in ipairs(keys) do
            local c = byKey[key]
            local label = type(c.hud) == "function" and c.hud() or c.hud
            local b = W.Button(row, label, BW, BH, function() c.run({ toggle = true }) self:Update() end,
                { kind = c.primary and "primary" or nil, perm = c.perm ~= false and "raid.command" or nil, size = 11 })
            b:SetPoint("TOPLEFT", (i - 1) * (BW + GAP), 0)
            b.cmd = c
            f.cmdButtons[#f.cmdButtons + 1] = b
        end
        f.cmdRows[r] = row
    end
    self.frame = f
    return f
end

-- 줄 수에 맞춰 버튼 위치/창 높이 조정
function HUD:Layout()
    local f = self.frame
    if not f then return end
    local lines = f.lineCount or 4
    local y = 22 + lines * 14 + 6
    f.auctionRow:ClearAllPoints()
    f.auctionRow:SetPoint("TOPLEFT", 6, -y)
    y = y + BH + GAP
    local showCmd = cfg().commands ~= false
    f.cmdToggle:SetText(showCmd and "지휘 ▾" or "지휘 ▸")
    for _, row in ipairs(f.cmdRows) do
        if showCmd then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -y)
            row:Show()
            y = y + BH + GAP
        else
            row:Hide()
        end
    end
    f:SetHeight(y + 6)
end

function HUD:Update()
    local f = self.frame
    if not f then return end
    local lines = self:Lines()
    f.body:SetText(table.concat(lines, "\n"))
    f.lineCount = #lines
    for _, b in ipairs(f.cmdButtons) do
        if type(b.cmd.hud) == "function" then b:SetText(b.cmd.hud()) end
    end
    self:Layout()
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
