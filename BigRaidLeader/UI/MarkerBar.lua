-- BIG RAID LEADER - 징표 바 (보안 버튼)
-- 12.x(포에버) 에서 SetRaidTarget 은 보호 함수이므로 SecureActionButtonTemplate 의
-- "raidtarget"/"worldmarker" 동작으로만 징표를 지정한다. (애드온 코드가 직접 호출하지 않음)
-- 보안 버튼이 포함된 창은 메인 창과 분리된 독립 창이며, 전투 중에는 생성/표시 전환을 하지 않는다.
local _, BRL = ...
local T, W, API = BRL.Theme, BRL.Widgets, BRL.API

local MB = {}
BRL.MarkerBar = MB

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

function MB:Create()
    if self.frame then return self.frame end
    if API.InCombat() then
        BRL:Print("징표 바는 전투 종료 후 만들 수 있습니다.")
        return nil
    end
    local f = CreateFrame("Frame", "BigRaidLeaderMarkerBar", UIParent, "BackdropTemplate")
    T.ApplyBackdrop(f, nil, nil, "panel")
    T.TopAccent(f)
    f:SetSize(8 * 30 + 3 * 34 + 24, 68)
    f:SetPoint("TOP", 0, -160)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    local title = W.Label(f, "징표 (대상에게 지정) · 아래: 월드 징표", 10, "muted")
    title:SetPoint("TOPLEFT", 8, -6)
    local x = 8
    for _, i in ipairs(BRL.Command.MARKER_ORDER) do
        local b = CreateFrame("Button", "BigRaidLeaderMarker" .. i, f, "SecureActionButtonTemplate")
        b:SetSize(26, 26)
        b:SetPoint("TOPLEFT", x, -19)
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(ICON .. i)
        tex:SetAllPoints()
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "raidtarget")
        b:SetAttribute("action", "toggle")
        b:SetAttribute("marker", i)
        b:SetAttribute("unit", "target")
        W.SetTooltip(b, BRL.Command:MarkerName(i), { "클릭: 현재 대상에게 징표 지정/해제" })
        x = x + 30
    end
    local clear = CreateFrame("Button", "BigRaidLeaderMarkerClear", f, "SecureActionButtonTemplate,BackdropTemplate")
    clear:SetSize(30, 26)
    clear:SetPoint("TOPLEFT", x + 4, -19)
    T.ApplyBackdrop(clear, nil, nil, "small")
    local cl = W.Label(clear, "해제", 10, "text", "CENTER")
    cl:SetPoint("CENTER")
    clear:RegisterForClicks("AnyUp", "AnyDown")
    clear:SetAttribute("type", "raidtarget")
    clear:SetAttribute("action", "clear")
    clear:SetAttribute("unit", "target")
    W.SetTooltip(clear, "대상 징표 해제", nil)
    -- 월드 징표 (지면 표시)
    local wx = 8
    for i = 1, 8 do
        local wb = CreateFrame("Button", "BigRaidLeaderWorldMarker" .. i, f, "SecureActionButtonTemplate,BackdropTemplate")
        wb:SetSize(26, 16)
        wb:SetPoint("TOPLEFT", wx, -47)
        T.ApplyBackdrop(wb, nil, nil, "small")
        local wl = W.Label(wb, tostring(i), 10, "gold", "CENTER")
        wl:SetPoint("CENTER")
        wb:RegisterForClicks("AnyUp", "AnyDown")
        wb:SetAttribute("type", "worldmarker")
        wb:SetAttribute("action", "toggle")
        wb:SetAttribute("marker", i)
        W.SetTooltip(wb, "월드 징표 " .. i, { "클릭 후 지면을 클릭해 설치 (설치된 경우 해제)" })
        wx = wx + 30
    end
    local wclear = CreateFrame("Button", "BigRaidLeaderWorldMarkerClear", f, "SecureActionButtonTemplate,BackdropTemplate")
    wclear:SetSize(64, 16)
    wclear:SetPoint("TOPLEFT", wx + 4, -47)
    T.ApplyBackdrop(wclear, nil, nil, "small")
    local wcl = W.Label(wclear, "월드 전체 해제", 9, "text", "CENTER")
    wcl:SetPoint("CENTER")
    wclear:RegisterForClicks("AnyUp", "AnyDown")
    wclear:SetAttribute("type", "worldmarker")
    wclear:SetAttribute("action", "clear") -- marker 미지정 = 전체 해제
    local close = W.CloseButton(f, function() MB:Hide() end, 18)
    close:SetPoint("TOPRIGHT", -3, -3)
    self.frame = f
    return f
end

function MB:Toggle()
    if API.InCombat() then
        BRL:Print("전투 중에는 징표 바를 열거나 닫을 수 없습니다.")
        return
    end
    local f = self:Create()
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

function MB:Hide()
    if API.InCombat() then
        BRL:Print("전투 중에는 징표 바를 닫을 수 없습니다.")
        return
    end
    if self.frame then self.frame:Hide() end
end

function MB:IsShown()
    return self.frame and self.frame:IsShown()
end
