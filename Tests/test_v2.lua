-- v2.0 추가 기능 테스트: 자가 진단 / 세션 보관 / 거래 정보 패널 / 미수금 독촉·입찰 제한 /
-- 연속 경매 / 구매자 기록 / 풀링 판정 / 보스 준비 적용 / 전멸 복구 / HUD / 공유 문자열
local M = MOCK
local G = 10000

-- 경매 1건 낙찰 + 수금 (collected 만큼)
local function sellOne(BRL, winner, amount, collected, itemId)
    local auc = assert(BRL.Auctions:Add(M.ItemLink(itemId or 100, "아이템" .. (itemId or 100)), { startPrice = 1 }))
    BRL.Auctions:Start(auc.id)
    assert(BRL.Bids:Place(auc.id, winner, amount, "manual").accepted)
    local aw = assert(BRL.Auctions:ConfirmAward(auc.id))
    if collected and collected > 0 then
        local tr = assert(BRL.TradeJournal:AddManual({ partner = winner, received = collected, note = "수금", purpose = "auction_payment" }))
        assert(BRL.Payments:AllocateAuction(tr.id, aw.id, collected))
    end
    return aw, auc
end

-- 정산 확정 + 전원 지급 완료
local function settleAndPay(BRL, s)
    local st = assert(BRL.Settlement:Create(s.id))
    assert(BRL.Settlement:Finalize(st.id, { force = true }))
    for _, ob in ipairs(BRL.Settlement:Obligations(st.id)) do
        if ob.memberKey == BRL.playerKey then
            assert(BRL.Payments:PaySelf(ob.id))
        else
            local tr = assert(BRL.TradeJournal:AddManual({ partner = ob.name, given = ob.amount, note = "분배", purpose = "payout" }))
            assert(BRL.Payments:AllocatePayout(tr.id, ob.id, ob.amount))
        end
    end
    return st
end

T.test("자가 진단: 섹션/수준 집계, 문제 상황 감지, 복사 텍스트", function()
    local BRL = T.fresh({ group = T.raid(10) })
    local rep = BRL.Diagnostics:Run()
    T.ok(#rep.sections >= 6, "섹션 수")
    local text = BRL.Diagnostics:Text(rep)
    T.contains(text, "자가 진단")
    T.contains(text, "권한: 공격대장")
    T.contains(text, "백업 없음")
    -- 공대장이 아니면 주의
    M.player.rank = 0
    M.group.members[1].rank = 0
    M.group.members[2].rank = 2
    T.contains(BRL.Diagnostics:Text(), "공대장이 아님")
    M.player.rank = 2
    M.group.members[1].rank = 2
    M.group.members[2].rank = 0
    -- 자동 기록 꺼짐 / 확인 불가 거래 / 오류 기록
    BRL.acct.trade.autoRecord = false
    BRL:Error("테스트", "가짜 오류")
    rep = BRL.Diagnostics:Run()
    text = BRL.Diagnostics:Text(rep)
    T.contains(text, "자동 기록 꺼짐")
    T.contains(text, "가짜 오류")
    T.ok(rep.warnings >= 2)
    table.remove(BRL.errors) -- 테스트용 가짜 오류 정리
    BRL.acct.trade.autoRecord = true
    -- 읽기 전용 = 오류
    BRL.readOnlyData = true
    T.ok(BRL.Diagnostics:Run().errors >= 1, "읽기 전용 오류")
    BRL.readOnlyData = nil
    -- 표시 (복사 창)
    T.ok(BRL.Diagnostics:Show())
end)

T.test("세션 보관: 조건 검사 / 보관 / 목록 제외 / 체크섬 / 복원 원래 ID", function()
    local BRL = T.fresh({ group = T.raid(5) })
    local s1 = BRL.Session:Create({ name = "지난주 공격대" })
    local aw = sellOne(BRL, "대원2", 3000 * G, 3000 * G, 101)
    local st = settleAndPay(BRL, s1)
    local nTrades = #BRL.TradeJournal:Query({ includeCancelled = true, includeVoided = true })
    local ok, why = BRL.Archive:CanArchive(s1.id)
    T.no(ok, "활성 세션 보관 불가")
    T.contains(why, "활성")
    local s2 = BRL.Session:Create({ name = "이번주" })
    ok, why = BRL.Archive:CanArchive(s1.id)
    T.no(ok)
    T.contains(why, "종료되지 않은")
    M.group = nil
    T.ok(BRL.Session:Close(s1.id))
    T.ok(BRL.Archive:CanArchive(s1.id), "종료 + 정산 완료 → 보관 가능")
    -- 기간 기준: 아직 30일 안 됨
    T.eq(#BRL.Archive:Candidates(30), 0)
    T.eq(#BRL.Archive:Candidates(0), 1)
    local before = BRL.Ledger:Summary(s1.id)
    local entry = assert(BRL.Archive:ArchiveSession(s1.id))
    T.ok(entry.recordCount >= 8, "레코드 수 " .. entry.recordCount)
    T.eq(entry.summary.total, 3000 * G)
    T.eq(entry.summary.buyers["대원2-아즈샤라"].count, 1)
    T.no(BRL.Session:Get(s1.id), "세션 목록에서 빠짐")
    T.no(BRL.Auctions:GetAward(aw.id), "낙찰 기록 빠짐")
    T.no(BRL.Settlement:Get(st.id))
    T.ok(#BRL.TradeJournal:Query({ includeCancelled = true, includeVoided = true }) < nTrades, "거래 로그에서 빠짐")
    T.eq(#BRL.Migration:Validate(), 0, "보관 후 무결성")
    T.ok(BRL.Archive:Verify(s1.id))
    -- 손상 감지
    local a = BRL.Archive:Get(s1.id)
    local good = a.data
    a.data = good:sub(1, -3) .. "xx"
    T.no(BRL.Archive:Verify(s1.id), "체크섬 불일치")
    T.no(BRL.Archive:Restore(s1.id), "손상 시 복원 중단")
    a.data = good
    -- 복원
    T.ok(BRL.Archive:Restore(s1.id))
    T.ok(BRL.Session:Get(s1.id))
    T.ok(BRL.Auctions:GetAward(aw.id), "원래 ID 로 복원")
    T.eq(#BRL.TradeJournal:Query({ includeCancelled = true, includeVoided = true }), nTrades)
    local after = BRL.Ledger:Summary(s1.id)
    T.eq(after.balance, before.balance, "장부 잔액 동일")
    T.eq(after.collected, before.collected)
    T.eq(#BRL.Migration:Validate(), 0, "복원 후 무결성")
    T.no(BRL.Archive:Get(s1.id))
    -- 내보내기 문자열
    assert(BRL.Archive:ArchiveSession(s1.id))
    local str = BRL.Archive:Export(s1.id)
    local obj = assert(BRL.Serializer.Import(str, "archive"))
    T.eq(obj.data.id, s1.id)
    T.ok(BRL.Archive:Delete(s1.id))
    T.eq(#BRL.Archive:List(), 0)
    T.ok(s2)
end)

T.test("세션 보관: 미수금 / 교차 연결 세션은 보관 거부, 일괄 보관은 건너뜀", function()
    local BRL = T.fresh({ group = T.raid(5) })
    local s1 = BRL.Session:Create({ name = "미수금 세션" })
    sellOne(BRL, "대원2", 2000 * G, 500 * G, 102)
    local s2 = BRL.Session:Create({ name = "교차 세션" })
    local aw2 = sellOne(BRL, "대원3", 1000 * G, 0, 103)
    local s3 = BRL.Session:Create({ name = "세션3" })
    local aw3 = sellOne(BRL, "대원3", 1000 * G, 0, 104)
    -- 한 거래(2000)로 세션 2와 세션 3 낙찰을 함께 수금 → 교차 연결
    local tr = assert(BRL.TradeJournal:AddManual({ partner = "대원3", received = 2000 * G, note = "x", purpose = "auction_payment" }))
    assert(BRL.Payments:AllocateAuction(tr.id, aw2.id, 1000 * G))
    assert(BRL.Payments:AllocateAuction(tr.id, aw3.id, 1000 * G))
    T.eq(BRL.TradeJournal:Get(tr.id).sessionId, s2.id, "첫 연결 세션으로 이동")
    BRL.Session:Create({ name = "세션4" })
    M.group = nil
    BRL.Session:Close(s1.id)
    BRL.Session:Close(s2.id)
    local ok, why = BRL.Archive:CanArchive(s1.id)
    T.no(ok)
    T.contains(why, "미수금")
    ok, why = BRL.Archive:CanArchive(s2.id)
    T.no(ok)
    T.contains(why, "교차 연결")
    BRL.Session:Close(s3.id)
    ok, why = BRL.Archive:CanArchive(s3.id)
    T.no(ok, "반대쪽 세션도 거부")
    T.contains(why, "교차 연결")
    local done, skipped = BRL.Archive:ArchiveOld(0)
    T.eq(done, 0)
    T.eq(#skipped, 3)
    T.ok(BRL.Archive:ArchiveSession(s1.id, { force = true }), "강제 보관(미수금 무시)")
end)

T.test("거래 정보 패널: 미납 낙찰금 비교 / 분배금 입력(수락 안 함) / 보호 함수 실패 대체", function()
    local BRL = T.fresh({ group = T.raid(5) })
    local s = BRL.Session:Create({})
    sellOne(BRL, "대원2", 1500 * G, 0, 201)
    M.trade = { partner = "대원2", partnerClass = "PRIEST", playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    local f = BRL.TradeAssist.frame
    T.ok(f and f:IsShown(), "거래 창 열면 패널 표시")
    T.contains(f.body:GetText(), "미납 낙찰금")
    T.contains(f.body:GetText(), "아직 없음")
    M.trade.targetMoney = 1000 * G
    M.Fire("TRADE_MONEY_CHANGED")
    T.eq(BRL.TradeAssist.lastInfo.offerState, "short")
    T.contains(f.body:GetText(), "부족")
    M.trade.targetMoney = 1500 * G
    M.Fire("TRADE_MONEY_CHANGED")
    T.eq(BRL.TradeAssist.lastInfo.offerState, "match")
    T.contains(f.body:GetText(), "일치")
    T.no(f.fill:IsShown(), "분배금 없으면 입력 버튼 숨김")
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_CANCELLED)
    M.Fire("TRADE_CLOSED")
    M.Advance(5)
    T.no(f:IsShown(), "거래 끝나면 숨김")
    -- 분배금: 정산 확정 후
    local tr = assert(BRL.TradeJournal:AddManual({ partner = "대원2", received = 1500 * G, note = "x", purpose = "auction_payment" }))
    assert(BRL.Payments:ApplySuggestion(tr.id) >= 0)
    local aw = BRL.Auctions:Awards(s.id)[1]
    if BRL.Payments:AwardStatus(aw).outstanding > 0 then assert(BRL.Payments:AllocateAuction(tr.id, aw.id, 1500 * G)) end
    local st = assert(BRL.Settlement:Create(s.id))
    assert(BRL.Settlement:Finalize(st.id, { force = true }))
    M.trade = { partner = "대원3", partnerClass = "MAGE", playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    local info = BRL.TradeAssist.lastInfo
    T.eq(info.payout, 300 * G, "1500 / 5명")
    T.ok(f.fill:IsShown())
    T.ok(BRL.TradeAssist:FillPayout())
    T.eq(M.tradeMoneySet, 300 * G, "골드 칸 입력")
    M.Fire("TRADE_MONEY_CHANGED")
    T.eq(BRL.TradeAssist.lastInfo.giveState, "match")
    T.no(BRL.TradeTracker.current.playerAccepted, "자동 수락 안 함")
    -- 보호 함수로 막히면 직접 입력 안내
    M.protectedTradeMoney = true
    local ok, err = BRL.TradeAssist:FillPayout()
    T.no(ok)
    T.contains(err, "직접 입력")
    M.protectedTradeMoney = false
    -- 설정 끄면 표시 안 함
    BRL.acct.trade.assistPanel = false
    M.Fire("TRADE_MONEY_CHANGED")
    T.no(f:IsShown())
end)

T.test("미수금: 독촉 귓속말 / 60초 재전송 방지 / 입찰 제한", function()
    local BRL = T.fresh({ group = T.raid(5) })
    local s = BRL.Session:Create({})
    sellOne(BRL, "대원2", 2000 * G, 500 * G, 301)
    sellOne(BRL, "대원3", 900 * G, 0, 302)
    sellOne(BRL, "대원3", 700 * G, 0, 303)
    local debtors = BRL.Payments:Debtors(s.id)
    T.eq(#debtors, 2)
    T.eq(debtors[1].key, "대원3-아즈샤라", "금액 큰 순")
    T.eq(debtors[1].outstanding, 1600 * G)
    T.eq(#debtors[1].items, 2)
    M.Advance(20)
    M.ClearSent()
    local sent = BRL.Payments:SendDunning(s.id)
    T.eq(sent, 2)
    M.Advance(3)
    local whispers = 0
    for _, m in ipairs(M.sent) do
        if m.chatType == "WHISPER" then
            whispers = whispers + 1
            T.contains(m.msg, "미납 낙찰금")
        end
    end
    T.eq(whispers, 2)
    local again, skipped = BRL.Payments:SendDunning(s.id)
    T.eq(again, 0)
    T.eq(skipped, 2, "60초 안 재전송 방지")
    M.Advance(61)
    T.eq(BRL.Payments:SendDunning(s.id, { "대원2-아즈샤라" }), 1, "선택 독촉")
    -- 입찰 제한 (기본 꺼짐)
    local auc = assert(BRL.Auctions:Add(M.ItemLink(304, "새 아이템"), { startPrice = 1 }))
    BRL.Auctions:Start(auc.id)
    local bid = BRL.Bids:Place(auc.id, "대원3", 100 * G, "chat", { channel = "RAID" })
    T.ok(bid.accepted, "제한 꺼짐: 입찰 가능")
    BRL.acct.auction.bidLimitOutstanding = 1000 * G
    local bid2, why = BRL.Bids:Place(auc.id, "대원3", 200 * G, "chat", { channel = "RAID" })
    T.no(bid2.accepted, "미납 1600 ≥ 기준 1000 → 거부")
    T.contains(why, "입찰 제한")
    BRL.acct.auction.bidLimitOutstanding = 1550 * G
    local bid3 = BRL.Bids:Place(auc.id, "대원2", 300 * G, "chat", { channel = "RAID" })
    T.ok(bid3.accepted, "미납 1500 < 기준 1550 → 입찰 가능")
    local bid4 = BRL.Bids:Place(auc.id, "대원3", 400 * G, "manual", { ignoreLimit = true })
    T.ok(bid4.accepted, "공대장 예외 처리(ignoreLimit)")
end)

T.test("연속 경매: 낙찰/유찰 후 자동 시작, 취소, 전투 중 보류, 대기열 끝 공지", function()
    local BRL = T.fresh({ group = T.raid(5) })
    BRL.Session:Create({})
    local a1 = assert(BRL.Auctions:Add(M.ItemLink(401, "첫째"), { startPrice = 1 }))
    local a2 = assert(BRL.Auctions:Add(M.ItemLink(402, "둘째"), { startPrice = 1 }))
    local a3 = assert(BRL.Auctions:Add(M.ItemLink(403, "셋째"), { startPrice = 1 }))
    BRL.acct.auction.autoNext = true
    BRL.acct.auction.autoNextDelay = 5
    assert(BRL.Auctions:StartNext())
    T.eq(BRL.Auctions:GetActive().id, a1.id)
    BRL.Bids:Place(a1.id, "대원2", 100 * G, "manual")
    assert(BRL.Auctions:ConfirmAward(a1.id))
    T.ok(BRL.Auctions.autoNext, "다음 경매 예약")
    T.eq(BRL.Auctions:AutoNextRemaining(), 5)
    M.Advance(5.1)
    T.eq(BRL.Auctions:GetActive().id, a2.id, "자동 시작")
    -- 유찰 후 예약 → 수동 취소
    BRL.Auctions:MarkUnsold(a2.id)
    T.ok(BRL.Auctions.autoNext)
    T.ok(BRL.Auctions:CancelAutoNext())
    M.Advance(6)
    T.no(BRL.Auctions:GetActive(), "취소하면 시작 안 함")
    -- 전투 중이면 보류
    BRL.Auctions:ScheduleAutoNext()
    M.combat = true
    M.Advance(6)
    T.no(BRL.Auctions:GetActive(), "전투 중 보류")
    M.combat = false
    -- 수동 시작하면 예약 취소
    BRL.Auctions:ScheduleAutoNext()
    assert(BRL.Auctions:Start(a3.id))
    T.no(BRL.Auctions.autoNext)
    BRL.Auctions:MarkUnsold(a3.id)
    T.no(BRL.Auctions.autoNext, "대기열 끝")
    local found = false
    M.Advance(3)
    for _, m in ipairs(M.sent) do if m.msg:find("모두 끝났습니다") then found = true end end
    T.ok(found, "대기열 끝 공지")
end)

T.test("구매자 기록: 세션 합산 / 보관된 세션 포함 / 검색 / 미수금", function()
    local BRL = T.fresh({ group = T.raid(5) })
    local s1 = BRL.Session:Create({ name = "1주차" })
    sellOne(BRL, "대원2", 1000 * G, 1000 * G, 501)
    sellOne(BRL, "대원3", 3000 * G, 3000 * G, 502)
    local s2 = BRL.Session:Create({ name = "2주차" })
    sellOne(BRL, "대원2", 2500 * G, 1000 * G, 503)
    local list = BRL.Statistics:Buyers()
    T.eq(list[1].key, "대원2-아즈샤라", "총액 순 (3500)")
    T.eq(list[1].count, 2)
    T.eq(list[1].total, 3500 * G)
    T.eq(list[1].max, 2500 * G)
    T.eq(list[1].average, 1750 * G)
    T.eq(list[1].sessions, 2)
    T.eq(list[1].outstanding, 1500 * G)
    T.eq(#BRL.Statistics:Buyers("대원3"), 1, "검색")
    -- 1주차 보관 후에도 집계 유지
    M.group = nil
    local st = assert(BRL.Settlement:Create(s1.id))
    assert(BRL.Settlement:Finalize(st.id, { force = true }))
    for _, ob in ipairs(BRL.Settlement:Obligations(st.id)) do
        if ob.memberKey == BRL.playerKey then assert(BRL.Payments:PaySelf(ob.id)) else
            local tr = assert(BRL.TradeJournal:AddManual({ partner = ob.name, given = ob.amount, note = "분배", purpose = "payout" }))
            assert(BRL.Payments:AllocatePayout(tr.id, ob.id, ob.amount))
        end
    end
    BRL.Session:Close(s1.id)
    assert(BRL.Archive:ArchiveSession(s1.id))
    list = BRL.Statistics:Buyers()
    T.eq(list[1].total, 3500 * G, "보관된 세션 포함")
    T.eq(list[1].sessions, 2)
    local found
    for _, it in ipairs(list[1].items) do if it.session and it.session:find("보관") then found = true end end
    T.ok(found, "보관 표시")
    T.ok(s2)
end)

-- 10인: 공대장(전사) + 마법사/도적/사냥꾼/흑마/드루이드/성기사/주술사/전사/사제
local function fullBuffs(n, extra)
    local now = M.clock
    for i = 1, n do
        M.auras["raid" .. i] = { { name = "포만감", spellId = 19709, expirationTime = now + 1800 }, { name = "거인의 영약", spellId = 17626, expirationTime = now + 7000 } }
    end
    for unit, list in pairs(extra or {}) do
        for _, a in ipairs(list) do table.insert(M.auras[unit], a) end
    end
end

local function readyAll(n)
    M.Fire("READY_CHECK", "공대장", 30)
    for i = 2, n do M.Fire("READY_CHECK_CONFIRM", "raid" .. i, true) end
    M.Fire("READY_CHECK_FINISHED")
end

T.test("풀링 판정: 미실시 → 주의 / 준비·도핑 완료 → 가능 / 사망·준비 안 됨 → 보류 / 전투 중", function()
    local BRL = T.fresh({ group = T.raid(10) })
    BRL.Roster:Refresh()
    BRL.acct.consumables.checkClassBuffs = false
    local pc = BRL.CombatPrep:PullCheck()
    T.eq(pc.verdict, "caution")
    T.contains(table.concat(pc.reasons, ","), "준비 확인 미실시")
    T.contains(table.concat(pc.reasons, ","), "도핑 점검 안 함")
    T.contains(table.concat(pc.reasons, ","), "탱커 미지정")
    BRL.Roles:SetMemberRole("공대장-아즈샤라", "TANK")
    fullBuffs(10)
    BRL.CombatPrep:Run({ silent = true })
    readyAll(10)
    pc = BRL.CombatPrep:PullCheck()
    T.eq(pc.verdict, "go", table.concat(pc.reasons, ","))
    T.eq(pc.label, "풀링 가능")
    -- 사망자
    M.group.members[3].dead = true
    BRL.Roster:Refresh()
    pc = BRL.CombatPrep:PullCheck()
    T.eq(pc.verdict, "stop")
    T.eq(pc.reasons[1], "사망 1명", "보류 사유가 먼저")
    M.group.members[3].dead = false
    BRL.Roster:Refresh()
    -- 준비 안 됨
    M.Fire("READY_CHECK", "공대장", 30)
    M.Fire("READY_CHECK_CONFIRM", "raid2", false)
    M.Fire("READY_CHECK_FINISHED")
    T.eq(BRL.CombatPrep:PullCheck().verdict, "stop")
    -- 도핑 오래됨
    readyAll(10)
    M.serverTime = M.serverTime + 900
    pc = BRL.CombatPrep:PullCheck()
    T.eq(pc.verdict, "caution")
    T.contains(table.concat(pc.reasons, ","), "도핑 점검 15분 지남")
    M.combat = true
    T.eq(BRL.CombatPrep:PullCheck().label, "전투 중")
    M.combat = false
    -- 공지 줄 / 판정 보류 시 풀링 확인
    T.contains(BRL.CombatPrep:PullCheckLines()[1], "풀링 판정")
    M.group.members[3].dead = true
    BRL.Roster:Refresh()
    T.no(BRL.UIActions.PullWithCheck(10), "보류면 확인 창 먼저")
end)

T.test("전멸 복구: 전투 실패 → 전투 종료 후 사망자/영혼석/재버프/도핑 점검", function()
    local BRL = T.fresh({ group = T.raid(10) })
    BRL.Roster:Refresh()
    BRL.acct.consumables.checkClassBuffs = true
    fullBuffs(10, { raid3 = { { name = "영혼석 부활", spellId = 20707, expirationTime = M.clock + 1500 } },
        raid5 = { { name = "영혼석 부활", spellId = 20707, expirationTime = M.clock + 1500 } } })
    M.auras.raid4 = {}
    M.group.members[3].dead = true
    M.group.members[6].dead = true
    M.combat = true
    M.Fire("ENCOUNTER_END", 1084, "오닉시아", 9, 10, 0)
    T.ok(BRL.CombatPrep.pendingWipe, "전멸 기록")
    M.Advance(3)
    T.no(BRL.CombatPrep.last, "전투 중에는 점검 안 함")
    M.combat = false
    M.Fire("PLAYER_REGEN_ENABLED")
    M.Advance(2)
    local res = BRL.CombatPrep.last
    T.ok(res and res.wipe, "전투 종료 후 자동 점검")
    T.eq(#res.wipe.dead, 2)
    T.eq(#res.wipe.soulstones, 2)
    T.eq(#res.wipe.deadWithStone, 1)
    T.eq(res.wipe.deadWithStone[1].short, "대원3")
    T.ok(#res.wipe.rebuff >= 1, "재버프 필요")
    T.ok(#res.noFood >= 1, "도핑 누락 (대원4)")
    local text = table.concat(BRL.CombatPrep:WipeLines(), "\n")
    T.contains(text, "사망 2명")
    T.contains(text, "영혼석 부활 가능: 대원3")
    T.contains(text, "재버프 필요")
    T.ok(BRL.PrepReport.frame:IsShown())
    T.contains(BRL.PrepReport.frame.title:GetText(), "전멸 복구")
    -- 처치 성공은 복구 안 함 / 설정 끄면 안 함
    BRL.CombatPrep.last = nil
    M.Fire("ENCOUNTER_END", 1084, "오닉시아", 9, 10, 1)
    M.Advance(3)
    T.no(BRL.CombatPrep.last)
    BRL.acct.consumables.wipeRecovery = false
    M.Fire("ENCOUNTER_END", 1084, "오닉시아", 9, 10, 0)
    M.Advance(3)
    T.no(BRL.CombatPrep.last, "설정 끔")
end)

T.test("보스 준비 적용: 현재 보스 + 보스 편성 템플릿 + 화면이 활성 전술표를 따라감", function()
    local BRL = T.fresh({ group = T.raid(10) })
    BRL.Roster:Refresh()
    BRL.Session:Create({ raidKey = "ONYXIAS_LAIR" })
    local boss = BRL.BossPlans:List("ONYXIAS_LAIR")[1]
    T.ok(boss, "보스 데이터")
    local res = assert(BRL.BossPlans:ApplyPrep(boss.key))
    T.no(res.groupTemplate, "템플릿 없으면 불러오지 않음")
    T.contains(table.concat(BRL.BossPlans:PrepLines(res), "\n"), "보스 편성 템플릿 없음")
    BRL.Groups:FromCurrent()
    local ok, name = BRL.BossPlans:SaveGroupTemplate(boss.key)
    T.ok(ok)
    T.eq(name, "보스:" .. boss.name)
    BRL.Groups:Reset()
    BRL.Roles:Assign(boss.key, "MAIN_TANK", "대원9")
    res = assert(BRL.BossPlans:ApplyPrep(boss.key))
    T.eq(res.groupTemplate, "보스:" .. boss.name, "보스 편성 불러옴")
    T.ok(#BRL.Groups:GetPlan().groups[1] > 0, "편성 계획 채워짐")
    T.eq(res.duties, 1)
    T.eq(BRL.RaidProgress:GetCurrentBoss(), boss.key)
    T.eq(BRL.BossPlans:ActivePlanKey(), boss.key)
    BRL.UI:Open("roles")
    BRL.UI:Refresh()
    T.eq(BRL.UI.pages.roles.frame.planKey, boss.key, "전술표 화면이 보스를 따라감")
    BRL.UI:Open("command")
    BRL.UI:Refresh()
    T.eq(BRL.UI.pages.command.frame.planKey, boss.key, "지휘 화면도 따라감")
    BRL.UI:Open("buffs")
    BRL.UI:Refresh()
    T.eq(BRL.UI.pages.buffs.frame.bossKey, boss.key, "버프 화면도 따라감")
    BRL.UIActions.ApplyBossPrep(boss.key)
    T.ok(BRL.Dialogs, "확인 창")
    -- 공대장이 아니면 거부
    M.player.rank = 0
    M.group.members[1].rank = 0
    M.group.members[2].rank = 2
    T.no(BRL.BossPlans:ApplyPrep(boss.key))
end)

T.test("공유 문자열: 공략/편성/전술표/징표/메모/목표 구성 왕복, 손상·종류 오류 감지", function()
    local BRL = T.fresh({ group = T.raid(10) })
    BRL.Roster:Refresh()
    local boss = BRL.BossPlans:List("ONYXIAS_LAIR")[1]
    BRL.BossPlans:Set(boss.key, "summary", "공유 테스트 요약")
    BRL.BossPlans:AddTimelineEvent(boss.key, 30, "숨결 주의")
    local str = assert(BRL.Share:Export("boss", boss.key))
    T.contains(str, "BRL:share_boss:")
    BRL.BossPlans:ResetToDefault(boss.key)
    T.no(BRL.BossPlans:Get(boss.key).summary == "공유 테스트 요약")
    local payload, desc = BRL.Share:Preview(str)
    T.ok(payload, desc)
    T.contains(desc, "공략")
    T.ok(BRL.Share:Apply(payload))
    T.eq(BRL.BossPlans:Get(boss.key).summary, "공유 테스트 요약", "공략 복원")
    -- 다른 사람의 사용자 보스 → 새 사용자 보스로 추가
    local ck = BRL.BossPlans:AddBoss("CUSTOM", "친구 보스")
    local cstr = BRL.Share:Export("boss", ck)
    BRL.BossPlans:RemoveBoss(ck)
    local ok, newKey = BRL.Share:Apply((BRL.Share:Preview(cstr)))
    T.ok(ok)
    T.ok(newKey ~= ck and newKey:find("^CUSTOM_"), "새 키로 추가")
    T.eq(BRL.BossPlans:Get(newKey).name, "친구 보스")
    -- 전술표: 기본 → 보스 전술표로 가져오기
    BRL.Roles:Assign("default", "MAIN_TANK", "대원9")
    BRL.Roles:AddToOrder("default", "INTERRUPT", "대원3")
    local rstr = BRL.Share:Export("roles", "default")
    T.ok(BRL.Share:Apply(BRL.Share:Preview(rstr), boss.key))
    T.eq(BRL.Roles:GetAssignees(boss.key, "MAIN_TANK")[1].key, "대원9-아즈샤라")
    T.eq(BRL.Roles:GetOrder(boss.key, "INTERRUPT")[1], "대원3-아즈샤라")
    -- 편성
    BRL.Groups:FromCurrent()
    T.ok(BRL.Share:Apply((BRL.Share:Preview(BRL.Share:Export("groups")))))
    local found
    for _, n in ipairs(BRL.Groups:Templates()) do if n:find("^가져온 편성") then found = n end end
    T.ok(found, "가져온 편성 템플릿")
    -- 징표 / 메모 / 목표 구성
    BRL.Command:SetMarkerRule("default", 8, "target", "해골 먼저")
    T.ok(BRL.Share:Apply(BRL.Share:Preview(BRL.Share:Export("markers", "default")), boss.key))
    T.eq(BRL.Command:GetMarkerPlan(boss.key)[8].target, "해골 먼저")
    BRL.Command:SetNote("default", "shared", "★ 숨결 피하기")
    T.ok(BRL.Share:Apply(BRL.Share:Preview(BRL.Share:Export("notes", "default")), boss.key))
    T.eq(BRL.Command:GetNote(boss.key, "shared"), "★ 숨결 피하기")
    local t = BRL.Composition:Target(20)
    local classes = {}
    for k, v in pairs(t.classes) do classes[k] = v end
    classes.MAGE = 5
    BRL.Composition:SetTargetClasses(20, classes)
    local cstr2 = BRL.Share:Export("comp", 20)
    BRL.Composition:ResetTarget(20)
    T.ok(BRL.Share:Apply((BRL.Share:Preview(cstr2))))
    T.eq(BRL.Composition:Target(20).classes.MAGE, 5, "목표 구성 복원")
    -- 손상 / 종류 오류
    local bad = str:sub(1, -6) .. "AAAA="
    T.no(BRL.Share:Preview(bad), "손상 감지")
    local _, err = BRL.Share:Preview(BRL.Serializer.Export("settings", BRL.acct))
    T.contains(err, "공유 문자열이 아닙니다")
    -- 권한
    M.player.rank = 0
    M.group.members[1].rank = 0
    M.group.members[2].rank = 2
    T.no(BRL.Share:Apply(BRL.Share:Preview(rstr), "default"), "공대장 아님 → 거부")
end)

T.test("HUD: 표시/숨김, 경매·카운트·거래·풀링 판정 줄, 슬래시 명령", function()
    local BRL = T.fresh({ group = T.raid(5) })
    BRL.Roster:Refresh()
    BRL.Session:Create({})
    sellOne(BRL, "대원2", 900 * G, 0, 601)
    BRL.HUD:Show()
    T.ok(BRL.HUD:IsShown())
    T.ok(BRL.acct.hud.show, "설정 저장")
    local text = table.concat(BRL.HUD:Lines(), "\n")
    T.contains(text, "경매 없음")
    T.contains(text, "풀링:")
    T.contains(text, "미수")
    local auc = assert(BRL.Auctions:Add(M.ItemLink(602, "HUD템"), { startPrice = 1 }))
    BRL.Auctions:Start(auc.id)
    BRL.Bids:Place(auc.id, "대원3", 100 * G, "manual")
    text = table.concat(BRL.HUD:Lines(), "\n")
    T.contains(text, "HUD템")
    T.contains(text, "대원3")
    BRL.Auctions:StartCount()
    T.contains(table.concat(BRL.HUD:Lines(), "\n"), "카운트")
    M.trade = { partner = "대원2", partnerClass = "MAGE", playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    T.contains(table.concat(BRL.HUD:Lines(), "\n"), "거래: 대원2")
    M.Advance(1)
    T.contains(BRL.HUD.frame.body:GetText(), "거래: 대원2", "주기 갱신")
    BRL.HUD:Hide()
    T.no(BRL.HUD:IsShown())
    T.no(BRL.acct.hud.show)
    -- 슬래시 명령 (오류 없음)
    local before = #BRL.errors
    for _, c in ipairs({ "hud", "hud", "판정", "독촉", "복구", "진단", "추적", "보관", "보스준비" }) do SlashCmdList.BIGRAIDLEADER(c) end
    T.eq(#BRL.errors, before, "슬래시 오류 없음")
    BigRaidLeader_Binding("HUD")
    BigRaidLeader_Binding("PULLCHECK")
    T.eq(#BRL.errors, before)
end)
