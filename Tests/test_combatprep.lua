-- 전투 준비 (도핑 점검) 테스트
local M = MOCK

local function setup()
    local BRL = T.fresh({ group = T.raid(5) })
    BRL.Roster:Refresh()
    BRL.acct.consumables.checkClassBuffs = false
    local now = M.clock
    M.auras = {
        raid1 = { { name = "포만감", spellId = 19709, expirationTime = now + 1800 }, { name = "거인의 영약", spellId = 17626, expirationTime = now + 7000 } },
        raid2 = { { name = "포만감", spellId = 19710, expirationTime = now + 1800 } },
        raid3 = { { name = "살쾡이의 비약", spellId = 17538, expirationTime = now + 3000 }, { name = "거인의 비약", spellId = 11405, expirationTime = now + 3000 } },
        raid4 = {},
        raid5 = "secret",
    }
    return BRL
end

local function names(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.member.short end
    table.sort(out)
    return table.concat(out, ",")
end

T.test("전투 준비: 음식/영약·비약 누락자 + 확인 불가 분리", function()
    local BRL = setup()
    local res = BRL.CombatPrep:Run()
    T.ok(res)
    T.eq(res.checked, 4)
    T.eq(names(res.noFood), "대원3,대원4", "음식 없음")
    T.eq(names(res.noMain), "대원2,대원4", "영약/비약 없음")
    T.eq(#res.unavailable, 1, "Secret → 확인 불가")
    T.eq(res.okCount, 1, "공대장만 완료")
    local lines = table.concat(BRL.CombatPrep:Lines(res), "\n")
    T.contains(lines, "음식 없음(2): 대원3, 대원4")
    T.contains(lines, "영약/비약 없음(2): 대원2, 대원4")
    T.contains(lines, "확인 불가(1): 대원5")
    T.ok(BRL.PrepReport.frame and BRL.PrepReport.frame:IsShown(), "결과 창")
end)

T.test("기준 변경: 영약 필수 / 비약 2개 이상", function()
    local BRL = setup()
    BRL.acct.consumables.mainMode = "flask"
    local res = BRL.CombatPrep:Run({ silent = true })
    T.eq(names(res.noMain), "대원2,대원3,대원4", "비약만 있으면 영약 누락")
    BRL.acct.consumables.mainMode = "elixir"
    BRL.acct.consumables.minElixirs = 2
    res = BRL.CombatPrep:Run({ silent = true })
    T.eq(names(res.noMain), "공대장,대원2,대원4", "비약 2개 기준")
    local row = BRL.CombatPrep:RowFor("대원3-아즈샤라")
    T.eq(row.elixirCount, 2)
    BRL.acct.consumables.mainMode = "none"
    BRL.acct.consumables.requireFood = false
    res = BRL.CombatPrep:Run({ silent = true })
    T.eq(res.okCount, 4, "점검 안 함")
end)

T.test("음식 버프 이름이 달라도 주문 ID로 인식 (예: 민첩성 증가)", function()
    local BRL = setup()
    M.auras.raid4 = { { name = "민첩성 증가", spellId = 18192, expirationTime = M.clock + 900 }, { name = "Flask of Supreme Power", spellId = 99999, expirationTime = M.clock + 7000 } }
    local res = BRL.CombatPrep:Run({ silent = true })
    local row = BRL.CombatPrep:RowFor("대원4-아즈샤라")
    T.ok(row.food, "주문 ID 음식")
    T.ok(row.flask, "영어 이름 키워드 영약")
    T.ok(row.ok)
    T.eq(names(res.noFood), "대원3")
end)

T.test("곧 만료되는 도핑 경고 / 누락으로 처리 옵션", function()
    local BRL = setup()
    M.auras.raid2 = { { name = "포만감", spellId = 19710, expirationTime = M.clock + 60 }, { name = "순수한 지혜의 영약", spellId = 17627, expirationTime = M.clock + 120 } }
    local res = BRL.CombatPrep:Run({ silent = true })
    local row = BRL.CombatPrep:RowFor("대원2-아즈샤라")
    T.ok(row.ok, "누락은 아님")
    T.eq(#row.expiring, 2, "음식/영약 만료 임박")
    T.eq(#res.expiring, 1)
    BRL.acct.consumables.expiringAsMissing = true
    BRL.CombatPrep:Run({ silent = true })
    row = BRL.CombatPrep:RowFor("대원2-아즈샤라")
    T.no(row.ok, "만료 임박도 누락 처리")
end)

T.test("필수 직업 버프도 함께 점검", function()
    local BRL = setup()
    BRL.acct.consumables.checkClassBuffs = true
    table.insert(M.auras.raid1, { name = "신의 권능: 인내", spellId = 10938, expirationTime = M.clock + 1800 })
    local res = BRL.CombatPrep:Run({ silent = true })
    T.ok(res.buffMissing.FORTITUDE, "인내 누락 목록")
    local leader = BRL.CombatPrep:RowFor(BRL.playerKey)
    local missingKeys = {}
    for _, b in ipairs(leader.buffsMissing) do missingKeys[#missingKeys + 1] = b.key end
    T.no(table.concat(missingKeys, ","):find("FORTITUDE"), "공대장은 인내 있음")
    T.contains(table.concat(BRL.CombatPrep:Lines(res), "\n"), "신의 권능: 인내")
end)

T.test("전투 중에는 점검하지 않음", function()
    local BRL = setup()
    M.combat = true
    local res, why = BRL.CombatPrep:Run({ silent = true })
    T.eq(res, nil)
    T.eq(why, "combat")
    M.combat = false
end)

T.test("공지 / 개별 귓속말 / 자동 공지·준비 확인 옵션", function()
    local BRL = setup()
    BRL.acct.consumables.autoAnnounce = true
    BRL.acct.consumables.withReadyCheck = true
    M.ClearSent()
    BRL.CombatPrep:Run({ silent = true })
    M.Advance(5)
    T.contains(M.calls, "DoReadyCheck", "준비 확인 함께 실행")
    local raidMsgs = {}
    for _, s in ipairs(M.sent) do if s.chatType == "RAID" then raidMsgs[#raidMsgs + 1] = s.msg end end
    T.contains(raidMsgs, "[BIG RAID LEADER 전투 준비]")
    M.ClearSent()
    local n = BRL.CombatPrep:WhisperMissing()
    M.Advance(5)
    T.eq(n, 3, "누락자 3명 (본인/확인 불가 제외)")
    local w = {}
    for _, s in ipairs(M.sent) do if s.chatType == "WHISPER" then w[#w + 1] = s.target .. ":" .. s.msg end end
    T.contains(w, "대원4-아즈샤라:[BRL 전투 준비] 필요: 음식, 영약/비약")
end)

T.test("버튼/단축키/명령어 + 준비 상태 화면 도핑 열", function()
    local BRL = setup()
    local before = #BRL.errors
    BigRaidLeader_Binding("PREP")
    T.ok(BRL.CombatPrep.last, "단축키")
    BRL.CombatPrep.last = nil
    SlashCmdList.BIGRAIDLEADER("전투준비")
    T.ok(BRL.CombatPrep.last, "명령어")
    BRL.UI:Open("ready")
    BRL.UI:Refresh()
    local list = BRL.UI.pages.ready.frame.panels.ready.list
    local doping
    for i, c in ipairs(list.columns) do if c.title == "도핑" then doping = i end end
    T.ok(doping, "도핑 열")
    local texts = {}
    for _, data in ipairs(list.data) do texts[#texts + 1] = list.columns[doping].render(data) end
    T.contains(texts, "음식")
    -- 결과 창 버튼 모두 클릭
    for _, f in ipairs(M.frames) do
        if f.__parent and f.__kind == "Button" and f.__scripts.OnClick then
            local p = f.__parent
            while p and p ~= BRL.PrepReport.frame do p = p.__parent end
            if p then f.__scripts.OnClick(f, "LeftButton") end
        end
    end
    M.Advance(5)
    BRL.UI:Open("dashboard")
    BRL.UI:Refresh()
    T.eq(#BRL.errors, before, "오류 없음")
end)
