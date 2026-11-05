-- BIG RAID LEADER - 미니맵 버튼
local _, BRL = ...
local W = BRL.Widgets

local MM = {}
BRL.Minimap = MM

local function updatePosition(btn)
    local angle = math.rad(BRL.acct.minimap.angle or 215)
    local radius = (Minimap:GetWidth() / 2) + 8
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function MM:Create()
    if self.button or not _G.Minimap then return end
    -- 기본 미니맵 버튼 모양 (둥근 추적 테두리 + 아이콘)
    local b = CreateFrame("Button", "BigRaidLeaderMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            BRL.UI:Open("auction")
        else
            BRL.UI:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local a = math.deg(math.atan2(cy - my, cx - mx))
            BRL.acct.minimap.angle = a
            updatePosition(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    W.SetTooltip(b, "BIG RAID LEADER", function()
        local lines = { "좌클릭: 창 열기/닫기", "우클릭: 전리품 경매", "드래그: 위치 이동" }
        local s = BRL.Session:GetActive()
        if s then
            local sum = BRL.Ledger:Summary(s.id)
            lines[#lines + 1] = " "
            lines[#lines + 1] = "세션: " .. s.name
            lines[#lines + 1] = "경매 " .. BRL.Money.Format(sum.totalAwarded) .. " / 수금 " .. BRL.Money.Format(sum.collected)
            lines[#lines + 1] = "분배 미지급 " .. BRL.Money.Format(sum.unpaid)
        end
        return lines
    end)
    self.button = b
    updatePosition(b)
    self:UpdateVisibility()
end

function MM:UpdateVisibility()
    if not self.button then return end
    if BRL.acct.minimap.hide then self.button:Hide() else self.button:Show() end
end
