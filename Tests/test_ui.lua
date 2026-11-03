-- UI 스모크 테스트: 모든 화면 생성/갱신/탭 전환/버튼 클릭 시 Lua 오류가 없는지 확인
-- (실제 렌더링/레이아웃은 게임 클라이언트에서만 확인 가능)
local M = MOCK
local G = 10000

local function seed()
    local BRL = T.fresh({ group = T.raid(20) })
    BRL.Roster:Refresh()
    local s = BRL.Session:Create({ name = "UI 테스트", raidKey = "HYJAL_SUMMIT" })
    local auc = BRL.Auctions:Add(M.ItemLink(1, "테스트 검"), { startPrice = 100 * G })
    BRL.Auctions:Start(auc.id)
    BRL.Bids:Place(auc.id, "대원2", 500 * G, "manual")
    BRL.Auctions:ConfirmAward(auc.id)
    BRL.Auctions:Add(M.ItemLink(2, "대기 방패"))
    local tr = BRL.TradeJournal:AddManual({ partner = "대원2", received = 300 * G, note = "UI 테스트", purpose = "auction_payment" })
    BRL.Payments:AllocateAuction(tr.id, BRL.Auctions:Awards(s.id)[1].id, 300 * G)
    BRL.TradeJournal:AddManual({ partner = "대원3", received = 50 * G, note = "미분류" })
    local st = BRL.Settlement:Create(s.id)
    BRL.Settlement:Finalize(st.id, { force = true })
    BRL.LootDistribution:Register(M.ItemLink(3, "주사위템"), "roll")
    BRL.Recruitment:AddApplicant("지원자", "힐 1")
    BRL.Command:SaveCommand("집결", "입구 집결", "RAID")
    return BRL, s
end

local function errorsSince(BRL, n)
    local out = {}
    for i = n + 1, #BRL.errors do out[#out + 1] = BRL.errors[i].context .. ": " .. BRL.errors[i].message:sub(1, 300) end
    return out
end

T.test("메인 창 열기 + 15개 메뉴 생성/갱신", function()
    local BRL = seed()
    local before = #BRL.errors
    BigRaidLeader_ToggleUI()
    T.ok(BRL.UI.frame and BRL.UI.frame:IsShown(), "창 열림")
    T.eq(#BRL.UI.pageOrder, 15, "메뉴 15개")
    for _, def in ipairs(BRL.UI.pageOrder) do
        BRL.UI:Open(def.key)
        BRL.UI:Refresh()
        T.ok(def.frame, def.key .. " 생성")
        if def.frame.tabs then
            for _, b in ipairs(def.frame.tabs.buttons) do
                def.frame.tabs:Select(b.key)
                BRL.UI:Refresh()
            end
        end
    end
    local errs = errorsSince(BRL, before)
    T.eq(#errs, 0, "화면 오류 없음\n" .. table.concat(errs, "\n"))
end)

T.test("모든 버튼 클릭 (공대장) - Lua 오류 없음", function()
    local BRL = seed()
    BRL.UI:Open("dashboard")
    for _, def in ipairs(BRL.UI.pageOrder) do BRL.UI:Open(def.key) end
    local before = #BRL.errors
    local snapshot = {}
    for _, f in ipairs(M.frames) do snapshot[#snapshot + 1] = f end
    local clicked = 0
    for _, f in ipairs(snapshot) do
        local onClick = f.__scripts and f.__scripts.OnClick
        if onClick and f.__kind == "Button" and not (f.__template or ""):find("Secure") then
            -- 모든 탭/페이지의 버튼 (파괴적 작업은 확인 대화상자를 거침)
            local ok, err = pcall(onClick, f, "LeftButton")
            T.ok(ok, "클릭 오류: " .. tostring(err))
            clicked = clicked + 1
            M.Advance(0.5)
        end
    end
    print("    클릭한 버튼: " .. clicked .. "개")
    T.ok(clicked > 150, "클릭한 버튼 수 " .. clicked)
    BRL.UI:Refresh()
    local errs = errorsSince(BRL, before)
    T.eq(#errs, 0, "오류 없음\n" .. table.concat(errs, "\n"))
end)

T.test("일반 공대원 권한으로 화면 열기 (읽기 전용)", function()
    local BRL = seed()
    M.player.rank = 0
    M.group.members[1].rank = 0
    M.group.members[2].rank = 2
    local before = #BRL.errors
    for _, def in ipairs(BRL.UI.pageOrder) do
        BRL.UI:Open(def.key)
        BRL.UI:Refresh()
    end
    BRL.Widgets.RefreshPermissionButtons()
    local disabled = 0
    for _, b in ipairs(BRL.Widgets.permButtons) do if not b:IsEnabled() then disabled = disabled + 1 end end
    T.ok(disabled > 20, "권한 없는 버튼 비활성화 " .. disabled)
    T.contains(BRL.UI.pages.settlement.frame.permBanner:GetText(), "읽기 전용")
    T.eq(#errorsSince(BRL, before), 0)
end)

T.test("입력 대화상자: 금액 파싱/필수 검증/콜백", function()
    local BRL = T.fresh()
    local got
    local f = BRL.Dialogs.Input("테스트", {
        { key = "amount", label = "금액", type = "money", required = true },
        { key = "name", label = "이름", type = "text", required = true },
    }, function(v) got = v return true end)
    f.widgets[1].ctrl:SetText("2500g 30s")
    f.widgets[2].ctrl:SetText("")
    f.accept:Click()
    T.eq(got, nil, "필수 항목 누락 시 콜백 없음")
    T.contains(f.err:GetText(), "필수")
    f.widgets[2].ctrl:SetText("홍길동")
    f.accept:Click()
    T.eq(got.amount, 25003000)
    T.eq(got.name, "홍길동")
    -- 기본값 표시 → 재파싱 일치
    local f2 = BRL.Dialogs.Input("기본값", { { key = "a", label = "a", type = "money", default = 25003005 } }, function(v) got = v return true end)
    f2.accept:Click()
    T.eq(got.a, 25003005, "기본 금액 왕복 보존")
end)

T.test("거래 완료 직후 분류 창 표시", function()
    local BRL = T.fresh({ group = T.raid(5) })
    M.trade = { partner = "대원2", playerMoney = 0, targetMoney = 100 * G, playerItems = {}, targetItems = {} }
    M.Fire("TRADE_SHOW")
    M.Fire("TRADE_ACCEPT_UPDATE", 1, 0)
    M.money = M.money + 100 * G
    M.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
    M.Fire("TRADE_CLOSED")
    M.Advance(4)
    T.ok(BRL.TradePopup.frame and BRL.TradePopup.frame:IsShown(), "분류 창")
    BRL.TradePopup.frame.personal:Click()
    T.eq(BRL.TradeJournal:Query({})[1].purpose, "personal")
end)

T.test("슬래시 명령", function()
    local BRL = T.fresh({ group = T.raid(5) })
    SlashCmdList.BIGRAIDLEADER("도움말")
    SlashCmdList.BIGRAIDLEADER("정산")
    T.eq(BRL.UI.current, "settlement")
    SlashCmdList.BIGRAIDLEADER("세션 오늘의 공격대")
    T.eq(BRL.Session:GetActive().name, "오늘의 공격대")
    SlashCmdList.BIGRAIDLEADER("경매 " .. M.ItemLink(77, "슬래시템") .. " 300")
    T.eq(BRL.Auctions:Queue(BRL.Session:GetActive().id)[1].startPrice, 300 * G)
    SlashCmdList.BIGRAIDLEADER("검사")
    SlashCmdList.BIGRAIDLEADER("호환성")
    SlashCmdList.BIGRAIDLEADER("백업")
    T.ok(#BRL.db.backups >= 1)
    SlashCmdList.BIGRAIDLEADER("풀 8")
    T.eq(M.calls[#M.calls], "DoCountdown:8")
end)

T.test("징표 바: 보안 버튼 속성 / 전투 중 생성 차단", function()
    local BRL = T.fresh({ group = T.raid(5) })
    BRL.MarkerBar.frame = nil
    M.combat = true
    BRL.MarkerBar:Toggle()
    T.eq(BRL.MarkerBar.frame, nil, "전투 중 생성 안 함")
    M.combat = false
    BRL.MarkerBar:Toggle()
    T.ok(BRL.MarkerBar:IsShown())
    local skull = _G.BigRaidLeaderMarker8
    T.eq(skull:GetAttribute("type"), "raidtarget")
    T.eq(skull:GetAttribute("marker"), 8)
    T.eq(skull:GetAttribute("unit"), "target")
    T.eq(_G.BigRaidLeaderWorldMarker1:GetAttribute("type"), "worldmarker")
end)
