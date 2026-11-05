-- UI 레이아웃 검사기: 모의 프레임의 SetPoint/SetSize 기록으로 절대 좌표를 계산해 위젯 겹침을 찾는다.
-- 좌표계: 화면 왼쪽 위 (0,0), x 오른쪽 +, y 아래쪽 + (WoW 의 y 는 위쪽 + 이므로 부호를 뒤집는다)
-- 실제 렌더링(글꼴 폭)은 근사치(넉넉하게): 한글 1자 = 글자 크기, 영문/숫자 ≈ 0.58 × 글자 크기
local L = {}

local function strip(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("|H.-|h(.-)|h", "%1")
    return s
end

-- 한 줄 글자 폭
function L.TextWidth(text, size)
    size = size or 12
    local w, maxW = 0, 0
    local s = strip(text)
    local i = 1
    while i <= #s do
        local c = s:byte(i)
        if c == 10 then
            maxW = math.max(maxW, w) w = 0 i = i + 1
        elseif c >= 0xE0 then
            w = w + size * 1.0 i = i + 3
        elseif c >= 0xC0 then
            w = w + size * 0.7 i = i + 2
        else
            w = w + size * 0.58 i = i + 1
        end
    end
    return math.max(maxW, w)
end

local function lineCount(text)
    local n = 1
    for _ in strip(text):gmatch("\n") do n = n + 1 end
    return n
end

local ANCHOR = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local cache
local function resolve(f, depth)
    if cache[f] then return cache[f] end
    depth = (depth or 0) + 1
    if depth > 60 then return { l = 0, t = 0, r = 0, b = 0 } end
    if f == _G.UIParent or not f.__parent then
        local r = { l = 0, t = 0, r = f.__width or 1920, b = f.__height or 1080 }
        cache[f] = r
        return r
    end
    local isText = f.__kind == "FontString"
    local size = f.__fontSize or 12
    -- 고유 크기
    local w, h = f.__width or 100, f.__height or 20
    if isText then
        local text = f.__text or ""
        local tw = L.TextWidth(text, size)
        if f.__explicitW and f.__wordWrap then
            w = f.__width
            local lines = 0
            for line in (strip(text) .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(L.TextWidth(line, size) / math.max(1, w)))
            end
            h = f.__explicitH and f.__height or lines * (size + 3)
        elseif f.__explicitW then
            w = f.__width
            h = f.__explicitH and f.__height or (size + 4) * lineCount(text)
        else
            w = tw
            h = (size + 4) * lineCount(text)
        end
    end
    local pts = f.__points or {}
    if #pts == 0 then
        local p = resolve(f.__parent, depth)
        local r = { l = p.l, t = p.t, r = p.l + w, b = p.t + h, unanchored = true }
        cache[f] = r
        return r
    end
    local xs, ys = {}, {}
    for _, pt in ipairs(pts) do
        local rel = pt.rel
        if type(rel) == "string" then rel = _G[rel] end
        rel = rel or f.__parent
        local rr = resolve(rel, depth)
        local ra = ANCHOR[pt.relPoint] or ANCHOR.CENTER
        local ax = rr.l + (rr.r - rr.l) * ra[1] + (pt.x or 0)
        local ay = rr.t + (rr.b - rr.t) * ra[2] - (pt.y or 0)
        local a = ANCHOR[pt.point] or ANCHOR.CENTER
        xs[#xs + 1] = { frac = a[1], v = ax }
        ys[#ys + 1] = { frac = a[2], v = ay }
    end
    local function edges(list, size0)
        local lo, hi
        for _, e in ipairs(list) do
            if e.frac == 0 then lo = e.v elseif e.frac == 1 then hi = e.v end
        end
        if lo and hi then return lo, hi end
        local e = list[1]
        for _, x in ipairs(list) do if x.frac ~= 0.5 then e = x break end end
        if lo then return lo, lo + size0 end
        if hi then return hi - size0, hi end
        return e.v - size0 * e.frac, e.v + size0 * (1 - e.frac)
    end
    -- 글자는 앵커 두 개(좌우)로 폭이 정해져도 실제 글자 폭만큼만 차지 (정렬 고려)
    local l, r = edges(xs, w)
    local t, b = edges(ys, h)
    if L.rawMode then return { l = l, t = t, r = r, b = b } end
    if isText and not f.__wordWrap and (r - l) > L.TextWidth(f.__text, size) + 1 then
        local tw = L.TextWidth(f.__text, size)
        local j = f.__justifyH or "LEFT"
        if j == "RIGHT" then l = r - tw elseif j == "CENTER" then local c = (l + r) / 2 l, r = c - tw / 2, c + tw / 2 else r = l + tw end
    end
    if isText and (b - t) > (size + 4) * lineCount(f.__text) + 1 and not f.__wordWrap then
        local th = (size + 4) * lineCount(f.__text)
        local c = (t + b) / 2
        t, b = c - th / 2, c + th / 2
    end
    local res = { l = l, t = t, r = r, b = b }
    cache[f] = res
    return res
end

function L.Rect(f)
    cache = cache or {}
    return resolve(f)
end

function L.Reset() cache = {} end

local function visible(f)
    while f do
        if f.__shown == false then return false end
        f = f.__parent
    end
    return true
end

local function isAncestor(a, b)
    local p = b.__parent
    while p do
        if p == a then return true end
        p = p.__parent
    end
    return false
end

-- 위젯 분류: 블록(내부는 보지 않음) / 글자 / 패널(배경 있는 프레임) / 컨테이너(투명)
local function classify(f)
    if f.__kind == "Texture" or f.__kind == "Line" or f.__kind == "AnimationGroup" then return "skip" end
    if f.__kind == "FontString" then return "text" end
    local raw = function(k) return rawget(f, k) end
    if raw("columns") and raw("SetData") then return "block" end   -- W.List
    if raw("edit") then return "block" end                          -- W.EditBox / W.TextArea
    if raw("SetItems") and raw("label") then return "block" end     -- W.Dropdown
    if raw("mark") and raw("label") then return "check" end         -- W.CheckBox
    if f.__kind == "Button" and raw("label") then return "block" end -- W.Button
    if f.__kind == "Slider" or f.__kind == "ScrollFrame" or f.__kind == "EditBox" then return "block" end
    if f.__template and tostring(f.__template):find("BackdropTemplate") then return "panel" end
    return "container"
end

-- root 아래 보이는 위젯의 겹침 목록
function L.Overlaps(root, opts)
    opts = opts or {}
    L.Reset()
    local items = {}
    local function add(f, kind, label)
        local r = L.Rect(f)
        if (r.r - r.l) < 1 or (r.b - r.t) < 1 then return end
        items[#items + 1] = { f = f, r = r, kind = kind, label = label }
    end
    local function walk(f)
        if not visible(f) then return end
        local c = classify(f)
        if c == "skip" then return end
        if c == "text" then
            if strip(f.__text) ~= "" then add(f, "text", strip(f.__text):sub(1, 40)) end
            return
        end
        if c == "block" then
            add(f, "block", rawget(f, "label") and strip(f.label.__text) or (rawget(f, "columns") and "목록") or f.__kind)
            return
        end
        if c == "check" then
            add(f, "check", "체크:" .. strip(f.label.__text):sub(1, 30))
            if strip(f.label.__text) ~= "" then add(f.label, "text", strip(f.label.__text):sub(1, 40)) end
            return
        end
        if c == "panel" and f ~= root then add(f, "panel", "패널") end
        for _, ch in ipairs(f.__children or {}) do walk(ch) end
    end
    for _, ch in ipairs(root.__children or {}) do walk(ch) end
    local out = {}
    local tol = opts.tolerance or 1.5
    for i = 1, #items do
        for j = i + 1, #items do
            local a, b = items[i], items[j]
            if not isAncestor(a.f, b.f) and not isAncestor(b.f, a.f) and not (rawget(a.f, "label") == b.f or rawget(b.f, "label") == a.f) then
                local ix = math.min(a.r.r, b.r.r) - math.max(a.r.l, b.r.l)
                local iy = math.min(a.r.b, b.r.b) - math.max(a.r.t, b.r.t)
                if ix > tol and iy > tol then
                    -- 패널 안에 완전히 들어간 위젯은 의도된 배치 (패널 위 배치)
                    local function inside(x, y) return x.r.l >= y.r.l - 0.5 and x.r.r <= y.r.r + 0.5 and x.r.t >= y.r.t - 0.5 and x.r.b <= y.r.b + 0.5 end
                    local intended = (a.kind == "panel" and inside(b, a)) or (b.kind == "panel" and inside(a, b))
                    if not intended then out[#out + 1] = { a = a, b = b, ix = ix, iy = iy } end
                end
            end
        end
    end
    -- 배경 있는 상자(패널) 밖으로 삐져나온 자식 위젯
    for _, it in ipairs(items) do
        if it.kind ~= "panel" then
            local p = it.f.__parent
            while p and p ~= root do
                if classify(p) == "panel" then
                    local pr = L.Rect(p)
                    local r = it.r
                    if r.l < pr.l - 1 or r.r > pr.r + 1 or r.t < pr.t - 1 or r.b > pr.b + 1 then
                        out[#out + 1] = { a = it, b = { f = p, r = pr, kind = "panel", label = "부모 상자 밖" }, ix = 0, iy = 0 }
                    end
                    break
                end
                p = p.__parent
            end
        end
    end
    -- 부모 영역 밖으로 나간 위젯 (잘림)
    local clipped = {}
    if opts.bounds then
        local B = L.Rect(opts.bounds)
        for _, it in ipairs(items) do
            if it.r.r > B.r + 2 or it.r.b > B.b + 2 or it.r.l < B.l - 2 or it.r.t < B.t - 2 then clipped[#clipped + 1] = it end
        end
    end
    return out, clipped, items
end

-- 폭이 정해진 글자(버튼 글자, 폭 지정 라벨)에 글자가 다 안 들어가는 경우 (게임에서는 "…" 로 잘림)
function L.Truncations(root)
    L.Reset()
    local out = {}
    local function check(fs, owner)
        if not fs or fs.__kind ~= "FontString" or fs.__wordWrap then return end
        local text = strip(fs.__text)
        if text == "" then return end
        local r = L.Rect(fs)
        -- 앵커 두 개 또는 SetWidth 로 정해진 폭
        local avail
        local pts = fs.__points or {}
        local hasL, hasR = false, false
        for _, pt in ipairs(pts) do
            local a = ANCHOR[pt.point]
            if a and a[1] == 0 then hasL = true elseif a and a[1] == 1 then hasR = true end
        end
        if hasL and hasR then
            -- edges() 로 구한 원래 폭 (정렬로 줄이기 전)
            L.rawMode = true
            cache[fs] = nil
            local full = L.Rect(fs)
            L.rawMode = false
            cache[fs] = nil
            avail = full.r - full.l
        elseif fs.__explicitW then
            avail = fs.__width
        end
        if not avail then return end
        local need = L.TextWidth(fs.__text, fs.__fontSize or 12)
        if need > avail + 1 then
            out[#out + 1] = { f = fs, owner = owner, text = text:sub(1, 40), need = need, avail = avail, r = r }
        end
    end
    -- 목록: 열 폭 합이 목록 폭을 넘는지 + 머리글 글자가 열에 들어가는지 (행 내용은 데이터에 따라 다르므로 제외)
    local function checkList(f)
        local rr = L.Rect(f)
        local total = (rr.r - rr.l) - 24
        local fixed, flex = 0, 0
        for _, c in ipairs(f.columns or {}) do
            if (c.width or 0) > 0 then fixed = fixed + c.width else flex = flex + 1 end
        end
        local need = fixed + flex * 40
        if need > total + 1 then
            out[#out + 1] = { f = f, text = "목록 열 폭 합계", need = need, avail = total, r = L.Rect(f) }
        end
        for i, c in ipairs(f.columns or {}) do
            local cell = f.headerCells and f.headerCells[i]
            if cell and cell.text and c.title and c.title ~= "" then
                local w = L.TextWidth(c.title, 11)
                local flexW = flex > 0 and math.max(40, (total - fixed) / flex) or 0
                local cw = ((c.width or 0) > 0 and c.width or flexW) - 4
                if w > cw + 1 then out[#out + 1] = { f = cell.text, text = "머리글 " .. c.title, need = w, avail = cw, r = L.Rect(f) } end
            end
        end
    end
    local function walk(f)
        if not visible(f) then return end
        if rawget(f, "columns") then checkList(f) return end
        if f.__kind == "FontString" then check(f) return end
        if rawget(f, "label") and rawget(f, "columns") == nil then check(f.label, f) end
        for _, ch in ipairs(f.__children or {}) do
            if ch.__kind == "FontString" then
                if ch ~= rawget(f, "label") then check(ch, f) end
            else
                walk(ch)
            end
        end
    end
    for _, ch in ipairs(root.__children or {}) do walk(ch) end
    return out
end

function L.Describe(it)
    local r = it.r
    return string.format("%s[%s] (%d,%d %dx%d)", it.kind, tostring(it.label), math.floor(r.l), math.floor(r.t), math.floor(r.r - r.l), math.floor(r.b - r.t))
end

return L
