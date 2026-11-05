-- BIG RAID LEADER - 테마 (포에버 순정 인터페이스 스타일)
-- 게임 기본 창과 같은 재료를 쓴다: 대화상자 테두리/배경, 툴팁 테두리, 금색 글자(NORMAL_FONT_COLOR),
-- 흰 글자(HIGHLIGHT_FONT_COLOR), 회색 비활성 글자. 텍스처는 모든 클라이언트에 있는 기본 파일만 사용한다.
local _, BRL = ...

local T = {}
BRL.Theme = T

T.colors = {
    -- 배경/테두리 (툴팁 테두리 텍스처에 곱해지는 색)
    bg = { 0.03, 0.03, 0.03, 0.92 },
    panel = { 0.06, 0.06, 0.06, 0.72 },
    panel2 = { 0.11, 0.11, 0.11, 0.78 },
    header = { 0.18, 0.18, 0.18, 0.9 },
    border = { 1, 0.82, 0, 1 },          -- 강조 테두리 (금색)
    borderDim = { 0.55, 0.55, 0.55, 1 }, -- 기본 테두리 (회색)
    -- 글자 (게임 기본 글꼴 색)
    gold = { 1, 0.82, 0 },               -- NORMAL_FONT_COLOR
    goldBright = { 1, 0.82, 0 },
    text = { 1, 1, 1 },                  -- HIGHLIGHT_FONT_COLOR
    muted = { 0.62, 0.62, 0.62 },
    disabled = { 0.5, 0.5, 0.5 },        -- DISABLED_FONT_COLOR
    red = { 1, 0.13, 0.13 },             -- RED_FONT_COLOR
    green = { 0.1, 1, 0.1 },             -- GREEN_FONT_COLOR
    yellow = { 1, 1, 0 },                -- YELLOW_FONT_COLOR
    blue = { 0.41, 0.8, 0.94 },
    -- 목록
    row = { 1, 1, 1, 0 },
    rowAlt = { 1, 1, 1, 0.035 },
    rowHover = { 0.2, 0.4, 0.8, 0.45 },  -- 퀘스트 목록 강조와 같은 푸른 빛
    rowSelected = { 1, 0.82, 0, 0.2 },
    -- 버튼/입력
    button = { 0.09, 0.09, 0.09, 0.85 },
    buttonHover = { 0.2, 0.2, 0.2, 0.9 },
    primary = { 0.3, 0.24, 0.05, 0.9 },
    danger = { 0.35, 0.05, 0.05, 0.9 },
    input = { 0, 0, 0, 0.6 },
    tooltip = { 0.09, 0.09, 0.19, 0.95 }, -- TOOLTIP_DEFAULT_BACKGROUND_COLOR
}

T.HEX = {
    gold = "ffffd100", red = "ffff2020", green = "ff20ff20", yellow = "ffffff00", muted = "ff9d9d9d", blue = "ff69ccf0", white = "ffffffff",
}

function T.Color(name, text)
    return "|c" .. (T.HEX[name] or T.HEX.white) .. tostring(text) .. "|r"
end

T.WHITE = "Interface\\Buttons\\WHITE8X8"

-- 기본 텍스처 경로
T.TEX = {
    dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dialogBgDark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
    dialogHeader = "Interface\\DialogFrame\\UI-DialogBox-Header",
    tooltipBg = "Interface\\Tooltips\\UI-Tooltip-Background",
    tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    navHighlight = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
    scrollKnob = "Interface\\Buttons\\UI-ScrollBar-Knob",
    dropArrowUp = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    dropArrowDown = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
    dropArrowHighlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    checkUp = "Interface\\Buttons\\UI-CheckBox-Up",
    checkDown = "Interface\\Buttons\\UI-CheckBox-Down",
    checkHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    checkDisabled = "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
    panelButtonUp = "Interface\\Buttons\\UI-Panel-Button-Up",
    panelButtonDown = "Interface\\Buttons\\UI-Panel-Button-Down",
    panelButtonDisabled = "Interface\\Buttons\\UI-Panel-Button-Disabled",
    panelButtonHighlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    sizeGrabUp = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
    sizeGrabDown = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
    sizeGrabHighlight = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
}

-- 배경 스타일
--  dialog : 게임 대화상자 (돌 테두리, 메인 창/확인 창)
--  panel  : 작은 떠 있는 창 (대화상자 배경 + 툴팁 테두리, HUD/거래 정보)
--  tooltip: 툴팁/드롭다운 목록 (남색 배경)
--  box    : 창 안의 구획 (옵션 창의 상자)
--  small  : 작은 버튼/탭/입력칸 테두리
--  flat   : 1px 단색 (배치도 말 등)
T.STYLES = {
    dialog = {
        backdrop = { bgFile = T.TEX.dialogBg, edgeFile = T.TEX.dialogBorder, tile = true, tileEdge = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 } },
        bg = { 1, 1, 1, 1 }, border = { 1, 1, 1, 1 }, inset = 14,
    },
    panel = {
        backdrop = { bgFile = T.TEX.dialogBg, edgeFile = T.TEX.tooltipBorder, tile = true, tileEdge = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } },
        bg = { 1, 1, 1, 1 }, border = { 0.8, 0.8, 0.8, 1 }, inset = 6,
    },
    tooltip = {
        backdrop = { bgFile = T.TEX.tooltipBg, edgeFile = T.TEX.tooltipBorder, tile = true, tileEdge = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } },
        bg = T.colors.tooltip, border = { 1, 1, 1, 1 }, inset = 6,
    },
    box = {
        backdrop = { bgFile = T.TEX.tooltipBg, edgeFile = T.TEX.tooltipBorder, tile = true, tileEdge = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } },
        bg = T.colors.panel, border = T.colors.borderDim, inset = 5,
    },
    small = {
        backdrop = { bgFile = T.TEX.tooltipBg, edgeFile = T.TEX.tooltipBorder, tile = true, tileEdge = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } },
        bg = T.colors.button, border = T.colors.borderDim, inset = 3,
    },
    flat = {
        backdrop = { bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
        bg = T.colors.panel, border = T.colors.borderDim, inset = 1,
    },
}
T.backdrop = T.STYLES.flat.backdrop

-- 스타일 안쪽 여백 (자식 배치용)
function T.Inset(style)
    local s = T.STYLES[style or "box"] or T.STYLES.box
    return s.inset
end

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
    -- 기본 글꼴처럼 아주 옅은 그림자
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end
end

-- frame 에 배경/테두리 적용. style 을 생략하면 flat (1px)
function T.ApplyBackdrop(frame, bg, border, style)
    if not frame.SetBackdrop then
        if _G.BackdropTemplateMixin and _G.Mixin then
            _G.Mixin(frame, _G.BackdropTemplateMixin)
        else
            return
        end
    end
    local s = T.STYLES[style or frame.brlStyle or "flat"] or T.STYLES.flat
    frame.brlStyle = style or frame.brlStyle or "flat"
    frame:SetBackdrop(s.backdrop)
    bg = bg or s.bg
    border = border or s.border
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
