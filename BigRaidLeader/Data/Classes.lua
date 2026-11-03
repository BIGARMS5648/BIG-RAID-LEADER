-- BIG RAID LEADER - 직업 데이터 (포에버: 오리지널 9개 직업)
local _, BRL = ...
BRL.Data = BRL.Data or {}

local Classes = {
    WARRIOR = { name = "전사", color = "c79c6e", roles = { "TANK", "MELEE" }, defaultRole = "MELEE", order = 1 },
    PALADIN = { name = "성기사", color = "f58cba", roles = { "HEALER", "TANK", "MELEE" }, defaultRole = "HEALER", order = 2 },
    HUNTER = { name = "사냥꾼", color = "abd473", roles = { "RANGED" }, defaultRole = "RANGED", order = 3 },
    ROGUE = { name = "도적", color = "fff569", roles = { "MELEE" }, defaultRole = "MELEE", order = 4 },
    PRIEST = { name = "사제", color = "ffffff", roles = { "HEALER", "RANGED" }, defaultRole = "HEALER", order = 5 },
    SHAMAN = { name = "주술사", color = "0070de", roles = { "HEALER", "MELEE", "RANGED" }, defaultRole = "HEALER", order = 6 },
    MAGE = { name = "마법사", color = "69ccf0", roles = { "RANGED" }, defaultRole = "RANGED", order = 7 },
    WARLOCK = { name = "흑마법사", color = "9482c9", roles = { "RANGED" }, defaultRole = "RANGED", order = 8 },
    DRUID = { name = "드루이드", color = "ff7d0a", roles = { "HEALER", "TANK", "MELEE", "RANGED" }, defaultRole = "HEALER", order = 9 },
}
BRL.Data.Classes = Classes

BRL.Data.ClassOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

BRL.Data.Roles = { "TANK", "HEALER", "MELEE", "RANGED" }

-- 채팅 키워드 → 직업 (모집 귓속말 분석)
BRL.Data.ClassKeywords = {
    WARRIOR = { "전사", "전탱", "무전", "분전", "warrior", "war" },
    PALADIN = { "성기사", "기사", "신기", "보기", "징기", "paladin", "pala" },
    HUNTER = { "사냥꾼", "냥꾼", "hunter" },
    ROGUE = { "도적", "rogue" },
    PRIEST = { "사제", "신사", "암사", "priest" },
    SHAMAN = { "주술사", "술사", "복술", "고술", "정술", "shaman", "sham" },
    MAGE = { "마법사", "법사", "mage" },
    WARLOCK = { "흑마법사", "흑마", "warlock", "lock" },
    DRUID = { "드루이드", "드루", "회드", "야드", "조드", "곰드", "druid" },
}

BRL.Data.RoleKeywords = {
    TANK = { "탱", "tank" },
    HEALER = { "힐", "heal", "회드", "신사", "신기", "복술" },
    MELEE = { "근딜", "근접", "melee", "도적", "분전", "무전", "고술", "야드" },
    RANGED = { "원딜", "원거리", "ranged", "법사", "흑마", "냥꾼", "암사", "정술", "조드" },
}

function BRL.Data.ClassColor(class)
    local rc = _G.RAID_CLASS_COLORS and class and _G.RAID_CLASS_COLORS[class]
    if rc and rc.colorStr then return rc.colorStr end
    local c = class and Classes[class]
    return "ff" .. (c and c.color or "aaaaaa")
end

function BRL.Data.ClassColorRGB(class)
    local rc = _G.RAID_CLASS_COLORS and class and _G.RAID_CLASS_COLORS[class]
    if rc and rc.r then return rc.r, rc.g, rc.b end
    local hex = (class and Classes[class] and Classes[class].color) or "aaaaaa"
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function BRL.Data.ColorName(name, class)
    return "|c" .. BRL.Data.ClassColor(class) .. tostring(name or "?") .. "|r"
end

function BRL.Data.ClassName(class)
    return (class and Classes[class] and Classes[class].name) or class or "?"
end
