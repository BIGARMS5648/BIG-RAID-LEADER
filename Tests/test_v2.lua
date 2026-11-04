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
