-- BIG RAID LEADER (빅 레이드 리더) - Bootstrap
-- 네임스페이스, 공용 유틸리티, 금액(코퍼) 계산, ID 생성, 모듈 수명주기, 오류 격리.
local ADDON_NAME, BRL = ...
BRL = BRL or {}
_G.BigRaidLeader = BRL

BRL.ADDON_NAME = ADDON_NAME or "BigRaidLeader"
BRL.TITLE = "BIG RAID LEADER"
BRL.TITLE_KO = "빅 레이드 리더"
BRL.SHORT = "BRL"
BRL.VERSION = "2.1.1"

do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if getMeta then
        local ok, v = pcall(getMeta, BRL.ADDON_NAME, "Version")
        if ok and type(v) == "string" and v ~= "" then BRL.VERSION = v end
    end
end

---------------------------------------------------------------------------
-- 공용 유틸리티
---------------------------------------------------------------------------
local U = {}
BRL.Util = U

local floor, tostring, tonumber, type, pairs, ipairs = math.floor, tostring, tonumber, type, pairs, ipairs
local strbyte, strsub, strfind, strgsub, strformat = string.byte, string.sub, string.find, string.gsub, string.format
local tinsert, tsort, tconcat = table.insert, table.sort, table.concat

function U.Trim(s)
    if type(s) ~= "string" then return s end
    return (strgsub(s, "^%s*(.-)%s*$", "%1"))
end

function U.Split(s, sep, plain)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    sep = sep or ","
    local start = 1
    while true do
        local i, j = strfind(s, sep, start, plain ~= false)
        if not i then
            tinsert(out, strsub(s, start))
            break
        end
        tinsert(out, strsub(s, start, i - 1))
        start = j + 1
    end
    return out
end

function U.DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, val in pairs(v) do
        t[U.DeepCopy(k, seen)] = U.DeepCopy(val, seen)
    end
    return t
end

function U.ShallowCopy(v)
    local t = {}
    for k, val in pairs(v or {}) do t[k] = val end
    return t
end

function U.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function U.Keys(t)
    local out = {}
    for k in pairs(t or {}) do tinsert(out, k) end
    tsort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function U.Values(t, sortFn)
    local out = {}
    for _, v in pairs(t or {}) do tinsert(out, v) end
    if sortFn then tsort(out, sortFn) end
    return out
end

function U.Filter(list, fn)
    local out = {}
    for _, v in ipairs(list or {}) do
        if fn(v) then tinsert(out, v) end
    end
    return out
end

function U.Map(list, fn)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = fn(v, i) end
    return out
end

function U.Contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

function U.RemoveValue(list, value)
    for i = #list, 1, -1 do
        if list[i] == value then table.remove(list, i) end
    end
end

function U.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = U.DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" and not v[1] then
            U.ApplyDefaults(target[k], v)
        end
    end
    return target
end

function U.Now()
    if _G.GetServerTime then
        local ok, t = pcall(_G.GetServerTime)
        if ok and type(t) == "number" then return t end
    end
    return time()
end

function U.Clock()
    if _G.GetTime then return _G.GetTime() end
    return os and os.clock and os.clock() or 0
end

function U.FormatDateTime(ts)
    if not ts then return "-" end
    return date("%Y-%m-%d %H:%M", ts)
end

function U.FormatDate(ts)
    if not ts then return "-" end
    return date("%Y-%m-%d", ts)
end

function U.FormatClock(ts)
    if not ts then return "-" end
    return date("%H:%M", ts)
end

function U.FormatDuration(sec)
    sec = floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    local h = floor(sec / 3600)
    local m = floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return strformat("%d:%02d:%02d", h, m, s) end
    return strformat("%d:%02d", m, s)
end

function U.FormatNumber(n)
    n = tonumber(n) or 0
    local neg = n < 0
    if neg then n = -n end
    local s = tostring(floor(n))
    local out = s
    while true do
        local k
        out, k = strgsub(out, "^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return (neg and "-" or "") .. out
end

-- UTF-8 문자 경계를 고려해 문자열을 바이트 제한 단위로 분할 (채팅 255바이트 제한 대응)
local function utf8CharLen(b)
    if not b then return 1 end
    if b < 0x80 then return 1 end
    if b >= 0xF0 then return 4 end
    if b >= 0xE0 then return 3 end
    if b >= 0xC0 then return 2 end
    return 1
end
U.Utf8CharLen = utf8CharLen

function U.Utf8Len(s)
    local i, n, len = 1, 0, #s
    while i <= len do
        i = i + utf8CharLen(strbyte(s, i))
        n = n + 1
    end
    return n
end

function U.Utf8Truncate(s, maxBytes)
    if #s <= maxBytes then return s end
    local i, last = 1, 0
    while i <= #s do
        local cl = utf8CharLen(strbyte(s, i))
        if i + cl - 1 > maxBytes then break end
        last = i + cl - 1
        i = i + cl
    end
    return strsub(s, 1, last)
end

-- 아이템 링크(|H...|h[...]|h|r)가 잘리지 않도록 분할한다.
local function tokenizeLine(line)
    local atoms = {}
    local i, len = 1, #line
    while i <= len do
        local linkEnd
        if strsub(line, i, i + 1) == "|c" or strsub(line, i, i + 1) == "|H" then
            local s, e = strfind(line, "|h|r", i, true)
            if s and strfind(strsub(line, i, e), "|H", 1, true) then linkEnd = e end
        end
        if linkEnd then
            tinsert(atoms, strsub(line, i, linkEnd))
            i = linkEnd + 1
        else
            local cl = utf8CharLen(strbyte(line, i))
            tinsert(atoms, strsub(line, i, i + cl - 1))
            i = i + cl
        end
    end
    return atoms
end

function U.SplitMessage(text, maxBytes)
    maxBytes = maxBytes or 250
    local out = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        line = U.Trim(line)
        if line ~= "" then
            local atoms = tokenizeLine(line)
            local buf, bufLen, lastSpaceIdx = {}, 0, nil
            local function flush(upto)
                local chunk = tconcat(buf, "", 1, upto)
                chunk = U.Trim(chunk)
                if chunk ~= "" then tinsert(out, chunk) end
                local rest = {}
                for k = upto + 1, #buf do tinsert(rest, buf[k]) end
                buf = rest
                bufLen = 0
                lastSpaceIdx = nil
                for k, a in ipairs(buf) do
                    bufLen = bufLen + #a
                    if a == " " then lastSpaceIdx = k end
                end
            end
            for _, atom in ipairs(atoms) do
                while bufLen + #atom > maxBytes and #buf > 0 do
                    if lastSpaceIdx and lastSpaceIdx > 1 then flush(lastSpaceIdx) else flush(#buf) end
                end
                tinsert(buf, atom)
                bufLen = bufLen + #atom
                if atom == " " then lastSpaceIdx = #buf end
            end
            if #buf > 0 then flush(#buf) end
        end
    end
    return out
end

-- 채팅 전송 시 파이프(|) 이스케이프 (아이템 링크는 유지)
function U.SanitizeChat(s)
    s = tostring(s or "")
    s = strgsub(s, "[\r\n]+", " ")
    return s
end

function U.StripColors(s)
    s = tostring(s or "")
    s = strgsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = strgsub(s, "|r", "")
    return s
end

-- 아이템 링크에서 [이름]만 추출
function U.ItemNameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h") or link
end

function U.ItemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- 대소문자 무시 검색 (한글은 그대로)
function U.MatchSearch(text, query)
    if not query or query == "" then return true end
    text = tostring(text or ""):lower()
    return strfind(text, tostring(query):lower(), 1, true) ~= nil
end

-- Adler-32 계열 체크섬 (비트 연산 없이 산술만 사용)
function U.Checksum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + strbyte(s, i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function U.Join(list, sep)
    local parts = {}
    for i, v in ipairs(list or {}) do parts[i] = tostring(v) end
    return tconcat(parts, sep or ", ")
end

---------------------------------------------------------------------------
-- 금액 (정수 코퍼 단위)
---------------------------------------------------------------------------
local Money = {}
BRL.Money = Money

Money.COPPER_PER_SILVER = 100
Money.COPPER_PER_GOLD = 10000
Money.MAX = 9007199254740991 -- 2^53-1 (Lua double 정수 정밀도 한계)
Money.UNIT_COPPER = 1
Money.UNIT_SILVER = 100
Money.UNIT_GOLD = 10000

function Money.IsInteger(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and floor(v) == v
end

function Money.IsValid(v, allowNegative)
    if not Money.IsInteger(v) then return false end
    if v > Money.MAX or v < -Money.MAX then return false end
    if not allowNegative and v < 0 then return false end
    return true
end

function Money.Split(c)
    c = floor(math.abs(c or 0))
    local g = floor(c / 10000)
    local s = floor((c % 10000) / 100)
    local cp = c % 100
    return g, s, cp
end

function Money.FromGSC(g, s, c)
    return floor(tonumber(g) or 0) * 10000 + floor(tonumber(s) or 0) * 100 + floor(tonumber(c) or 0)
end

-- 예: 25003005 -> "2,500골드 30실버 5코퍼"
function Money.Format(c, opts)
    opts = opts or {}
    c = tonumber(c) or 0
    local neg = c < 0
    local g, s, cp = Money.Split(c)
    local parts = {}
    if g > 0 or (s == 0 and cp == 0) then tinsert(parts, U.FormatNumber(g) .. (opts.short and "g" or "골드")) end
    if not opts.goldOnly then
        if s > 0 then tinsert(parts, s .. (opts.short and "s" or "실버")) end
        if cp > 0 then tinsert(parts, cp .. (opts.short and "c" or "코퍼")) end
    end
    local text = tconcat(parts, opts.short and "" or " ")
    if neg then text = "-" .. text elseif opts.sign and c > 0 then text = "+" .. text end
    if opts.color then
        if neg then text = "|cffff5555" .. text .. "|r"
        elseif c > 0 then text = "|cff55ff55" .. text .. "|r" end
    end
    return text
end

function Money.FormatShort(c)
    return Money.Format(c, { short = true })
end

-- 금액 문자열 파싱. 숫자만 입력하면 골드로 간주.
-- 지원: "2500", "2,500", "2500g", "2500골드 30실버 5코퍼", "2500g30s5c", "2.5k", "1.2만", "3천"
function Money.Parse(str)
    if type(str) == "number" then
        if str < 0 then return nil, "음수 금액은 입력할 수 없습니다." end
        return floor(str * 10000 + 0.5)
    end
    if type(str) ~= "string" then return nil, "금액이 비어 있습니다." end
    local s = U.Trim(str):lower()
    s = strgsub(s, ",", "")
    s = strgsub(s, "%s+", "")
    if s == "" then return nil, "금액이 비어 있습니다." end
    if s:sub(1, 1) == "-" then return nil, "음수 금액은 입력할 수 없습니다." end
    -- 단위 표기
    s = strgsub(s, "골드", "g")
    s = strgsub(s, "골", "g")
    s = strgsub(s, "실버", "s")
    s = strgsub(s, "은", "s")
    s = strgsub(s, "코퍼", "c")
    s = strgsub(s, "동", "c")
    s = strgsub(s, "gold", "g")
    s = strgsub(s, "silver", "s")
    s = strgsub(s, "copper", "c")
    -- 배수 표기 (골드 기준)
    -- (한글은 멀티바이트이므로 문자 클래스 대신 접미사 비교)
    local base = s
    if strsub(base, -1) == "g" then base = strsub(base, 1, -2) end
    for _, suffix in ipairs({ { "k", 1000 }, { "천", 1000 }, { "만", 10000 } }) do
        local sfx, factor = suffix[1], suffix[2]
        if #base > #sfx and strsub(base, -#sfx) == sfx then
            local num = strsub(base, 1, -#sfx - 1)
            if num:match("^%d+%.?%d*$") then
                local v = tonumber(num)
                if not v then return nil, "금액 형식이 올바르지 않습니다." end
                return floor(v * factor * 10000 + 0.5)
            end
        end
    end
    if s:match("^%d+%.?%d*$") then
        local v = tonumber(s)
        if not v then return nil, "금액 형식이 올바르지 않습니다." end
        return floor(v * 10000 + 0.5)
    end
    local total, matched = 0, false
    local rest = s
    for amount, unit in s:gmatch("(%d+)([gsc])") do
        matched = true
        local v = tonumber(amount)
        if unit == "g" then total = total + v * 10000
        elseif unit == "s" then
            if v >= 100 then return nil, "실버는 0~99 사이여야 합니다." end
            total = total + v * 100
        else
            if v >= 100 then return nil, "코퍼는 0~99 사이여야 합니다." end
            total = total + v
        end
    end
    rest = strgsub(rest, "%d+[gsc]", "")
    if not matched or rest ~= "" then return nil, "금액 형식이 올바르지 않습니다: " .. str end
    if total > Money.MAX then return nil, "금액이 너무 큽니다." end
    return total
end

-- 정밀도 손실 없는 floor(a * num / den) (a >= 0, num >= 0, den > 0)
function Money.MulDiv(a, num, den)
    assert(den and den > 0, "MulDiv: den must be > 0")
    local q = floor(a / den)
    local r = a - q * den
    return q * num + floor(r * num / den)
end

function Money.FloorToUnit(c, unit)
    unit = unit or 1
    if unit <= 1 then return floor(c) end
    return floor(c / unit) * unit
end

function Money.Sum(list, key)
    local total = 0
    for _, v in ipairs(list or {}) do
        local n = key and v[key] or v
        total = total + (tonumber(n) or 0)
    end
    return total
end

---------------------------------------------------------------------------
-- 로깅 / 오류 처리
---------------------------------------------------------------------------
local GOLD = "|cffd4af37"

function BRL:Print(msg, ...)
    if select("#", ...) > 0 then msg = strformat(msg, ...) end
    local frame = _G.DEFAULT_CHAT_FRAME
    local text = GOLD .. "[BRL]|r " .. tostring(msg)
    if frame and frame.AddMessage then
        frame:AddMessage(text)
    elseif print then
        print(text)
    end
end

function BRL:Debug(msg, ...)
    if self.acct and self.acct.debug then
        self:Print("|cff888888[디버그]|r " .. tostring(msg), ...)
    end
end

BRL.errors = {}
function BRL:Error(context, err)
    local entry = { at = U.Now(), context = tostring(context), message = tostring(err) }
    tinsert(self.errors, entry)
    if #self.errors > 50 then table.remove(self.errors, 1) end
    if self.db then
        self.db.errorLog = self.db.errorLog or {}
        tinsert(self.db.errorLog, entry)
        while #self.db.errorLog > 50 do table.remove(self.db.errorLog, 1) end
    end
    self:Print("|cffff5555오류|r (%s): %s", tostring(context), tostring(err))
end

local function traceback(err)
    local tb = (_G.debugstack and _G.debugstack(2, 8, 4)) or (debug and debug.traceback and debug.traceback("", 2)) or ""
    return tostring(err) .. "\n" .. tostring(tb)
end

-- 오류를 격리하여 실행. 실패 시 BRL:Error 로 기록하고 false 반환.
function BRL.SafeCall(context, fn, ...)
    local args = { n = select("#", ...), ... }
    local ok, a, b, c, d = xpcall(function() return fn(unpack(args, 1, args.n)) end, traceback)
    if not ok then
        BRL:Error(context, a)
        return false
    end
    return true, a, b, c, d
end

---------------------------------------------------------------------------
-- ID 생성 (계정 내 고유)
---------------------------------------------------------------------------
local fallbackCounter = 0
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function base36(n)
    n = floor(n)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local r = n % 36
        out = strsub(B36, r + 1, r + 1) .. out
        n = floor(n / 36)
    end
    return out
end
U.Base36 = base36

function BRL.NewId(prefix)
    local counter
    if BRL.db then
        BRL.db.nextId = (BRL.db.nextId or 0) + 1
        counter = BRL.db.nextId
    else
        fallbackCounter = fallbackCounter + 1
        counter = fallbackCounter
    end
    return (prefix or "ID") .. "-" .. base36(U.Now()) .. "-" .. base36(counter)
end

---------------------------------------------------------------------------
-- 모듈 수명주기
---------------------------------------------------------------------------
BRL.modules = {}
BRL.moduleOrder = {}

function BRL:NewModule(name)
    if self.modules[name] then return self.modules[name] end
    local m = { moduleName = name }
    self.modules[name] = m
    self[name] = m
    tinsert(self.moduleOrder, m)
    return m
end

function BRL:InitializeModules()
    for _, m in ipairs(self.moduleOrder) do
        if m.OnInitialize then BRL.SafeCall(m.moduleName .. ":OnInitialize", m.OnInitialize, m) end
    end
end

function BRL:EnableModules()
    for _, m in ipairs(self.moduleOrder) do
        if m.OnEnable then BRL.SafeCall(m.moduleName .. ":OnEnable", m.OnEnable, m) end
    end
    self.enabled = true
end

-- 테스트/디버그 용 전역 진입점
function _G.BigRaidLeader_ToggleUI()
    if BRL.UI and BRL.UI.Toggle then BRL.UI:Toggle() end
end

function _G.BigRaidLeader_OnAddonCompartmentClick()
    _G.BigRaidLeader_ToggleUI()
end
