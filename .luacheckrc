-- BIG RAID LEADER luacheck 설정 (WoW 클라이언트 Lua 5.1 환경)
std = "lua51"
max_line_length = false
codes = true
unused_args = false
self = false
exclude_files = { "Tests/**", "dist/**" }
ignore = {
    "212", -- unused argument
    "213", -- unused loop variable
    "432", -- shadowing upvalue argument (self in nested methods)
    "542", -- empty if branch
}
globals = {
    "BigRaidLeader", "BigRaidLeaderDB", "BigRaidLeader_ToggleUI", "BigRaidLeader_OnAddonCompartmentClick",
    "BigRaidLeader_Binding", "SlashCmdList", "SLASH_BIGRAIDLEADER1", "SLASH_BIGRAIDLEADER2", "SLASH_BIGRAIDLEADER3",
    "BINDING_HEADER_BIGRAIDLEADER", "BINDING_NAME_BRL_TOGGLE", "BINDING_NAME_BRL_READYCHECK", "BINDING_NAME_BRL_PULL",
    "BINDING_NAME_BRL_CANCELPULL", "BINDING_NAME_BRL_AUCTION", "BINDING_NAME_BRL_COMBATPREP", "UISpecialFrames",
}
read_globals = {
    -- Lua / WoW 확장
    "date", "time", "strtrim", "wipe", "tinsert", "tremove", "strsplit", "debugstack", "issecretvalue", "hooksecurefunc",
    -- 프레임/UI
    "CreateFrame", "UIParent", "Minimap", "GameTooltip", "UIErrorsFrame", "WorldFrame", "DEFAULT_CHAT_FRAME",
    "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo", "GameFontNormal", "GameFontHighlight", "STANDARD_TEXT_FONT",
    "BackdropTemplateMixin", "ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "ChatFrameUtil", "Settings", "SettingsPanel",
    "TradeFrameRecipientNameText", "GetCursorPosition", "GetScreenWidth", "GetScreenHeight", "IsShiftKeyDown",
    "IsControlKeyDown", "IsAltKeyDown", "PlaySound", "SOUNDKIT", "CLASS_ICON_TCOORDS", "RAID_CLASS_COLORS",
    "ITEM_QUALITY_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE", "UNKNOWNOBJECT",
    "AddonCompartmentFrame", "CloseDropDownMenus", "MenuUtil",
    -- API
    "GetTime", "GetServerTime", "GetBuildInfo", "InCombatLockdown", "GetMoney", "GetNormalizedRealmName", "GetRealmName",
    "GetRealZoneText", "GetInstanceInfo", "UnitName", "UnitFullName", "UnitClass", "UnitGUID", "UnitExists", "UnitLevel",
    "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsAFK", "UnitGroupRolesAssigned", "UnitInRange", "IsInGroup", "IsInRaid",
    "GetNumGroupMembers", "UnitIsGroupLeader", "UnitIsGroupAssistant", "GetRaidRosterInfo", "GetReadyCheckStatus",
    "DoReadyCheck", "SetRaidSubgroup", "SwapRaidSubgroup", "C_PartyInfo", "C_ChatInfo", "C_Timer", "C_Item", "C_UnitAuras",
    "C_AddOns", "GetAddOnMetadata", "SendChatMessage", "SendAddonMessage", "RegisterAddonMessagePrefix", "GetChannelList",
    "InviteUnit", "ConvertToRaid", "GetPlayerTradeMoney", "GetTargetTradeMoney", "GetTradePlayerItemInfo",
    "GetTradeTargetItemInfo", "GetTradePlayerItemLink", "GetTradeTargetItemLink", "MAX_TRADE_ITEMS", "TRADE_ENCHANT_SLOT",
    "ERR_TRADE_COMPLETE", "GetItemInfo", "GetItemIcon", "GetItemQualityColor", "GetCursorInfo", "ClearCursor",
    "GetNumLootItems", "GetLootSlotLink", "UnitBuff", "GetInventoryItemDurability", "RANDOM_ROLL_RESULT",
    "Ambiguate", "EJ_GetInstanceInfo", "EJ_GetEncounterInfoByIndex", "EJ_SelectInstance", "GetRaidTargetIndex",
}
