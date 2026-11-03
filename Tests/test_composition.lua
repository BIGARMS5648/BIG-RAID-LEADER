-- 구성 분석 / 추천 직업 테스트
local M = MOCK

local function members(list)
    -- list: { {class, role, subgroup} }, 첫 번째는 공대장(플레이어)
    local out = {}
    for i, x in ipairs(list) do
        out[i] = { name = i == 1 and M.player.name or ("대원" .. i), class = x[1], rank = i == 1 and 2 or 0, subgroup = x[3] or math.floor((i - 1) / 5) + 1 }
    end
    return out
end

local function setup(list)
    local BRL = T.fresh({ group = members(list) })
    BRL.Roster:Refresh()
    for i, x in ipairs(list) do
        local key = (i == 1 and M.player.name or ("대원" .. i)) .. "-아즈샤라"
        if x[2] then BRL.Roles:SetMemberRole(key, x[2]) end
    end
    BRL.Composition.cache = nil
    return BRL
end

local function item(a, key)
    for _, it in ipairs(a.eval.items) do if it.syn.key == key then return it end end
end

local function recClasses(a, n)
    local out = {}
    for i, r in ipairs(a.recommendations) do if i <= (n or 99) then out[#out + 1] = r.class end end
    return table.concat(out, ",")
end

T.test("공대장 혼자(20인 기준): 핵심 공격대 버프 없음 + 추천/남은 자리 계획", function()
    local BRL = T.fresh()
    BRL.Roster:Refresh()
    local a = BRL.Composition:Analyze(20, "roster")
    T.eq(a.state.total, 1)
    T.eq(item(a, "FORTITUDE").status, "missing")
    T.eq(item(a, "INTELLECT").status, "missing")
    T.eq(item(a, "MOTW").status, "missing")
    T.eq(item(a, "BATTLE_RES").status, "missing", "전투 부활 없음")
    T.ok(#a.recommendations >= 5, "추천 직업")
    T.eq(a.plan.open, 19, "남은 19자리")
    local planned = 0
    for _, n in pairs(a.plan.byClass) do planned = planned + n end
    T.eq(planned, 19)
    -- 계획대로 채우면 핵심(중요도 3) 항목은 모두 확보
    for _, it in ipairs(a.plan.final.items) do
        if it.syn.weight >= 3 then T.ok(it.status == "ok", it.syn.name .. " 계획 후 확보") end
    end
    T.contains(BRL.Composition:Lines(a), "없는 공격대 버프")
end)

T.test("최적 20인 구성: 핵심 시너지 모두 확보", function()
    local list = {
        { "WARRIOR", "TANK" }, { "WARRIOR", "TANK" }, { "WARRIOR", "MELEE" }, { "ROGUE", "MELEE" }, { "SHAMAN", "MELEE" },
        { "PRIEST", "HEALER" }, { "PRIEST", "HEALER" }, { "PALADIN", "HEALER" }, { "DRUID", "HEALER" }, { "SHAMAN", "HEALER" },
        { "ROGUE", "MELEE" }, { "PALADIN", "HEALER" }, { "DRUID", "MELEE" }, { "HUNTER", "RANGED" }, { "HUNTER", "RANGED" },
        { "MAGE", "RANGED" }, { "MAGE", "RANGED" }, { "WARLOCK", "RANGED" }, { "WARLOCK", "RANGED" }, { "PRIEST", "RANGED" },
    }
    local BRL = setup(list)
    local a = BRL.Composition:Analyze(20, "roster")
    T.eq(a.state.total, 20)
    for _, it in ipairs(a.eval.items) do
        if it.syn.weight >= 3 then T.eq(it.status, "ok", it.syn.name) end
    end
    T.eq(a.plan.open, 0)
end)

T.test("주술사 없는 근접 위주 구성 → 질풍의 토템 없음, 주술사 추천", function()
    local list = { { "WARRIOR", "TANK" }, { "WARRIOR", "MELEE" }, { "ROGUE", "MELEE" }, { "ROGUE", "MELEE" }, { "WARRIOR", "MELEE" },
        { "PRIEST", "HEALER" }, { "PALADIN", "HEALER" }, { "MAGE", "RANGED" }, { "DRUID", "HEALER" }, { "WARLOCK", "RANGED" } }
    local BRL = setup(list)
    local a = BRL.Composition:Analyze(20, "roster")
    T.eq(item(a, "WINDFURY").status, "missing")
    T.eq(item(a, "TREMOR").status, "missing", "진동의 토템 없음")
    T.contains(recClasses(a, 3), "SHAMAN", "상위 추천에 주술사")
    local sham
    for _, r in ipairs(a.recommendations) do if r.class == "SHAMAN" then sham = r end end
    local reasons = {}
    for _, x in ipairs(sham.reasons) do reasons[#reasons + 1] = x.syn.key end
    T.contains(table.concat(reasons, ","), "WINDFURY")
    T.contains(BRL.Composition:RecommendText(sham, 5), "주술사")
end)

T.test("파티 버프 필요 수는 수혜 인원에 비례 (근접 12명 → 질풍 3파티)", function()
    local list = { { "SHAMAN", "MELEE" }, { "SHAMAN", "HEALER" } }
    for _ = 1, 11 do list[#list + 1] = { "ROGUE", "MELEE" } end
    local BRL = setup(list)
    local a = BRL.Composition:Analyze(40, "roster")
    local wf = item(a, "WINDFURY")
    T.eq(wf.beneficiaries, 12)
    T.eq(wf.need, 3)
    T.eq(wf.have, 2)
    T.eq(wf.status, "partial")
end)

T.test("같은 주술사를 질풍/마나샘이 나눠 씀 (중요도 높은 질풍 우선)", function()
    local list = { { "SHAMAN", "MELEE" }, { "ROGUE", "MELEE" }, { "PRIEST", "HEALER" }, { "MAGE", "RANGED" } }
    local BRL = setup(list)
    local a = BRL.Composition:Analyze(20, "roster")
    T.eq(item(a, "WINDFURY").status, "ok")
    T.eq(item(a, "MANA_SPRING").status, "missing", "주술사 1명은 한 파티만 담당")
end)

T.test("사용 불가 직업 제외 → '직업 제한' 표시, 추천 제외", function()
    local BRL = setup({ { "WARRIOR", "TANK" }, { "ROGUE", "MELEE" } })
    T.ok(BRL.Composition:SetExcluded("SHAMAN", true))
    local a = BRL.Composition:Analyze(20, "roster")
    T.eq(item(a, "WINDFURY").status, "unavailable")
    T.eq(item(a, "TREMOR").status, "unavailable")
    T.no(recClasses(a):find("SHAMAN"), "주술사 추천 안 함")
    BRL.Composition:SetExcluded("SHAMAN", false)
end)

T.test("포에버 야영지 준비 시 대체 처리 (인내/축복)", function()
    local BRL = setup({ { "WARRIOR", "TANK" }, { "PALADIN", "HEALER" } })
    local a = BRL.Composition:Analyze(40, "roster")
    T.eq(item(a, "BLESSINGS").need, 4)
    T.eq(item(a, "FORTITUDE").status, "missing")
    BRL.Campsites:Set("FIRST_AID_KIT", "prepared", true)
    BRL.Campsites:Set("FISHING_BOWL", "prepared", true)
    BRL.Campsites:Set("MANA_WELL", "prepared", true)
    a = BRL.Composition:Analyze(40, "roster")
    T.eq(item(a, "FORTITUDE").status, "camp", "구급 상자가 인내 대체")
    T.eq(item(a, "BLESSINGS").need, 2, "어항/마나 우물 → 축복 2종 대체")
end)

T.test("지원자 포함 모드 (승인/대기)", function()
    local BRL = setup({ { "WARRIOR", "TANK" } })
    BRL.Recruitment:AddApplicant("사제지원", "신사 힐 1", "PRIEST", "HEALER")
    local roster = BRL.Composition:Analyze(20, "roster")
    T.eq(item(roster, "FORTITUDE").status, "missing")
    local all = BRL.Composition:Analyze(20, "all")
    T.eq(item(all, "FORTITUDE").status, "ok", "대기 지원자 포함")
    local approved = BRL.Composition:Analyze(20, "approved")
    T.eq(item(approved, "FORTITUDE").status, "missing", "승인 전에는 미포함")
    BRL.Recruitment:Approve("사제지원-아즈샤라")
    approved = BRL.Composition:Analyze(20, "approved")
    T.eq(item(approved, "FORTITUDE").status, "ok", "승인 후 포함")
end)

T.test("추천을 모집 정원에 반영 + 모집 문구 {recommend}", function()
    local BRL = setup({ { "WARRIOR", "TANK" }, { "WARRIOR", "MELEE" }, { "ROGUE", "MELEE" } })
    BRL.Recruitment:SetField("raidKey", "HYJAL_SUMMIT")
    local ok, a = BRL.Composition:ApplyToRecruitment(20, "roster")
    T.ok(ok)
    local cur = BRL.Recruitment:GetCurrent()
    local total = 0
    for c, q in pairs(cur.classQuotas) do total = total + q - (a.state.class[c] or 0) end
    T.eq(total, 17, "남은 17자리만큼 직업 정원")
    T.eq(cur.roleQuotas.HEALER, 5, "목표 역할 반영")
    local msg = BRL.Recruitment:BuildMessage()
    T.no(msg:find("{recommend}", 1, true), "치환됨")
    T.contains(msg, "우대:")
end)

T.test("목표 구성 편집/초기화", function()
    local BRL = setup({ { "WARRIOR", "TANK" } })
    local t = BRL.Composition:Target(20)
    T.eq(t.classes.WARRIOR, 3)
    local sum = 0
    for _, n in pairs(BRL.Composition:Target(40).classes) do sum = sum + n end
    T.eq(sum, 40, "40인 기본 구성 합계")
    T.ok(BRL.Composition:SetTargetClasses(20, { WARRIOR = 5, PRIEST = 3, PALADIN = 2, SHAMAN = 2, DRUID = 2, MAGE = 2, WARLOCK = 2, ROGUE = 1, HUNTER = 1 }))
    T.eq(BRL.Composition:Target(20).classes.WARRIOR, 5)
    T.ok(BRL.Composition:ResetTarget(20))
    T.eq(BRL.Composition:Target(20).classes.WARRIOR, 3)
end)

T.test("현재 파티 배치에서 빠진 파티 버프 표시", function()
    local list = {
        { "WARRIOR", "TANK", 1 }, { "ROGUE", "MELEE", 1 },
        { "ROGUE", "MELEE", 2 }, { "ROGUE", "MELEE", 2 }, { "MAGE", "RANGED", 3 },
    }
    local BRL = setup(list)
    local a = BRL.Composition:Analyze(20, "roster")
    local found = false
    for _, g in ipairs(a.partyGaps) do if g.group == 2 and g.syn.key == "BATTLE_SHOUT" then found = true end end
    T.ok(found, "2파티 전투의 외침 없음")
end)

T.test("권한: 공대원은 목표 구성/제외 직업 수정 불가", function()
    local BRL = setup({ { "WARRIOR", "TANK" }, { "PRIEST", "HEALER" } })
    M.player.rank = 0
    M.group.members[1].rank = 0
    M.group.members[2].rank = 2
    T.no(BRL.Composition:SetExcluded("MAGE", true))
    T.no(BRL.Composition:SetTargetClasses(20, {}))
    T.ok(BRL.Composition:Analyze(20, "roster"), "분석 열람은 가능")
end)

T.test("성능: 40인 기준 39자리 계획 + 캐시", function()
    local BRL = setup({ { "WARRIOR", "TANK" } })
    local t0 = os.clock()
    local a = BRL.Composition:Analyze(40, "roster")
    local t1 = os.clock() - t0
    T.eq(a.plan.open, 39)
    t0 = os.clock()
    for _ = 1, 50 do BRL.Composition:Analyze(40, "roster") end
    local t2 = (os.clock() - t0) / 50
    print(string.format("    40인 분석+계획 %.1fms / 캐시 재사용 %.2fms", t1 * 1000, t2 * 1000))
    T.ok(t1 < 0.5, "분석 시간")
    T.ok(t2 < t1, "캐시")
end)

T.test("UI: 모집 > 구성 분석 탭 / 버튼", function()
    local BRL = setup({ { "WARRIOR", "TANK" }, { "ROGUE", "MELEE" } })
    local before = #BRL.errors
    BRL.UI:Open("recruit")
    local page = BRL.UI.pages.recruit.frame
    page.tabs:Select("analysis")
    BRL.UI:Refresh()
    T.ok(#page.aList.data > 30, "시너지 목록")
    T.ok(#page.aRecs.data >= 3, "추천 목록")
    T.contains(page.aPlan:GetText(), "남은")
    page.aOnlyMissing:Click()
    BRL.UI:Refresh()
    for _, it in ipairs(page.aList.data) do T.ok(it.status == "missing" or it.status == "partial", "부족한 것만") end
    page.tabs:Select("recruit")
    BRL.UI:Refresh()
    T.contains(page.progress:GetText(), "추천 추가 직업")
    T.eq(#BRL.errors, before, "오류 없음")
end)
