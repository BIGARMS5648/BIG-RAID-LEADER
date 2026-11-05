-- BIG RAID LEADER - UI 위젯 (모던 다크 · 청록 강조)
-- 버튼/입력/체크/드롭다운/가상 스크롤 목록을 1px 선의 평평한 모양으로 직접 그린다.
-- Blizzard 템플릿에 의존하지 않아 클라이언트 버전과 무관하게 같은 모양이고, 보안 오염(taint)도 없다.
local _, BRL = ...
local T = BRL.Theme
local U = BRL.Util

local W = {}
BRL.Widgets = W

W.focusedEdit = nil
W.permButtons = {}

local function cf(kind, parent, template, name)
    return CreateFrame(kind, name, parent, template)
end

local C = T.colors

---------------------------------------------------------------------------
-- 툴팁
---------------------------------------------------------------------------
function W.SetTooltip(frame, title, lines)
    frame.tooltipTitle, frame.tooltipLines = title, lines
    frame:HookScript("OnEnter", function(self)
        local t = self.tooltipTitle
        if type(t) == "function" then t = t(self) end
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(t, 1, 1, 1)
        local l = self.tooltipLines
        if type(l) == "function" then l = l(self) end
        if type(l) == "string" then l = { l } end
        for _, line in ipairs(l or {}) do GameTooltip:AddLine(line, 0.78, 0.78, 0.82, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- 기본 요소
---------------------------------------------------------------------------
-- style: "box"(기본) / "dialog" / "panel" / "tooltip" / "small" / "flat"  (Theme.STYLES)
function W.Panel(parent, bg, border, style)
    local f = cf("Frame", parent, "BackdropTemplate")
    T.ApplyBackdrop(f, bg, border, style or "box")
    return f
end

function W.Label(parent, text, size, color, justify, bold)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    T.SetFont(fs, size or 12, nil, bold)
    fs:SetText(text or "")
    T.SetTextColor(fs, color or "text")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

function W.Paragraph(parent, text, width, size)
    local fs = W.Label(parent, text, size or 12)
    fs:SetWidth(width or 300)
    fs:SetJustifyV("TOP")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
    return fs
end

-- 구획 제목: 작은 회색 글자 + 아주 옅은 구분선. width 를 주면 선 길이를 제한 (두 칸 화면의 왼쪽 칸이 오른쪽 칸을 가로지르지 않게)
function W.Section(parent, text, width)
    local fs = W.Label(parent, text, 12, "muted", nil, true)
    local line = T.Solid(parent, "ARTWORK", { 1, 1, 1, 0.05 })
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    if width then line:SetWidth(width) else line:SetPoint("RIGHT", parent, "RIGHT", -12, 0) end
    fs.line = line
    return fs
end

---------------------------------------------------------------------------
-- 버튼
--  normal  : 짙은 회색 + 얇은 선            primary : 짙은 청록 + 청록 테두리 + 민트 글자
--  danger  : 짙은 빨강 + 붉은 글자           subtle  : 투명 + 선
--  dropdown: 입력칸 모양 + 아래 화살표       tab     : 글자 + 선택 시 청록 밑줄
--  nav     : 왼쪽 메뉴 (아이콘 + 글자, 선택 시 왼쪽 청록 막대)
---------------------------------------------------------------------------
local NONE = { 0, 0, 0, 0 }
local KIND = {
    normal = { bg = C.button, bgHover = C.buttonHover, border = C.buttonBorder, borderHover = { 0.48, 0.55, 0.56, 1 }, text = "text", textHover = "goldBright" },
    primary = { bg = C.primary, bgHover = C.primaryHover, border = { C.accent[1], C.accent[2], C.accent[3], 1 }, borderHover = { C.accentBright[1], C.accentBright[2], C.accentBright[3], 1 }, text = "accentText", textHover = "goldBright" },
    danger = { bg = C.danger, bgHover = { 0.26, 0.1, 0.1, 1 }, border = C.dangerBorder, borderHover = { 0.85, 0.3, 0.3, 1 }, text = "dangerText", textHover = "goldBright" },
    subtle = { bg = NONE, bgHover = { 1, 1, 1, 0.05 }, border = C.borderDim, borderHover = { 0.45, 0.52, 0.53, 1 }, text = "muted", textHover = "goldBright" },
    dropdown = { bg = C.input, bgHover = { 0.085, 0.105, 0.11, 1 }, border = C.buttonBorder, borderHover = { 0.48, 0.55, 0.56, 1 }, text = "text", textHover = "goldBright" },
    tab = { bg = NONE, bgHover = { 1, 1, 1, 0.03 }, border = NONE, borderHover = NONE, text = "muted", textHover = "text",
        selBg = NONE, selText = "goldBright" },
    nav = { bg = NONE, bgHover = { 1, 1, 1, 0.04 }, border = NONE, borderHover = NONE, text = "text", textHover = "goldBright",
        selBg = { 0.13, 0.17, 0.18, 1 }, selText = "goldBright" },
}
local DISABLED = { bg = { 0.085, 0.085, 0.095, 1 }, border = { 0.15, 0.15, 0.17, 1 } }
W.BUTTON_KINDS = KIND

local function paintButton(b)
    if not b.label then return end
    local k = KIND[b.kind] or KIND.normal
    local enabled = b:IsEnabled()
    local bg, bd, tc
    if not enabled then
        bg, bd, tc = (b.kind == "tab" or b.kind == "nav") and NONE or DISABLED.bg, (b.kind == "tab" or b.kind == "nav") and NONE or DISABLED.border, "disabled"
    elseif b.brlSelected and k.selBg then
        bg, bd, tc = k.selBg, k.border, k.selText
    elseif b.brlHover then
        bg, bd, tc = k.bgHover, k.borderHover, k.textHover
    else
        bg, bd, tc = k.bg, k.border, k.text
    end
    b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
    T.SetTextColor(b.label, tc)
    if b.accent then
        if b.brlSelected then b.accent:Show() else b.accent:Hide() end
    end
    if b.icon then
        local ic = (not enabled) and C.disabled or ((b.brlSelected or b.brlHover) and C.goldBright or C.text)
        b.icon:SetVertexColor(ic[1], ic[2], ic[3], 1)
    end
end
W.PaintButton = paintButton

-- 탭/메뉴 선택 상태
function W.SetSelected(b, v)
    b.brlSelected = v and true or false
    paintButton(b)
end

function W.Button(parent, text, width, height, onClick, opts)
    opts = opts or {}
    local kind = KIND[opts.kind or "normal"] and (opts.kind or "normal") or "normal"
    local b = cf("Button", parent, "BackdropTemplate")
    T.ApplyBackdrop(b, KIND[kind].bg, KIND[kind].border, "small")
    b.kind = kind
    b:SetSize(width or 90, height or 22)
    local fs = W.Label(b, text, opts.size or 12, KIND[kind].text, kind == "nav" and "LEFT" or "CENTER", kind == "primary" or kind == "tab")
    local textLeft = kind == "nav" and 14 or 4
    if opts.icon then
        local ic = b:CreateTexture(nil, "ARTWORK")
        T.SetIcon(ic, opts.icon)
        local isz = opts.iconSize or 20
        ic:SetSize(isz, isz)
        ic:SetPoint("LEFT", kind == "nav" and 18 or 6, 0)
        b.icon = ic
        textLeft = (kind == "nav" and 18 or 6) + isz + 12
    end
    fs:SetPoint("LEFT", textLeft, 0)
    fs:SetPoint("RIGHT", -4, 0)
    b.label = fs
    if kind == "nav" then
        local bar = T.Solid(b, "OVERLAY", { C.accent[1], C.accent[2], C.accent[3], 1 })
        bar:SetWidth(3)
        bar:SetPoint("TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", 0, 0)
        b.accent = bar
    elseif kind == "tab" then
        local bar = T.Solid(b, "OVERLAY", { C.accent[1], C.accent[2], C.accent[3], 1 })
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", 2, 0)
        bar:SetPoint("BOTTOMRIGHT", -2, 0)
        b.accent = bar
    end
    if b.accent then b.accent:Hide() end
    b:SetScript("OnEnter", function(self)
        self.brlHover = true
        paintButton(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.brlHover = false
        paintButton(self)
    end)
    b:SetScript("OnClick", function(self, button)
        if onClick then BRL.SafeCall("버튼:" .. tostring(text), onClick, self, button) end
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end
    local origEnable, origDisable = b.Enable, b.Disable
    function b:SetEnabledState(v)
        if v then origEnable(self) else origDisable(self) end
        paintButton(self)
    end
    if opts.tooltip then W.SetTooltip(b, text, opts.tooltip) end
    if opts.perm then
        b.perm = opts.perm
        table.insert(W.permButtons, b)
    end
    paintButton(b)
    return b
end

-- 권한에 따라 버튼 활성/비활성
function W.RefreshPermissionButtons()
    for _, b in ipairs(W.permButtons) do
        local allowed
        if type(b.perm) == "function" then allowed = b.perm()
        else allowed = BRL.Perm:Can(b.perm) end
        b:SetEnabledState(allowed)
    end
end

-- 창 닫기 버튼: 얇은 선 사각형 + X 아이콘, 마우스를 올리면 붉은 바탕
function W.CloseButton(parent, onClick, size)
    size = size or 24
    local b = cf("Button", parent, "BackdropTemplate")
    T.ApplyBackdrop(b, { 0, 0, 0, 0.25 }, C.buttonBorder, "small")
    b:SetSize(size, size)
    local x = b:CreateTexture(nil, "OVERLAY")
    T.SetIcon(x, "close", C.text)
    local isz = math.max(8, math.floor(size * 0.5))
    x:SetSize(isz, isz)
    x:SetPoint("CENTER")
    b.glyph = x
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.55, 0.13, 0.13, 0.95)
        self:SetBackdropBorderColor(0.85, 0.3, 0.3, 1)
        self.glyph:SetVertexColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.25)
        self:SetBackdropBorderColor(C.buttonBorder[1], C.buttonBorder[2], C.buttonBorder[3], 1)
        self.glyph:SetVertexColor(C.text[1], C.text[2], C.text[3], 1)
    end)
    b:SetScript("OnClick", function(self, button)
        if onClick then BRL.SafeCall("닫기", onClick, self, button) else parent:Hide() end
    end)
    b.isClose = true
    return b
end

-- 체크 상자 → 토글 스위치 (30x16, 켜지면 청록 바탕 + 오른쪽 흰 손잡이)
local TOGGLE_W, TOGGLE_H = 30, 16
function W.CheckBox(parent, label, onChange, tooltip)
    local b = cf("Button", parent, "BackdropTemplate")
    b:SetSize(TOGGLE_W, TOGGLE_H)
    T.ApplyBackdrop(b, C.toggleOff, C.borderStrong, "small")
    local knob = T.Solid(b, "OVERLAY", { 0.62, 0.66, 0.67, 1 })
    knob:SetSize(TOGGLE_H - 6, TOGGLE_H - 6)
    knob:SetPoint("LEFT", 3, 0)
    b.mark = knob
    b.checked = false
    local fs = W.Label(b, label or "", 12)
    fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label = fs
    local function hitRect()
        local w = (fs.GetStringWidth and fs:GetStringWidth()) or 0
        if b.SetHitRectInsets and w > 0 then b:SetHitRectInsets(0, -(w + 10), 0, 0) end
    end
    hitRect()
    function b:SetLabel(t) fs:SetText(t or "") hitRect() end
    local function paint(self)
        local hover = self.brlHover
        if self.checked then
            local a = hover and C.accentBright or C.accent
            self:SetBackdropColor(a[1] * 0.85, a[2] * 0.85, a[3] * 0.85, 1)
            self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
            self.mark:SetVertexColor(1, 1, 1, 1)
            self.mark:ClearAllPoints()
            self.mark:SetPoint("RIGHT", -3, 0)
        else
            self:SetBackdropColor(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
            local bd = hover and { 0.5, 0.57, 0.58 } or C.borderStrong
            self:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
            self.mark:SetVertexColor(0.62, 0.66, 0.67, 1)
            self.mark:ClearAllPoints()
            self.mark:SetPoint("LEFT", 3, 0)
        end
    end
    function b:SetChecked(v)
        self.checked = v and true or false
        paint(self)
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnEnter", function(self) self.brlHover = true paint(self) end)
    b:SetScript("OnLeave", function(self) self.brlHover = false paint(self) end)
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        BRL.API.PlaySound(self.checked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if onChange then BRL.SafeCall("체크박스", onChange, self.checked, self) end
    end)
    if tooltip then W.SetTooltip(b, label, tooltip) end
    paint(b)
    return b
end

-- 입력칸
local FOCUS = { C.accent[1], C.accent[2], C.accent[3], 1 }
function W.EditBox(parent, width, height, opts)
    opts = opts or {}
    local holder = cf("Frame", parent, "BackdropTemplate")
    holder:SetSize(width or 120, height or 22)
    T.ApplyBackdrop(holder, C.input, C.buttonBorder, "small")
    local eb = cf("EditBox", holder)
    eb:SetPoint("TOPLEFT", 7, -2)
    eb:SetPoint("BOTTOMRIGHT", -6, 2)
    T.SetFont(eb, opts.size or 12)
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetAutoFocus(false)
    if opts.numeric and eb.SetNumeric then eb:SetNumeric(true) end
    if opts.maxLetters then eb:SetMaxLetters(opts.maxLetters) end
    local ph = W.Label(holder, opts.placeholder or "", 11, "disabled")
    ph:SetPoint("LEFT", 7, 0)
    ph:SetPoint("RIGHT", -4, 0)
    holder.placeholder = ph
    local function updatePH()
        if (eb:GetText() or "") == "" and not eb.hasFocus then ph:Show() else ph:Hide() end
    end
    local function focusBorder(on)
        local c = on and FOCUS or C.buttonBorder
        holder:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then BRL.SafeCall("입력", opts.onEnter, self:GetText(), self) end
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        self.hasFocus = true
        W.focusedEdit = self
        focusBorder(true)
        updatePH()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self.hasFocus = false
        if W.focusedEdit == self then W.focusedEdit = nil end
        if self.HighlightText then self:HighlightText(0, 0) end
        focusBorder(false)
        updatePH()
        if opts.onCommit then BRL.SafeCall("입력", opts.onCommit, self:GetText(), self) end
    end)
    eb:SetScript("OnTextChanged", function(self, user)
        updatePH()
        if user and opts.onChange then BRL.SafeCall("입력", opts.onChange, self:GetText(), self) end
    end)
    -- 아이템 드래그 놓기 → 링크 입력
    if opts.acceptItems then
        eb:SetScript("OnReceiveDrag", function(self)
            local item = BRL.API.GetCursorItem()
            if item then
                self:SetText(type(item) == "string" and item or tostring(item))
                BRL.API.ClearCursor()
                if opts.onChange then opts.onChange(self:GetText(), self) end
            end
        end)
        eb:SetScript("OnMouseUp", function(self)
            local item = BRL.API.GetCursorItem()
            if item then self:GetScript("OnReceiveDrag")(self) end
        end)
    end
    holder.edit = eb
    function holder:SetText(t) eb:SetText(t or "") updatePH() end
    function holder:GetText() return eb:GetText() or "" end
    function holder:SetFocus() eb:SetFocus() end
    function holder:ClearFocus() eb:ClearFocus() end
    updatePH()
    return holder
end

-- 여러 줄 입력/복사용 텍스트 영역
function W.TextArea(parent, width, height, opts)
    opts = opts or {}
    local holder = W.Panel(parent, C.input, C.buttonBorder, "box")
    holder:SetSize(width or 300, height or 120)
    local sf = cf("ScrollFrame", holder)
    sf:SetPoint("TOPLEFT", 8, -7)
    sf:SetPoint("BOTTOMRIGHT", -8, 7)
    local eb = cf("EditBox", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    T.SetFont(eb, opts.size or 12)
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetWidth((width or 300) - 18)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        W.focusedEdit = self
        holder:SetBackdropBorderColor(FOCUS[1], FOCUS[2], FOCUS[3], 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if W.focusedEdit == self then W.focusedEdit = nil end
        holder:SetBackdropBorderColor(C.buttonBorder[1], C.buttonBorder[2], C.buttonBorder[3], 1)
        if opts.onCommit then BRL.SafeCall("메모", opts.onCommit, self:GetText(), self) end
    end)
    eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local offset = sf:GetVerticalScroll()
        local height2 = sf:GetHeight()
        y = -y
        if y < offset then sf:SetVerticalScroll(y)
        elseif y + h > offset + height2 then sf:SetVerticalScroll(y + h - height2) end
    end)
    if opts.readOnly then
        eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.fixedText or "") self:HighlightText() end end)
    end
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local v = U.Clamp(self:GetVerticalScroll() - delta * 30, 0, math.max(0, range))
        self:SetVerticalScroll(v)
    end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
    holder.edit = eb
    holder.scroll = sf
    function holder:SetText(t)
        eb.fixedText = t or ""
        eb:SetText(t or "")
    end
    function holder:GetText() return eb:GetText() or "" end
    function holder:SetAreaWidth(w)
        holder:SetWidth(w)
        eb:SetWidth(w - 18)
    end
    return holder
end

---------------------------------------------------------------------------
-- 드롭다운 (자체 구현 팝업 목록)
---------------------------------------------------------------------------
local popup
local POPUP_ROW, POPUP_PAD = 20, 4
local function getPopup()
    if popup then return popup end
    popup = W.Panel(UIParent, nil, nil, "tooltip")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup:EnableMouse(true)
    popup.buttons = {}
    popup.offset = 0
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #self.items - self.visible)
        self.offset = U.Clamp(self.offset - delta, 0, maxOff)
        self:Render()
    end)
    function popup:Render()
        for i, btn in ipairs(self.buttons) do
            local item = self.items[i + self.offset]
            if item and i <= self.visible then
                local cur = item.value == self.current
                btn.label:SetText(item.text)
                T.SetTextColor(btn.label, cur and "goldBright" or "text")
                if cur then btn.cur:Show() else btn.cur:Hide() end
                btn.item = item
                btn:Show()
            else
                btn:Hide()
            end
        end
    end
    popup:SetScript("OnHide", function(self) self.owner = nil end)
    return popup
end

function W.ClosePopup()
    if popup then popup:Hide() end
end

-- items: { {value=, text=}, ... } 또는 function() -> items
function W.Dropdown(parent, width, items, onSelect, opts)
    opts = opts or {}
    local h = opts.height or 22
    local b = W.Button(parent, opts.placeholder or "선택", width or 140, h, nil, { kind = "dropdown" })
    b.label:SetJustifyH("LEFT")
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    local arrow = b:CreateTexture(nil, "OVERLAY")
    T.SetIcon(arrow, "chevron", C.muted)
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -7, 0)
    b.arrow = arrow
    b.items = items
    b.value = nil
    local function resolve()
        local list = b.items
        if type(list) == "function" then list = list() end
        return list or {}
    end
    function b:SetValue(v, silent)
        self.value = v
        local text = opts.placeholder or "선택"
        for _, it in ipairs(resolve()) do
            if it.value == v then text = it.text break end
        end
        self.label:SetText(text)
        if not silent and onSelect then BRL.SafeCall("드롭다운", onSelect, v, self) end
    end
    function b:GetValue() return self.value end
    function b:SetItems(list) self.items = list self:SetValue(self.value, true) end
    b:SetScript("OnClick", function(self)
        local p = getPopup()
        if p:IsShown() and p.owner == self then p:Hide() return end
        local list = resolve()
        p.items = list
        p.current = self.value
        p.owner = self
        p.offset = 0
        p.visible = math.min(#list, opts.maxVisible or 14)
        for i = #p.buttons + 1, p.visible do
            local btn = cf("Button", p)
            btn:SetHeight(POPUP_ROW)
            btn:SetPoint("TOPLEFT", POPUP_PAD, -POPUP_PAD - (i - 1) * POPUP_ROW)
            btn:SetPoint("RIGHT", -POPUP_PAD, 0)
            local hl = T.Solid(btn, "HIGHLIGHT", C.rowHover)
            hl:SetAllPoints()
            btn.cur = T.Solid(btn, "ARTWORK", { C.accent[1], C.accent[2], C.accent[3], 1 })
            btn.cur:SetWidth(2)
            btn.cur:SetPoint("TOPLEFT", 0, -3)
            btn.cur:SetPoint("BOTTOMLEFT", 0, 3)
            btn.label = W.Label(btn, "", 12)
            btn.label:SetPoint("LEFT", 10, 0)
            btn.label:SetPoint("RIGHT", -4, 0)
            btn:SetScript("OnClick", function(bb)
                local owner = p.owner
                p:Hide()
                if owner and bb.item then owner:SetValue(bb.item.value) end
            end)
            p.buttons[i] = btn
        end
        p:SetWidth(math.max(self:GetWidth(), opts.popupWidth or 0))
        p:SetHeight(math.max(1, p.visible) * POPUP_ROW + POPUP_PAD * 2)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        p:Render()
        p:Show()
    end)
    return b
end

---------------------------------------------------------------------------
-- 가상 스크롤 목록 (40인/수백 건 거래에서도 행 프레임 재사용)
-- opts.columns = { { key=, title=, width=(px, 0=남은 공간), align=, render=function(row, data) -> text } }
---------------------------------------------------------------------------
function W.List(parent, opts)
    opts = opts or {}
    local rowH = opts.rowHeight or 20
    local f = W.Panel(parent, T.colors.panel, T.colors.borderDim, "box")
    local I = 1          -- 1px 선 안쪽
    local SB = 8         -- 얇은 스크롤 막대 칸
    f.columns = opts.columns or {}
    f.data = {}
    f.offset = 0
    f.rows = {}
    f.selected = nil
    local headerH = opts.noHeader and 0 or 20
    local header = cf("Frame", f)
    header:SetPoint("TOPLEFT", I, -I)
    header:SetPoint("TOPRIGHT", -I - SB, -I)
    header:SetHeight(headerH)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetTexture(T.WHITE)
    hbg:SetAllPoints()
    hbg:SetVertexColor(T.colors.header[1], T.colors.header[2], T.colors.header[3], T.colors.header[4] or 1)
    local hline = header:CreateTexture(nil, "BORDER")
    hline:SetTexture(T.WHITE)
    hline:SetHeight(1)
    hline:SetPoint("BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", 0, 0)
    hline:SetVertexColor(1, 1, 1, 0.1)
    if opts.noHeader then header:Hide() end
    f.header = header
    f.headerCells = {}

    local scroll = cf("Slider", f)
    scroll:SetOrientation("VERTICAL")
    scroll:SetPoint("TOPRIGHT", -I - 2, -I - headerH - 2)
    scroll:SetPoint("BOTTOMRIGHT", -I - 2, I + 2)
    scroll:SetWidth(4)
    local track = scroll:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(T.WHITE)
    track:SetAllPoints()
    track:SetVertexColor(1, 1, 1, 0.04)
    -- 얇은 손잡이
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.WHITE)
    thumb:SetVertexColor(0.38, 0.45, 0.46, 0.95)
    thumb:SetSize(4, 28)
    scroll:SetThumbTexture(thumb)
    scroll:SetMinMaxValues(0, 0)
    scroll:SetValueStep(1)
    if scroll.SetObeyStepOnDrag then scroll:SetObeyStepOnDrag(true) end
    scroll:SetValue(0)
    scroll:SetScript("OnValueChanged", function(_, v)
        local nv = math.floor(v + 0.5)
        if nv ~= f.offset then
            f.offset = nv
            f:Render()
        end
    end)
    f.scroll = scroll

    local empty = W.Label(f, opts.emptyText or "표시할 항목이 없습니다", 12, "muted", "CENTER")
    empty:SetPoint("CENTER", 0, 0)
    f.emptyLabel = empty

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local _, max = scroll:GetMinMaxValues()
        scroll:SetValue(U.Clamp(f.offset - delta * 3, 0, max))
    end)

    function f:LayoutColumns()
        local total = self:GetWidth() - 2 * I - SB - 4
        local fixed, flexCount = 0, 0
        for _, c in ipairs(self.columns) do
            if (c.width or 0) > 0 then fixed = fixed + c.width else flexCount = flexCount + 1 end
        end
        local flexW = flexCount > 0 and math.max(40, (total - fixed) / flexCount) or 0
        local x = 4
        for i, c in ipairs(self.columns) do
            c._x = x
            c._w = (c.width or 0) > 0 and c.width or flexW
            x = x + c._w
            local cell = self.headerCells[i]
            if not cell then
                cell = cf("Button", header)
                cell.text = W.Label(cell, "", 11, "muted")
                local chl = cell:CreateTexture(nil, "HIGHLIGHT")
                chl:SetTexture(T.WHITE)
                chl:SetAllPoints()
                chl:SetVertexColor(1, 1, 1, 0.06)
                cell.text:SetPoint("LEFT", 2, 0)
                cell.text:SetPoint("RIGHT", -2, 0)
                cell:SetScript("OnClick", function()
                    if self.columns[i].sort and opts.onSort then opts.onSort(self.columns[i].key) end
                end)
                self.headerCells[i] = cell
            end
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", c._x, 0)
            cell:SetSize(c._w, headerH)
            cell.text:SetText(c.title or "")
            cell.text:SetJustifyH(c.align or "LEFT")
        end
    end

    function f:VisibleCount()
        return math.max(1, math.floor((self:GetHeight() - headerH - 2 * I) / rowH))
    end

    function f:EnsureRows()
        local need = self:VisibleCount()
        for i = #self.rows + 1, need do
            local r = cf("Button", self)
            r:SetHeight(rowH)
            r:SetPoint("TOPLEFT", I, -I - headerH - (i - 1) * rowH)
            r:SetPoint("RIGHT", self, "RIGHT", -I - SB, 0)
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(T.WHITE)
            bg:SetAllPoints()
            r.bg = bg
            local hl = T.Solid(r, "HIGHLIGHT", T.colors.rowHover)
            hl:SetAllPoints()
            r.cells = {}
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r:SetScript("OnClick", function(row, button)
                if not row.data then return end
                local now = U.Clock()
                if button == "LeftButton" then
                    self.selected = row.data
                    self:Render()
                    if row.lastClick and now - row.lastClick < 0.35 and opts.onDoubleClick then
                        BRL.SafeCall("목록", opts.onDoubleClick, row.data, row)
                    elseif opts.onClick then
                        BRL.SafeCall("목록", opts.onClick, row.data, row)
                    end
                    row.lastClick = now
                elseif button == "RightButton" and opts.onRightClick then
                    self.selected = row.data
                    self:Render()
                    BRL.SafeCall("목록", opts.onRightClick, row.data, row)
                end
            end)
            r:SetScript("OnEnter", function(row)
                if row.data and opts.tooltip then
                    local title, lines = opts.tooltip(row.data)
                    if title then
                        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
                        GameTooltip:SetText(title, 1, 1, 1)
                        for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l, 0.78, 0.78, 0.82, true) end
                        GameTooltip:Show()
                    end
                end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.rows[i] = r
        end
    end

    function f:Render()
        self:EnsureRows()
        local visible = self:VisibleCount()
        local maxOff = math.max(0, #self.data - visible)
        if self.offset > maxOff then self.offset = maxOff end
        scroll:SetMinMaxValues(0, maxOff)
        if maxOff == 0 then scroll:Hide() else scroll:Show() end
        for i, r in ipairs(self.rows) do
            local data = self.data[i + self.offset]
            if data and i <= visible then
                r.data = data
                local c = (i + self.offset) % 2 == 0 and T.colors.rowAlt or T.colors.row
                if self.selected == data then c = T.colors.rowSelected end
                r.bg:SetVertexColor(c[1], c[2], c[3], c[4])
                for ci, col in ipairs(self.columns) do
                    local cell = r.cells[ci]
                    if not cell then
                        cell = W.Label(r, "", opts.fontSize or 12)
                        r.cells[ci] = cell
                    end
                    cell:ClearAllPoints()
                    cell:SetPoint("LEFT", r, "LEFT", (col._x or 0) + 2, 0)
                    cell:SetWidth(math.max(10, (col._w or 60) - 4))
                    cell:SetJustifyH(col.align or "LEFT")
                    local text
                    if col.render then
                        local ok, res = pcall(col.render, data, r)
                        text = ok and res or "!"
                    else
                        text = data[col.key]
                    end
                    cell:SetText(text == nil and "" or tostring(text))
                    cell:Show()
                end
                r:Show()
            else
                r.data = nil
                r:Hide()
            end
        end
        if #self.data == 0 then self.emptyLabel:Show() else self.emptyLabel:Hide() end
    end

    function f:SetData(list, keepSelection)
        self.data = list or {}
        if not keepSelection then
            self.selected = nil
        elseif self.selected then
            local still = false
            for _, d in ipairs(self.data) do
                if d == self.selected or (opts.idKey and self.selected[opts.idKey] and d[opts.idKey] == self.selected[opts.idKey]) then
                    self.selected = d
                    still = true
                    break
                end
            end
            if not still then self.selected = nil end
        end
        self:LayoutColumns()
        self:Render()
    end

    function f:GetSelected() return self.selected end
    function f:SetColumns(cols) self.columns = cols self:LayoutColumns() self:Render() end

    f:SetScript("OnSizeChanged", function(self) self:LayoutColumns() self:Render() end)
    return f
end

---------------------------------------------------------------------------
-- 하위 탭
---------------------------------------------------------------------------
function W.Tabs(parent, tabs, onSelect)
    local holder = cf("Frame", parent)
    holder:SetHeight(26)
    holder.buttons = {}
    holder.current = nil
    local x = 0
    for i, t in ipairs(tabs) do
        local b = W.Button(holder, t.text, t.width or 100, 24, function()
            holder:Select(t.key)
        end, { kind = "tab" })
        b:SetPoint("LEFT", x, 0)
        x = x + (t.width or 100) + 4
        b.key = t.key
        holder.buttons[i] = b
    end
    -- 폭을 정해 두어야 TOPRIGHT 등 오른쪽 기준 배치에서 버튼이 창 밖으로 나가지 않음
    holder.totalWidth = math.max(1, x - 4)
    holder:SetWidth(holder.totalWidth)
    -- 탭 아래 옅은 기준선 (선택 탭의 청록 밑줄이 이 선 위에 놓임)
    local base = T.Solid(holder, "BACKGROUND", { 1, 1, 1, 0.07 })
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", 0, 0)
    base:SetPoint("BOTTOMRIGHT", 0, 0)
    holder.baseLine = base
    function holder:Select(key)
        self.current = key
        for _, b in ipairs(self.buttons) do W.SetSelected(b, b.key == key) end
        if onSelect then BRL.SafeCall("탭", onSelect, key) end
    end
    return holder
end

---------------------------------------------------------------------------
-- 통계 타일
---------------------------------------------------------------------------
function W.StatTile(parent, label, width, height)
    local f = W.Panel(parent, T.colors.panel2, T.colors.borderDim, "box")
    f:SetSize(width or 150, height or 50)
    f.title = W.Label(f, label, 11, "muted")
    f.title:SetPoint("TOPLEFT", 9, -7)
    f.title:SetPoint("RIGHT", -7, 0)
    f.value = W.Label(f, "-", 15, "goldBright", nil, true)
    f.value:SetPoint("BOTTOMLEFT", 9, 7)
    f.value:SetPoint("RIGHT", -7, 0)
    -- 값이 길면 칸에 들어갈 때까지 글자 크기를 줄임 (잘림 방지)
    function f:SetValue(text, color)
        local v = self.value
        v:SetText(text or "-")
        T.SetTextColor(v, color or "goldBright")
        local avail = (self:GetWidth() or 150) - 16
        local size = 15
        T.SetFont(v, size, nil, true)
        while size > 10 and (v:GetStringWidth() or 0) > avail do
            size = size - 1
            T.SetFont(v, size, nil, true)
        end
    end
    return f
end

---------------------------------------------------------------------------
-- 레이아웃 도우미: 왼쪽→오른쪽 순서 배치
---------------------------------------------------------------------------
function W.Flow(parent, x, y, gap)
    local flow = { x = x, y = y, gap = gap or 6, cursor = x, parent = parent }
    function flow:Add(widget, width)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.cursor, -self.y)
        self.cursor = self.cursor + (width or widget:GetWidth()) + self.gap
        return widget
    end
    function flow:AddLabel(text, width, color)
        local fs = W.Label(self.parent, text, 12, color or "muted")
        fs:SetWidth(width or (#text * 4 + 10))
        fs:SetHeight(22)
        return self:Add(fs, width or (#text * 4 + 10))
    end
    function flow:NewLine(dy)
        self.y = self.y + (dy or 28)
        self.cursor = self.x
    end
    return flow
end

-- 이름 + 직업색
function W.ClassName(name, class)
    return BRL.Data.ColorName(name, class)
end

-- 아이템 링크 Shift+클릭 → 포커스된 BRL 입력창에 삽입
function W.HookLinkInsert()
    if W.linkHooked then return end
    W.linkHooked = true
    local function handler(link)
        local eb = W.focusedEdit
        if eb and link and eb:IsVisible() then
            eb:Insert(link)
            return true
        end
    end
    if _G.ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", handler)
    end
    if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then
        hooksecurefunc(_G.ChatFrameUtil, "InsertLink", handler)
    end
end
