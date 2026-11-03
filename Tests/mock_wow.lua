-- BIG RAID LEADER 자동 테스트용 WoW API 모의 환경 (Lua 5.1)
-- 실제 게임 클라이언트가 아니므로 UI 렌더링/보호 함수 동작은 검증하지 않는다.
local M = {}
_G.MOCK = M

M.clock = 1000.0
M.serverTime = 1793000000
M.money = 1000000 * 10000
M.combat = false
M.lockdown = false
M.sent = {}        -- 전송된 채팅
M.addonSent = {}   -- 전송된 애드온 메시지
M.chatlog = {}     -- 기본 채팅창 출력
M.timers = {}
M.realm = "아즈샤라"
M.player = { name = "공대장", class = "WARRIOR" }
M.group = nil      -- { raid=true, members={ {name, rank, subgroup, class, online, dead, level, zone} } }
M.trade = { partner = nil, playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
M.registeredEvents = {}
M.frames = {}
M.loot = {}
M.auras = {}
M.calls = {}

M.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function noop() end

---------------------------------------------------------------------------
-- 기본 함수
---------------------------------------------------------------------------
_G.time = os.time
_G.date = os.date
_G.strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert = table.insert
_G.tremove = table.remove
_G.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
_G.GetTime = function() return M.clock end
_G.GetServerTime = function() return M.serverTime + math.floor(M.clock - 1000) end
_G.debugstack = nil
_G.issecretvalue = function(v) return v == M.SECRET end
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "string" then
        local orig = _G[a]
        _G[a] = function(...) local r = { orig(...) } b(...) return unpack(r) end
    else
        local orig = a[b]
        a[b] = function(...) local r = { orig(...) } c(...) return unpack(r) end
    end
end
_G.GetBuildInfo = function() return "1.60.1", "99999", "Nov 1 2026", 16001 end
_G.InCombatLockdown = function() return M.combat end
_G.GetMoney = function() return M.money end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.GetCursorPosition = function() return 500, 400 end
_G.GetScreenWidth = function() return 1920 end
_G.GetScreenHeight = function() return 1080 end
_G.PlaySound = noop
_G.SOUNDKIT = { RAID_WARNING = 8959, IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, READY_CHECK = 8960 }
_G.GetRealZoneText = function() return "오닉시아의 둥지" end
_G.GetInstanceInfo = function() return "오닉시아의 둥지", "raid", 9, "40인", 40, 0, false, 249 end
_G.GetNormalizedRealmName = function() return M.realm end
_G.GetRealmName = function() return M.realm end
_G.UNKNOWNOBJECT = "알 수 없음"
_G.ERR_TRADE_COMPLETE = "거래가 완료되었습니다."
_G.ERR_TRADE_CANCELLED = "거래가 취소되었습니다."
_G.ERR_TRADE_BAG_FULL = "가방이 가득 찼습니다."
_G.ERR_TRADE_TARGET_BAG_FULL = "상대방의 가방이 가득 찼습니다."
_G.ERR_TRADE_TOO_FAR = "거래하기에는 너무 멀리 있습니다."
_G.MAX_TRADE_ITEMS = 7
_G.TRADE_ENCHANT_SLOT = 7
_G.RANDOM_ROLL_RESULT = "%s|1이;가; 주사위를 굴려 %d|1이;가; 나왔습니다. (%d-%d)"
_G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "전사", PALADIN = "성기사", HUNTER = "사냥꾼", ROGUE = "도적", PRIEST = "사제", SHAMAN = "주술사", MAGE = "마법사", WARLOCK = "흑마법사", DRUID = "드루이드" }
_G.RAID_CLASS_COLORS = {}
for k in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
    _G.RAID_CLASS_COLORS[k] = { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
end
_G.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
_G.ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" } }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.STANDARD_TEXT_FONT = "Fonts\\2002.TTF"

---------------------------------------------------------------------------
-- 타이머
---------------------------------------------------------------------------
_G.C_Timer = {
    After = function(sec, fn) M.timers[#M.timers + 1] = { at = M.clock + sec, fn = fn } end,
    NewTicker = function(sec, fn)
        local t = { cancelled = false }
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled end
        local function schedule()
            M.timers[#M.timers + 1] = { at = M.clock + sec, fn = function()
                if not t.cancelled then fn(t) schedule() end
            end }
        end
        schedule()
        return t
    end,
}
_G.C_Timer.NewTimer = function(sec, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    M.timers[#M.timers + 1] = { at = M.clock + sec, fn = function() if not t.cancelled then fn(t) end end }
    return t
end

function M.Advance(dt)
    local target = M.clock + dt
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 100000 then error("timer loop") end
        table.sort(M.timers, function(a, b) return a.at < b.at end)
        local nextT = M.timers[1]
        if not nextT or nextT.at > target then break end
        table.remove(M.timers, 1)
        M.clock = nextT.at
        nextT.fn()
    end
    M.clock = target
end

---------------------------------------------------------------------------
-- 유닛 / 그룹
---------------------------------------------------------------------------
local function unitInfo(unit)
    if unit == "player" then return M.player end
    if unit == "NPC" then
        if M.trade.partner then return { name = M.trade.partner, class = M.trade.partnerClass or "MAGE" } end
        return nil
    end
    local idx = unit:match("^raid(%d+)$") or unit:match("^party(%d+)$")
    if idx and M.group then
        local i = tonumber(idx)
        if unit:match("^party") then i = i + 1 end
        return M.group.members[i]
    end
    return nil
end
M.UnitInfo = unitInfo

_G.UnitName = function(unit)
    local u = unitInfo(unit)
    if not u then return nil end
    if u.secret then return M.SECRET end
    local n, r = u.name:match("^([^%-]+)%-(.+)$")
    if n then return n, r end
    return u.name, nil
end
_G.UnitFullName = function(unit)
    local n, r = _G.UnitName(unit)
    if n and not r and unit == "player" then r = M.realm end
    return n, r
end
_G.UnitClass = function(unit)
    local u = unitInfo(unit)
    if not u then return nil end
    return _G.LOCALIZED_CLASS_NAMES_MALE[u.class] or u.class, u.class
end
_G.UnitGUID = function(unit)
    local u = unitInfo(unit)
    if not u then return nil end
    return "Player-0000-" .. (u.name:gsub("[^%w]", "")):sub(1, 8)
end
_G.UnitExists = function(unit) return unitInfo(unit) ~= nil end
_G.UnitLevel = function() return 60 end
_G.UnitIsConnected = function(unit) local u = unitInfo(unit) return u and u.online ~= false end
_G.UnitIsDeadOrGhost = function(unit) local u = unitInfo(unit) return u and u.dead or false end
_G.UnitIsAFK = function() return false end
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.UnitInRange = function() return true end
_G.IsInGroup = function() return M.group ~= nil end
_G.IsInRaid = function() return M.group ~= nil and M.group.raid end
_G.GetNumGroupMembers = function() return M.group and #M.group.members or 0 end
_G.UnitIsGroupLeader = function(unit)
    if not M.group then return false end
    if M.leaderSecret then return M.SECRET end
    if unit == "player" then return M.player.rank == 2 end
    local u = unitInfo(unit) or (function()
        for _, m in ipairs(M.group.members) do if m.name == unit then return m end end
    end)()
    return u and u.rank == 2 or false
end
_G.UnitIsGroupAssistant = function(unit)
    if not M.group then return false end
    if unit == "player" then return M.player.rank == 1 end
    local u = unitInfo(unit)
    return u and u.rank == 1 or false
end
_G.GetRaidRosterInfo = function(i)
    local m = M.group and M.group.members[i]
    if not m then return nil end
    return m.name, m.rank or 0, m.subgroup or 1, m.level or 60, _G.LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class,
        m.class, m.zone or "오닉시아의 둥지", m.online ~= false, m.dead or false, nil, nil, m.combatRole
end
_G.GetReadyCheckStatus = function(unit) local u = unitInfo(unit) return u and u.ready or nil end
_G.DoReadyCheck = function() M.calls[#M.calls + 1] = "DoReadyCheck" end
_G.SetRaidSubgroup = function(i, g)
    M.calls[#M.calls + 1] = "SetRaidSubgroup:" .. i .. ":" .. g
    local m = M.group.members[i]
    if m then m.subgroup = g end
end
_G.SwapRaidSubgroup = function(a, b)
    M.calls[#M.calls + 1] = "SwapRaidSubgroup:" .. a .. ":" .. b
    local ma, mb = M.group.members[a], M.group.members[b]
    ma.subgroup, mb.subgroup = mb.subgroup, ma.subgroup
end
_G.C_PartyInfo = {
    DoCountdown = function(sec) M.calls[#M.calls + 1] = "DoCountdown:" .. tostring(sec) end,
    InviteUnit = function(name) M.calls[#M.calls + 1] = "InviteUnit:" .. tostring(name) end,
    ConvertToRaid = function() M.calls[#M.calls + 1] = "ConvertToRaid" end,
}

-- 그룹 설정 헬퍼: members = { {name=, class=, subgroup=, rank=} }
function M.SetGroup(members, raid)
    if not members then M.group = nil return end
    M.group = { raid = raid ~= false, members = members }
    for _, m in ipairs(members) do
        if m.name == M.player.name then M.player.rank = m.rank or 0 end
    end
end

---------------------------------------------------------------------------
-- 거래
---------------------------------------------------------------------------
_G.GetPlayerTradeMoney = function() return M.trade.playerMoney or 0 end
_G.GetTargetTradeMoney = function() return M.trade.targetMoney or 0 end
local function itemInfo(list, slot)
    local it = list[slot]
    if not it then return nil end
    return it.name, it.icon or 134400, it.count or 1, it.quality or 4
end
_G.GetTradePlayerItemInfo = function(slot) return itemInfo(M.trade.playerItems, slot) end
_G.GetTradeTargetItemInfo = function(slot) return itemInfo(M.trade.targetItems, slot) end
_G.GetTradePlayerItemLink = function(slot) local it = M.trade.playerItems[slot] return it and it.link end
_G.GetTradeTargetItemLink = function(slot) local it = M.trade.targetItems[slot] return it and it.link end

function M.ItemLink(id, name)
    return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r"
end

---------------------------------------------------------------------------
-- 채팅 / 애드온 통신
---------------------------------------------------------------------------
_G.C_ChatInfo = {
    SendChatMessage = function(msg, chatType, _, target)
        if M.lockdown then error("ADDON_ACTION_BLOCKED") end
        if #msg > 255 then error("message too long") end
        M.sent[#M.sent + 1] = { msg = msg, chatType = chatType, target = target }
    end,
    SendAddonMessage = function(prefix, msg, chatType, target)
        if #msg > 255 then return 1 end
        M.addonSent[#M.addonSent + 1] = { prefix = prefix, msg = msg, chatType = chatType, target = target }
        return 0
    end,
    RegisterAddonMessagePrefix = function() return true end,
    InChatMessagingLockdown = function() return M.lockdown end,
}
_G.GetChannelList = function() return 1, "일반", false, 2, "거래", false, 4, "파티찾기", false end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.chatlog[#M.chatlog + 1] = msg end }
_G.RaidNotice_AddMessage = function(_, msg) M.calls[#M.calls + 1] = "Alert:" .. tostring(msg) end
_G.RaidWarningFrame = {}
_G.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.5, b = 0 } }
_G.ChatEdit_InsertLink = function() return false end

---------------------------------------------------------------------------
-- 아이템 / 오라 / 내구도 / 전리품
---------------------------------------------------------------------------
_G.C_Item = {
    GetItemInfo = function(link)
        if type(link) ~= "string" then return nil end
        local name = link:match("%[(.-)%]")
        return name, link, 4, 60, 60, "방어구", "판금", 1, "INVTYPE_CHEST", 134400
    end,
    GetItemIconByID = function() return 134400 end,
    GetItemQualityColor = function() return 0.64, 0.21, 0.93, "ffa335ee" end,
}
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i)
        local list = M.auras[unit]
        if list == "secret" then return M.SECRET end
        return list and list[i] or nil
    end,
}
_G.GetInventoryItemDurability = function(slot)
    if slot == 1 then return 50, 100 end
    if slot == 5 then return 100, 100 end
    return nil
end
_G.GetCursorInfo = function() return nil end
_G.ClearCursor = noop
_G.GetNumLootItems = function() return #M.loot end
_G.GetLootSlotLink = function(i) return M.loot[i] end

---------------------------------------------------------------------------
-- 프레임 (UI 스모크 테스트용 범용 모의 객체)
---------------------------------------------------------------------------
local FrameMT = {}
local frameMethods = {}

local function newObject(kind, name, parent)
    local o = setmetatable({
        __kind = kind, __name = name, __parent = parent, __shown = true, __scripts = {},
        __width = 100, __height = 20, __text = "", __attrs = {}, __children = {}, __points = {},
        __checked = false, __value = 0, __min = 0, __max = 1, __enabled = true, __alpha = 1, __level = 1,
    }, FrameMT)
    if parent and type(parent) == "table" and parent.__children then table.insert(parent.__children, o) end
    if name then _G[name] = o end
    M.frames[#M.frames + 1] = o
    return o
end
M.NewObject = newObject

FrameMT.__index = function(t, k)
    local m = frameMethods[k]
    if m then return m end
    if type(k) == "string" and k:match("^[A-Z]") then return noop end
    return nil
end

function frameMethods:RegisterEvent(e) M.registeredEvents[e] = self end
function frameMethods:UnregisterEvent(e) M.registeredEvents[e] = nil end
function frameMethods:UnregisterAllEvents() end
function frameMethods:SetScript(s, fn) self.__scripts[s] = fn end
function frameMethods:GetScript(s) return self.__scripts[s] end
function frameMethods:HookScript(s, fn)
    local old = self.__scripts[s]
    self.__scripts[s] = function(...) if old then old(...) end fn(...) end
end
function frameMethods:Show() self.__shown = true if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function frameMethods:Hide() self.__shown = false if self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function frameMethods:IsShown() return self.__shown end
function frameMethods:IsVisible() return self.__shown end
function frameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function frameMethods:SetWidth(w) self.__width = w end
function frameMethods:SetHeight(h) self.__height = h end
function frameMethods:SetSize(w, h) self.__width = w self.__height = h end
function frameMethods:GetWidth() return self.__width end
function frameMethods:GetHeight() return self.__height end
function frameMethods:GetSize() return self.__width, self.__height end
function frameMethods:GetLeft() return 0 end
function frameMethods:GetRight() return self.__width end
function frameMethods:GetTop() return self.__height end
function frameMethods:GetBottom() return 0 end
function frameMethods:GetCenter() return self.__width / 2, self.__height / 2 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:GetScale() return 1 end
function frameMethods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function frameMethods:GetNumPoints() return 1 end
function frameMethods:SetText(t) self.__text = t == nil and "" or tostring(t) end
function frameMethods:GetText() return self.__text end
function frameMethods:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function frameMethods:GetStringWidth() return #self.__text * 6 end
function frameMethods:GetUnboundedStringWidth() return #self.__text * 6 end
function frameMethods:GetStringHeight() return 12 end
function frameMethods:GetTextWidth() return #self.__text * 6 end
function frameMethods:GetNumber() return tonumber(self.__text) or 0 end
function frameMethods:SetNumber(n) self.__text = tostring(n) end
function frameMethods:SetChecked(v) self.__checked = v and true or false end
function frameMethods:GetChecked() return self.__checked end
function frameMethods:SetValue(v) self.__value = v if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v, true) end end
function frameMethods:GetValue() return self.__value end
function frameMethods:SetMinMaxValues(a, b) self.__min = a self.__max = b end
function frameMethods:GetMinMaxValues() return self.__min, self.__max end
function frameMethods:SetAttribute(k, v) self.__attrs[k] = v end
function frameMethods:GetAttribute(k) return self.__attrs[k] end
function frameMethods:GetName() return self.__name end
function frameMethods:GetParent() return self.__parent end
function frameMethods:SetParent(p) self.__parent = p end
function frameMethods:GetChildren() return unpack(self.__children) end
function frameMethods:GetNumChildren() return #self.__children end
function frameMethods:GetFrameLevel() return self.__level end
function frameMethods:SetFrameLevel(l) self.__level = l end
function frameMethods:GetAlpha() return self.__alpha end
function frameMethods:SetAlpha(a) self.__alpha = a end
function frameMethods:IsEnabled() return self.__enabled end
function frameMethods:Enable() self.__enabled = true end
function frameMethods:Disable() self.__enabled = false end
function frameMethods:SetEnabled(v) self.__enabled = v and true or false end
function frameMethods:IsMouseOver() return false end
function frameMethods:HasFocus() return false end
function frameMethods:GetObjectType() return self.__kind end
function frameMethods:IsObjectType(t) return self.__kind == t end
function frameMethods:GetVerticalScroll() return 0 end
function frameMethods:GetVerticalScrollRange() return 0 end
function frameMethods:GetHorizontalScroll() return 0 end
function frameMethods:GetCursorPosition() return 0 end
function frameMethods:IsMultiLine() return false end
function frameMethods:GetFont() return _G.STANDARD_TEXT_FONT, 12, "" end
function frameMethods:GetFontObject() return nil end
function frameMethods:GetTextColor() return 1, 1, 1, 1 end
function frameMethods:IsDragging() return false end
function frameMethods:GetID() return self.__id or 0 end
function frameMethods:SetID(i) self.__id = i end
function frameMethods:GetTexture() return self.__texture end
function frameMethods:SetTexture(t) self.__texture = t end
function frameMethods:GetMaxLetters() return 0 end
function frameMethods:GetScrollChild() return self.__scrollChild end
function frameMethods:SetScrollChild(c) self.__scrollChild = c end
function frameMethods:GetRegions() return end
function frameMethods:IsMouseEnabled() return true end
function frameMethods:GetFrameStrata() return "MEDIUM" end
function frameMethods:IsProtected() return false end
function frameMethods:IsForbidden() return false end
function frameMethods:CanChangeProtectedState() return not M.combat end
function frameMethods:CreateFontString(name) return newObject("FontString", name, self) end
function frameMethods:CreateTexture(name) return newObject("Texture", name, self) end
function frameMethods:CreateLine(name) return newObject("Line", name, self) end
function frameMethods:CreateAnimationGroup() return newObject("AnimationGroup", nil, self) end
function frameMethods:Click(button)
    if self.__scripts.PreClick then self.__scripts.PreClick(self, button or "LeftButton") end
    if self.__scripts.OnClick then self.__scripts.OnClick(self, button or "LeftButton", true) end
end

_G.CreateFrame = function(kind, name, parent, template)
    local f = newObject(kind, name, parent)
    f.__template = template
    if template and template:find("BackdropTemplate") then
        f.SetBackdrop = noop
        f.SetBackdropColor = noop
        f.SetBackdropBorderColor = noop
    end
    return f
end

_G.UIParent = newObject("Frame", "UIParent")
_G.UIParent.__width, _G.UIParent.__height = 1920, 1080
_G.Minimap = newObject("Frame", "Minimap")
_G.Minimap.__width, _G.Minimap.__height = 140, 140
_G.GameTooltip = newObject("GameTooltip", "GameTooltip")
_G.UIErrorsFrame = newObject("Frame", "UIErrorsFrame")
_G.WorldFrame = newObject("Frame", "WorldFrame")
_G.GameFontNormal = newObject("Font", "GameFontNormal")
_G.CreateFont = function(name) return newObject("Font", name) end
_G.BackdropTemplateMixin = {}

---------------------------------------------------------------------------
-- 애드온 로드
---------------------------------------------------------------------------
function M.LoadAddon(dir)
    local toc = io.open(dir .. "/BigRaidLeader.toc"):read("*a")
    local ns = {}
    local files = {}
    for line in toc:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = line
        end
    end
    for _, f in ipairs(files) do
        local path = dir .. "/" .. f:gsub("\\", "/")
        if path:match("%.lua$") then
            local chunk, err = loadfile(path)
            if not chunk then error("로드 실패 " .. path .. ": " .. tostring(err)) end
            chunk("BigRaidLeader", ns)
        end
    end
    M.files = files
    return ns
end

-- 등록된 이벤트 발생
function M.Fire(event, ...)
    local f = M.registeredEvents[event]
    if f and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
end

function M.Boot(dir)
    local ns = M.LoadAddon(dir)
    M.Fire("ADDON_LOADED", "BigRaidLeader")
    M.Fire("PLAYER_LOGIN")
    M.Fire("PLAYER_ENTERING_WORLD", true, false)
    return ns
end

function M.ClearSent()
    M.sent = {}
    M.addonSent = {}
    M.chatlog = {}
    M.calls = {}
end

return M
