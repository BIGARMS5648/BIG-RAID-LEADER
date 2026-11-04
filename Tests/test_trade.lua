-- 23.1 거래 기록 테스트
local M = MOCK
local G = 10000

local function open(partner, class)
    M.trade = { partner = partner, partnerClass = class or "MAGE", playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
end
local function setTarget(c) M.trade.targetMoney = c M.Fire("TRADE_MONEY_CHANGED") end
local function setPlayer(c) M.trade.playerMoney = c M.Fire("TRADE_MONEY_CHANGED") end
local function addItem(side, slot, id, name, count)
    local list = side == "player" and M.trade.playerItems or M.trade.targetItems
    list[slot] = { name = name, link = M.ItemLink(id, name), count = count or 1, quality = 4 }
    M.Fire(side == "player" and "TRADE_PLAYER_ITEM_CHANGED" or "TRADE_TARGET_ITEM_CHANGED", slot)
end
local function accept(p, t) M.Fire("TRADE_ACCEPT_UPDATE", p, t) end
-- 게임의 완료 처리 흉내: 골드/아이템 이동 → 완료 메시지 → 창 비움 → 창 닫힘 → PLAYER_MONEY → 가방 갱신
local function moveItems(target, player)
    for _, it in pairs(target) do
        local id = tonumber(it.link:match("item:(%d+)"))
        M.bags[id] = (M.bags[id] or 0) + (it.count or 1)
    end
    for _, it in pairs(player) do
        local id = tonumber(it.link:match("item:(%d+)"))
        M.bags[id] = (M.bags[id] or 0) - (it.count or 1)
    end
end
local function complete(order)
    local delta = M.trade.targetMoney - M.trade.playerMoney
    local tItems, pItems = M.trade.targetItems, M.trade.playerItems
    order = order or { "money", "items", "msg", "clear", "closed", "pmoney", "bag" }
    for _, step in ipairs(order) do
        if step == "money" then M.money = M.money + delta
        elseif step == "items" then moveItems(tItems, pItems)
        elseif step == "bag" then M.Fire("BAG_UPDATE_DELAYED")
        elseif step == "msg" then M.Fire("UI_INFO_MESSAGE", 226, ERR_TRADE_COMPLETE)
        elseif step == "clear" then
            M.trade.playerItems, M.trade.targetItems = {}, {}
            M.trade.playerMoney, M.trade.targetMoney = 0, 0
            M.Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
            M.Fire("TRADE_MONEY_CHANGED")
        elseif step == "closed" then M.Fire("TRADE_CLOSED")
        elseif step == "pmoney" then M.Fire("PLAYER_MONEY") end
    end
    M.Advance(5)
end
local function cancel()
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_CANCELLED)
    M.Fire("TRADE_CLOSED")
    M.Advance(5)
end
local function trades() return BRL.TradeJournal:Query({ includeCancelled = true, includeVoided = true }) end
local function last() return trades()[1] end

T.test("1. 골드 수령", function()
    T.fresh()
    open("미라")
    setTarget(2500 * G)
    accept(0, 1)
    accept(1, 1)
    complete()
    local tr = last()
    T.ok(tr, "기록")
    T.eq(tr.status, "completed", "상태")
    T.eq(tr.verification, "message+money", "검증 방식")
    T.eq(tr.targetMoney, 2500 * G, "받은 골드")
    T.eq(tr.playerMoney, 0, "지급 골드")
    T.eq(tr.partnerKey, "미라-아즈샤라", "상대")
    T.ok(BRL.TradeJournal:IsCounted(tr), "합산 대상")
end)

T.test("2. 골드 지급", function()
    T.fresh()
    open("철수")
    setPlayer(1234 * G + 56 * 100 + 78)
    accept(1, 0)
    complete()
    local tr = last()
    T.eq(tr.status, "completed")
    T.eq(tr.playerMoney, 12345678, "지급 코퍼 정확")
    T.eq(BRL.TradeJournal:Effective(tr).net, -12345678, "순액")
end)

T.test("3. 아이템만 거래", function()
    T.fresh()
    open("영희")
    addItem("player", 1, 19019, "천둥분노")
    accept(1, 0)
    complete()
    local tr = last()
    T.eq(tr.status, "completed")
    T.eq(tr.verification, "message+items", "아이템 거래는 메시지 + 가방 수량으로 검증")
    T.eq(#tr.playerItems, 1, "지급 아이템 수")
    T.eq(tr.playerItems[1].name, "천둥분노")
end)

T.test("4. 아이템과 골드 동시 거래 (창 비움 이후에도 수락 시점 내용 보존)", function()
    T.fresh()
    open("민수")
    addItem("player", 1, 17076, "스톰파이크 망치")
    setTarget(3000 * G)
    accept(0, 1)
    complete()
    local tr = last()
    T.eq(tr.status, "completed")
    T.eq(tr.targetMoney, 3000 * G)
    T.eq(#tr.playerItems, 1)
end)

T.test("5. 여러 아이템 거래", function()
    T.fresh()
    open("길동")
    addItem("target", 1, 1, "아이템A", 5)
    addItem("target", 2, 2, "아이템B")
    addItem("target", 3, 3, "아이템C", 20)
    accept(1, 1)
    complete()
    local tr = last()
    T.eq(#tr.targetItems, 3, "받은 아이템 3종")
    T.eq(tr.targetItems[3].count, 20, "수량")
end)

T.test("6. 거래 취소 - 완료로 오인하지 않음", function()
    T.fresh()
    open("취소맨")
    setTarget(500 * G)
    cancel()
    local tr = last()
    T.ok(tr, "취소 거래 기록")
    T.eq(tr.status, "cancelled")
    T.no(BRL.TradeJournal:IsCounted(tr), "합산 제외")
    -- 아무것도 없는 취소 거래는 기록하지 않음
    open("빈거래")
    cancel()
    T.eq(#trades(), 1, "빈 취소 거래 미기록")
end)

T.test("7. 수락 후 거래 취소", function()
    T.fresh()
    open("변심")
    setTarget(1000 * G)
    accept(1, 0)
    accept(1, 1)
    M.Fire("TRADE_REQUEST_CANCEL")
    M.Fire("TRADE_CLOSED")
    M.Advance(5)
    T.eq(last().status, "cancelled")
end)

T.test("8. 거래 금액 변경 - 최종 수락 금액 기록", function()
    T.fresh()
    open("흥정")
    setTarget(1000 * G)
    accept(1, 0)
    setTarget(2000 * G)
    accept(0, 0)
    accept(0, 1)
    complete()
    local tr = last()
    T.eq(tr.targetMoney, 2000 * G, "변경된 금액")
    T.eq(tr.verification, "message+money")
end)

T.test("9. 같은 금액 반복 거래 - 모두 기록", function()
    T.fresh()
    for _ = 1, 3 do
        open("반복")
        setTarget(100 * G)
        accept(1, 1)
        complete()
    end
    local list = trades()
    T.eq(#list, 3, "3건 기록")
    T.ok(list[1].id ~= list[2].id and list[2].id ~= list[3].id, "고유 ID")
end)

T.test("10. 이벤트 중복 - 이중 기록 방지", function()
    T.fresh()
    open("중복")
    setTarget(700 * G)
    accept(1, 1)
    M.money = M.money + 700 * G
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    M.Fire("CHAT_MSG_SYSTEM", ERR_TRADE_COMPLETE)
    M.Fire("TRADE_CLOSED")
    M.Fire("TRADE_CLOSED")
    M.Fire("PLAYER_MONEY")
    M.Fire("PLAYER_MONEY")
    M.Advance(5)
    T.eq(#trades(), 1, "1건만 기록")
    T.eq(last().status, "completed")
end)

T.test("11. 이벤트 순서 변경", function()
    T.fresh()
    -- 창 닫힘 → 골드 변화 → 완료 메시지 순서
    open("순서A")
    setTarget(900 * G)
    accept(1, 0)
    complete({ "clear", "closed", "money", "pmoney", "msg" })
    T.eq(last().status, "completed", "닫힘 먼저")
    T.eq(last().targetMoney, 900 * G)
    -- 완료 메시지 → 닫힘 → 골드 변화 늦게
    open("순서B")
    setPlayer(300 * G)
    accept(0, 1)
    complete({ "msg", "closed", "clear", "money", "pmoney" })
    T.eq(last().status, "completed", "메시지 먼저")
    T.eq(last().playerMoney, 300 * G)
end)

T.test("12. 완료 메시지 누락 - 골드 변화로 검증 / 아이템만이면 확인 불가", function()
    T.fresh()
    open("누락")
    setTarget(1500 * G)
    accept(1, 0)
    complete({ "money", "clear", "closed", "pmoney" })
    T.eq(last().status, "completed")
    T.eq(last().verification, "money")
    -- 아이템만 + 메시지 없음 + 가방 수량 읽기 불가 → 확인 불가
    M.noItemCount = true
    open("누락아이템")
    addItem("target", 1, 5, "물건")
    accept(1, 0)
    complete({ "items", "clear", "closed", "bag" })
    T.eq(last().status, "unverified", "아이템만 + 메시지 없음 + 수량 확인 불가")
    T.no(BRL.TradeJournal:IsCounted(last()), "합산 제외")
    -- 늦게 도착한 완료 메시지로 승격
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    T.eq(last().status, "completed", "늦은 메시지 승격")
    M.noItemCount = false
end)

T.test("12c. 아이템 거래: 가방 수량 변화로 완료 검증 / 변화 없으면 취소 / 메시지+아이템", function()
    T.fresh()
    local function lastOf() return BRL.TradeJournal:Get(BRL.TradeTracker:RecentTraces()[1].id) end
    M.bags[777] = 2
    open("아이템상대")
    addItem("target", 1, 777, "전리품", 3)
    addItem("player", 1, 888, "내물건", 1)
    M.bags[888] = 1
    accept(0, 1)
    -- 완료 메시지 누락, 가방은 실제로 변함
    complete({ "items", "clear", "closed", "bag" })
    T.eq(lastOf().status, "completed", "가방 변화 일치 → 완료")
    T.eq(lastOf().verification, "items")
    T.eq(M.bags[777], 5)
    T.eq(M.bags[888], 0)
    -- 메시지 없이 닫힘 + 가방 변화 없음 → 취소
    open("도망아이템")
    addItem("target", 1, 999, "다른템")
    accept(1, 0)
    complete({ "clear", "closed", "bag" })
    T.eq(lastOf().status, "cancelled", "가방 변화 없음 → 취소")
    T.eq(lastOf().verification, "items_unchanged")
    -- 완료 메시지 + 가방 갱신이 창 닫힘 뒤에 도착 → 메시지+아이템
    open("정상아이템")
    addItem("target", 1, 555, "보석", 2)
    accept(0, 1)
    complete({ "msg", "clear", "closed", "items", "bag" })
    T.eq(lastOf().status, "completed")
    T.eq(lastOf().verification, "message+items", "가방 반영까지 기다린 뒤 판정")
    -- 이벤트 추적: 기록 안 된 빈 거래 포함, 최대 10건
    open("빈거래")
    cancel()
    local traces = BRL.TradeTracker:RecentTraces()
    T.eq(traces[1].partnerKey, "빈거래-아즈샤라")
    T.no(traces[1].recorded, "빈 취소 거래는 기록 안 함")
    T.ok(#traces >= 4)
    T.contains(table.concat(BRL.TradeTracker:FormatEvents(traces[2].events), "\n"), "가방 변화")
    for i = 1, 12 do open("반복" .. i) cancel() end
    T.eq(#BRL.TradeTracker:RecentTraces(), 10, "최근 10건만 보관")
end)

T.test("12b. 골드 제시 후 메시지 없이 닫힘 + 골드 변화 없음 → 취소", function()
    T.fresh()
    open("도망")
    setTarget(400 * G)
    M.Fire("TRADE_CLOSED")
    M.Advance(5)
    T.eq(last().status, "cancelled")
    T.eq(last().verification, "money_unchanged")
end)

T.test("13. 거래 중 UI 재시작 - 확인 불가로 보존", function()
    T.fresh()
    open("리로드")
    setTarget(800 * G)
    accept(1, 0)
    T.ok(BRL.db.activeTrade, "진행 중 거래 저장")
    -- 재시작 흉내: 모듈 상태 초기화 후 복구
    BRL.TradeTracker.current = nil
    BRL.TradeTracker:RecoverInterrupted()
    local tr = last()
    T.eq(tr.status, "unverified")
    T.eq(tr.verification, "interrupted")
    T.eq(tr.targetMoney, 800 * G, "수락 시점 금액 보존")
    T.eq(BRL.db.activeTrade, nil, "복구 후 정리")
end)

T.test("14. 개인 거래 - 공대 수입 미반영", function()
    T.fresh()
    local s = BRL.Session:Create({ name = "테스트" })
    open("친구")
    setTarget(5000 * G)
    accept(1, 1)
    complete()
    local tr = last()
    T.ok(BRL.TradeJournal:SetPurpose(tr.id, "personal", "개인"))
    local sum = BRL.Ledger:Summary(s.id)
    T.eq(sum.income, 0, "공대 수입 0")
    T.eq(#BRL.Ledger:Entries(s.id), 0, "장부 항목 없음")
end)

T.test("15. 여러 거래 연속 처리", function()
    T.fresh()
    open("연속A")
    setTarget(100 * G)
    accept(1, 1)
    M.money = M.money + 100 * G
    M.Fire("TRADE_CLOSED")
    -- A 판정 전에 B 시작
    open("연속B")
    setTarget(200 * G)
    accept(1, 1)
    complete()
    local list = trades()
    T.eq(#list, 2, "2건")
    local byName = {}
    for _, t in ipairs(list) do byName[t.partnerName] = t end
    T.eq(byName["연속A"].targetMoney, 100 * G)
    T.eq(byName["연속B"].targetMoney, 200 * G)
    T.eq(byName["연속B"].status, "completed")
end)

T.test("16. 수동 기록 - 사유 필수 / 수동 확인 상태", function()
    T.fresh()
    local rec, err = BRL.TradeJournal:AddManual({ partner = "우편맨", received = 300 * G })
    T.no(rec, "사유 없으면 거부")
    T.ok(err)
    rec = BRL.TradeJournal:AddManual({ partner = "우편맨", received = 300 * G, note = "자동 기록 누락" })
    T.ok(rec, "생성")
    T.eq(rec.status, "manual")
    T.eq(rec.source, "manual")
    T.ok(BRL.TradeJournal:IsCounted(rec))
end)

T.test("17. 기록 수정 - 원본 보존 + 이력 + 장부 반영", function()
    T.fresh()
    local s = BRL.Session:Create({})
    open("정정")
    setTarget(1000 * G)
    accept(1, 1)
    complete()
    local tr = last()
    T.ok(BRL.TradeJournal:SetPurpose(tr.id, "raid_income", "기타 수입"))
    T.eq(BRL.Ledger:Summary(s.id).income, 1000 * G)
    local ok = BRL.TradeJournal:Adjust(tr.id, 0, 900 * G, "")
    T.no(ok, "사유 필수")
    T.ok(BRL.TradeJournal:Adjust(tr.id, 0, 900 * G, "실제 금액 정정"))
    T.eq(tr.targetMoney, 1000 * G, "원본 보존")
    T.eq(BRL.TradeJournal:Effective(tr).received, 900 * G, "실효 금액")
    T.eq(BRL.Ledger:Summary(s.id).income, 900 * G, "장부 반영")
    T.ok(#tr.history >= 2, "수정 이력")
end)

T.test("18. 기록 취소/복원 + 백업 복구", function()
    T.fresh()
    local s = BRL.Session:Create({})
    local rec = BRL.TradeJournal:AddManual({ partner = "복구", received = 50 * G, note = "테스트", purpose = "raid_income" })
    T.eq(BRL.Ledger:Summary(s.id).income, 50 * G)
    T.ok(BRL.TradeJournal:Void(rec.id, "중복 입력"))
    T.eq(BRL.Ledger:Summary(s.id).income, 0, "취소 시 제외")
    T.ok(BRL.TradeJournal:Restore(rec.id, "복원"))
    T.eq(BRL.Ledger:Summary(s.id).income, 50 * G, "복원")
    -- 백업 → 데이터 손상 → 복구
    BRL.Migration:CreateBackup("테스트 백업")
    BRL.db.trades[rec.id] = nil
    T.eq(BRL.TradeJournal:Get(rec.id), nil)
    local ok, why = BRL.Migration:VerifyBackup(1)
    T.ok(ok, "백업 검증 " .. tostring(why))
    T.ok(BRL.Migration:RestoreBackup(1))
    T.ok(BRL.TradeJournal:Get(rec.id), "복구됨")
    T.eq(#BRL.Migration:Validate(), 0, "무결성")
end)

