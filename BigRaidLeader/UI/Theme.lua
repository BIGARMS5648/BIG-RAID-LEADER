-- BIG RAID LEADER - 테마 (어두운 배경 + 금색 강조, 판타지 스타일)
local _, BRL = ...

local T = {}
BRL.Theme = T

T.colors = {
    bg = { 0.05, 0.05, 0.07, 0.97 },
    panel = { 0.09, 0.09, 0.11, 0.96 },
    panel2 = { 0.13, 0.12, 0.15, 0.96 },
    header = { 0.16, 0.13, 0.08, 1 },
    border = { 0.52, 0.42, 0.18, 1 },
    borderDim = { 0.28, 0.24, 0.14, 1 },
    gold = { 0.83, 0.69, 0.22 },
    goldBright = { 1, 0.84, 0.32 },
    text = { 0.93, 0.91, 0.86 },
    muted = { 0.62, 0.6, 0.56 },
    red = { 1, 0.36, 0.36 },
    green = { 0.36, 0.95, 0.45 },
    yellow = { 1, 0.82, 0.1 },
    blue = { 0.45, 0.7, 1 },
    row = { 1, 1, 1, 0.025 },
    rowAlt = { 1, 1, 1, 0.055 },
    rowHover = { 0.83, 0.69, 0.22, 0.14 },
    rowSelected = { 0.83, 0.69, 0.22, 0.30 },
    button = { 0.17, 0.14, 0.09, 1 },
    buttonHover = { 0.27, 0.21, 0.1, 1 },
    primary = { 0.42, 0.31, 0.07, 1 },
    danger = { 0.4, 0.09, 0.09, 1 },
    input = { 0.03, 0.03, 0.04, 1 },
}

T.HEX = {
    gold = "ffd4af37", red = "ffff5c5c", green = "ff5cf272", yellow = "ffffd11a", muted = "ff9e9a8f", blue = "ff73b3ff", white = "ffffffff",
}

function T.Color(name, text)
    return "|c" .. (T.HEX[name] or T.HEX.white) .. tostring(text) .. "|r"
end

T.WHITE = "Interface\\Buttons\\WHITE8X8"
T.backdrop = {
    bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

function T.FontPath()
    if _G.STANDARD_TEXT_FONT then return _G.STANDARD_TEXT_FONT end
    if _G.GameFontNormal and _G.GameFontNormal.GetFont then
        local path = _G.GameFontNormal:GetFont()
        if path then return path end
    end
    return "Fonts\\2002.TTF"
end

function T.SetFont(fs, size, flags)
    local ok = pcall(fs.SetFont, fs, T.FontPath(), size or 12, flags or "")
    if not ok and fs.SetFontObject and _G.GameFontNormal then fs:SetFontObject(_G.GameFontNormal) end
end

function T.ApplyBackdrop(frame, bg, border)
    if not frame.SetBackdrop then
        if _G.BackdropTemplateMixin and _G.Mixin then
            _G.Mixin(frame, _G.BackdropTemplateMixin)
        else
            return
        end
    end
    frame:SetBackdrop(T.backdrop)
    bg = bg or T.colors.panel
    border = border or T.colors.borderDim
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function T.SetTextColor(fs, name)
    local c = T.colors[name] or T.colors.text
    fs:SetTextColor(c[1], c[2], c[3], 1)
end

-- 상태별 색 이름
T.STATUS_COLOR = {
    completed = "green", manual = "blue", cancelled = "muted", unverified = "yellow", open = "yellow",
    unpaid = "red", partial = "yellow", paid = "green", overpaid = "blue", refund_due = "red", refunded = "muted",
    pending = "red", check = "yellow", hold = "muted",
    queued = "muted", active = "yellow", ended = "yellow", awarded = "green", unsold = "muted",
    ready = "green", notready = "red", noresponse = "yellow", waiting = "muted", offline = "muted",
    draft = "yellow", confirmed = "blue", closed_with_issues = "red",
}

function T.StatusText(status, label)
    return T.Color(T.STATUS_COLOR[status] or "white", label or status)
end
