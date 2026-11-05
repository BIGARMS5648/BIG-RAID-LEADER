-- BIG RAID LEADER - 테마 (모던 모노크롬 "블랙 팬서")
-- 검은 로우폴리 표범 로고에 맞춘 무채색 테마: 짙은 검정 면 + 얇은 회색 선 + 흰/은색 글자,
-- 주요 버튼만 흰 바탕에 검은 글자(로고처럼 반전). 색은 상태 표시(성공/경고/오류)에만 쓴다.
-- 미니맵 버튼 테두리만 게임 기본 에셋(MiniMap-TrackingBorder)을 쓴다.
local _, BRL = ...

local T = {}
BRL.Theme = T

T.MEDIA = "Interface\\AddOns\\BigRaidLeader\\Media\\"

T.colors = {
    -- 면
    bg = { 0.047, 0.047, 0.055, 0.97 },     -- 창 바탕
    panel = { 0.075, 0.075, 0.085, 0.92 },  -- 구획 상자
    panel2 = { 0.095, 0.095, 0.105, 0.95 }, -- 카드/타일
    header = { 0.11, 0.11, 0.12, 1 },       -- 목록 머리글
    sidebar = { 0.06, 0.06, 0.068, 1 },     -- 왼쪽 메뉴
    -- 선
    border = { 0.85, 0.85, 0.88, 1 },       -- 강조 선 (흰색에 가까움)
    borderDim = { 0.2, 0.2, 0.22, 1 },      -- 기본 선
    line = { 1, 1, 1, 0.07 },               -- 구분선
    -- 글자
    gold = { 0.86, 0.86, 0.9 },             -- 강조 글자 (은색) - 이전 버전의 금색 자리
    goldBright = { 1, 1, 1 },               -- 제목
    text = { 0.9, 0.9, 0.92 },
    muted = { 0.56, 0.56, 0.6 },
    disabled = { 0.36, 0.36, 0.39 },
    ink = { 0.05, 0.05, 0.06 },             -- 흰 버튼 위 검은 글자
    red = { 1, 0.38, 0.38 },
    green = { 0.38, 0.86, 0.5 },
    yellow = { 1, 0.8, 0.32 },
    blue = { 0.45, 0.72, 1 },
    -- 목록
    row = { 1, 1, 1, 0 },
    rowAlt = { 1, 1, 1, 0.025 },
    rowHover = { 1, 1, 1, 0.06 },
    rowSelected = { 1, 1, 1, 0.12 },
    -- 버튼/입력
    button = { 0.14, 0.14, 0.155, 1 },
    buttonHover = { 0.2, 0.2, 0.22, 1 },
    buttonBorder = { 0.27, 0.27, 0.3, 1 },
    primary = { 0.9, 0.9, 0.92, 1 },        -- 흰 버튼
    primaryHover = { 1, 1, 1, 1 },
    danger = { 0.2, 0.075, 0.075, 1 },
    dangerBorder = { 0.5, 0.17, 0.17, 1 },
    dangerText = { 1, 0.58, 0.58 },
    input = { 0.025, 0.025, 0.03, 1 },
    tooltip = { 0.07, 0.07, 0.08, 0.98 },
}

T.HEX = {
    gold = "ffdcdce6", red = "ffff6161", green = "ff61db80", yellow = "ffffcc52", muted = "ff8f8f99", blue = "ff73b8ff", white = "ffffffff",
}

function T.Color(name, text)
    return "|c" .. (T.HEX[name] or T.HEX.white) .. tostring(text) .. "|r"
end

T.WHITE = "Interface\\Buttons\\WHITE8X8"

T.TEX = {
    logo = T.MEDIA .. "Logo.tga",              -- 은색 로우폴리 표범 (256x64, 투명)
    headerPoly = T.MEDIA .. "HeaderPoly.tga",  -- 머리 띠 로우폴리 무늬 (512x64)
    minimapIcon = T.MEDIA .. "MinimapIcon.tga", -- 원형 표범 아이콘 (64x64, 원형 투명)
    -- 게임 기본 에셋 (미니맵 버튼)
    minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
    minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
}

-- 배경 스타일 (모두 1px 단색 선. 이름은 화면 코드 호환용)
--  dialog : 대화상자/메인 창   panel: 작은 떠 있는 창(HUD 등)   tooltip: 드롭다운 목록
--  box    : 창 안 구획           small: 버튼/입력칸                flat : 단색
local FLAT = { bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
T.STYLES = {
    dialog = { backdrop = FLAT, bg = T.colors.bg, border = { 0.24, 0.24, 0.27, 1 }, inset = 1 },
    panel = { backdrop = FLAT, bg = { 0.05, 0.05, 0.058, 0.94 }, border = { 0.26, 0.26, 0.29, 1 }, inset = 1 },
    tooltip = { backdrop = FLAT, bg = T.colors.tooltip, border = { 0.32, 0.32, 0.36, 1 }, inset = 1 },
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
        fs:SetShadowColor(0, 0, 0, 0.8)
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
