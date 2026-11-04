-- BIG RAID LEADER - 게임 API 호환 계층
-- 모든 게임 API 호출은 이 파일을 통해 이루어진다.
--  * 존재하지 않는 API는 안전하게 대체/비활성화
--  * Secret Value(12.x / 포에버) 는 읽거나 비교하지 않고 "확인 불가"로 처리
--  * 전투 중/채팅 제한 중 호출 금지 기능은 차단 또는 대기열 처리
local _, BRL = ...
local U = BRL.Util

local API = {}
BRL.API = API

local G = _G
local type, pcall, tostring = type, pcall, tostring

-- 지원 여부 보고 (API_COMPATIBILITY 화면/문서용)
API.support = {}
local function mark(name, ok)
    API.support[name] = ok and true or false
    return ok
end

local function fn(path)
    -- "C_ChatInfo.SendAddonMessage" 형태 경로를 함수로 해석
    local cur = G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    if type(cur) == "function" then return cur end
    return nil
end
API.Resolve = fn

function API.Has(path)
    return fn(path) ~= nil
end

---------------------------------------------------------------------------
-- Secret Value 처리
---------------------------------------------------------------------------
function API.IsSecret(v)
    local f = G.issecretvalue
    if f then
        local ok, r = pcall(f, v)
        if ok then return r and true or false end
        return true
    end
    return false
end

-- secret 이면 fallback 반환
function API.Safe(v, fallback)
    if v == nil then return fallback end
    if API.IsSecret(v) then return fallback end
    return v
end

-- 함수 호출 결과 중 secret 이 있으면 nil 처리 (pcall 보호)
local function safeCall(f, ...)
    if not f then return false end
    local res = { pcall(f, ...) }
    if not res[1] then return false end
    for i = 2, #res do
        if API.IsSecret(res[i]) then res[i] = nil end
    end
    return unpack(res)
end
API.SafeCall = safeCall

---------------------------------------------------------------------------
-- 상태
---------------------------------------------------------------------------
function API.InCombat()
    if G.InCombatLockdown then
        local ok, r = pcall(G.InCombatLockdown)
        return ok and r and true or false
    end
    return false
end

-- 12.x 채팅 메시지 잠금(우두머리 전투, 쐐기, PvP 경기 중)
function API.InChatLockdown()
    local f = fn("C_ChatInfo.InChatMessagingLockdown")
    if f then
        local ok, r = pcall(f)
        if ok and not API.IsSecret(r) then return r and true or false end
    end
    return false
end

function API.GetMoney()
    local ok, m = safeCall(G.GetMoney)
    if ok and type(m) == "number" then return m end
    return nil
end

function API.GetInterfaceVersion()
    if G.GetBuildInfo then
        local ok, _, _, _, iface = pcall(G.GetBuildInfo)
        if ok then return iface end
    end
    return nil
end

function API.GetBuildText()
    if G.GetBuildInfo then
        local ok, version, build, d, iface = pcall(G.GetBuildInfo)
        if ok then return string.format("%s (%s) %s / Interface %s", tostring(version), tostring(build), tostring(d), tostring(iface)) end
    end
    return "알 수 없음"
end

---------------------------------------------------------------------------
-- 이름/식별자
---------------------------------------------------------------------------
function API.GetPlayerRealm()
    local ok, r = safeCall(G.GetNormalizedRealmName)
    if ok and r and r ~= "" then return r end
    ok, r = safeCall(G.GetRealmName)
    if ok and r then return (r:gsub("[%s%-]", "")) end
    return "Unknown"
end

-- 캐릭터 키: "이름-서버" (서버 생략 시 내 서버)
function API.NormalizeName(name, realm)
    if type(name) ~= "string" or name == "" or API.IsSecret(name) then return nil end
    name = U.StripColors(name)
    if name:find("-", 1, true) then
        local n, r = name:match("^([^%-]+)%-(.+)$")
        if n and r and r ~= "" then return n .. "-" .. (r:gsub("%s", "")) end
    end
    if type(realm) ~= "string" or realm == "" or API.IsSecret(realm) then realm = API.GetPlayerRealm() end
    return name .. "-" .. (realm:gsub("%s", ""))
end

function API.ShortName(full)
    if type(full) ~= "string" then return "?" end
    local n, r = full:match("^([^%-]+)%-(.+)$")
    if not n then return full end
    if r == API.GetPlayerRealm() then return n end
    return full
end

function API.GetPlayerKey()
    local ok, name, realm = safeCall(G.UnitFullName, "player")
    if not ok or not name then
        local _
        _, name = safeCall(G.UnitName, "player")
    end
    return API.NormalizeName(name or "Player", realm)
end

-- 유닛의 캐릭터 키. Secret 이면 nil.
function API.UnitKey(unit)
    local ok, name, realm = safeCall(G.UnitName, unit)
    if not ok or not name or name == "" or name == G.UNKNOWNOBJECT then return nil end
    return API.NormalizeName(name, realm)
end

-- GUID 는 포에버에서 난독화될 수 있으므로 보조 식별자로만 사용
function API.UnitGUID(unit)
    local ok, guid = safeCall(G.UnitGUID, unit)
    if ok and type(guid) == "string" then return guid end
    return nil
end

function API.UnitClass(unit)
    local ok, loc, file = safeCall(G.UnitClass, unit)
    if ok then return loc, file end
    return nil, nil
end

function API.UnitExists(unit)
    local ok, r = safeCall(G.UnitExists, unit)
    return ok and r and true or false
end

---------------------------------------------------------------------------
-- 그룹 / 공격대
---------------------------------------------------------------------------
function API.IsInGroup()
    local ok, r = safeCall(G.IsInGroup)
    return ok and r and true or false
end

function API.IsInRaid()
    local ok, r = safeCall(G.IsInRaid)
    return ok and r and true or false
end

function API.GetNumGroupMembers()
    local ok, n = safeCall(G.GetNumGroupMembers)
    if ok and type(n) == "number" then return n end
    return 0
end

-- 반환: true/false, 또는 확인 불가(오류/Secret Value) 시 nil
local function boolOrUnknown(f, unit)
    if not f then return nil end
    local ok, r = pcall(f, unit)
    if not ok or API.IsSecret(r) then return nil end
    return r and true or false
end

function API.IsLeader(unit)
    unit = unit or "player"
    if not API.IsInGroup() then return false end
    return boolOrUnknown(G.UnitIsGroupLeader, unit)
end

function API.IsAssistant(unit)
    unit = unit or "player"
    if not API.IsInGroup() then return false end
    return boolOrUnknown(G.UnitIsGroupAssistant, unit)
end

local CLASS_FROM_LOCAL
local function classFileFromLocalized(loc)
    if not CLASS_FROM_LOCAL then
        CLASS_FROM_LOCAL = {}
        for file, name in pairs(G.LOCALIZED_CLASS_NAMES_MALE or {}) do CLASS_FROM_LOCAL[name] = file end
        for file, name in pairs(G.LOCALIZED_CLASS_NAMES_FEMALE or {}) do CLASS_FROM_LOCAL[name] = file end
    end
    return CLASS_FROM_LOCAL[loc]
end

-- 현재 그룹 구성원 목록. 각 항목: key, name, short, rank(0/1/2), subgroup, level, classLocal,
-- class(파일명), zone, online, dead, unit, raidIndex, isLeader, isAssistant, combatRole, afk
function API.GetGroupRoster()
    local list = {}
    if API.IsInRaid() then
        local n = API.GetNumGroupMembers()
        for i = 1, n do
            local ok, name, rank, subgroup, level, classLocal, classFile, zone, online, isDead, _, _, combatRole =
                safeCall(G.GetRaidRosterInfo, i)
            if ok and name then
                local unit = "raid" .. i
                local key = API.NormalizeName(name)
                if key then
                    local afkOk, afk = safeCall(G.UnitIsAFK, unit)
                    list[#list + 1] = {
                        key = key, name = name, short = API.ShortName(key), rank = rank or 0,
                        subgroup = subgroup or 1, level = level, classLocal = classLocal,
                        class = classFile or classFileFromLocalized(classLocal), zone = zone,
                        online = online and true or false, dead = isDead and true or false,
                        unit = unit, raidIndex = i, isLeader = rank == 2, isAssistant = rank == 1,
                        combatRole = combatRole, afk = afkOk and afk and true or false,
                        guid = API.UnitGUID(unit),
                    }
                end
            end
        end
    elseif API.IsInGroup() then
        local units = { "player", "party1", "party2", "party3", "party4" }
        for idx, unit in ipairs(units) do
            if API.UnitExists(unit) then
                local key = API.UnitKey(unit)
                if key then
                    local classLocal, classFile = API.UnitClass(unit)
                    local okL, level = safeCall(G.UnitLevel, unit)
                    local okC, connected = safeCall(G.UnitIsConnected, unit)
                    local okD, dead = safeCall(G.UnitIsDeadOrGhost, unit)
                    local okA, afk = safeCall(G.UnitIsAFK, unit)
                    local okR, role = safeCall(G.UnitGroupRolesAssigned, unit)
                    local isLeader = API.IsLeader(unit)
                    list[#list + 1] = {
                        key = key, name = key, short = API.ShortName(key), rank = isLeader and 2 or 0,
                        subgroup = 1, level = okL and level or nil, classLocal = classLocal, class = classFile,
                        zone = nil, online = (not okC) or connected and true or false,
                        dead = okD and dead and true or false, unit = unit, raidIndex = idx,
                        isLeader = isLeader and true or false, isAssistant = false,
                        combatRole = okR and role or nil, afk = okA and afk and true or false,
                        guid = API.UnitGUID(unit),
                    }
                end
            end
        end
    end
    return list
end

function API.GetCurrentZone()
    local ok, z = safeCall(G.GetRealZoneText)
    if ok then return z end
    return nil
end

function API.GetInstanceInfo()
    local ok, name, instanceType, difficultyID, _, maxPlayers, _, _, instanceID = safeCall(G.GetInstanceInfo)
    if ok then return name, instanceType, difficultyID, maxPlayers, instanceID end
    return nil
end

---------------------------------------------------------------------------
-- 공격대 운영 명령 (전투 중 차단)
---------------------------------------------------------------------------
local function guardCombat()
    if API.InCombat() then
        BRL:Print(BRL.L.IN_COMBAT_BLOCKED)
        return false
    end
    return true
end
API.GuardCombat = guardCombat

function API.DoReadyCheck()
    if not guardCombat() then return false end
    if not mark("DoReadyCheck", G.DoReadyCheck ~= nil) then return false end
    local ok, err = pcall(G.DoReadyCheck)
    if not ok then BRL:Error("DoReadyCheck", err) end
    return ok
end

-- 공식 풀링 카운트다운 (C_PartyInfo.DoCountdown). 미지원 시 false.
function API.DoCountdown(seconds)
    if not guardCombat() then return false end
    local f = fn("C_PartyInfo.DoCountdown")
    if not mark("C_PartyInfo.DoCountdown", f ~= nil) then return false end
    local ok, err = pcall(f, seconds)
    if not ok then BRL:Debug("DoCountdown 실패: " .. tostring(err)) end
    return ok
end

function API.InviteUnit(name)
    if not guardCombat() then return false end
    local f = fn("C_PartyInfo.InviteUnit") or G.InviteUnit
    if not mark("InviteUnit", f ~= nil) then return false end
    local ok, err = pcall(f, name)
    if not ok then BRL:Error("InviteUnit", err) end
    return ok
end

function API.ConvertToRaid()
    if not guardCombat() then return false end
    local f = fn("C_PartyInfo.ConvertToRaid") or G.ConvertToRaid
    if not f then return false end
    return (pcall(f))
end

function API.SetRaidSubgroup(raidIndex, subgroup)
    if not guardCombat() then return false end
    if not mark("SetRaidSubgroup", G.SetRaidSubgroup ~= nil) then return false end
    local ok, err = pcall(G.SetRaidSubgroup, raidIndex, subgroup)
    if not ok then BRL:Debug("SetRaidSubgroup 실패: " .. tostring(err)) end
    return ok
end

function API.SwapRaidSubgroup(i1, i2)
    if not guardCombat() then return false end
    if not mark("SwapRaidSubgroup", G.SwapRaidSubgroup ~= nil) then return false end
    local ok, err = pcall(G.SwapRaidSubgroup, i1, i2)
    if not ok then BRL:Debug("SwapRaidSubgroup 실패: " .. tostring(err)) end
    return ok
end

function API.GetReadyCheckStatus(unit)
    local ok, s = safeCall(G.GetReadyCheckStatus, unit)
    if ok then return s end
    return nil
end

---------------------------------------------------------------------------
-- 채팅
---------------------------------------------------------------------------
local chatSend = fn("C_ChatInfo.SendChatMessage") or G.SendChatMessage
mark("SendChatMessage", chatSend ~= nil)

-- 채널 이름/번호 목록 (모집 채널 선택용)
function API.GetChannels()
    local out = {}
    if not G.GetChannelList then return out end
    local res = { pcall(G.GetChannelList) }
    if not res[1] then return out end
    local i = 2
    while res[i] do
        local id, name, disabled = res[i], res[i + 1], res[i + 2]
        if type(id) == "number" and type(name) == "string" then
            out[#out + 1] = { id = id, name = name, disabled = disabled and true or false }
            i = i + 3
        else
            i = i + 1
        end
    end
    return out
end

-- 채팅 메시지 전송 (즉시). 반환: true / false, 사유
-- 주의: CHANNEL/SAY/YELL 은 하드웨어 이벤트(버튼 클릭) 컨텍스트에서만 호출해야 한다.
function API.SendChatRaw(msg, chatType, target)
    if not chatSend then return false, "unsupported" end
    if API.InChatLockdown() then return false, "lockdown" end
    if chatType == "RAID_WARNING" and not (API.IsLeader() or API.IsAssistant()) then
        chatType = API.IsInRaid() and "RAID" or "PARTY"
    end
    if (chatType == "RAID" or chatType == "RAID_WARNING") and not API.IsInRaid() then
        if API.IsInGroup() then chatType = "PARTY" else return false, "nogroup" end
    end
    if chatType == "PARTY" and not API.IsInGroup() then return false, "nogroup" end
    local ok, err = pcall(chatSend, msg, chatType, nil, target)
    if not ok then return false, tostring(err) end
    return true
end

---------------------------------------------------------------------------
-- 화면 알림 / 소리
---------------------------------------------------------------------------
function API.ScreenAlert(msg)
    if G.RaidNotice_AddMessage and G.RaidWarningFrame and G.ChatTypeInfo then
        pcall(G.RaidNotice_AddMessage, G.RaidWarningFrame, msg, G.ChatTypeInfo["RAID_WARNING"])
    elseif G.UIErrorsFrame and G.UIErrorsFrame.AddMessage then
        G.UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
end

function API.PlaySound(name)
    if not G.PlaySound then return end
    local kit = G.SOUNDKIT and G.SOUNDKIT[name or "RAID_WARNING"]
    if kit then pcall(G.PlaySound, kit) end
end

---------------------------------------------------------------------------
-- 거래 API
---------------------------------------------------------------------------
local function tradeSlotCount()
    local max = G.MAX_TRADE_ITEMS or 7
    local enchant = G.TRADE_ENCHANT_SLOT or max
    -- 마지막 슬롯(마법부여 슬롯)은 실제로 교환되지 않음
    if enchant == max then return max - 1 end
    return max
end
API.TradeSlotCount = tradeSlotCount

local function readTradeItems(infoFn, linkFn)
    local items = {}
    if not infoFn then return items end
    for slot = 1, tradeSlotCount() do
        local ok, name, texture, count, quality = safeCall(infoFn, slot)
        if ok and name and name ~= "" then
            local okL, link = safeCall(linkFn, slot)
            items[#items + 1] = {
                slot = slot, name = name, icon = texture, count = count or 1,
                quality = quality, link = okL and link or nil,
            }
        end
    end
    return items
end

function API.GetTradeSnapshot()
    local okP, pm = safeCall(G.GetPlayerTradeMoney)
    local okT, tm = safeCall(G.GetTargetTradeMoney)
    local snap = {
        playerMoney = (okP and type(pm) == "number") and pm or 0,
        targetMoney = (okT and type(tm) == "number") and tm or 0,
        playerItems = readTradeItems(G.GetTradePlayerItemInfo, G.GetTradePlayerItemLink),
        targetItems = readTradeItems(G.GetTradeTargetItemInfo, G.GetTradeTargetItemLink),
        moneyReadable = okP and okT,
    }
    return snap
end

-- 거래 상대 (거래 창이 열린 동안 "NPC" 유닛 토큰이 상대를 가리킴)
function API.GetTradePartner()
    local key = API.UnitKey("NPC")
    if not key and G.TradeFrameRecipientNameText and G.TradeFrameRecipientNameText.GetText then
        local ok, text = pcall(G.TradeFrameRecipientNameText.GetText, G.TradeFrameRecipientNameText)
        if ok and type(text) == "string" and not API.IsSecret(text) and text ~= "" then
            key = API.NormalizeName(text)
        end
    end
    local guid = API.UnitGUID("NPC")
    local _, class = API.UnitClass("NPC")
    return key, guid, class
end

-- 거래 완료/취소 시스템 메시지 판별
local CANCEL_KEYS = {
    "ERR_TRADE_CANCELLED", "ERR_TRADE_BAG_FULL", "ERR_TRADE_TARGET_BAG_FULL",
    "ERR_TRADE_MAX_COUNT_EXCEEDED", "ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED",
    "ERR_TRADE_TOO_FAR", "ERR_TRADE_TARGET_DEAD", "ERR_TRADE_QUEST_ITEM",
    "ERR_TRADE_BOUND_ITEM", "ERR_TRADE_GROUND_ITEM", "ERR_TRADE_NOT_ON_TAPLIST",
    "ERR_TRADE_TEMP_ENCHANT_BOUND", "ERR_TRADE_WRONG_REALM", "ERR_TRADE_SELF",
    "ERR_TRADE_TARGET_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS", "ERR_TRADE_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS",
    "ERR_NOT_ENOUGH_MONEY",
}

function API.IsTradeCompleteMessage(msg)
    if type(msg) ~= "string" or API.IsSecret(msg) then return false end
    local complete = G.ERR_TRADE_COMPLETE
    return complete ~= nil and msg == complete
end

function API.IsTradeCancelMessage(msg)
    if type(msg) ~= "string" or API.IsSecret(msg) then return false end
    for _, k in ipairs(CANCEL_KEYS) do
        local s = G[k]
        if type(s) == "string" and s ~= "" then
            if msg == s then return true end
            if s:find("%%s") then
                local pattern = "^" .. s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", ".+") .. "$"
                if msg:match(pattern) then return true end
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- 아이템
---------------------------------------------------------------------------
function API.GetItemInfo(item)
    if not item then return nil end
    local f = fn("C_Item.GetItemInfo") or G.GetItemInfo
    if not f then return nil end
    local ok, name, link, quality, _, _, _, _, _, _, icon = safeCall(f, item)
    if ok and name then return name, link, quality, icon end
    return nil
end

function API.GetItemIcon(item)
    local f = fn("C_Item.GetItemIconByID") or G.GetItemIcon
    local id = type(item) == "number" and item or U.ItemIdFromLink(item)
    if f and id then
        local ok, icon = safeCall(f, id)
        if ok and icon then return icon end
    end
    local _, _, _, icon = API.GetItemInfo(item)
    return icon
end

function API.GetQualityColor(quality)
    if type(quality) ~= "number" then return 1, 1, 1, "ffffffff" end
    local f = fn("C_Item.GetItemQualityColor") or G.GetItemQualityColor
    if f then
        local ok, r, g, b, hex = safeCall(f, quality)
        if ok and r then return r, g, b, hex end
    end
    local c = G.ITEM_QUALITY_COLORS and G.ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b, c.hex end
    return 1, 1, 1, "ffffffff"
end

function API.GetCursorItem()
    if not G.GetCursorInfo then return nil end
    local ok, kind, itemID, link = safeCall(G.GetCursorInfo)
    if ok and kind == "item" then return link or itemID end
    return nil
end

function API.ClearCursor()
    if G.ClearCursor then pcall(G.ClearCursor) end
end

-- 전리품 창 아이템 목록
function API.GetLootItems()
    local out = {}
    local okN, n = safeCall(G.GetNumLootItems)
    if not okN or not n then return out end
    for slot = 1, n do
        local okLink, link = safeCall(G.GetLootSlotLink, slot)
        if okLink and link then
            local _, _, quality = API.GetItemInfo(link)
            out[#out + 1] = { slot = slot, link = link, quality = quality }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- 오라 (버프 점검)
---------------------------------------------------------------------------
-- 반환: auras 목록 또는 nil, 사유("combat"|"secret"|"unsupported")
function API.GetUnitBuffs(unit)
    if API.InCombat() then return nil, "combat" end
    local getByIndex = fn("C_UnitAuras.GetAuraDataByIndex")
    local out = {}
    if getByIndex then
        for i = 1, 60 do
            local ok, data = pcall(getByIndex, unit, i, "HELPFUL")
            if not ok then return nil, "unsupported" end
            if not data then break end
            if API.IsSecret(data) then return nil, "secret" end
            local name, spellId, exp = data.name, data.spellId, data.expirationTime
            if API.IsSecret(name) or API.IsSecret(spellId) then return nil, "secret" end
            out[#out + 1] = {
                name = name, spellId = spellId,
                expirationTime = API.Safe(exp, nil), duration = API.Safe(data.duration, nil),
            }
        end
        return out
    end
    if G.UnitBuff then
        for i = 1, 40 do
            local ok, name, _, _, _, duration, exp, _, _, _, spellId = pcall(G.UnitBuff, unit, i)
            if not ok then return nil, "unsupported" end
            if not name then break end
            if API.IsSecret(name) then return nil, "secret" end
            out[#out + 1] = { name = name, spellId = API.Safe(spellId, nil), expirationTime = API.Safe(exp, nil), duration = API.Safe(duration, nil) }
        end
        return out
    end
    return nil, "unsupported"
end

-- 내 장비 내구도 (최소/평균 %)
function API.GetOwnDurability()
    if not G.GetInventoryItemDurability then return nil end
    local minPct, sum, count = 100, 0, 0
    for slot = 1, 19 do
        local ok, cur, max = safeCall(G.GetInventoryItemDurability, slot)
        if ok and cur and max and max > 0 then
            local pct = cur / max * 100
            if pct < minPct then minPct = pct end
            sum = sum + pct
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return math.floor(minPct + 0.5), math.floor(sum / count + 0.5)
end

---------------------------------------------------------------------------
-- 타이머
---------------------------------------------------------------------------
function API.After(sec, callback)
    if G.C_Timer and G.C_Timer.After then
        G.C_Timer.After(sec, function() BRL.SafeCall("timer", callback) end)
        return true
    end
    return false
end

function API.NewTicker(sec, callback)
    if G.C_Timer and G.C_Timer.NewTicker then
        return G.C_Timer.NewTicker(sec, function() BRL.SafeCall("ticker", callback) end)
    end
    return nil
end

function API.Time()
    return U.Clock()
end

---------------------------------------------------------------------------
-- 지원 여부 점검 (설정 > 호환성 화면)
---------------------------------------------------------------------------
API.CHECK_LIST = {
    "issecretvalue", "InCombatLockdown", "C_ChatInfo.InChatMessagingLockdown",
    "GetMoney", "GetPlayerTradeMoney", "GetTargetTradeMoney",
    "GetTradePlayerItemInfo", "GetTradeTargetItemInfo", "GetTradePlayerItemLink", "GetTradeTargetItemLink",
    "GetRaidRosterInfo", "UnitIsGroupLeader", "UnitIsGroupAssistant", "GetNumGroupMembers",
    "SetRaidSubgroup", "SwapRaidSubgroup", "DoReadyCheck", "GetReadyCheckStatus",
    "C_PartyInfo.DoCountdown", "C_PartyInfo.InviteUnit", "C_PartyInfo.ConvertToRaid",
    "C_ChatInfo.SendChatMessage", "SendChatMessage", "C_UnitAuras.GetAuraDataByIndex",
    "C_Item.GetItemInfo", "GetItemInfo", "GetLootSlotLink", "GetInventoryItemDurability",
    "C_Timer.After", "C_Timer.NewTicker", "GetServerTime", "UnitFullName", "GetNormalizedRealmName",
    "GetChannelList", "RaidNotice_AddMessage",
}

function API.RunCompatibilityCheck()
    local results = {}
    for _, path in ipairs(API.CHECK_LIST) do
        results[#results + 1] = { name = path, ok = fn(path) ~= nil }
    end
    results[#results + 1] = { name = "ERR_TRADE_COMPLETE (전역 문자열)", ok = type(G.ERR_TRADE_COMPLETE) == "string" }
    results[#results + 1] = { name = "Interface", ok = true, value = tostring(API.GetInterfaceVersion()) }
    for event, ok in pairs(BRL.Events and BRL.Events.unsupported or {}) do
        results[#results + 1] = { name = "이벤트 " .. event, ok = not ok }
    end
    return results
end
