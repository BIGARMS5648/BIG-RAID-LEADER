-- BIG RAID LEADER - 버프 / 도핑 / 포에버 야영지 효과 데이터
-- 버프 판별: 주문 ID(오리지널 기준) + 이름(한국어/영어) 키워드. 포에버 클라이언트에서 ID/이름이
-- 다를 수 있으므로 설정 > 버프 키워드에서 직접 보완할 수 있다. (실제 클라이언트 검증 필요)
local _, BRL = ...
BRL.Data = BRL.Data or {}

BRL.Data.ClassBuffs = {
    { key = "FORTITUDE", name = "인내(신의 권능: 인내)", provider = "PRIEST", group = "stamina",
      spellIds = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 }, keywords = { "인내", "Fortitude" } },
    { key = "SPIRIT", name = "천상의 정신", provider = "PRIEST", group = "spirit",
      spellIds = { 14752, 14818, 14819, 27841, 27681 }, keywords = { "천상의 정신", "정신력의 기원", "Divine Spirit", "Prayer of Spirit" } },
    { key = "SHADOW_PROT", name = "암흑 보호", provider = "PRIEST", group = "shadowres",
      spellIds = { 976, 10957, 10958, 27683 }, keywords = { "암흑 보호", "Shadow Protection" } },
    { key = "INTELLECT", name = "신비한 지능", provider = "MAGE", group = "intellect",
      spellIds = { 1459, 1460, 1461, 10156, 10157, 23028 }, keywords = { "신비한 지능", "신비한 총명함", "Arcane Intellect", "Arcane Brilliance" } },
    { key = "MOTW", name = "야생의 징표", provider = "DRUID", group = "allstats",
      spellIds = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 }, keywords = { "야생의 징표", "야생의 선물", "Mark of the Wild", "Gift of the Wild" } },
    { key = "KINGS", name = "왕의 축복", provider = "PALADIN", group = "kings",
      spellIds = { 20217, 25898 }, keywords = { "왕의 축복", "Blessing of Kings" } },
    { key = "MIGHT", name = "힘의 축복", provider = "PALADIN", group = "might",
      spellIds = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 }, keywords = { "힘의 축복", "Blessing of Might" } },
    { key = "WISDOM", name = "지혜의 축복", provider = "PALADIN", group = "wisdom",
      spellIds = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 }, keywords = { "지혜의 축복", "Blessing of Wisdom" } },
    { key = "SALVATION", name = "구원의 축복", provider = "PALADIN", group = "salvation",
      spellIds = { 1038, 25895 }, keywords = { "구원의 축복", "Blessing of Salvation" } },
    { key = "BATTLE_SHOUT", name = "전투의 외침", provider = "WARRIOR", group = "ap",
      spellIds = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, keywords = { "전투의 외침", "Battle Shout" } },
    { key = "TRUESHOT", name = "정조준 오라", provider = "HUNTER", group = "rangedap",
      spellIds = { 19506, 20905, 20906 }, keywords = { "정조준 오라", "Trueshot Aura" } },
}

-- 도핑(소모품) 판별: 이름 키워드 + 오리지널 주문 ID. 포에버 클라이언트에서 다를 수 있으며
-- 설정 > 버프 키워드 보완에서 이름을 추가할 수 있다. (물약은 사용 시 사라져 점검 불가 → 수동)
BRL.Data.ConsumableGroups = {
    { key = "FOOD", name = "음식 버프",
      keywords = { "포만감", "Well Fed" },
      -- 일부 음식은 '포만감'이 아닌 이름의 버프를 준다 (민첩성 증가, 마나 회복 등)
      spellIds = { 19705, 19706, 19708, 19709, 19710, 19711, 18192, 18194, 22730, 24799, 25661, 18125, 18141 } },
    { key = "FLASK", name = "영약",
      keywords = { "영약", "Flask" },
      spellIds = { 17626, 17627, 17628, 17629 } },
    { key = "ELIXIR", name = "비약",
      keywords = { "비약", "Elixir" },
      spellIds = { 17538, 17539, 11405, 11348, 11334, 3593, 11474, 26276, 21920, 17535, 17537, 11396, 11390, 11406 } },
    { key = "POTION", name = "전투 물약", manual = true },
    { key = "PROTECTION", name = "보호 물약", manual = true },
}

-- 준비 확인 수동 점검 항목 (API로 확인할 수 없는 항목)
BRL.Data.ReadyManualItems = {
    { key = "ENCHANT", name = "마법부여" },
    { key = "RESIST", name = "저항 장비" },
    { key = "REAGENT", name = "주요 시약" },
    { key = "AMMO", name = "탄약/직업 자원" },
    { key = "POTION", name = "전투 물약" },
    { key = "GEAR", name = "장비 착용" },
}

-- 포에버 야영지(캠핑) 시설. 각 시설 효과는 대응 직업 버프와 중복 적용되지 않음(대체 관계).
-- 출처: 2026년 10월 베타 기준 커뮤니티 가이드. 한글 명칭은 비공식 번역이며 수치는 변경될 수 있음.
BRL.Data.CampFacilities = {
    { key = "SHARPENING_WHEEL", name = "숫돌 바퀴", nameEn = "Sharpening Wheel", replaces = "STRENGTH_OF_EARTH",
      replacesName = "대지력 토템", effect = "힘 증가", keywords = { "Sharpening Wheel", "숫돌" } },
    { key = "FISHING_BOWL", name = "어항", nameEn = "Fishing Bowl", replaces = "KINGS",
      replacesName = "왕의 축복", effect = "모든 능력치 % 증가", keywords = { "Fishing Bowl", "Fish Bowl", "어항" } },
    { key = "MANA_WELL", name = "마나 우물", nameEn = "Mana Well", replaces = "WISDOM",
      replacesName = "지혜의 축복", effect = "5초당 마나 회복", keywords = { "Mana Well", "마나 우물" } },
    { key = "ENCHANTED_LUTE", name = "마법 류트", nameEn = "Enchanted Lute", replaces = "MOTW",
      replacesName = "야생의 징표", effect = "모든 능력치/저항 증가", keywords = { "Enchanted Lute", "류트" } },
    { key = "CAMP_CHAIR", name = "야영 의자", nameEn = "Camp Chair", replaces = "MOONKIN_AURA",
      replacesName = "달빛야수 오라", effect = "치명타 증가", keywords = { "Camp Chair", "의자" } },
    { key = "INCENSE_CANDLE", name = "향초", nameEn = "Incense Candle", replaces = "INTELLECT",
      replacesName = "신비한 지능", effect = "지능 증가", keywords = { "Incense Candle", "향초" } },
    { key = "FIRST_AID_KIT", name = "구급 상자", nameEn = "First Aid Kit", replaces = "FORTITUDE",
      replacesName = "신의 권능: 인내", effect = "체력 증가", keywords = { "First Aid Kit", "구급" } },
    { key = "FACTION_BANNER", name = "진영 깃발", nameEn = "Faction Banner", replaces = "SPIRIT",
      replacesName = "천상의 정신", effect = "정신력 증가", keywords = { "Faction Banner", "깃발" } },
}

BRL.Data.CampWelcomeKeywords = { "Welcoming Campfire", "환영의 모닥불", "모닥불" }

function BRL.Data.FindClassBuff(key)
    for _, b in ipairs(BRL.Data.ClassBuffs) do if b.key == key then return b end end
    return nil
end

function BRL.Data.FindCamp(key)
    for _, c in ipairs(BRL.Data.CampFacilities) do if c.key == key then return c end end
    return nil
end

-- 기본 필수 버프
BRL.Data.DefaultRequiredBuffs = { FORTITUDE = true, INTELLECT = true, MOTW = true, KINGS = true }

-- 영혼석(흑마법사) 오라 이름 키워드 - 전멸 복구 화면의 자가 부활 가능 인원 표시
BRL.Data.SoulstoneKeywords = { "영혼석", "Soulstone" }
