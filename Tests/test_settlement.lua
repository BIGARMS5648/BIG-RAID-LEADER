-- 23.3 골드 정산 테스트 (+ 16.4 파티별 정산, 17 보고서)
local M = MOCK
local G = 10000

-- n인 공격대 + 실제 수금액 collected (코퍼) 를 가진 세션과 정산 생성
local function setup(n, collected, opts)
    opts = opts or {}
    local BRL = T.fresh({ group = T.raid(n) })
    local s = BRL.Session:Create({ name = n .. "인 정산", raidKey = opts.raidKey or "HYJAL_SUMMIT" })
    if collected and collected > 0 then
        local auc = assert(BRL.Auctions:Add(M.ItemLink(100, "정산용 아이템"), { startPrice = 1 }))
        BRL.Auctions:Start(auc.id)
        local bid = BRL.Bids:Place(auc.id, "대원2", opts.awardAmount or collected, "manual")
        assert(bid.accepted)
        local aw = assert(BRL.Auctions:ConfirmAward(auc.id))
        local tr = assert(BRL.TradeJournal:AddManual({ partner = "대원2", received = collected, note = "테스트 수금", purpose = "auction_payment" }))
        assert(BRL.Payments:AllocateAuction(tr.id, aw.id, collected))
    end
    local st = assert(BRL.Settlement:Create(s.id))
    return BRL, s, st
end

local function identity(r)
    return r.ledgerExpenses + r.operating + r.deductions + r.leaderFee + r.reserve + r.distributed + r.kept + r.carryOut
end

local function payTrade(name, amount)
    return assert(BRL.TradeJournal:AddManual({ partner = name, given = amount, note = "분배 지급", purpose = "payout" }))
end

T.test("1. 10인 정산 (균등)", function()
    local BRL, _, st = setup(10, 10000 * G)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.ok(r.valid, table.concat(r.errors, ","))
    T.eq(r.headcount, 10)
    T.eq(r.perPerson, 1000 * G)
    T.eq(r.remainder, 0)
    T.eq(identity(r), r.gross, "합계 항등식")
end)

T.test("2. 20인 정산 - 명세 예시 (120,000 / 운영비 4,000 / 1인 5,800)", function()
    local BRL, _, st = setup(20, 120000 * G)
    T.ok(BRL.Settlement:AddCost(st.id, "operatingCosts", "운영비", 4000 * G))
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.distributable, 116000 * G)
    T.eq(r.perPerson, 5800 * G)
    T.eq(identity(r), r.gross)
    local brief = table.concat(BRL.Reports:BuildBrief(st.id), "\n")
    T.contains(brief, "공격대: 하이잘 정상")
    T.contains(brief, "총 경매액: 120,000골드")
    T.contains(brief, "실제 수금: 120,000골드")
    T.contains(brief, "운영비: 4,000골드")
    T.contains(brief, "분배 가능: 116,000골드")
    T.contains(brief, "분배 인원: 20명")
    T.contains(brief, "1인당 분배: 5,800골드")
end)

T.test("3. 40인 정산 - 코퍼 단위 잔돈 정확", function()
    local BRL, _, st = setup(40, 1000001 * G + 23)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.headcount, 40)
    local total = 1000001 * G + 23
    T.eq(r.perPerson, math.floor(total / 40))
    T.eq(r.remainder, total - 40 * math.floor(total / 40))
    T.eq(identity(r), r.gross)
end)

T.test("4. 23인 정산 + 골드 단위 절사", function()
    local BRL, _, st = setup(23, 100000 * G)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.perPerson, 43478260, "코퍼 단위")
    T.eq(r.remainder, 20)
    BRL.Settlement:SetConfig(st.id, "rounding", 10000)
    r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.perPerson, 4347 * G, "골드 단위 절사")
    T.eq(r.remainder, 100000 * G - 23 * 4347 * G, "잔액")
    T.eq(identity(r), r.gross)
end)

T.test("5. 특정 인원 제외", function()
    local BRL, _, st = setup(10, 8000 * G)
    BRL.Settlement:SetParticipant(st.id, "대원9-아즈샤라", { include = false })
    BRL.Settlement:SetParticipant(st.id, "대원10-아즈샤라", { include = false })
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.headcount, 8)
    T.eq(r.excluded, 2)
    T.eq(r.perPerson, 1000 * G)
end)

T.test("6. 공대장 수수료 (5%)", function()
    local BRL, _, st = setup(10, 10000 * G)
    T.ok(BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 500))
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.leaderFee, 500 * G)
    T.eq(r.perPerson, 950 * G)
    T.eq(identity(r), r.gross)
end)

T.test("7. 추가 보상 (고정 / 역할 / 비율)", function()
    local BRL, _, st = setup(10, 10000 * G)
    BRL.Settlement:SetParticipant(st.id, "대원2-아즈샤라", { bonusFixed = 100 * G })
    BRL.Settlement:SetParticipant(st.id, "대원3-아즈샤라", { role = "TANK" })
    BRL.Settlement:SetConfig(st.id, "roleBonus.TANK", 50 * G)
    BRL.Settlement:SetParticipant(st.id, "대원4-아즈샤라", { bonusBp = 1000 }) -- +10% 지분
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.ok(r.valid)
    local byKey = {}
    for _, row in ipairs(r.rows) do byKey[row.key] = row end
    local pool = 10000 * G - 150 * G
    local W = 9 * 100 * 10000 + 100 * 11000
    T.eq(byKey["대원5-아즈샤라"].total, math.floor(pool * 1000000 / W))
    T.eq(byKey["대원4-아즈샤라"].total, math.floor(pool * 1100000 / W))
    T.eq(byKey["대원2-아즈샤라"].total, math.floor(pool * 1000000 / W) + 100 * G)
    T.eq(byKey["대원3-아즈샤라"].total, math.floor(pool * 1000000 / W) + 50 * G)
    T.eq(identity(r), r.gross)
    -- 수동 금액 지정
    BRL.Settlement:SetParticipant(st.id, "대원6-아즈샤라", { manualAmount = 500 * G })
    r = BRL.Settlement:Compute(st, "confirmed")
    for _, row in ipairs(r.rows) do byKey[row.key] = row end
    T.eq(byKey["대원6-아즈샤라"].total, 500 * G)
    T.eq(identity(r), r.gross)
end)

T.test("8. 운영비/기타 공제/예비금 + 장부 지출 반영", function()
    local BRL, s, st = setup(10, 10000 * G)
    BRL.Settlement:AddCost(st.id, "operatingCosts", "수리비", 300 * G)
    BRL.Settlement:AddCost(st.id, "deductions", "소모품", 200 * G)
    BRL.Settlement:SetConfig(st.id, "reserveFixed", 500 * G)
    BRL.Ledger:AddManual(s.id, "expense", "other_expense", 1000 * G, "공용 물약 구매")
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.distributable, 10000 * G - 300 * G - 200 * G - 500 * G - 1000 * G)
    T.eq(r.perPerson, 800 * G)
    T.eq(identity(r), r.gross)
end)

T.test("9. 0골드 정산", function()
    local BRL, _, st = setup(10, 0)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.ok(r.valid)
    T.eq(r.gross, 0) T.eq(r.perPerson, 0) T.eq(r.distributed, 0)
    local ok = BRL.Settlement:Finalize(st.id, { force = true })
    T.ok(ok, "0골드 확정 가능")
    T.eq(#BRL.Settlement:Obligations(st.id), 0, "0골드 의무 미생성")
end)

T.test("10. 부분 지급 / 지급 완료 / 중복 지급 방지(16)", function()
    local BRL, _, st = setup(10, 10000 * G)
    T.ok(BRL.Settlement:Finalize(st.id, { force = true }))
    local obs = BRL.Settlement:Obligations(st.id)
    T.eq(#obs, 10)
    local ob2
    for _, ob in ipairs(obs) do if ob.memberKey == "대원2-아즈샤라" then ob2 = ob end end
    local t1 = payTrade("대원2", 400 * G)
    T.ok(BRL.Payments:AllocatePayout(t1.id, ob2.id, 400 * G))
    T.eq(BRL.Payments:ObligationStatus(ob2).status, "partial")
    local res, err = BRL.Payments:AllocatePayout(t1.id, ob2.id, 1)
    T.no(res, "같은 거래 재연결 거부")
    -- 한 거래(1000)로 두 명(각 1000)을 모두 완료 처리할 수 없음
    local ob3, ob4
    for _, ob in ipairs(obs) do
        if ob.memberKey == "대원3-아즈샤라" then ob3 = ob end
        if ob.memberKey == "대원4-아즈샤라" then ob4 = ob end
    end
    local t2 = payTrade("대원3", 1000 * G)
    T.ok(BRL.Payments:AllocatePayout(t2.id, ob3.id, 1000 * G))
    res, err = BRL.Payments:AllocatePayout(t2.id, ob4.id, 1000 * G, { proxy = true })
    T.no(res, "이미 사용된 거래 금액 재사용 거부")
    T.contains(err, "미연결 지급 금액")
    local t3 = payTrade("대원2", 600 * G)
    T.ok(BRL.Payments:AllocatePayout(t3.id, ob2.id, 600 * G))
    T.eq(BRL.Payments:ObligationStatus(ob2).status, "paid")
end)

T.test("11. 수금 연결된 골드만 분배 (예상 정산·미수금 경고 없음)", function()
    local BRL, _, st = setup(10, 6000 * G, { awardAmount = 10000 * G })
    local r = BRL.Settlement:Compute(st)
    T.eq(r.gross, 6000 * G, "수금 연결되지 않은 낙찰금은 분배에 넣지 않음")
    T.eq(BRL.Settlement:Compute(st, "estimated").gross, 6000 * G, "예상 정산(전원 완납 가정) 없음")
    for _, w in ipairs(r.warnings) do T.no(w:find("미수", 1, true), "미수금 경고 없음") end
    for _, c in ipairs(BRL.Settlement:Validate(st.id)) do T.no(c.label:find("미수", 1, true), "미수금 검증 항목 없음") end
    T.ok(BRL.Settlement:Finalize(st.id), "미수금 때문에 확정이 막히지 않음")
    for _, l in ipairs(BRL.Reports:BuildBrief(st.id)) do T.no(l:find("미수", 1, true), "보고서에 미수금 줄 없음") end
end)

T.test("12. 미지급금 발생 - 종료 경고 후 기록 유지", function()
    local BRL, s, st = setup(10, 10000 * G)
    BRL.Settlement:Finalize(st.id, { force = true })
    local ok, why, issues = BRL.Settlement:Close(st.id)
    T.no(ok)
    T.eq(why, "issues")
    T.contains(issues, "미지급금")
    T.ok(BRL.Settlement:Close(st.id, true))
    T.eq(st.status, "closed_with_issues")
    T.eq(#BRL.Settlement:Obligations(st.id), 10, "기록 유지")
    T.eq(BRL.Ledger:Summary(s.id).unpaid, 10000 * G)
end)

T.test("13. 잔돈 발생 - 보관/이월/공대장 + 다음 정산 이월 사용", function()
    local BRL, _, st = setup(3, 1000 * G + 1)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.remainder, (1000 * G + 1) % 3)
    T.eq(r.kept, r.remainder, "기본: 잔돈 보관")
    BRL.Settlement:SetConfig(st.id, "remainderMode", "leader")
    r = BRL.Settlement:Compute(st, "confirmed")
    local leaderRow
    for _, row in ipairs(r.rows) do if row.key == "공대장-아즈샤라" then leaderRow = row end end
    T.eq(leaderRow.remainderAdd, r.remainder, "공대장 지급")
    T.eq(identity(r), r.gross)
    BRL.Settlement:SetConfig(st.id, "rounding", 10000)
    BRL.Settlement:SetConfig(st.id, "remainderMode", "carry")
    r = BRL.Settlement:Compute(st, "confirmed")
    T.eq(r.carryOut, 1000 * G + 1 - 3 * 333 * G, "이월")
    BRL.Settlement:Finalize(st.id, { force = true })
    -- 전원 지급
    for _, ob in ipairs(BRL.Settlement:Obligations(st.id)) do
        if ob.memberKey == BRL.playerKey then
            T.ok(BRL.Payments:PaySelf(ob.id))
        else
            local tr = payTrade(BRL.API.ShortName(ob.memberKey), ob.amount)
            T.ok(BRL.Payments:AllocatePayout(tr.id, ob.id, ob.amount))
        end
    end
    T.ok(BRL.Settlement:Close(st.id))
    T.eq(st.status, "completed")
    T.eq(BRL.char.carryover, r.carryOut, "이월 적용")
    -- 다음 세션 정산에서 이월 사용
    local s2 = BRL.Session:Create({ name = "다음 공격대" })
    local st2 = BRL.Settlement:Create(s2.id)
    local r2 = BRL.Settlement:Compute(st2, "confirmed")
    T.eq(r2.carryIn, r.carryOut, "이월 잔돈 포함")
    BRL.Settlement:Finalize(st2.id, { force = true })
    T.eq(BRL.char.carryover, 0, "이월 사용 후 차감")
end)

T.test("14. 음수 금액 방지", function()
    local BRL, _, st = setup(10, 1000 * G)
    T.no(BRL.Settlement:AddCost(st.id, "operatingCosts", "음수", -100), "음수 입력 거부")
    T.no(BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 20000), "100% 초과 거부")
    BRL.Settlement:AddCost(st.id, "operatingCosts", "과다", 2000 * G)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.no(r.valid, "공제 초과 시 무효")
    for _, row in ipairs(r.rows) do T.ok(row.total >= 0, "음수 분배 없음") end
    T.no(BRL.Settlement:Finalize(st.id, { force = true }), "확정 불가")
    T.eq(BRL.Money.Parse("-100"), nil, "음수 입력 파싱 거부")
end)

T.test("15. 큰 금액 처리 (900만 골드 / 40인)", function()
    local BRL, _, st = setup(40, 9000000 * G + 9999)
    BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 333)
    local r = BRL.Settlement:Compute(st, "confirmed")
    T.ok(r.valid)
    T.eq(identity(r), r.gross, "큰 금액 항등식")
    T.eq(r.leaderFee, math.floor((9000000 * G + 9999) * 333 / 10000))
end)

T.test("16b. 파티별 정산 (인원수가 다른 파티) + 대표 수령", function()
    local BRL, _, st = setup(23, 23000 * G)
    BRL.Settlement:Finalize(st.id, { force = true })
    local pay = BRL.Settlement:PaymentState(st.id)
    local counts = {}
    for g, p in pairs(pay.parties) do counts[g] = p.count end
    T.eq(counts[1], 5) T.eq(counts[5], 3, "5파티 3명")
    T.eq(pay.parties[5].total, 3 * 1000 * G)
    -- 5파티 대표(대원21)에게 파티 전체 금액을 한 번에 지급
    local tr = payTrade("대원21", 3000 * G)
    local obs = {}
    for _, row in ipairs(pay.rows) do if row.ob.subgroup == 5 then obs[#obs + 1] = row.ob end end
    for _, ob in ipairs(obs) do
        local res, err = BRL.Payments:AllocatePayout(tr.id, ob.id, ob.amount, { proxy = true })
        T.ok(res, tostring(err))
    end
    local res, err = BRL.Payments:AllocatePayout(tr.id, obs[1].id, 1, { proxy = true })
    T.no(res, "초과 연결 불가")
    pay = BRL.Settlement:PaymentState(st.id)
    T.eq(pay.parties[5].paidCount, 3)
    T.eq(pay.parties[5].remaining, 0)
    T.eq(pay.parties[1].unpaidCount, 5)
end)

T.test("17. 정산 기록 수정 (잠금 해제 → 재확정, 지급 기록 보존)", function()
    local BRL, _, st = setup(10, 10000 * G)
    BRL.Settlement:Finalize(st.id, { force = true })
    T.eq(st.version, 1)
    T.no(BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 500), "잠금 상태 수정 불가")
    local ob2
    for _, ob in ipairs(BRL.Settlement:Obligations(st.id)) do if ob.memberKey == "대원2-아즈샤라" then ob2 = ob end end
    local tr = payTrade("대원2", 1000 * G)
    BRL.Payments:AllocatePayout(tr.id, ob2.id, 1000 * G)
    T.no(BRL.Settlement:Unlock(st.id, ""), "사유 필수")
    T.ok(BRL.Settlement:Unlock(st.id, "수수료 추가"))
    T.ok(BRL.Settlement:SetConfig(st.id, "leaderFeeBp", 500))
    T.ok(BRL.Settlement:Finalize(st.id, { force = true }))
    T.eq(st.version, 2, "보고서 버전 갱신")
    T.eq(ob2.amount, 950 * G, "의무 금액 갱신")
    local s = BRL.Payments:ObligationStatus(ob2)
    T.eq(s.status, "check", "초과 지급 확인 필요")
    T.eq(s.over, 50 * G)
    T.eq(#BRL.Reports:History(st.id), 2, "버전별 보고서")
end)

T.test("18. 정산 장부 복구", function()
    local BRL, s, st = setup(10, 10000 * G)
    BRL.Settlement:Finalize(st.id, { force = true })
    local before = BRL.Ledger:Summary(s.id)
    T.ok(BRL.Migration:CreateBackup("정산 후"))
    for k in pairs(BRL.db.payouts) do BRL.db.payouts[k] = nil end
    T.eq(#BRL.Settlement:Obligations(st.id), 0)
    T.ok(BRL.Migration:RestoreBackup(1))
    T.eq(#BRL.Settlement:Obligations(st.id), 10)
    local after = BRL.Ledger:Summary(s.id)
    T.eq(after.payoutPlanned, before.payoutPlanned)
    T.eq(#BRL.Migration:Validate(), 0)
end)

T.test("19. 보고서 합계 검증 + 정산 완료 검증 + 채팅 분할", function()
    local BRL, s, st = setup(20, 120000 * G)
    BRL.Settlement:AddCost(st.id, "operatingCosts", "운영비", 4000 * G)
    BRL.Settlement:Finalize(st.id, { force = true })
    for _, ob in ipairs(BRL.Settlement:Obligations(st.id)) do
        if ob.memberKey == BRL.playerKey then BRL.Payments:PaySelf(ob.id)
        else
            local tr = payTrade(BRL.API.ShortName(ob.memberKey), ob.amount)
            assert(BRL.Payments:AllocatePayout(tr.id, ob.id, ob.amount))
        end
    end
    local checks = BRL.Settlement:Validate(st.id)
    for _, c in ipairs(checks) do T.ok(c.ok, c.label .. " - " .. tostring(c.detail)) end
    T.eq(BRL.Ledger:Summary(s.id).balance, 4000 * G, "운영비만 잔액으로 남음")
    T.ok(BRL.Settlement:Close(st.id))
    local brief = BRL.Reports:BuildBrief(st.id)
    T.contains(brief, "미지급: 0골드")
    T.contains(brief, "정산 상태: 완료")
    local detailed = BRL.Reports:BuildDetailed(st.id)
    T.contains(detailed, "[파티별 지급액]")
    T.contains(detailed, "미지급 총액: 0골드")
    local discord = BRL.Reports:BuildDiscord(st.id)
    T.contains(discord, "```")
    -- 채팅 출력: 모든 메시지 255바이트 이하
    M.ClearSent()
    BRL.Reports:SendToChat(detailed, "RAID")
    M.Advance(60)
    T.ok(#M.sent > 5, "분할 전송")
    for _, m in ipairs(M.sent) do T.ok(#m.msg <= 255, "255바이트 이하") end
end)

T.test("금액 파싱/표시 (정수 코퍼)", function()
    local Money = BRL.Money
    T.eq(Money.Parse("2,500"), 25000000)
    T.eq(Money.Parse("2500골드 30실버 5코퍼"), 25003005)
    T.eq(Money.Parse("2500g30s5c"), 25003005)
    T.eq(Money.Parse("1.2만"), 12000 * G)
    T.eq(Money.Parse("3천"), 3000 * G)
    T.eq(Money.Parse("2.5k"), 2500 * G)
    T.eq(Money.Parse("10s"), 1000)
    T.eq(Money.Parse("abc"), nil)
    T.eq(Money.Parse("1g 150s"), nil, "실버 범위")
    T.eq(Money.Format(25003005), "2,500골드 30실버 5코퍼")
    T.eq(Money.Format(0), "0골드")
    T.eq(Money.MulDiv(9007199254740, 9999, 10000), math.floor(9007199254740 / 10000) * 9999 + math.floor((9007199254740 % 10000) * 9999 / 10000))
end)

T.test("메시지 분할 - 아이템 링크/한글 보존", function()
    local U = BRL.Util
    local l = M.ItemLink(1, "아주긴이름의전설아이템")
    local text = string.rep("가나다라마바사 ", 30) .. l .. string.rep(" 아자차카", 20)
    local parts = U.SplitMessage(text, 120)
    local joined = table.concat(parts, " ")
    T.contains(joined, l, "링크 보존")
    for _, p in ipairs(parts) do
        T.ok(#p <= 120, "길이")
        -- UTF-8 유효성: 잘린 멀티바이트 없음
        T.ok(not p:find("[\192-\255]$"), "멀티바이트 경계")
    end
end)
