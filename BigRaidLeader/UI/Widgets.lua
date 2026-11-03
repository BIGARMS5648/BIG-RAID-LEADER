-- BIG RAID LEADER - UI 위젯 (Blizzard 템플릿 의존 최소화: 버튼/입력/드롭다운/가상 스크롤 목록)
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
        GameTooltip:SetText(t, 1, 0.84, 0.32)
        local l = self.tooltipLines
        if type(l) == "function" then l = l(self) end
        if type(l) == "string" then l = { l } end
        for _, line in ipairs(l or {}) do GameTooltip:AddLine(line, 0.93, 0.91, 0.86, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- 기본 요소
---------------------------------------------------------------------------
function W.Panel(parent, bg, border)
    local f = cf("Frame", parent, "BackdropTemplate")
    T.ApplyBackdrop(f, bg or T.colors.panel, border or T.colors.borderDim)
    return f
end

function W.Label(parent, text, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    T.SetFont(fs, size or 12)
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

function W.Section(parent, text)
    local fs = W.Label(parent, text, 13, "goldBright")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(T.WHITE)
    line:SetVertexColor(T.colors.border[1], T.colors.border[2], T.colors.border[3], 0.6)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    fs.line = line
    return fs
end

local KIND_COLORS = {
    normal = T.colors.button, primary = T.colors.primary, danger = T.colors.danger, subtle = T.colors.panel2,
}

function W.Button(parent, text, width, height, onClick, opts)
    opts = opts or {}
    local b = cf("Button", parent, "BackdropTemplate")
    b:SetSize(width or 90, height or 22)
    local base = KIND_COLORS[opts.kind or "normal"] or T.colors.button
    T.ApplyBackdrop(b, base, opts.kind == "primary" and T.colors.border or T.colors.borderDim)
    local fs = W.Label(b, text, opts.size or 12, opts.kind == "primary" and "goldBright" or "text", "CENTER")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetPoint("LEFT", 4, 0)
    fs:SetPoint("RIGHT", -4, 0)
    b.label = fs
    b.baseColor = base
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(T.colors.buttonHover[1], T.colors.buttonHover[2], T.colors.buttonHover[3], 1)
            self:SetBackdropBorderColor(T.colors.border[1], T.colors.border[2], T.colors.border[3], 1)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(self.baseColor[1], self.baseColor[2], self.baseColor[3], self.baseColor[4] or 1)
        local bc = (opts.kind == "primary") and T.colors.border or T.colors.borderDim
        self:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
    end)
    b:SetScript("OnClick", function(self, button)
        if onClick then BRL.SafeCall("버튼:" .. tostring(text), onClick, self, button) end
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end
    local origEnable, origDisable = b.Enable, b.Disable
    function b:SetEnabledState(v)
        if v then origEnable(self) T.SetTextColor(self.label, opts.kind == "primary" and "goldBright" or "text")
        else origDisable(self) T.SetTextColor(self.label, "muted") end
    end
    if opts.tooltip then W.SetTooltip(b, text, opts.tooltip) end
    if opts.perm then
        b.perm = opts.perm
        table.insert(W.permButtons, b)
    end
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

function W.CheckBox(parent, label, onChange, tooltip)
    local b = cf("Button", parent, "BackdropTemplate")
    b:SetSize(16, 16)
    T.ApplyBackdrop(b, T.colors.input, T.colors.border)
    local mark = b:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(T.WHITE)
    mark:SetVertexColor(T.colors.goldBright[1], T.colors.goldBright[2], T.colors.goldBright[3], 1)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:Hide()
    b.mark = mark
    b.checked = false
    local fs = W.Label(b, label or "", 12)
    fs:SetPoint("LEFT", b, "RIGHT", 5, 0)
    b.label = fs
    function b:SetChecked(v)
        self.checked = v and true or false
        if self.checked then self.mark:Show() else self.mark:Hide() end
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then BRL.SafeCall("체크박스", onChange, self.checked, self) end
    end)
    if tooltip then W.SetTooltip(b, label, tooltip) end
    return b
end

function W.EditBox(parent, width, height, opts)
    opts = opts or {}
    local holder = cf("Frame", parent, "BackdropTemplate")
    holder:SetSize(width or 120, height or 22)
    T.ApplyBackdrop(holder, T.colors.input, T.colors.borderDim)
    local eb = cf("EditBox", holder)
    eb:SetPoint("TOPLEFT", 5, -2)
    eb:SetPoint("BOTTOMRIGHT", -5, 2)
    T.SetFont(eb, opts.size or 12)
    eb:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3])
    eb:SetAutoFocus(false)
    if opts.numeric and eb.SetNumeric then eb:SetNumeric(true) end
    if opts.maxLetters then eb:SetMaxLetters(opts.maxLetters) end
    local ph = W.Label(holder, opts.placeholder or "", 11, "muted")
    ph:SetPoint("LEFT", 6, 0)
    holder.placeholder = ph
    local function updatePH()
        if (eb:GetText() or "") == "" and not eb.hasFocus then ph:Show() else ph:Hide() end
    end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then BRL.SafeCall("입력", opts.onEnter, self:GetText(), self) end
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        self.hasFocus = true
        W.focusedEdit = self
        T.ApplyBackdrop(holder, T.colors.input, T.colors.border)
        updatePH()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self.hasFocus = false
        if W.focusedEdit == self then W.focusedEdit = nil end
        T.ApplyBackdrop(holder, T.colors.input, T.colors.borderDim)
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
    local holder = W.Panel(parent, T.colors.input, T.colors.borderDim)
    holder:SetSize(width or 300, height or 120)
    local sf = cf("ScrollFrame", holder)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    local eb = cf("EditBox", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    T.SetFont(eb, opts.size or 12)
    eb:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3])
    eb:SetWidth((width or 300) - 14)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self) W.focusedEdit = self end)
    eb:SetScript("OnEditFocusLost", function(self)
        if W.focusedEdit == self then W.focusedEdit = nil end
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
        eb:SetWidth(w - 14)
    end
    return holder
end

---------------------------------------------------------------------------
-- 드롭다운 (자체 구현 팝업 목록)
---------------------------------------------------------------------------
local popup
local function getPopup()
    if popup then return popup end
    popup = W.Panel(UIParent, T.colors.panel2, T.colors.border)
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
                btn.label:SetText((item.value == self.current and "|cffffd100▶ |r" or "") .. item.text)
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
    local b = W.Button(parent, opts.placeholder or "선택", width or 140, opts.height or 22, nil)
    b.label:SetJustifyH("LEFT")
    local arrow = W.Label(b, "▼", 9, "gold", "RIGHT")
    arrow:SetPoint("RIGHT", -5, 0)
    b.label:SetPoint("RIGHT", -16, 0)
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
        local rowH = 20
        p.visible = math.min(#list, opts.maxVisible or 14)
        for i = #p.buttons + 1, p.visible do
            local btn = cf("Button", p)
            btn:SetHeight(rowH)
            btn:SetPoint("TOPLEFT", 4, -4 - (i - 1) * rowH)
            btn:SetPoint("RIGHT", -4, 0)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture(T.WHITE)
            hl:SetAllPoints()
            hl:SetVertexColor(T.colors.rowHover[1], T.colors.rowHover[2], T.colors.rowHover[3], 0.5)
            btn.label = W.Label(btn, "", 12)
            btn.label:SetPoint("LEFT", 4, 0)
            btn.label:SetPoint("RIGHT", -4, 0)
            btn:SetScript("OnClick", function(bb)
                local owner = p.owner
                p:Hide()
                if owner and bb.item then owner:SetValue(bb.item.value) end
            end)
            p.buttons[i] = btn
        end
        p:SetWidth(math.max(self:GetWidth(), opts.popupWidth or 0))
        p:SetHeight(math.max(1, p.visible) * rowH + 8)
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
    local f = W.Panel(parent, T.colors.panel, T.colors.borderDim)
    f.columns = opts.columns or {}
    f.data = {}
    f.offset = 0
    f.rows = {}
    f.selected = nil
    local headerH = opts.noHeader and 0 or 20
    local header = cf("Frame", f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -13, -1)
    header:SetHeight(headerH)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetTexture(T.WHITE)
    hbg:SetAllPoints()
    hbg:SetVertexColor(T.colors.header[1], T.colors.header[2], T.colors.header[3], 1)
    if opts.noHeader then header:Hide() end
    f.header = header
    f.headerCells = {}

    local scroll = cf("Slider", f)
    scroll:SetOrientation("VERTICAL")
    scroll:SetPoint("TOPRIGHT", -2, -2 - headerH)
    scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    scroll:SetWidth(9)
    local track = scroll:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(T.WHITE)
    track:SetAllPoints()
    track:SetVertexColor(0, 0, 0, 0.4)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.WHITE)
    thumb:SetVertexColor(T.colors.border[1], T.colors.border[2], T.colors.border[3], 0.9)
    thumb:SetSize(9, 30)
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
        local total = self:GetWidth() - 16
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
                cell.text = W.Label(cell, "", 11, "gold")
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
        return math.max(1, math.floor((self:GetHeight() - headerH - 4) / rowH))
    end

    function f:EnsureRows()
        local need = self:VisibleCount()
        for i = #self.rows + 1, need do
            local r = cf("Button", self)
            r:SetHeight(rowH)
            r:SetPoint("TOPLEFT", 1, -1 - headerH - (i - 1) * rowH)
            r:SetPoint("RIGHT", self, "RIGHT", -13, 0)
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(T.WHITE)
            bg:SetAllPoints()
            r.bg = bg
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture(T.WHITE)
            hl:SetAllPoints()
            hl:SetVertexColor(T.colors.rowHover[1], T.colors.rowHover[2], T.colors.rowHover[3], T.colors.rowHover[4])
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
                        GameTooltip:SetText(title, 1, 0.84, 0.32)
                        for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l, 0.93, 0.91, 0.86, true) end
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
    holder:SetHeight(24)
    holder.buttons = {}
    holder.current = nil
    local x = 0
    for i, t in ipairs(tabs) do
        local b = W.Button(holder, t.text, t.width or 100, 22, function()
            holder:Select(t.key)
        end, { kind = "subtle" })
        b:SetPoint("LEFT", x, 0)
        x = x + (t.width or 100) + 4
        b.key = t.key
        holder.buttons[i] = b
    end
    function holder:Select(key)
        self.current = key
        for _, b in ipairs(self.buttons) do
            if b.key == key then
                b.baseColor = T.colors.primary
                T.ApplyBackdrop(b, T.colors.primary, T.colors.border)
                T.SetTextColor(b.label, "goldBright")
            else
                b.baseColor = T.colors.panel2
                T.ApplyBackdrop(b, T.colors.panel2, T.colors.borderDim)
                T.SetTextColor(b.label, "text")
            end
        end
        if onSelect then BRL.SafeCall("탭", onSelect, key) end
    end
    return holder
end

---------------------------------------------------------------------------
-- 통계 타일
---------------------------------------------------------------------------
function W.StatTile(parent, label, width, height)
    local f = W.Panel(parent, T.colors.panel2, T.colors.borderDim)
    f:SetSize(width or 150, height or 50)
    f.title = W.Label(f, label, 11, "muted")
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.title:SetPoint("RIGHT", -6, 0)
    f.value = W.Label(f, "-", 15, "goldBright")
    f.value:SetPoint("BOTTOMLEFT", 8, 7)
    f.value:SetPoint("RIGHT", -6, 0)
    function f:SetValue(text, color)
        self.value:SetText(text or "-")
        T.SetTextColor(self.value, color or "goldBright")
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
