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
