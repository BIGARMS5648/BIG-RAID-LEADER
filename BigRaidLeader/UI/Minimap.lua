-- BIG RAID LEADER - 미니맵 버튼
local _, BRL = ...
local T, W = BRL.Theme, BRL.Widgets

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
    -- 미니맵 버튼: 원형 표범 아이콘(애드온 Media, 가장자리를 원형 투명 처리한 TGA) + 게임 기본 추적 테두리
    -- (마스크 텍스처 없이도 둥글게 보이도록 이미지 자체를 원형으로 만듦)
    local b = CreateFrame("Button", "BigRaidLeaderMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(T.TEX.minimapIcon)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture(T.TEX.minimapBorder)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b.border = border
    b:SetHighlightTexture(T.TEX.minimapHighlight, "ADD")
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 8, -6) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("TOPLEFT", 7, -5) end)
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
