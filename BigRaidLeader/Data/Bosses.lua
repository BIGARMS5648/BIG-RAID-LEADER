-- BIG RAID LEADER - 우두머리 기본 데이터
-- 중요: 포에버 신규 공격대(지하 심굴/하이잘 정상)의 공식 우두머리 정보는 공개되지 않았다.
--  * verified=false 인 항목은 비공식/미확인 정보이며 화면에 "미확인"으로 표시된다.
--  * 공대장은 보스 공략 화면에서 이름/기술/전술을 직접 편집할 수 있다 (사용자 데이터가 기본 데이터보다 우선).
--  * 실제 전투 시작(ENCOUNTER_START) 시 게임이 알려주는 우두머리 이름으로 자동 갱신된다.
local _, BRL = ...
BRL.Data = BRL.Data or {}

local function placeholder(raidKey, idx, name, nameEn)
    return {
        key = raidKey .. "_" .. idx,
        raid = raidKey,
        order = idx,
        name = name or ("우두머리 " .. idx),
        nameEn = nameEn,
        verified = false,
        summary = "공식 공략 정보가 확인되지 않았습니다. 실제 공략 후 내용을 편집하세요.",
        abilities = {},
        phases = { { name = "1단계", text = "" } },
        tank = "", healer = "", dps = "",
        interrupts = {}, dispels = {}, cc = {}, dangers = {},
        formation = "",
        notes = "",
        loot = {},
        timeline = {},
    }
end

local Bosses = {}

-- 지하 심굴 (10인, 우두머리 8) - BlizzCon 시연/데이터마이닝 기반 비공식 명칭
local barrowNames = {
    { "Deepscar Matriarch" }, { "Khalith the Dreadspinner" }, { "Amethrax" }, { "Ravus and Darlissa" },
    { "Elder Tangleclaw" }, { "Well of Sorrow" }, { "Del'lynar Songwood" }, { "Sonya Darkhallow" },
}
for i, n in ipairs(barrowNames) do
    local b = placeholder("BARROW_DEEPS", i, n[1] .. " (미확인)", n[1])
    Bosses[b.key] = b
end

-- 하이잘 정상 (20인, 우두머리 13) - 명칭 미확인, 첫 우두머리는 고대 수호자로 알려짐
for i = 1, 13 do
    local b = placeholder("HYJAL_SUMMIT", i, i == 1 and "고대 수호자 (미확인)" or nil, i == 1 and "Ancient Guardian" or nil)
    Bosses[b.key] = b
end

-- 오닉시아의 둥지 (40인) - 오리지널 오닉시아 기준
Bosses.ONYXIAS_LAIR_1 = {
    key = "ONYXIAS_LAIR_1",
    raid = "ONYXIAS_LAIR",
    order = 1,
    name = "오닉시아",
    nameEn = "Onyxia",
    verified = false,
    summary = "오리지널 오닉시아 기준 3단계 전투. 포에버에서 수치/기술이 변경되었을 수 있으니 첫 공략 후 확인하세요.",
    abilities = {
        { name = "화염 숨결", text = "전방 원뿔 화염 피해. 탱커 외에는 정면에 서지 않는다.", type = "danger" },
        { name = "꼬리 후려치기", text = "후방 범위 넉백. 근접 딜러는 옆구리에서 공격.", type = "danger" },
        { name = "날개 치기", text = "전방 넉백 및 위협 수준 감소 가능. 탱커는 벽을 등지고 위협 수준 유지.", type = "tank" },
        { name = "화염구", text = "2단계 공중에서 무작위 대상에게 화염구. 산개 유지.", type = "raid" },
        { name = "깊은 숨결", text = "2단계에 방을 가로지르는 강력한 화염 숨결. 오닉시아 머리 방향 선상에서 즉시 이탈.", type = "danger" },
        { name = "새끼용 무리", text = "2·3단계 양쪽 동굴에서 새끼용 대량 등장. 담당 조가 광역 처리.", type = "add" },
        { name = "우렁찬 포효", text = "3단계 광역 공포. 공포 수호물/진동의 토템 활용, 바닥 균열(용암) 주의.", type = "raid" },
    },
    phases = {
        { name = "1단계 (100~65%)", text = "메인 탱커가 오닉시아를 둥지 안쪽 벽으로 돌려 세움. 딜러는 옆구리, 위협 수준 관리." },
        { name = "2단계 (65~40%)", text = "공중 단계. 원거리 딜러/힐러 산개, 깊은 숨결 회피, 근접/탱커는 새끼용 처리." },
        { name = "3단계 (40~0%)", text = "착지. 메인 탱커 즉시 위협 수준 확보, 공포 대응, 남은 새끼용 처리 후 전력 공격." },
    },
    tank = "1단계: 벽을 등지고 정면 유지, 날개 치기 대비 위협 수준 확보. 3단계 착지 직후 즉시 도발 준비. 보조 탱커는 새끼용 담당.",
    healer = "메인 탱커 집중 치유 배정. 2단계 화염구/깊은 숨결 피해 대비 전체 치유 담당 지정. 3단계 공포 해제/예방.",
    dps = "1단계 위협 수준 주의(초반 딜 자제). 2단계 원거리는 오닉시아, 근접은 새끼용. 정면/후방 금지.",
    interrupts = {},
    dispels = { "우렁찬 포효(공포) - 공포 수호물/진동의 토템" },
    cc = {},
    dangers = { "정면 화염 숨결", "후방 꼬리 후려치기", "깊은 숨결 직선", "3단계 용암 균열" },
    formation = "탱커: 둥지 안쪽 벽 / 근접: 양 옆구리 / 원거리·힐러: 입구 쪽 반원 산개 / 새끼용 담당: 양쪽 동굴 입구",
    notes = "화염 저항 장비가 있으면 유리. 위협 수준 감소 대비 탱커 교대 순서 지정.",
    loot = {},
    timeline = {
        { t = 0, text = "풀링 - 메인 탱커 위치 잡기", kind = "phase" },
        { t = 15, text = "딜 시작 신호 (위협 수준 확보 후)", kind = "note" },
        { t = 90, text = "65% 근접 시 2단계 대비 - 산개", kind = "phase" },
        { t = 240, text = "40% 근접 시 3단계 대비 - 공포 대응", kind = "phase" },
    },
}

BRL.Data.Bosses = Bosses

function BRL.Data.BossesForRaid(raidKey)
    local list = {}
    for _, b in pairs(Bosses) do
        if b.raid == raidKey then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end
