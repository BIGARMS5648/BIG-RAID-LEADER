-- BIG RAID LEADER - 공격대 구성 시너지 데이터 (구성 분석 / 추천 직업)
-- 기준: 오리지널(클래식) 60레벨 공격대 메타. 포에버에서 직업 기술/특성이 바뀌었을 수 있으므로
-- 목표 구성과 사용 불가 직업은 화면에서 직접 조정할 수 있다. 기술 명칭은 오리지널 한국어 기준.
--
-- providers : 제공 조건 { class = 직업, roles = {역할...}(nil=역할 무관), talent = 특성 필요 여부 }
-- need      : 공격대 규모별 필요 제공자 수 (party 분류는 수혜 파티 수로 자동 계산)
-- benefit   : 파티 버프 수혜 대상 { roles = {...}, classes = {...} }
-- camp      : 대체 가능한 포에버 야영지 시설 (준비되어 있으면 "야영지 대체"로 표시)
-- weight    : 중요도 (3=핵심, 2=중요, 1=있으면 좋음)
local _, BRL = ...
BRL.Data = BRL.Data or {}

local ALL = { roles = { "TANK", "HEALER", "MELEE", "RANGED" } }
local PHYSICAL = { roles = { "TANK", "MELEE" }, classes = { "HUNTER" } }
local MELEE = { roles = { "TANK", "MELEE" } }
local CASTER = { roles = { "HEALER", "RANGED" }, notClasses = { "HUNTER" } }

BRL.Data.SynergyCategories = {
    { key = "raidbuff", name = "공격대 버프" },
    { key = "partybuff", name = "파티 버프" },
    { key = "debuff", name = "보스 약화" },
    { key = "cooldown", name = "공격대 생존기" },
    { key = "utility", name = "유틸리티" },
}

BRL.Data.Synergies = {
    -- 공격대 버프
    { key = "FORTITUDE", name = "신의 권능: 인내", category = "raidbuff", weight = 3, camp = "FIRST_AID_KIT",
      providers = { { class = "PRIEST" } } },
    { key = "INTELLECT", name = "신비한 지능", category = "raidbuff", weight = 3, camp = "INCENSE_CANDLE",
      providers = { { class = "MAGE" } } },
    { key = "MOTW", name = "야생의 징표", category = "raidbuff", weight = 3, camp = "ENCHANTED_LUTE",
      providers = { { class = "DRUID" } } },
    { key = "BLESSINGS", name = "성기사 축복 (왕/힘/지혜/구원)", category = "raidbuff", weight = 3,
      need = { [10] = 1, [20] = 2, [40] = 4 }, campReduce = { "FISHING_BOWL", "MANA_WELL" },
      note = "상급 축복은 성기사 1명이 직업별로 1종씩 → 축복 종류만큼 성기사 필요",
      providers = { { class = "PALADIN" } } },
    { key = "SPIRIT", name = "천상의 정신", category = "raidbuff", weight = 1, camp = "FACTION_BANNER",
      providers = { { class = "PRIEST", roles = { "HEALER" }, talent = true } } },
    { key = "SHADOW_PROT", name = "암흑 보호", category = "raidbuff", weight = 1,
      providers = { { class = "PRIEST" } } },

    -- 파티 버프 (수혜자가 있는 파티마다 제공자 1명 필요)
    { key = "BATTLE_SHOUT", name = "전투의 외침", category = "partybuff", weight = 2, benefit = MELEE,
      providers = { { class = "WARRIOR" } } },
    { key = "WINDFURY", name = "질풍의 토템", category = "partybuff", weight = 3, benefit = MELEE,
      providers = { { class = "SHAMAN" } }, shareGroup = "SHAMAN_PARTY" },
    { key = "MANA_SPRING", name = "마나샘 토템", category = "partybuff", weight = 2, benefit = CASTER,
      providers = { { class = "SHAMAN" } }, shareGroup = "SHAMAN_PARTY" },
    { key = "STRENGTH_OF_EARTH", name = "대지력의 토템", category = "partybuff", weight = 1, benefit = MELEE, camp = "SHARPENING_WHEEL",
      providers = { { class = "SHAMAN" } } },
    { key = "LEADER_OF_PACK", name = "무리의 우두머리", category = "partybuff", weight = 2, benefit = PHYSICAL,
      providers = { { class = "DRUID", roles = { "TANK", "MELEE" }, talent = true } } },
    { key = "TRUESHOT", name = "정조준 오라", category = "partybuff", weight = 1, benefit = PHYSICAL,
      providers = { { class = "HUNTER", talent = true } } },
    { key = "MOONKIN_AURA", name = "달빛야수 오라", category = "partybuff", weight = 1, benefit = CASTER, camp = "CAMP_CHAIR",
      providers = { { class = "DRUID", roles = { "RANGED" }, talent = true } } },
    { key = "PALADIN_AURA", name = "성기사 오라 (헌신/집중/저항)", category = "partybuff", weight = 1, benefit = ALL,
      providers = { { class = "PALADIN" } } },
    { key = "BLOOD_PACT", name = "피의 서약 (임프)", category = "partybuff", weight = 1, benefit = ALL,
      providers = { { class = "WARLOCK" } } },
    { key = "VAMPIRIC_EMBRACE", name = "흡혈의 선물", category = "partybuff", weight = 1, benefit = ALL,
      providers = { { class = "PRIEST", roles = { "RANGED" }, talent = true } } },

    -- 보스 약화 효과
    { key = "SUNDER", name = "방어구 가르기", category = "debuff", weight = 3,
      providers = { { class = "WARRIOR" } } },
    { key = "CURSES", name = "흑마법사 저주 (무모함/원소/어둠)", category = "debuff", weight = 2,
      need = { [10] = 1, [20] = 2, [40] = 3 }, note = "흑마법사 1명이 대상 하나에 저주 1종만 유지",
      providers = { { class = "WARLOCK" } } },
    { key = "FAERIE_FIRE", name = "요정의 불꽃", category = "debuff", weight = 2,
      providers = { { class = "DRUID" } } },
    { key = "JUDGEMENT", name = "성기사 심판 (지혜/빛/성전사)", category = "debuff", weight = 2,
      providers = { { class = "PALADIN" } } },
    { key = "THUNDER_CLAP", name = "천둥벼락 / 사기의 외침", category = "debuff", weight = 2,
      providers = { { class = "WARRIOR", roles = { "TANK" } } } },
    { key = "FIRE_VULN", name = "화염 취약 (불태우기 연마)", category = "debuff", weight = 1,
      providers = { { class = "MAGE", talent = true } } },
    { key = "SHADOW_WEAVING", name = "암흑의 그물 (암흑 사제)", category = "debuff", weight = 1,
      providers = { { class = "PRIEST", roles = { "RANGED" }, talent = true } } },

    -- 공격대 생존기 / 재정비
    { key = "BATTLE_RES", name = "전투 부활 (환생)", category = "cooldown", weight = 3,
      need = { [10] = 1, [20] = 1, [40] = 2 }, providers = { { class = "DRUID" } } },
    { key = "SOULSTONE", name = "영혼석 (부활 대기)", category = "cooldown", weight = 2,
      providers = { { class = "WARLOCK" } } },
    { key = "INNERVATE", name = "정신 자극 (마나 회복)", category = "cooldown", weight = 2,
      need = { [10] = 1, [20] = 1, [40] = 2 }, providers = { { class = "DRUID" } } },
    { key = "MANA_TIDE", name = "마나 해일 토템", category = "cooldown", weight = 2,
      providers = { { class = "SHAMAN", roles = { "HEALER" }, talent = true } } },
    { key = "TREMOR", name = "진동의 토템 (공포 해제)", category = "cooldown", weight = 2,
      providers = { { class = "SHAMAN" } } },
    { key = "FEAR_WARD", name = "공포의 수호물", category = "cooldown", weight = 2,
      note = "오리지널은 드워프 사제 종족 기술", providers = { { class = "PRIEST" } } },
    { key = "TANK_CD", name = "탱커 생존기 (방패의 벽/최후의 저항)", category = "cooldown", weight = 3,
      need = { [10] = 1, [20] = 2, [40] = 3 }, providers = { { class = "WARRIOR", roles = { "TANK" } } } },
    { key = "AOE_TAUNT", name = "광역 도발 (도전의 외침/위협의 포효)", category = "cooldown", weight = 2,
      providers = { { class = "WARRIOR" }, { class = "DRUID", roles = { "TANK", "MELEE" } } } },
    { key = "DIVINE_INTERVENTION", name = "신의 중재 (전멸 복구)", category = "cooldown", weight = 1,
      providers = { { class = "PALADIN" } } },
    { key = "BOP", name = "보호의 축복 / 신의 축복", category = "cooldown", weight = 1,
      providers = { { class = "PALADIN" } } },
    { key = "TRANQUILITY", name = "평온 (공격대 치유)", category = "cooldown", weight = 1,
      providers = { { class = "DRUID", roles = { "HEALER" } } } },

    -- 유틸리티
    { key = "INTERRUPT", name = "주문 차단 (발차기/자루 공격/마법 차단/대지 충격)", category = "utility", weight = 2,
      need = { [10] = 2, [20] = 3, [40] = 5 },
      providers = { { class = "ROGUE" }, { class = "WARRIOR" }, { class = "MAGE" }, { class = "SHAMAN" } } },
    { key = "DECURSE", name = "저주 해제", category = "utility", weight = 2,
      need = { [10] = 1, [20] = 2, [40] = 3 }, providers = { { class = "MAGE" }, { class = "DRUID" } } },
    { key = "DISPEL", name = "마법 해제 (무효화/정화)", category = "utility", weight = 2,
      need = { [10] = 1, [20] = 2, [40] = 4 }, providers = { { class = "PRIEST" }, { class = "PALADIN" } } },
    { key = "CURE", name = "독/질병 해제", category = "utility", weight = 1,
      need = { [10] = 1, [20] = 2, [40] = 3 },
      providers = { { class = "SHAMAN" }, { class = "PALADIN" }, { class = "DRUID" }, { class = "PRIEST" } } },
    { key = "HEALTHSTONE", name = "생명석", category = "utility", weight = 1, providers = { { class = "WARLOCK" } } },
    { key = "SUMMON", name = "소환 의식", category = "utility", weight = 1, providers = { { class = "WARLOCK" } } },
    { key = "TRANQ_SHOT", name = "평정의 사격 (격노 해제)", category = "utility", weight = 1,
      need = { [10] = 1, [20] = 1, [40] = 2 }, providers = { { class = "HUNTER" } } },
    { key = "CC", name = "군중제어 (변이/덫/추방/속박 등)", category = "utility", weight = 1,
      need = { [10] = 2, [20] = 3, [40] = 4 },
      providers = { { class = "MAGE" }, { class = "HUNTER" }, { class = "WARLOCK" }, { class = "ROGUE" }, { class = "PRIEST" }, { class = "DRUID" } } },
}

-- 최적 직업 구성 (오리지널 메타 기준 기본값, 화면에서 수정 가능)
BRL.Data.TargetComposition = {
    [10] = {
        classes = { WARRIOR = 2, PRIEST = 1, PALADIN = 1, SHAMAN = 1, DRUID = 1, MAGE = 1, WARLOCK = 1, ROGUE = 1, HUNTER = 1 },
        roles = { TANK = 2, HEALER = 3, MELEE = 2, RANGED = 3 },
    },
    [20] = {
        classes = { WARRIOR = 3, PRIEST = 3, PALADIN = 2, SHAMAN = 2, DRUID = 2, MAGE = 2, WARLOCK = 2, ROGUE = 2, HUNTER = 2 },
        roles = { TANK = 2, HEALER = 5, MELEE = 6, RANGED = 7 },
    },
    [40] = {
        classes = { WARRIOR = 7, PRIEST = 6, PALADIN = 4, SHAMAN = 4, DRUID = 3, MAGE = 5, WARLOCK = 4, ROGUE = 4, HUNTER = 3 },
        roles = { TANK = 4, HEALER = 10, MELEE = 13, RANGED = 13 },
    },
}

function BRL.Data.FindSynergy(key)
    for _, s in ipairs(BRL.Data.Synergies) do if s.key == key then return s end end
    return nil
end
