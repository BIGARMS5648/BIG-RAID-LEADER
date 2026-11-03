-- 23.4 운영 및 권한 테스트 + 40인 성능
local M = MOCK
local G = 10000

local function setRank(rank)
    M.player.rank = rank
    M.group.members[1].rank = rank
end

T.test("공대장: 경매/낙찰/정산 확정 가능", function()
    local BRL = T.fresh({ group = T.raid(10) })
    T.eq(BRL.Perm:GetRole(), "leader")
    local s = BRL.Session:Create({})
    T.ok(s)
    local auc = BRL.Auctions:Add(M.ItemLink(1, "템"))
    T.ok(auc)
    local st = BRL.Settlement:Create(s.id)
    T.ok(BRL.Settlement:Finalize(st.id, { force = true }))
end)

T.test("부공대장: 지휘 가능 / 경매·장부·정산 수정 차단 / 열람 가능", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local s = BRL.Session:Create({})
    local st = BRL.Settlement:Create(s.id)
    setRank(1)
    BRL.Roster:Refresh()
    T.eq(BRL.Perm:GetRole(), "assistant")
    T.ok(BRL.Perm:Can("raid.command"), "지휘 가능")
    T.ok(BRL.Command:Pull(10), "풀링 가능")
    T.ok(BRL.Readiness:Start(), "준비 확인 가능")
    T.no(BRL.Auctions:Add(M.ItemLink(2, "템2")), "경매 등록 차단")
    T.no(BRL.Settlement:Finalize(st.id, { force = true }), "정산 확정 차단")
    T.no(BRL.Ledger:AddManual(s.id, "income", "other_income", 100 * G, "x"), "장부 수정 차단")
    T.no(BRL.Roles:Assign("default", "MAIN_TANK", "대원2"), "전술 편집은 공대장")
    T.ok(BRL.Ledger:Summary(s.id), "열람 가능")
    T.ok(BRL.Perm:Can("raid.groups.apply"), "게임 허용 범위: 파티 이동")
end)

T.test("일반 공대원: 장부 수정 차단 / 내 거래 기록·개인 분류 가능", function()
    local BRL = T.fresh({ group = T.raid(10) })
    setRank(0)
    T.eq(BRL.Perm:GetRole(), "member")
    T.no(BRL.Session:Create({}), "세션 생성 차단")
    -- 내 거래는 자동 기록됨
    M.trade = { partner = "대원2", playerMoney = 0, targetMoney = 100 * G, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    M.Fire("TRADE_ACCEPT_UPDATE", 1, 0)
    M.money = M.money + 100 * G
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    M.Fire("TRADE_CLOSED")
    M.Advance(4)
    local tr = BRL.TradeJournal:Query({})[1]
    T.eq(tr.status, "completed", "공대원도 내 거래 기록")
    T.ok(BRL.TradeJournal:SetPurpose(tr.id, "personal", "개인"), "개인 분류 가능")
    T.no(BRL.TradeJournal:SetPurpose(tr.id, "auction_payment", "x"), "공대 목적 분류 차단")
    T.no(BRL.Ledger:AddManual(nil, "income", "other_income", 1, "x"))
    T.no(BRL.Command:Pull(10), "지휘 차단")
end)

T.test("공대장 변경 상황: 공대장 권한 이전 시 금융 수정 차단, 복귀 시 재개", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local s = BRL.Session:Create({})
    local auc = BRL.Auctions:Add(M.ItemLink(3, "템3"))
    setRank(0)
    M.group.members[2].rank = 2
    T.no(BRL.Auctions:Start(auc.id), "권한 이전 후 차단")
    setRank(2)
    M.group.members[2].rank = 0
    T.ok(BRL.Auctions:Start(auc.id), "복귀 후 가능")
    T.ok(s)
end)

T.test("다른 캐릭터가 만든 세션은 수정 불가", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local s = BRL.Session:Create({})
    s.owner = "다른캐릭-아즈샤라"
    T.no(BRL.Perm:CanEditSession(s))
end)

T.test("공격대 해산 후: 세션 소유자는 정산·지급 기록 가능", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local s = BRL.Session:Create({})
    local st = BRL.Settlement:Create(s.id)
    M.SetGroup(nil)
    T.eq(BRL.Perm:GetRole(), "solo")
    T.ok(BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 100))
    T.ok(BRL.Settlement:Finalize(st.id, { force = true }))
end)

T.test("권한 정보 확인 불가(Secret) → 민감 작업 차단, 거래 기록은 유지", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local s = BRL.Session:Create({})
    M.leaderSecret = true
    T.eq(BRL.Perm:GetRole(), "unknown")
    T.no(BRL.Auctions:Add(M.ItemLink(4, "템4")), "차단")
    local ok = BRL.Perm:CanEditSession(s)
    T.no(ok)
    M.leaderSecret = false
end)

T.test("전투 중 기능 제한: 편성 적용/준비 확인/풀링/버프 점검 차단, 거래 기록은 정상", function()
    local BRL = T.fresh({ group = T.raid(10) })
    BRL.Roster:Refresh()
    M.combat = true
    T.no(BRL.Groups:Apply(), "편성 적용")
    T.no(BRL.Readiness:Start(), "준비 확인")
    T.no(BRL.Command:Pull(10), "풀링")
    T.no(BRL.Buffs:Scan(), "버프 점검")
    T.no(BRL.API.InviteUnit("누군가"), "초대")
    M.trade = { partner = "대원3", playerMoney = 0, targetMoney = 10 * G, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    M.Fire("TRADE_ACCEPT_UPDATE", 0, 1)
    M.money = M.money + 10 * G
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    M.Fire("TRADE_CLOSED")
    M.Advance(4)
    T.eq(BRL.TradeJournal:Query({})[1].status, "completed", "전투 중에도 거래 기록")
    M.combat = false
end)

T.test("채팅 잠금 중 공지는 대기 후 전송", function()
    local BRL = T.fresh({ group = T.raid(10) })
    M.lockdown = true
    BRL.ChatOut:Send("잠금 공지", "RAID")
    M.Advance(3)
    T.eq(#M.sent, 0)
    M.lockdown = false
    M.Advance(3)
    T.eq(#M.sent, 1)
    T.eq(M.sent[1].msg, "잠금 공지")
end)

T.test("40인 공격대 성능 (로스터/버프/편성/정산/장부)", function()
    local BRL = T.fresh({ group = T.raid(40) })
    local s = BRL.Session:Create({ raidKey = "ONYXIAS_LAIR" })
    -- 경매 40건 + 거래 200건
    for i = 1, 40 do
        local auc = BRL.Auctions:Add(M.ItemLink(1000 + i, "아이템" .. i), { startPrice = 1, allowDuplicate = true })
        BRL.Auctions:Start(auc.id)
        BRL.Bids:Place(auc.id, "대원" .. ((i % 39) + 2), (100 + i) * G, "manual")
        BRL.Auctions:ConfirmAward(auc.id)
    end
    for i = 1, 200 do
        BRL.TradeJournal:AddManual({ partner = "대원" .. ((i % 39) + 2), received = 10 * G, note = "부하 테스트", purpose = "raid_income" })
    end
    local st = BRL.Settlement:Create(s.id)
    local t0 = os.clock()
    for _ = 1, 10 do BRL.Roster:Refresh() end
    local tRoster = (os.clock() - t0) / 10
    t0 = os.clock()
    for _ = 1, 10 do BRL.Settlement:Compute(st, "confirmed") end
    local tSettle = (os.clock() - t0) / 10
    t0 = os.clock()
    for _ = 1, 10 do BRL.Ledger:Summary(s.id) end
    local tLedger = (os.clock() - t0) / 10
    t0 = os.clock()
    BRL.Groups:AutoSuggest()
    local tGroups = os.clock() - t0
    t0 = os.clock()
    BRL.Buffs:Scan()
    local tBuffs = os.clock() - t0
    print(string.format("    로스터 %.2fms / 정산 %.2fms / 장부 %.2fms / 자동편성 %.2fms / 버프 %.2fms",
        tRoster * 1000, tSettle * 1000, tLedger * 1000, tGroups * 1000, tBuffs * 1000))
    T.ok(tRoster < 0.05 and tSettle < 0.1 and tLedger < 0.1 and tGroups < 0.1 and tBuffs < 0.1, "성능 기준 이내")
    T.eq(BRL.Settlement:Compute(st, "confirmed").headcount, 40)
end)
