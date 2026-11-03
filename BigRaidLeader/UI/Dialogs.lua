-- BIG RAID LEADER - 대화상자 (중요 작업 확인 / 입력 / 복사 / 선택)
local _, BRL = ...
local T, W, U, Money = BRL.Theme, BRL.Widgets, BRL.Util, BRL.Money

local D = {}
BRL.Dialogs = D

local function makeFrame(name, width, height)
    local f = W.Panel(UIParent, T.colors.bg, T.colors.border)
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    _G[name] = f
    table.insert(UISpecialFrames, name)
    f.title = W.Label(f, "", 14, "goldBright")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetPoint("RIGHT", -34, 0)
    local close = W.Button(f, "X", 22, 20, function() f:Hide() end, { kind = "subtle" })
    close:SetPoint("TOPRIGHT", -8, -8)
    return f
end

---------------------------------------------------------------------------
-- 확인
---------------------------------------------------------------------------
-- opts: { title, acceptText, cancelText, danger, onCancel }
function D.Confirm(text, onAccept, opts)
    opts = opts or {}
    local f = D.confirm
    if not f then
        f = makeFrame("BigRaidLeaderConfirmDialog", 420, 180)
        f.body = W.Paragraph(f, "", 390, 12)
        f.body:SetPoint("TOPLEFT", 16, -40)
        f.accept = W.Button(f, "확인", 110, 24, function()
            local cb = f.onAccept
            f:Hide()
            if cb then BRL.SafeCall("확인 대화상자", cb) end
        end, { kind = "primary" })
        f.accept:SetPoint("BOTTOMRIGHT", -16, 14)
        f.cancel = W.Button(f, "취소", 90, 24, function()
            local cb = f.onCancel
            f:Hide()
            if cb then cb() end
        end)
        f.cancel:SetPoint("RIGHT", f.accept, "LEFT", -8, 0)
        D.confirm = f
    end
    f.title:SetText(opts.title or "확인")
    f.body:SetText(text or "")
    f.accept:SetText(opts.acceptText or "확인")
    f.cancel:SetText(opts.cancelText or "취소")
    local h = 100 + math.min(260, (f.body.GetStringHeight and f.body:GetStringHeight() or 40))
    f:SetHeight(math.max(160, h))
    f.onAccept, f.onCancel = onAccept, opts.onCancel
    if opts.danger then
        T.ApplyBackdrop(f.accept, T.colors.danger, T.colors.border)
        f.accept.baseColor = T.colors.danger
    else
        T.ApplyBackdrop(f.accept, T.colors.primary, T.colors.border)
        f.accept.baseColor = T.colors.primary
    end
    f:Show()
    f:Raise()
    return f
end

function D.Message(text, title)
    return D.Confirm(text, nil, { title = title or "알림", acceptText = "확인", cancelText = "닫기" })
end

---------------------------------------------------------------------------
-- 입력 양식
-- fields: { { key=, label=, type="text"|"money"|"number"|"multiline"|"dropdown"|"check", default=, items=, required=, placeholder= } }
-- onAccept(values) → true 또는 false, "오류 메시지" (false 면 창 유지)
---------------------------------------------------------------------------
function D.Input(title, fields, onAccept, opts)
    opts = opts or {}
    local f = D.input
    if not f then
        f = makeFrame("BigRaidLeaderInputDialog", 460, 200)
        f.widgets = {}
        f.err = W.Label(f, "", 11, "red")
        f.err:SetPoint("BOTTOMLEFT", 16, 46)
        f.err:SetPoint("RIGHT", -16, 0)
        f.accept = W.Button(f, "확인", 110, 24, function()
            local values = {}
            for _, w in ipairs(f.widgets) do
                local fd = w.field
                local v
                if fd.type == "check" then v = w.ctrl:GetChecked()
                elseif fd.type == "dropdown" then v = w.ctrl:GetValue()
                else v = U.Trim(w.ctrl:GetText() or "") end
                if fd.type == "money" then
                    if v == "" then
                        if fd.required then f.err:SetText(fd.label .. ": 금액을 입력하세요") return end
                        v = fd.allowEmpty and nil or 0
                    else
                        local c, e = Money.Parse(v)
                        if not c then f.err:SetText(fd.label .. ": " .. tostring(e)) return end
                        v = c
                    end
                elseif fd.type == "number" then
                    if v == "" then v = nil else
                        v = tonumber(v)
                        if not v then f.err:SetText(fd.label .. ": 숫자를 입력하세요") return end
                    end
                    if fd.required and v == nil then f.err:SetText(fd.label .. ": 필수 항목") return end
                elseif fd.required and (v == nil or v == "") then
                    f.err:SetText(fd.label .. ": 필수 항목입니다")
                    return
                end
                values[fd.key] = v
            end
            local cb = f.onAccept
            if cb then
                local ok, res, err = BRL.SafeCall("입력 대화상자", cb, values)
                if not ok then f.err:SetText("오류가 발생했습니다") return end
                if res == false then f.err:SetText(tostring(err or "처리할 수 없습니다")) return end
            end
            f:Hide()
        end, { kind = "primary" })
        f.accept:SetPoint("BOTTOMRIGHT", -16, 14)
        f.cancel = W.Button(f, "취소", 90, 24, function() f:Hide() end)
        f.cancel:SetPoint("RIGHT", f.accept, "LEFT", -8, 0)
        f.desc = W.Paragraph(f, "", 420, 11)
        f.desc:SetPoint("TOPLEFT", 16, -36)
        D.input = f
    end
    for _, w in ipairs(f.widgets) do
        w.label:Hide()
        w.ctrl:Hide()
    end
    f.widgets = {}
    f.title:SetText(title or "입력")
    f.desc:SetText(opts.description or "")
    f.err:SetText("")
    f.accept:SetText(opts.acceptText or "확인")
    local y = opts.description and (48 + math.min(80, f.desc:GetStringHeight() or 14)) or 42
    for _, fd in ipairs(fields) do
        local label = W.Label(f, fd.label or fd.key, 12, "muted")
        label:SetPoint("TOPLEFT", 16, -y - 4)
        label:SetWidth(120)
        local ctrl
        if fd.type == "check" then
            ctrl = W.CheckBox(f, fd.checkLabel or "", nil)
            ctrl:SetPoint("TOPLEFT", 140, -y - 3)
            ctrl:SetChecked(fd.default and true or false)
            y = y + 26
        elseif fd.type == "dropdown" then
            ctrl = W.Dropdown(f, 290, fd.items or {}, nil)
            ctrl:SetPoint("TOPLEFT", 140, -y)
            ctrl:SetValue(fd.default, true)
            y = y + 28
        elseif fd.type == "multiline" then
            ctrl = W.TextArea(f, 290, fd.height or 80)
            ctrl:SetPoint("TOPLEFT", 140, -y)
            ctrl:SetText(fd.default or "")
            y = y + (fd.height or 80) + 6
        else
            ctrl = W.EditBox(f, 290, 22, { placeholder = fd.placeholder or (fd.type == "money" and "예: 2500 / 2500g 30s / 1.2만" or ""), acceptItems = fd.acceptItems })
            ctrl:SetPoint("TOPLEFT", 140, -y)
            local d = fd.default
            if fd.type == "money" and type(d) == "number" then
                local g, s, c = Money.Split(d)
                if s > 0 or c > 0 then
                    d = g .. "g" .. (s > 0 and (" " .. s .. "s") or "") .. (c > 0 and (" " .. c .. "c") or "")
                else
                    d = tostring(g)
                end
                if d == "0" and fd.allowEmpty then d = "" end
            end
            ctrl:SetText(d ~= nil and tostring(d) or "")
            y = y + 28
        end
        ctrl:Show()
        label:Show()
        table.insert(f.widgets, { field = fd, label = label, ctrl = ctrl })
    end
    f:SetHeight(y + 70)
    f.onAccept = onAccept
    f:Show()
    f:Raise()
    if f.widgets[1] and f.widgets[1].ctrl.SetFocus and f.widgets[1].field.type ~= "dropdown" then
        f.widgets[1].ctrl:SetFocus()
    end
    return f
end

-- 사유 입력 단축
function D.Reason(title, onAccept, description)
    return D.Input(title, { { key = "reason", label = "사유", type = "text", required = true } }, function(v)
        return onAccept(v.reason)
    end, { description = description })
end

---------------------------------------------------------------------------
-- 복사 (보고서/내보내기)
---------------------------------------------------------------------------
function D.CopyText(title, text, opts)
    opts = opts or {}
    local f = D.copy
    if not f then
        f = makeFrame("BigRaidLeaderCopyDialog", 620, 460)
        f.hint = W.Label(f, "Ctrl+A 로 전체 선택 후 Ctrl+C 로 복사하세요.", 11, "muted")
        f.hint:SetPoint("TOPLEFT", 16, -34)
        f.area = W.TextArea(f, 588, 360)
        f.area:SetPoint("TOPLEFT", 16, -54)
        f.selectAll = W.Button(f, "전체 선택", 100, 24, function()
            f.area.edit:SetFocus()
            f.area.edit:HighlightText()
        end)
        f.selectAll:SetPoint("BOTTOMLEFT", 16, 12)
        f.extra = W.Button(f, "", 140, 24, function() if f.extraFn then f.extraFn(f.area:GetText()) end end, { kind = "primary" })
        f.extra:SetPoint("BOTTOMRIGHT", -16, 12)
        D.copy = f
    end
    f.title:SetText(title or "복사")
    f.hint:SetText(opts.hint or "Ctrl+A 로 전체 선택 후 Ctrl+C 로 복사하세요.")
    f.area:SetText(text or "")
    if opts.extraText then
        f.extra:SetText(opts.extraText)
        f.extraFn = opts.extraFn
        f.extra:Show()
    else
        f.extra:Hide()
    end
    f:Show()
    f:Raise()
    f.area.edit:SetFocus()
    f.area.edit:HighlightText()
    return f
end

-- 가져오기 (붙여넣기 → 콜백)
function D.Paste(title, onAccept, hint)
    local f = D.CopyText(title, "", {
        hint = hint or "내보내기 문자열을 붙여넣은 뒤 [가져오기]를 누르세요.",
        extraText = "가져오기",
        extraFn = function(text)
            local ok, err = onAccept(text)
            if ok then D.copy:Hide() else BRL:Print("가져오기 실패: %s", tostring(err)) end
        end,
    })
    return f
end

---------------------------------------------------------------------------
-- 선택 목록
-- items: { {value=, text=, sub=} } ; onSelect(value)
---------------------------------------------------------------------------
function D.Select(title, items, onSelect, opts)
    opts = opts or {}
    local f = D.select
    if not f then
        f = makeFrame("BigRaidLeaderSelectDialog", 520, 400)
        f.desc = W.Paragraph(f, "", 480, 11)
        f.desc:SetPoint("TOPLEFT", 16, -34)
        f.list = W.List(f, {
            columns = { { key = "text", title = "항목", width = 0 }, { key = "sub", title = "", width = 170, align = "RIGHT" } },
            onDoubleClick = function(data) f.choose(data) end,
        })
        f.list:SetPoint("TOPLEFT", 16, -60)
        f.list:SetPoint("BOTTOMRIGHT", -16, 48)
        f.ok = W.Button(f, "선택", 100, 24, function()
            local sel = f.list:GetSelected()
            if sel then f.choose(sel) end
        end, { kind = "primary" })
        f.ok:SetPoint("BOTTOMRIGHT", -16, 12)
        D.select = f
    end
    f.choose = function(data)
        f:Hide()
        if onSelect then BRL.SafeCall("선택 대화상자", onSelect, data.value, data) end
    end
    f.title:SetText(title or "선택")
    f.desc:SetText(opts.description or "")
    f:Show()
    f:Raise()
    f.list:SetData(items or {})
    return f
end
