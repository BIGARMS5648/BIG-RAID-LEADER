-- BIG RAID LEADER - 메인 창 / 메뉴 / 화면 등록
local _, BRL = ...
local T, W, API = BRL.Theme, BRL.Widgets, BRL.API

local UI = BRL:NewModule("UI")
BRL.UI = UI

UI.pages = {}
UI.pageOrder = {}
UI.current = nil

-- def: { title, order, build(page), refresh(page), tick(page, auc, remaining), access(role) -> "full"|"read"|"limited" }
function UI:RegisterPage(key, def)
    def.key = key
    self.pages[key] = def
    table.insert(self.pageOrder, def)
    table.sort(self.pageOrder, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

function UI:OnEnable()
    W.HookLinkInsert()
    local E = BRL.Events
    E:On("ANY", self, function(_, msg)
        if msg == E.MSG.AUCTION_TICK then return end
        self:RequestRefresh()
    end)
    E:On(E.MSG.AUCTION_TICK, self, function(_, auc, rem)
        if self.frame and self.frame:IsShown() and self.current then
            local p = self.pages[self.current]
            if p.tick and p.frame then BRL.SafeCall("tick", p.tick, p.frame, auc, rem) end
        end
    end)
    E:On(E.MSG.COMBAT_CHANGED, self, function() self:UpdateHeader() end)
    if BRL.Minimap then BRL.Minimap:Create() end
    self:RegisterSettingsCategory()
end

function UI:RequestRefresh()
    if not self.frame or not self.frame:IsShown() then return end
    if self.refreshPending then return end
    self.refreshPending = true
    API.After(0.1, function()
        self.refreshPending = false
        self:Refresh()
    end)
end

---------------------------------------------------------------------------
-- 창 생성
---------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end
    local cfg = BRL.char.ui
    local f = W.Panel(UIParent, T.colors.bg, T.colors.border)
    _G.BigRaidLeaderMainFrame = f
    f:SetSize(cfg.width or 1080, cfg.height or 700)
    if cfg.point then
        f:SetPoint(cfg.point[1], UIParent, cfg.point[3] or cfg.point[1], cfg.point[4] or 0, cfg.point[5] or 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetScale(cfg.scale or 1)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(900, 600, 1800, 1200) elseif f.SetMinResize then f:SetMinResize(900, 600) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    table.insert(UISpecialFrames, "BigRaidLeaderMainFrame")
    self.frame = f

    -- 제목 표시줄
    local title = W.Panel(f, T.colors.header, T.colors.border)
    title:SetPoint("TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", -1, -1)
    title:SetHeight(36)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        cfg.point = { p, nil, rp, x, y }
    end)
    local logo = W.Label(title, "BIG RAID LEADER", 17, "goldBright")
    logo:SetPoint("LEFT", 14, 0)
    local sub = W.Label(title, "빅 레이드 리더  v" .. BRL.VERSION, 11, "muted")
    sub:SetPoint("LEFT", logo, "RIGHT", 10, -1)
    local close = W.Button(title, "X", 26, 22, function() f:Hide() end, { kind = "subtle" })
    close:SetPoint("RIGHT", -6, 0)
    self.roleBadge = W.Label(title, "", 12, "gold", "RIGHT")
    self.roleBadge:SetPoint("RIGHT", close, "LEFT", -12, 0)
    self.combatBadge = W.Label(title, "", 12, "red", "RIGHT")
    self.combatBadge:SetPoint("RIGHT", self.roleBadge, "LEFT", -12, 0)
    self.sessionDrop = W.Dropdown(title, 230, function() return self:SessionItems() end, function(v)
        if v == "__new" then
            self:PromptNewSession()
        elseif v then
            BRL.Session:SetActive(v)
        end
    end, { placeholder = "공격대 세션 없음", popupWidth = 260 })
    self.sessionDrop:SetPoint("LEFT", sub, "RIGHT", 24, 1)
    W.SetTooltip(self.sessionDrop, "공격대 세션", { "경매·거래 연결·정산은 공격대 세션 단위로 관리됩니다.", "세션을 선택하거나 새로 만드세요." })

    -- 메뉴
    local nav = W.Panel(f, T.colors.panel, T.colors.borderDim)
    nav:SetPoint("TOPLEFT", 1, -38)
    nav:SetPoint("BOTTOMLEFT", 1, 22)
    nav:SetWidth(168)
    self.nav = nav
    self.navButtons = {}
    for i, def in ipairs(self.pageOrder) do
        local b = W.Button(nav, def.title, 156, 30, function() self:Open(def.key) end, { kind = "subtle", size = 13 })
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 34)
        b.label:SetJustifyH("LEFT")
        b.label:SetPoint("LEFT", 12, 0)
        b.badge = W.Label(b, "", 11, "red", "RIGHT")
        b.badge:SetPoint("RIGHT", -8, 0)
        b.key = def.key
        self.navButtons[def.key] = b
    end

    -- 내용 영역
    local content = W.Panel(f, T.colors.bg, T.colors.bg)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 2, 0)
    content:SetPoint("BOTTOMRIGHT", -1, 22)
    self.content = content

    -- 상태 표시줄
    local status = W.Panel(f, T.colors.panel, T.colors.borderDim)
    status:SetPoint("BOTTOMLEFT", 1, 1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetHeight(20)
    self.statusLeft = W.Label(status, "", 11, "muted")
    self.statusLeft:SetPoint("LEFT", 8, 0)
    self.statusRight = W.Label(status, "/brl 도움말 · 단축키 설정: 키 설정 > 애드온", 11, "muted", "RIGHT")
    self.statusRight:SetPoint("RIGHT", -24, 0)

    -- 크기 조절
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetTexture(T.WHITE)
    gt:SetAllPoints()
    gt:SetVertexColor(T.colors.border[1], T.colors.border[2], T.colors.border[3], 0.6)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        cfg.width, cfg.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
        self:Refresh()
    end)

    f:SetScript("OnShow", function()
        API.PlaySound("IG_MAINMENU_OPEN")
        self:Refresh()
    end)
    f:SetScript("OnHide", function()
        API.PlaySound("IG_MAINMENU_CLOSE")
        W.ClosePopup()
    end)
    return f
end

function UI:SessionItems()
    local items = {}
    for _, s in ipairs(BRL.Session:List()) do
        local mark = s.status == "closed" and " (종료)" or ""
        items[#items + 1] = { value = s.id, text = s.name .. mark }
        if #items >= 25 then break end
    end
    items[#items + 1] = { value = "__new", text = "|cffffd100+ 새 공격대 세션|r" }
    return items
end

function UI:PromptNewSession()
    local raidItems = {}
    for _, r in ipairs(BRL.Data.RaidList()) do raidItems[#raidItems + 1] = { value = r.key, text = r.name .. " (" .. r.size .. "인)" } end
    local inst = API.GetInstanceInfo()
    BRL.Dialogs.Input("새 공격대 세션", {
        { key = "raidKey", label = "공격대", type = "dropdown", items = raidItems, default = BRL.Data.FindRaidByName(inst) or "HYJAL_SUMMIT" },
        { key = "name", label = "세션 이름", type = "text", placeholder = "비우면 자동 (공격대 + 날짜)" },
    }, function(v)
        local s = BRL.Session:Create({ raidKey = v.raidKey, name = v.name })
        if not s then return false, "권한이 없습니다 (공대장 또는 파티 없음 상태에서만 생성)" end
        return true
    end)
end

---------------------------------------------------------------------------
-- 화면 전환 / 갱신
---------------------------------------------------------------------------
function UI:Open(key)
    self:Create()
    if not self.pages[key] then key = "dashboard" end
    self.current = key
    BRL.char.ui.lastPage = key
    for k, def in pairs(self.pages) do
        if def.frame then def.frame:Hide() end
        local b = self.navButtons[k]
        if b then
            local active = k == key
            b.baseColor = active and T.colors.primary or T.colors.panel2
            T.ApplyBackdrop(b, b.baseColor, active and T.colors.border or T.colors.borderDim)
            T.SetTextColor(b.label, active and "goldBright" or "text")
        end
    end
    local def = self.pages[key]
    if not def.frame then
        local page = CreateFrame("Frame", nil, self.content)
        page:SetPoint("TOPLEFT", 8, -8)
        page:SetPoint("BOTTOMRIGHT", -8, 8)
        def.frame = page
        page.def = def
        BRL.SafeCall("화면 생성:" .. key, def.build, page)
    end
    def.frame:Show()
    W.ClosePopup()
    if not self.frame:IsShown() then self.frame:Show() else self:Refresh() end
end

function UI:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open(self.current or BRL.char.ui.lastPage or "dashboard")
    end
end

function UI:UpdateHeader()
    if not self.frame then return end
    local role = BRL.Perm:GetRole()
    if BRL.Perm:IsOperator(role) then
        self.roleBadge:SetText(T.Color(role == "leader" and "gold" or "muted", role == "leader" and "공격대장" or "그룹 밖 (준비/정산)"))
    else
        self.roleBadge:SetText(T.Color("red", "공대장 아님 (" .. BRL.Perm:RoleLabel(role) .. ") · 잠김"))
    end
    self.combatBadge:SetText(API.InCombat() and "전투 중 (일부 기능 제한)" or "")
    local s = BRL.Session:GetActive()
    self.sessionDrop:SetValue(s and s.id or nil, true)
    if not s then self.sessionDrop.label:SetText("공격대 세션 없음") end
    -- 상태 표시줄: 진행 중 거래 / 채팅 잠금
    local parts = {}
    local cur = BRL.TradeTracker:GetCurrent()
    if cur then
        local snap = cur.acceptSnap or cur.live or {}
        parts[#parts + 1] = T.Color("yellow", "거래 중: " .. (cur.partnerKey and API.ShortName(cur.partnerKey) or "?") ..
            " (받음 " .. BRL.Money.Format(snap.targetMoney or 0) .. " / 줌 " .. BRL.Money.Format(snap.playerMoney or 0) .. ")")
    end
    if API.InChatLockdown() then parts[#parts + 1] = T.Color("red", "채팅 제한 중 - 메시지 대기") end
    if BRL.readOnlyData then parts[#parts + 1] = T.Color("red", "데이터 읽기 전용") end
    local unverified = #BRL.TradeJournal:Query({ group = "unverified" })
    if unverified > 0 then parts[#parts + 1] = T.Color("yellow", "확인 불가 거래 " .. unverified .. "건") end
    self.statusLeft:SetText(#parts > 0 and table.concat(parts, "   ") or "준비됨")
    -- 메뉴 배지
    local unclassified = #BRL.TradeJournal:Query({ group = "unclassified" })
    if self.navButtons.trades then
        local n = unverified + unclassified
        self.navButtons.trades.badge:SetText(n > 0 and tostring(n) or "")
    end
    if self.navButtons.auction then
        local active = BRL.Auctions:GetActive()
        self.navButtons.auction.badge:SetText(active and T.Color("yellow", "진행") or "")
    end
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:UpdateHeader()
    W.RefreshPermissionButtons()
    local def = self.current and self.pages[self.current]
    if def and def.frame and def.refresh then
        BRL.SafeCall("화면 갱신:" .. def.key, def.refresh, def.frame)
    end
end

-- 페이지 공통: 상단 제목 + 안내
function UI:PageHeader(page, title, subtitle)
    local t = W.Label(page, title, 16, "goldBright")
    t:SetPoint("TOPLEFT", 4, -2)
    if subtitle then
        local s = W.Label(page, subtitle, 11, "muted")
        s:SetPoint("LEFT", t, "RIGHT", 12, -1)
        page.subtitle = s
    end
    page.titleLabel = t
    -- 권한 안내 배너
    local banner = W.Label(page, "", 11, "yellow", "RIGHT")
    banner:SetPoint("TOPRIGHT", -4, -4)
    page.permBanner = banner
    return t
end

function UI:SetPermBanner(page, action)
    if not page.permBanner then return end
    if action and not BRL.Perm:Can(action) then
        page.permBanner:SetText("공대장 권한 없음 · 편집 잠김")
    else
        page.permBanner:SetText("")
    end
end

-- 전술표/체크리스트 대상: 기본 + 현재 세션 공격대의 보스
function UI.PlanItems()
    local items = { { value = "default", text = "기본 (모든 전투)" } }
    local s = BRL.Session:GetActive()
    local raidKey = s and s.raidKey
    if raidKey then
        for _, b in ipairs(BRL.BossPlans:List(raidKey)) do items[#items + 1] = { value = b.key, text = "보스: " .. b.name } end
    end
    return items
end

-- [보스 준비 적용] 후 전술표/징표/메모/필수 버프 화면이 활성 보스를 따라가게 함
function UI.FollowActivePlan(page, apply)
    local ops = BRL.db.raidOps
    local v = ops.activePlanVersion or 0
    if page.seenPlanVersion ~= v then
        page.seenPlanVersion = v
        if v > 0 then apply(ops.activePlanKey or "default") end
    end
end

-- 페이지 하단 버튼 줄
function UI.BottomBar(page, x, y)
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("BOTTOMLEFT", x or 4, y or 4)
    bar:SetSize(890, 26)
    return bar, W.Flow(bar, 0, 1, 6)
end

-- 활성 세션 (없으면 nil)
function UI:Session()
    return BRL.Session:GetActive()
end

---------------------------------------------------------------------------
-- 게임 설정 패널에 등록 (설정 > 애드온)
---------------------------------------------------------------------------
function UI:RegisterSettingsCategory()
    if not (_G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel.name = BRL.TITLE
    local t = W.Label(panel, BRL.TITLE .. " (빅 레이드 리더)", 16, "goldBright")
    t:SetPoint("TOPLEFT", 16, -16)
    local d = W.Paragraph(panel, "모든 설정은 BIG RAID LEADER 창의 [설정] 메뉴에서 관리합니다. 명령어: /brl", 500, 12)
    d:SetPoint("TOPLEFT", 16, -46)
    local b = W.Button(panel, "BIG RAID LEADER 열기", 180, 26, function()
        if _G.SettingsPanel and _G.SettingsPanel.Hide then pcall(_G.SettingsPanel.Hide, _G.SettingsPanel) end
        self:Open("settings")
    end, { kind = "primary" })
    b:SetPoint("TOPLEFT", 16, -80)
    local ok, category = pcall(_G.Settings.RegisterCanvasLayoutCategory, panel, BRL.TITLE)
    if ok and category then pcall(_G.Settings.RegisterAddOnCategory, category) end
end

