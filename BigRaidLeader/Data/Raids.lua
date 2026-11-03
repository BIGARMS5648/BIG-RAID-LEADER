-- BIG RAID LEADER - 공격대 목록 (WoW: Forever 1단계, 2026-12-09 개방 예정)
-- 출처: 블리자드 개발자 Q&A/공개 정보를 인용한 2026년 10~11월 커뮤니티 자료.
-- 인원/우두머리 수는 여러 자료가 일치하나, 실제 클라이언트에서 재확인 필요 (verified=false).
local _, BRL = ...
BRL.Data = BRL.Data or {}

BRL.Data.Raids = {
    BARROW_DEEPS = {
        key = "BARROW_DEEPS",
        name = "지하 심굴",
        nameEn = "Barrow Deeps",
        aliases = { "지하 감옥", "지하심굴", "Barrow Deeps" },
        size = 10,
        bossCount = 8,
        order = 1,
        verified = false,
        note = "10인 공격대, 우두머리 8. 공식 우두머리 목록 미공개(비공식 명칭은 보스 공략에서 '미확인'으로 표시).",
    },
    HYJAL_SUMMIT = {
        key = "HYJAL_SUMMIT",
        name = "하이잘 정상",
        nameEn = "Hyjal Summit",
        aliases = { "하이잘", "Hyjal Summit" },
        size = 20,
        bossCount = 13,
        order = 2,
        verified = false,
        note = "포에버 신규 20인 공격대(불타는 성전 하이잘 정상과 다른 던전), 우두머리 13. 우두머리 명칭 미확인.",
    },
    ONYXIAS_LAIR = {
        key = "ONYXIAS_LAIR",
        name = "오닉시아의 둥지",
        nameEn = "Onyxia's Lair",
        aliases = { "오닉시아", "오닉", "Onyxia" },
        size = 40,
        bossCount = 1,
        order = 3,
        verified = false,
        note = "40인 공격대, 단일 우두머리. 공략은 오리지널 기준이며 포에버 변경 여부 확인 필요.",
    },
    CUSTOM = {
        key = "CUSTOM",
        name = "사용자 지정",
        nameEn = "Custom",
        aliases = {},
        size = 40,
        bossCount = 0,
        order = 99,
        verified = true,
        note = "직접 우두머리를 추가해 사용하는 공격대.",
    },
}

function BRL.Data.RaidList()
    local list = {}
    for _, r in pairs(BRL.Data.Raids) do list[#list + 1] = r end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

-- 인스턴스 이름으로 공격대 추정
function BRL.Data.FindRaidByName(name)
    if not name then return nil end
    for key, r in pairs(BRL.Data.Raids) do
        if r.name == name or r.nameEn == name then return key end
        for _, a in ipairs(r.aliases or {}) do if a == name then return key end end
    end
    return nil
end
