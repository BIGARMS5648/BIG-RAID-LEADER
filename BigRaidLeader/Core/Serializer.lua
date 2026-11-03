-- BIG RAID LEADER - 직렬화 (내보내기/가져오기/백업 검증)
-- loadstring 등 코드 실행을 사용하지 않는 안전한 자체 포맷.
local _, BRL = ...
local U = BRL.Util

local S = {}
BRL.Serializer = S

local tconcat, strsub, strbyte, strchar, floor = table.concat, string.sub, string.byte, string.char, math.floor
local tostring, tonumber, type, pairs = tostring, tonumber, type, pairs

local function serializeValue(v, out, depth)
    if depth > 40 then error("직렬화 깊이 초과") end
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("유효하지 않은 숫자") end
        -- %d 는 일부 플랫폼에서 32비트로 잘릴 수 있으므로 %.0f 사용 (2^53 까지 정확)
        if floor(v) == v then out[#out + 1] = "n" .. string.format("%.0f", v) .. ";"
        else out[#out + 1] = "n" .. string.format("%.17g", v) .. ";" end
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        -- 결정적 출력(체크섬 안정성)을 위해 키 정렬
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" or kt == "boolean" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local vt = type(val)
            if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
                serializeValue(k, out, depth + 1)
                serializeValue(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "N"
    end
end

function S.Serialize(v)
    local out = {}
    serializeValue(v, out, 0)
    return tconcat(out)
end

function S.Deserialize(str, maxLen)
    if type(str) ~= "string" then return nil, "문자열이 아닙니다" end
    if maxLen and #str > maxLen then return nil, "데이터가 너무 큽니다" end
    local pos = 1
    local len = #str
    local parse
    parse = function(depth)
        if depth > 40 then error("깊이 초과") end
        if pos > len then error("데이터가 중간에 끝났습니다") end
        local c = strsub(str, pos, pos)
        if c == "n" then
            local e = str:find(";", pos, true)
            if not e then error("숫자 형식 오류") end
            local n = tonumber(strsub(str, pos + 1, e - 1))
            if not n then error("숫자 형식 오류") end
            pos = e + 1
            return n
        elseif c == "s" then
            local e = str:find(":", pos, true)
            if not e then error("문자열 형식 오류") end
            local l = tonumber(strsub(str, pos + 1, e - 1))
            if not l or l < 0 or e + l > len then error("문자열 길이 오류") end
            local s = strsub(str, e + 1, e + l)
            pos = e + l + 1
            return s
        elseif c == "T" then pos = pos + 1 return true
        elseif c == "F" then pos = pos + 1 return false
        elseif c == "N" then pos = pos + 1 return nil
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while true do
                if pos > len then error("테이블이 닫히지 않았습니다") end
                if strsub(str, pos, pos) == "}" then pos = pos + 1 break end
                local k = parse(depth + 1)
                local v = parse(depth + 1)
                if k == nil then error("nil 키") end
                t[k] = v
            end
            return t
        end
        error("알 수 없는 토큰: " .. c)
    end
    local ok, res = pcall(parse, 0)
    if not ok then return nil, tostring(res) end
    if pos <= len then return nil, "불필요한 데이터가 남아 있습니다" end
    return res
end

-- Base64 (비트 연산 없이 산술 구현)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do B64INV[strbyte(B64, i)] = i - 1 end

function S.Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = strbyte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = strsub(B64, c1 + 1, c1 + 1) .. strsub(B64, c2 + 1, c2 + 1)
            .. (b and strsub(B64, c3 + 1, c3 + 1) or "=") .. (c and strsub(B64, c4 + 1, c4 + 1) or "=")
    end
    return tconcat(out)
end

function S.Base64Decode(data)
    data = data:gsub("[^%w%+/=]", "")
    if #data % 4 ~= 0 then return nil, "Base64 길이 오류" end
    local out = {}
    for i = 1, #data, 4 do
        local q = { strbyte(data, i, i + 3) }
        local v, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j]
            local d
            if ch == 61 then d = 0 pad = pad + 1 else d = B64INV[ch] end
            if d == nil then return nil, "Base64 문자 오류" end
            v = v * 64 + d
        end
        local b1 = floor(v / 65536) % 256
        local b2 = floor(v / 256) % 256
        local b3 = v % 256
        if pad == 0 then out[#out + 1] = strchar(b1, b2, b3)
        elseif pad == 1 then out[#out + 1] = strchar(b1, b2)
        else out[#out + 1] = strchar(b1) end
    end
    return tconcat(out)
end

-- 내보내기 문자열: "BRL:<종류>:<버전>:<체크섬>:<base64>"
function S.Export(kind, data)
    local payload = S.Serialize({ kind = kind, version = BRL.VERSION, schema = BRL.DB.SCHEMA_VERSION, at = U.Now(), data = data })
    local sum = U.Checksum(payload)
    return "BRL:" .. kind .. ":" .. BRL.DB.SCHEMA_VERSION .. ":" .. sum .. ":" .. S.Base64Encode(payload)
end

function S.Import(text, expectedKind)
    if type(text) ~= "string" then return nil, "가져올 문자열이 없습니다" end
    text = U.Trim(text)
    local kind, schema, sum, b64 = text:match("^BRL:([%w_]+):(%d+):(%d+):(.+)$")
    if not kind then return nil, "BIG RAID LEADER 내보내기 형식이 아닙니다" end
    if expectedKind and kind ~= expectedKind then return nil, "데이터 종류가 다릅니다: " .. kind end
    local payload, err = S.Base64Decode(b64)
    if not payload then return nil, err end
    if U.Checksum(payload) ~= tonumber(sum) then return nil, "체크섬 불일치: 데이터가 손상되었거나 일부만 복사되었습니다" end
    local obj, derr = S.Deserialize(payload, 8 * 1024 * 1024)
    if not obj then return nil, derr end
    if type(obj) ~= "table" or obj.kind ~= kind then return nil, "데이터 구조 오류" end
    obj.schema = tonumber(schema)
    return obj
end
