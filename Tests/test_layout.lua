-- UI 레이아웃 회귀 테스트: 모의 프레임의 앵커/크기 기록으로 화면 좌표를 계산해
-- (1) 위젯끼리 겹침 (2) 화면/창 밖으로 나감 (3) 버튼·폭 지정 글자 잘림 (4) 목록 열 폭 초과 를 찾는다.
-- 글자 폭은 근사치(한글 1자 = 글자 크기)이므로 실제 게임보다 약간 넉넉하게 판정한다.
local M = MOCK
local G = 10000
local Lay = dofile("Tests/layout.lua")

local function seed()
    local BRL = T.fresh({ group = T.raid(25) })
    BRL.Roster:Refresh()
    local s = BRL.Session:Create({ name = "레이아웃 점검 세션 이름이 꽤 긴 경우", raidKey = "HYJAL_SUMMIT" })
    local auc = BRL.Auctions:Add(M.ItemLink(1, "테스트 검"), { startPrice = 100 * G })
    BRL.Auctions:Start(auc.id)
    BRL.Bids:Place(auc.id, "대원2", 500 * G, "manual")
    BRL.Auctions:ConfirmAward(auc.id)
    BRL.Auctions:Add(M.ItemLink(2, "대기 방패"))
    BRL.TradeJournal:AddManual({ partner = "대원3", received = 50 * G, note = "미분류" })
    local st = BRL.Settlement:Create(s.id)
    BRL.Settlement:Finalize(st.id, { force = true })
    BRL.Recruitment:AddApplicant("지원자", "힐 1")
    return BRL, s
end

local function problems(name, root, out)
    local ov, clip = Lay.Overlaps(root, { bounds = root })
    for _, o in ipairs(ov) do out[#out + 1] = string.format("[%s] 겹침: %s ↔ %s", name, Lay.Describe(o.a), Lay.Describe(o.b)) end
    for _, c in ipairs(clip) do out[#out + 1] = string.format("[%s] 영역 밖: %s", name, Lay.Describe(c)) end
    for _, t in ipairs(Lay.Truncations(root)) do
        out[#out + 1] = string.format("[%s] 잘림: '%s' (필요 %d > 폭 %d)", name, t.text, t.need, t.avail)
    end
end

T.test("레이아웃: 모든 화면/탭에 겹침·잘림·영역 밖 위젯 없음", function()
    local BRL = seed()
    BigRaidLeader_ToggleUI()
    local out = {}
    for _, def in ipairs(BRL.UI.pageOrder) do
        BRL.UI:Open(def.key)
        BRL.UI:Refresh()
        local page = def.frame
        if page.tabs and page.tabs.buttons then
            for _, b in ipairs(page.tabs.buttons) do
                page.tabs:Select(b.key)
                BRL.UI:Refresh()
                problems(def.key .. "/" .. b.key, page, out)
            end
        else
            problems(def.key, page, out)
        end
    end
    T.eq(#out, 0, "레이아웃 문제\n" .. table.concat(out, "\n"))
end)

T.test("레이아웃: 메인 창 틀(머리/세션/메뉴/상태줄)과 최소 크기", function()
    local BRL = seed()
    BRL.char.ui.width, BRL.char.ui.height = 900, 600 -- 이전 버전에서 줄여 둔 크기
    -- 앞 테스트에서 만든 창은 버리고 새로 생성 (저장된 크기 보정 확인)
    for _, def in pairs(BRL.UI.pages) do def.frame = nil end
    BRL.UI.frame = nil
    BigRaidLeader_ToggleUI()
    local f = BRL.UI.frame
    T.ok(f:GetWidth() >= BRL.UI.MIN_W and f:GetHeight() >= BRL.UI.MIN_H, "저장된 작은 크기는 최소 크기로 보정")
    T.eq(BRL.char.ui.width, BRL.UI.MIN_W, "보정된 크기 저장")
    for _, def in ipairs(BRL.UI.pageOrder) do if def.frame then def.frame:Hide() end end
    local out = {}
    problems("main", f, out)
    T.eq(#out, 0, "레이아웃 문제\n" .. table.concat(out, "\n"))
    -- 화면 폭: 페이지 영역은 고정 배치(약 890px)를 담을 수 있어야 함
    BRL.UI:Open("dashboard")
    Lay.Reset()
    local r = Lay.Rect(BRL.UI.pages.dashboard.frame)
    T.ok(r.r - r.l >= 886, "페이지 폭 " .. (r.r - r.l))
end)

T.test("레이아웃: HUD/거래 정보/대화상자/전투 준비 창", function()
    local BRL = seed()
    local out = {}
    BRL.HUD:Show()
    problems("HUD", BRL.HUD.frame, out)
    BRL.HUD.frame.cmdToggle:Click()
    problems("HUD 접힘", BRL.HUD.frame, out)
    local D = BRL.Dialogs
    D.Confirm("정산을 확정하시겠습니까? 확정 후에는 잠금 해제 전까지 편집할 수 없습니다.", function() end, { title = "정산 확정", danger = true })
    problems("확인 창", D.confirm, out)
    D.Input("새 공격대 세션", {
        { key = "raidKey", label = "공격대", type = "dropdown", items = { { value = 1, text = "하이잘 정상" } }, default = 1 },
        { key = "name", label = "세션 이름", type = "text", placeholder = "비우면 자동 (공격대 + 날짜)" },
        { key = "amt", label = "금액", type = "money" },
        { key = "memo", label = "메모", type = "multiline" },
        { key = "c", label = "옵션", type = "check", checkLabel = "공지 보내기" },
    }, function() return true end, { description = "설명 문장이 들어가는 경우입니다. 두 줄 이상이 될 수도 있습니다." })
    problems("입력 창", D.input, out)
    D.CopyText("자가 진단 결과", "내용", { hint = "문제 보고 시 이 내용을 함께 전달하세요. 개인 정보(캐릭터 이름)가 포함됩니다.", extraText = "가져오기", extraFn = function() end })
    problems("복사 창", D.copy, out)
    D.Select("선택", { { value = 1, text = "가", sub = "나" } }, function() end, { description = "목록에서 선택하세요" })
    problems("선택 창", D.select, out)
    BRL.CombatPrep:Run()
    T.ok(BRL.PrepReport.frame, "전투 준비 창 생성")
    problems("전투 준비", BRL.PrepReport.frame, out)
    local wkey
    for _, a in pairs(BRL.db.awards) do wkey = a.winnerKey end
    BRL.TradeAssist:Update({ id = "layout", partnerKey = wkey, live = { targetMoney = 200 * G, playerMoney = 0 } })
    T.ok(BRL.TradeAssist.frame:IsShown(), "거래 정보 표시")
    problems("거래 정보", BRL.TradeAssist.frame, out)
    local pf = BRL.TradePopup:Create()
    pf:Show()
    problems("거래 완료 창", pf, out)
    T.eq(#out, 0, "레이아웃 문제\n" .. table.concat(out, "\n"))
end)

T.test("레이아웃 검사기 자체 확인: 겹침/잘림을 실제로 잡아냄", function()
    local W = T.fresh().Widgets
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(300, 100)
    root:SetPoint("TOPLEFT")
    local a = W.Button(root, "왼쪽 버튼", 100, 22)
    a:SetPoint("TOPLEFT", 10, -10)
    local b = W.Button(root, "겹친 버튼", 100, 22)
    b:SetPoint("TOPLEFT", 60, -15)
    local c = W.Button(root, "아주 긴 글자가 들어간 버튼", 60, 22)
    c:SetPoint("TOPLEFT", 10, -60)
    local ov, clip = Lay.Overlaps(root, { bounds = root })
    T.eq(#ov, 1, "겹침 1건")
    T.eq(#clip, 0, "영역 밖 없음")
    local tr = Lay.Truncations(root)
    T.eq(#tr, 1, "잘림 1건")
    local d = W.Button(root, "밖", 60, 22)
    d:SetPoint("TOPLEFT", 280, -60)
    local _, clip2 = Lay.Overlaps(root, { bounds = root })
    T.eq(#clip2, 1, "영역 밖 1건")
end)

-- 텍스처 파일: 애드온 Media 의 TGA 는 게임이 읽을 수 있는 형식(무압축 트루컬러, 2의 거듭제곱 크기)이어야 함
local function readTGA(gamePath)
    local rel = gamePath:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/")
    local fh = io.open(rel, "rb")
    if not fh then return nil, rel end
    local data = fh:read("*a")
    fh:close()
    local b = function(i) return data:byte(i) end
    local w = b(13) + b(14) * 256
    local h = b(15) + b(16) * 256
    return { type = b(3), bpp = b(17), desc = b(18), w = w, h = h, data = data, size = #data }, rel
end
local function pow2(n) return n > 0 and math.floor(math.log(n) / math.log(2) + 0.5) == math.log(n) / math.log(2) end

T.test("미디어: 표범 아이콘/로고/아이콘 아틀라스/머리 빛/바탕 TGA 형식", function()
    local BRL = T.fresh()
    local TX = BRL.Theme.TEX
    for _, key in ipairs({ "minimapIcon", "logo", "icons", "headerGlow", "backdrop", "logoBadge" }) do
        local t, rel = readTGA(TX[key])
        T.ok(t, "파일 있음: " .. tostring(rel))
        T.eq(t.type, 2, key .. " 무압축 트루컬러")
        T.ok(t.bpp == 32 or t.bpp == 24, key .. " 24/32비트")
        T.ok(pow2(t.w) and pow2(t.h), key .. " 크기 2의 거듭제곱 " .. t.w .. "x" .. t.h)
        local exp = 18 + t.w * t.h * t.bpp / 8
        T.ok(t.size == exp or t.size == exp + 26, key .. " 데이터 길이 (TGA 2.0 꼬리말 26바이트 허용) " .. t.size)
    end
    -- 미니맵 아이콘은 원형: 모서리는 투명, 가운데는 불투명 (원점 왼쪽 아래, BGRA)
    local ic = readTGA(TX.minimapIcon)
    T.eq(ic.bpp, 32, "아이콘은 알파 포함")
    local function alpha(x, y) return ic.data:byte(18 + (y * ic.w + x) * 4 + 4) end
    T.eq(alpha(0, 0), 0, "모서리 투명")
    T.eq(alpha(ic.w - 1, ic.h - 1), 0, "반대 모서리 투명")
    T.eq(alpha(ic.w / 2, ic.h / 2), 255, "가운데 불투명")
end)

T.test("미니맵 버튼: 원형 표범 아이콘 + 게임 기본 추적 테두리", function()
    local BRL = T.fresh()
    BRL.Minimap.button = nil
    BRL.Minimap:Create()
    local b = BRL.Minimap.button
    T.ok(b, "버튼 생성")
    T.eq(b.icon:GetTexture(), BRL.Theme.TEX.minimapIcon, "업로드한 표범 이미지 아이콘")
    T.eq(b.border:GetTexture(), "Interface\\Minimap\\MiniMap-TrackingBorder", "기본 미니맵 테두리 에셋")
    T.eq(b.icon:GetWidth(), 20, "테두리 안쪽 크기")
end)
