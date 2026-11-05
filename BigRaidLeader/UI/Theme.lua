-- BIG RAID LEADER - 테마 (모던 다크 · 청록 강조)
-- 짙은 청록빛 회색 면 + 청록 강조색(선택 막대/밑줄/토글/주요 버튼 테두리) + 빛나는 머리 선,
-- 아이콘 사이드바, 큰 화면 제목, 카드형 구획. 미니맵 버튼 테두리만 게임 기본 에셋을 쓴다.
local _, BRL = ...

local T = {}
BRL.Theme = T

T.MEDIA = "Interface\\AddOns\\BigRaidLeader\\Media\\"

T.colors = {
    -- 면
    bg = { 0.086, 0.114, 0.122, 0.98 },      -- 내용 바탕
    sidebar = { 0.063, 0.082, 0.09, 1 },     -- 왼쪽 메뉴
    panel = { 0.098, 0.125, 0.133, 0.96 },   -- 카드/상자
    panel2 = { 0.11, 0.14, 0.149, 0.97 },    -- 타일/강조 카드
    header = { 0.13, 0.163, 0.172, 1 },      -- 목록 머리글
    footer = { 0.058, 0.075, 0.082, 1 },     -- 아래 줄
    -- 선
    border = { 0.07, 0.79, 0.61, 1 },        -- 강조 선 (청록)
    borderDim = { 0.17, 0.21, 0.22, 1 },     -- 기본 선
    borderStrong = { 0.27, 0.32, 0.33, 1 },  -- 버튼/입력 선
    line = { 1, 1, 1, 0.06 },                -- 구분선
    -- 강조색
    accent = { 0.07, 0.79, 0.61 },
    accentBright = { 0.3, 0.95, 0.77 },
    accentDim = { 0.04, 0.26, 0.21 },
    accentText = { 0.7, 1, 0.9 },
    -- 글자
    gold = { 0.36, 0.92, 0.74 },             -- 강조 글자 (청록) - 이전 버전 금색 자리
    goldBright = { 1, 1, 1 },                -- 제목
    text = { 0.88, 0.91, 0.91 },
    muted = { 0.53, 0.59, 0.6 },
    disabled = { 0.33, 0.38, 0.39 },
    ink = { 0.04, 0.06, 0.06 },
    red = { 1, 0.42, 0.42 },
    green = { 0.36, 0.88, 0.58 },
    yellow = { 1, 0.8, 0.35 },
    blue = { 0.45, 0.72, 1 },
    -- 목록
    row = { 1, 1, 1, 0 },
    rowAlt = { 1, 1, 1, 0.022 },
    rowHover = { 1, 1, 1, 0.055 },
    rowSelected = { 0.07, 0.79, 0.61, 0.18 },
    -- 버튼/입력
    button = { 0.11, 0.137, 0.145, 1 },
    buttonHover = { 0.15, 0.185, 0.195, 1 },
    buttonBorder = { 0.27, 0.32, 0.33, 1 },
    primary = { 0.06, 0.16, 0.14, 1 },       -- 주요 버튼: 짙은 청록 + 청록 테두리
    primaryHover = { 0.08, 0.24, 0.2, 1 },
    danger = { 0.17, 0.08, 0.08, 1 },
    dangerBorder = { 0.55, 0.2, 0.2, 1 },
    dangerText = { 1, 0.6, 0.6 },
    input = { 0.06, 0.078, 0.082, 1 },
    tooltip = { 0.075, 0.098, 0.105, 0.98 },
    toggleOff = { 0.2, 0.235, 0.245, 1 },
}

T.HEX = {
    gold = "ff5cebbd", red = "ffff6b6b", green = "ff5ce094", yellow = "ffffcc59", muted = "ff879699", blue = "ff73b8ff", white = "ffffffff",
}

function T.Color(name, text)
    return "|c" .. (T.HEX[name] or T.HEX.white) .. tostring(text) .. "|r"
end

T.WHITE = "Interface\\Buttons\\WHITE8X8"

T.TEX = {
    icons = T.MEDIA .. "Icons.tga",            -- 흰 선 아이콘 아틀라스 (256x256, 64px 칸 4x4)
    headerGlow = T.MEDIA .. "HeaderGlow.tga",  -- 머리 띠 청록 빛 + 꺾인 선 (1024x128)
    backdrop = T.MEDIA .. "Backdrop.tga",      -- 내용 바탕 결 (512x512)
    logoBadge = T.MEDIA .. "LogoBadge.tga",    -- 원형 청록 배지 + 표범 (128x128)
    logo = T.MEDIA .. "Logo.tga",              -- 은색 표범 (256x64, 투명)
    minimapIcon = T.MEDIA .. "MinimapIcon.tga", -- 원형 표범 아이콘 (64x64)
    -- 게임 기본 에셋 (미니맵 버튼)
    minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
    minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
}

-- 아이콘 아틀라스 칸 번호 (왼쪽 위부터 0)
T.ICON = {
    dashboard = 0, recruit = 1, roster = 2, groups = 3, roles = 4, ready = 5, command = 6, boss = 7,
    auction = 8, trades = 9, ledger = 10, settlement = 11, settings = 12, chevron = 13, close = 14, check = 15,
}

-- texture 에 아틀라스 아이콘 지정
function T.SetIcon(tex, name, color)
    local i = T.ICON[name] or 0
    local col, row = i % 4, math.floor(i / 4)
    tex:SetTexture(T.TEX.icons)
    tex:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
    local c = color or T.colors.text
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- 배경 스타일 (모두 1px 단색 선. 이름은 화면 코드 호환용)
local FLAT = { bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
T.STYLES = {
    dialog = { backdrop = FLAT, bg = T.colors.bg, border = { 0.2, 0.25, 0.26, 1 }, inset = 1 },
    panel = { backdrop = FLAT, bg = { 0.075, 0.098, 0.105, 0.95 }, border = { 0.2, 0.25, 0.26, 1 }, inset = 1 },
    tooltip = { backdrop = FLAT, bg = T.colors.tooltip, border = { 0.24, 0.29, 0.3, 1 }, inset = 1 },
    box = { backdrop = FLAT, bg = T.colors.panel, border = T.colors.borderDim, inset = 1 },
    small = { backdrop = FLAT, bg = T.colors.button, border = T.colors.buttonBorder, inset = 1 },
    flat = { backdrop = FLAT, bg = T.colors.panel, border = T.colors.borderDim, inset = 1 },
}
T.backdrop = FLAT

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

-- 제목용 굵은 글꼴 (한글 클라이언트 2002B). 없으면 기본 글꼴
T.BOLD_FONT = "Fonts\\2002B.TTF"

function T.SetFont(fs, size, flags, bold)
    local done = false
    if bold then
        local ok, res = pcall(fs.SetFont, fs, T.BOLD_FONT, size or 12, flags or "")
        done = ok and res == true
    end
    if not done then
        local ok = pcall(fs.SetFont, fs, T.FontPath(), size or 12, flags or "")
        if not ok and fs.SetFontObject and _G.GameFontNormal then fs:SetFontObject(_G.GameFontNormal) end
    end
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 0.75)
        fs:SetShadowOffset(1, -1)
    end
end

-- frame 에 배경/선 적용. style 생략 시 flat
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

-- 단색 텍스처 한 장 (구분선/강조 막대)
function T.Solid(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(T.WHITE)
    local c = color or T.colors.line
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return t
end

-- 떠 있는 창 위쪽의 얇은 청록 강조선
function T.TopAccent(frame)
    local t = T.Solid(frame, "OVERLAY", { T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.9 })
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("TOPRIGHT", -1, -1)
    return t
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
