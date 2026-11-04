-- 공격대 운영 모듈 테스트 (공대원/편성/역할/준비/버프/야영지/지휘/공략/진행/전리품/동기화/모집)
local M = MOCK
local G = 10000

local function raid(n)
    local BRL = T.fresh({ group = T.raid(n) })
    BRL.Roster:Refresh()
    return BRL
end

T.test("공대원 목록 / 역할 집계 / 정렬 / 검색", function()
    local BRL = raid(20)
    local members = BRL.Roster:GetMembers()
    T.eq(#members, 20)
    local c = BRL.Roster:Counts()
    T.eq(c.total, 20)
    T.eq(c.byGroup[1], 5)
    T.eq(c.byGroup[4], 5)
    T.ok(c.HEALER > 0, "힐러 추정")
    local found = BRL.Roster:Sorted("name", "대원1")
    T.ok(#found >= 1, "검색")
    local byClass = BRL.Roster:Sorted("class")
    T.eq(byClass[1].class, "WARRIOR", "직업 정렬")
end)

T.test("역할 지정 + 부족 역할 경고", function()
    local BRL = raid(10)
    BRL.Session:Create({ raidKey = "BARROW_DEEPS" })
    for _, m in ipairs(BRL.Roster:GetMembers()) do BRL.Roles:SetMemberRole(m.key, "MELEE") end
    local warnings = BRL.Roster:Warnings(10)
    T.contains(warnings, "탱커 부족")
    T.contains(warnings, "힐러 부족")
    BRL.Roles:SetMemberRole("대원2-아즈샤라", "TANK")
    T.eq(BRL.Roster:Get("대원2-아즈샤라").role, "TANK")
end)

T.test("파티 편성: 현재 편성 복사 / 이동 / 가득 찬 파티 / 교체", function()
    local BRL = raid(10)
    local plan = BRL.Groups:FromCurrent()
    T.eq(#plan.groups[1], 5)
    T.eq(#plan.groups[2], 5)
    local ok, err = BRL.Groups:Move("대원2-아즈샤라", 2)
    T.no(ok, "가득 찬 파티")
    T.ok(err)
    T.ok(BRL.Groups:Move("대원2-아즈샤라", 2, "대원7-아즈샤라"), "교체")
    T.eq(BRL.Groups:Locate("대원2-아즈샤라"), 2)
    T.eq(BRL.Groups:Locate("대원7-아즈샤라"), 1)
    T.ok(BRL.Groups:Move("대원3-아즈샤라", 3))
    T.eq(BRL.Groups:Locate("대원3-아즈샤라"), 3)
    T.contains(BRL.Groups:OutputLines(), "3파티: 대원3")
end)

T.test("자동 편성 제안: 힐러 균등 / 고정 인원 유지 / 정원 5명", function()
    local BRL = raid(20)
    local roles = { "TANK", "TANK", "HEALER", "HEALER", "HEALER", "HEALER" }
    local members = BRL.Roster:GetMembers()
    for i, m in ipairs(members) do BRL.Roles:SetMemberRole(m.key, roles[i] or (i % 2 == 0 and "MELEE" or "RANGED")) end
    BRL.Groups:FromCurrent()
    BRL.Groups:SetPinned("대원20-아즈샤라", true)
    local plan = BRL.Groups:AutoSuggest()
    local comp = BRL.Groups:Composition(plan)
    for g = 1, 4 do
        T.ok(comp[g].total <= 5, "정원")
        T.eq(comp[g].HEALER, 1, g .. "파티 힐러 1명")
    end
    T.eq(BRL.Groups:Locate("대원20-아즈샤라", plan), 4, "고정 인원 유지")
    local total = 0
    for g = 1, 8 do total = total + #plan.groups[g] end
    T.eq(total, 20, "전원 배치")
end)

T.test("편성 적용: 단계별 이동 + 전투 중 차단", function()
    local BRL = raid(10)
    local plan = BRL.Groups:FromCurrent()
    plan.groups[1][2], plan.groups[2][1] = plan.groups[2][1], plan.groups[1][2]
    M.combat = true
    T.no(BRL.Groups:Apply(plan), "전투 중 적용 불가")
    M.combat = false
    T.ok(BRL.Groups:Apply(plan))
    M.Advance(10)
    T.no(BRL.Groups:IsApplying(), "적용 완료")
    local roster = BRL.API.GetGroupRoster()
    for _, m in ipairs(roster) do
        T.eq(m.subgroup, BRL.Groups:Locate(m.key, plan), m.key .. " 파티")
    end
end)

T.test("전술 임무 배정 / 중복 경고 / 순서표 / 교체 / 출력", function()
    local BRL = raid(10)
    T.ok(BRL.Roles:Assign("default", "MAIN_TANK", "대원2"))
    T.ok(BRL.Roles:Assign("default", "TANK_HEALER", "대원2"))
    local w = BRL.Roles:Validate("default")
    T.contains(w, "중복 배정")
    BRL.Roles:Unassign("default", "TANK_HEALER", "대원2-아즈샤라")
    BRL.Roles:AddToOrder("default", "INTERRUPT", "대원3")
    BRL.Roles:AddToOrder("default", "INTERRUPT", "대원4")
    BRL.Roles:AddToOrder("default", "INTERRUPT", "대원5", true)
    BRL.Roles:MoveInOrder("default", "INTERRUPT", 2, -1)
    T.eq(BRL.Roles:GetOrder("default", "INTERRUPT")[1], "대원4-아즈샤라")
    T.eq(BRL.Roles:ReplaceMember("default", "대원3-아즈샤라", "대원6"), 1)
    local duties = BRL.Roles:DutiesFor("default", "대원6-아즈샤라")
    T.contains(duties, "차단 순서 2번")
    local lines = BRL.Roles:OutputLines("default")
    T.contains(lines, "차단 순서: 1.대원4 → 2.대원6 / 예비: 대원5")
    T.ok(BRL.Roles:SaveTemplate("기본", "default"))
    BRL.Roles:ClearPlan("default")
    T.ok(BRL.Roles:LoadTemplate("기본", "default"))
    T.eq(#BRL.Roles:GetAssignees("default", "MAIN_TANK"), 1)
end)

T.test("준비 확인: 결과 수집 / 미응답 / 오프라인 / 전투 중 차단", function()
    local BRL = raid(5)
    M.group.members[5].online = false
    BRL.Roster:Refresh()
    M.combat = true
    T.no(BRL.Readiness:Start(), "전투 중 차단")
    M.combat = false
    T.ok(BRL.Readiness:Start())
    T.eq(M.calls[#M.calls], "DoReadyCheck")
    M.Fire("READY_CHECK", "공대장", 30)
    M.Fire("READY_CHECK_CONFIRM", "raid2", true)
    M.Fire("READY_CHECK_CONFIRM", "raid3", false)
    M.Fire("READY_CHECK_FINISHED")
    local s = BRL.Readiness:Summary()
    T.eq(s.ready, 2) T.eq(s.notready, 1) T.eq(s.noresponse, 1) T.eq(s.offline, 1)
    T.contains(BRL.Readiness:OutputLines(), "미응답: 대원4")
    local me
    for _, row in ipairs(BRL.Readiness:Rows()) do if row.key == BRL.playerKey then me = row end end
    T.eq(me.durability, 50, "내 내구도 최소값")
end)

T.test("버프 점검: 누락 / 야영지 대체 / 확인 불가 / 전투 중 차단 / 담당자", function()
    local BRL = raid(3)
    M.auras.raid1 = { { name = "신의 권능: 인내", spellId = 10938, expirationTime = M.clock + 1000 } }
    M.auras.raid2 = { { name = "Fishing Bowl", spellId = 999999, expirationTime = M.clock + 100 } }
    M.auras.raid3 = "secret"
    M.combat = true
    T.no(BRL.Buffs:Scan(), "전투 중 점검 불가")
    M.combat = false
    T.ok(BRL.Buffs:Scan())
    local missing, unknown = BRL.Buffs:Missing()
    T.eq(#unknown, 1, "Secret → 확인 불가")
    local kingsMissing = missing.KINGS or {}
    local raid2Missing = false
    for _, k in ipairs(kingsMissing) do if k == "대원2-아즈샤라" then raid2Missing = true end end
    T.no(raid2Missing, "어항 효과가 왕의 축복을 대체")
    local fortMissing = missing.FORTITUDE or {}
    T.eq(#fortMissing, 1, "인내 누락 1명(대원2)")
    T.ok(#BRL.Buffs:Expiring() >= 1, "곧 만료")
    T.ok(BRL.Buffs:AutoAssignProviders() >= 1)
    T.contains(BRL.Buffs:MissingLines(), "인내")
    -- 야영지 효과 확인
    BRL.Campsites:Verify()
    T.eq(BRL.Campsites:Status("FISHING_BOWL").appliedCount, 1)
    T.ok(BRL.Campsites:Set("FISHING_BOWL", "prepared", true))
    T.contains(BRL.Campsites:OutputLines(), "어항")
    -- 전멸 후 재도핑 점검 플래그
    M.Fire("ENCOUNTER_END", 1, "보스", 9, 20, 0)
    T.ok(BRL.Buffs.needsRecheck, "전멸 후 재점검 필요")
end)

T.test("지휘: 풀링(공식 카운트다운) / 취소 / 대체 카운트다운 / 휴식 / 저장 명령", function()
    local BRL = raid(10)
    T.ok(BRL.Command:Pull(10))
    T.eq(M.calls[#M.calls], "DoCountdown:10")
    T.ok(BRL.Command:CancelPull())
    T.eq(M.calls[#M.calls], "DoCountdown:0")
    -- 공식 API 없음 → 채팅 대체
    local saved = C_PartyInfo.DoCountdown
    C_PartyInfo.DoCountdown = nil
    M.ClearSent()
    T.ok(BRL.Command:Pull(6))
    M.Advance(7)
    local texts = {}
    for _, s in ipairs(M.sent) do texts[#texts + 1] = s.msg end
    T.contains(texts, "풀링 6초 전")
    T.contains(texts, "풀링!")
    C_PartyInfo.DoCountdown = saved
    M.combat = true
    T.no(BRL.Command:Pull(10), "전투 중 불가")
    M.combat = false
    T.ok(BRL.Command:BreakStart(2))
    T.ok(BRL.Command:BreakRemaining() > 100)
    T.ok(BRL.Command:SaveCommand("집결", "입구로 집결", "RAID"))
    M.ClearSent()
    T.ok(BRL.Command:RunCommand(1))
    M.Advance(1)
    T.eq(M.sent[1].msg, "입구로 집결")
end)

T.test("전술 메모 / 강조 / 개인 메모", function()
    local BRL = raid(10)
    T.eq(BRL.Command:MarkerName(8), "해골", "징표 바 이름")
    BRL.Command:SetNote("default", "tank", "★ 벽을 등지고\n일반 메모")
    T.contains(BRL.Command:FormatNote(BRL.Command:GetNote("default", "tank")), "|cffff5555★ 벽을 등지고|r")
    BRL.Command:SetNote(nil, "private", "개인 메모")
    T.eq(BRL.Command:GetNote(nil, "private"), "개인 메모")
end)

T.test("보스 공략: 기본 데이터 / 편집 우선 / 사용자 보스 / 배치도 / 타임라인", function()
    local BRL = raid(20)
    local list = BRL.BossPlans:List("HYJAL_SUMMIT")
    T.eq(#list, 13, "하이잘 정상 13")
    T.eq(#BRL.BossPlans:List("BARROW_DEEPS"), 8, "지하 심굴 8")
    local ony = BRL.BossPlans:Get("ONYXIAS_LAIR_1")
    T.eq(#ony.phases, 3)
    T.ok(BRL.BossPlans:Set("HYJAL_SUMMIT_2", "name", "테스트 보스"))
    T.eq(BRL.BossPlans:Get("HYJAL_SUMMIT_2").name, "테스트 보스")
    T.ok(BRL.BossPlans:Get("HYJAL_SUMMIT_2").verified, "편집 시 확인됨")
    local key = BRL.BossPlans:AddBoss("CUSTOM", "연습 허수아비")
    T.ok(key)
    T.eq(#BRL.BossPlans:List("CUSTOM"), 1)
    local tok = BRL.BossPlans:AddToken("ONYXIAS_LAIR_1", 1, "tank", "MT", 0.1, 0.1)
    T.ok(tok)
    T.ok(BRL.BossPlans:MoveToken("ONYXIAS_LAIR_1", 1, tok.id, 0.9, 0.9))
    T.contains(BRL.BossPlans:LayoutLines("ONYXIAS_LAIR_1", 1), "남동: MT")
    T.ok(BRL.BossPlans:ApplyLayoutTemplate("ONYXIAS_LAIR_1", 2, 1))
    T.ok(#BRL.BossPlans:GetLayout("ONYXIAS_LAIR_1", 2).tokens >= 5)
    BRL.BossPlans:StartTimer("ONYXIAS_LAIR_1")
    M.Advance(20)
    local up = BRL.BossPlans:Upcoming(2)
    T.eq(up[1].t, 90, "다음 예정 항목")
    BRL.BossPlans:NextPhase()
    T.eq(BRL.BossPlans.timer.phase, 2)
    BRL.BossPlans:StopTimer()
    T.contains(BRL.BossPlans:BriefingLines("ONYXIAS_LAIR_1"), "탱커:")
end)

T.test("보스 진행: ENCOUNTER 이벤트 자동 기록 + 미확인 이름 자동 갱신", function()
    local BRL = raid(20)
    local s = BRL.Session:Create({ raidKey = "HYJAL_SUMMIT" })
    BRL.RaidProgress:SetCurrentBoss("HYJAL_SUMMIT_1")
    M.Fire("ENCOUNTER_START", 3001, "고대 수호자 아라낙", 9, 20)
    M.Advance(65)
    M.Fire("ENCOUNTER_END", 3001, "고대 수호자 아라낙", 9, 20, 0)
    M.Fire("ENCOUNTER_START", 3001, "고대 수호자 아라낙", 9, 20)
    M.Advance(120)
    M.Fire("ENCOUNTER_END", 3001, "고대 수호자 아라낙", 9, 20, 1)
    local b = BRL.RaidProgress:Boss("HYJAL_SUMMIT_1")
    T.eq(b.attempts, 2) T.eq(b.wipes, 1) T.eq(b.kills, 1)
    T.eq(b.killTime, 120)
    T.eq(BRL.BossPlans:Get("HYJAL_SUMMIT_1").name, "고대 수호자 아라낙", "이름 자동 갱신")
    local sum = BRL.RaidProgress:Summary(s.id)
    T.eq(sum.killed, 1) T.eq(sum.total, 13) T.eq(sum.percent, 8)
    T.eq(sum.wipes, 1)
end)

T.test("모집: 진행 상황 / 문구 / 귓속말 지원자 / 중복 / 승인·거절·보류 / 채널 전송", function()
    local BRL = raid(5)
    BRL.Recruitment:SetField("raidKey", "BARROW_DEEPS")
    BRL.Recruitment:SetQuota("class", "MAGE", 3)
    local p = BRL.Recruitment:Progress()
    T.eq(p.size, 10)
    T.eq(p.have, 5)
    local msg = BRL.Recruitment:BuildMessage()
    T.contains(msg, "지하 심굴 10인 (5/10)")
    T.ok(BRL.Recruitment:Send("CHANNEL:4"))
    T.eq(M.sent[#M.sent].chatType, "CHANNEL")
    T.eq(M.sent[#M.sent].target, 4)
    T.ok(BRL.Recruitment:IsActive())
    M.Fire("CHAT_MSG_WHISPER", "회드 1 가능합니다", "지원자A-아즈샤라")
    M.Fire("CHAT_MSG_WHISPER", "안녕하세요 질문이 있어요 아이템 레벨 제한이 어떻게 되나요 궁금합니다 답장 부탁드려요 감사합니다 그럼", "잡담러-아즈샤라")
    M.Fire("CHAT_MSG_WHISPER", "법사 참", "지원자B-아즈샤라")
    M.Fire("CHAT_MSG_WHISPER", "1", "지원자A-아즈샤라")
    local apps = BRL.Recruitment:Applicants()
    T.eq(#apps, 2, "지원자 2명 (잡담 제외)")
    local a
    for _, x in ipairs(apps) do if x.key == "지원자A-아즈샤라" then a = x end end
    T.eq(a.class, "DRUID") T.eq(a.role, "HEALER")
    T.ok(a.duplicate, "중복 지원 표시")
    T.ok(BRL.Recruitment:Approve(a.key))
    T.eq(M.calls[#M.calls], "InviteUnit:지원자A-아즈샤라")
    T.ok(BRL.Recruitment:Hold("지원자B-아즈샤라"))
    T.ok(BRL.Recruitment:Reject("지원자B-아즈샤라", true))
    T.ok(BRL.Recruitment:CloseNotice("GUILD"))
    T.no(BRL.Recruitment:IsActive())
end)
