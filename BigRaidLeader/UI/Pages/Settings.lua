-- BIG RAID LEADER - 설정 / 데이터 관리 / 진단
local _, BRL = ...
local T, W, L, U, Money, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money, BRL.API
local UI, D = BRL.UI, BRL.Dialogs

local function build(page)
    UI:PageHeader(page, L.MENU_SETTINGS, "애드온 설정 · 데이터 관리")
    page.panels = {}
    page.tabs = W.Tabs(page, {
        { key = "general", text = "일반/거래", width = 100 }, { key = "auction", text = "경매/정산", width = 100 },
        { key = "data", text = "데이터 관리", width = 100 },
        { key = "compat", text = "진단", width = 70 },
    }, function(key)
        page.tab = key
        for k, p in pairs(page.panels) do if k == key then p:Show() else p:Hide() end end
        UI:RequestRefresh()
    end)
    page.tabs:SetPoint("TOPLEFT", 4, -28)
    local function panel(key)
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -60)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        page.panels[key] = p
        return p
    end
    page.checks = {}
    local function check(parent, x, y, label, path, tip, after)
        local cb = W.CheckBox(parent, label, function(v)
            BRL.DB:SetSetting(path, v)
            if after then after(v) end
        end, tip)
        cb:SetPoint("TOPLEFT", x, -y)
        cb.path = path
        table.insert(page.checks, cb)
        return cb
    end

    -- 일반 / 거래
    local pg = panel("general")
    local s1 = W.Section(pg, "거래 자동 기록")
    s1:SetPoint("TOPLEFT", 4, 0)
    check(pg, 8, 24, "거래 자동 기록", "trade.autoRecord", { "거래 창 이벤트를 추적해 완료가 확인된 거래를 기록합니다." })
    check(pg, 8, 48, "거래 완료 화면 알림", "trade.notifyScreen")
    check(pg, 8, 72, "채팅창 거래 기록 출력", "trade.notifyChat")
    check(pg, 8, 96, "거래 직후 목적 분류 창", "trade.completionPopup")
    check(pg, 8, 120, "경매/분배 연결 제안 (자동 확정 없음)", "trade.suggestLinks")
    check(pg, 230, 24, "거래 창 옆 정보 패널", "trade.assistPanel", { "거래 상대에게서 받을 낙찰금/줄 분배금과 거래 창 금액을 비교해 보여줍니다.", "[분배금 입력]은 골드 칸만 채우며 수락은 직접 해야 합니다." })
    local s2 = W.Section(pg, "인터페이스")
    s2:SetPoint("TOPLEFT", 4, -180)
    check(pg, 8, 204, "미니맵 버튼 숨기기", "minimap.hide", nil, function() BRL.Minimap:UpdateVisibility() end)
    check(pg, 230, 204, "공대장 HUD 표시", "hud.show", { "메인 창 없이 경매/카운트, 거래 상대, 풀링 판정, 도핑, 미지급을 보여주는 작은 창", "/brl hud" },
        function(v) if v then BRL.HUD:Show() else BRL.HUD:Hide() end end)
    check(pg, 8, 228, "HUD 위치 잠금", "hud.locked")
    check(pg, 230, 228, "HUD 지휘 명령 버튼", "hud.commands", { "준비 확인/풀링/공격 중지/후퇴/재정비/휴식/공략 안내 버튼을 HUD 에 표시합니다.", "HUD 제목줄의 [지휘]로도 접고 펼 수 있습니다." },
        function() if BRL.HUD.frame then BRL.HUD:Layout() end end)
    local sl = W.Label(pg, "창 크기 배율", 12, "muted")
    sl:SetPoint("TOPLEFT", 8, -262)
    local scaleDrop = W.Dropdown(pg, 100, {
        { value = 0.8, text = "80%" }, { value = 0.9, text = "90%" }, { value = 1.0, text = "100%" }, { value = 1.1, text = "110%" }, { value = 1.2, text = "120%" },
    }, function(v) BRL.char.ui.scale = v if UI.frame then UI.frame:SetScale(v) end end)
    scaleDrop:SetPoint("TOPLEFT", 110, -258)
    scaleDrop:SetValue(BRL.char.ui.scale or 1, true)
    W.Button(pg, "창 위치 초기화", 110, 22, function()
        BRL.char.ui.point = nil
        if UI.frame then UI.frame:ClearAllPoints() UI.frame:SetPoint("CENTER") end
    end):SetPoint("TOPLEFT", 220, -258)
    local s4 = W.Section(pg, "버프 / 준비 확인")
    s4:SetPoint("TOPLEFT", 4, -296)
    check(pg, 8, 320, "야영지 효과가 대응 직업 버프를 대체한 것으로 인정", "buffs.campReplacesClassBuff")
    W.Button(pg, "버프 키워드 보완", 120, 22, function()
        local items = {}
        for _, b in ipairs(BRL.Data.ClassBuffs) do items[#items + 1] = { value = b.key, text = b.name } end
        for _, c in ipairs(BRL.Data.CampFacilities) do items[#items + 1] = { value = c.key, text = "야영지: " .. c.name } end
        for _, g in ipairs(BRL.Data.ConsumableGroups) do if not g.manual then items[#items + 1] = { value = g.key, text = "도핑: " .. g.name } end end
        D.Select("키워드를 보완할 버프", items, function(key)
            BRL.acct.buffs.keywords = BRL.acct.buffs.keywords or {}
            local cur = table.concat(BRL.acct.buffs.keywords[key] or {}, ", ")
            D.Input("버프 이름 키워드 (쉼표 구분)", { { key = "kw", label = "키워드", type = "text", default = cur } }, function(v)
                local list = {}
                for _, k in ipairs(U.Split(v.kw, ",")) do k = U.Trim(k) if k ~= "" then list[#list + 1] = k end end
                BRL.acct.buffs.keywords[key] = list
                return true
            end, { description = "포에버 클라이언트의 실제 버프 이름이 기본 데이터와 다르면 여기에 추가하세요." })
        end)
    end):SetPoint("TOPLEFT", 8, -348)
    local s5 = W.Section(pg, "전투 준비 (도핑 점검)")
    s5:SetPoint("TOPLEFT", 450, 0)
    check(pg, 454, 24, "음식 버프 필수", "consumables.requireFood")
    check(pg, 454, 48, "필수 직업 버프도 함께 점검", "consumables.checkClassBuffs")
    check(pg, 454, 72, "곧 만료되는 도핑도 누락으로 알림", "consumables.expiringAsMissing")
    check(pg, 454, 96, "전투 준비 시 공격대 채팅에 자동 공지", "consumables.autoAnnounce")
    check(pg, 454, 120, "전투 준비 시 준비 확인 함께 실행", "consumables.withReadyCheck")
    local ml = W.Label(pg, "영약/비약 기준", 12, "muted")
    ml:SetPoint("TOPLEFT", 454, -152)
    pg.prepMode = W.Dropdown(pg, 130, BRL.CombatPrep.MODES, function(v) BRL.DB:SetSetting("consumables.mainMode", v) end)
    pg.prepMode:SetPoint("TOPLEFT", 560, -148)
    local el = W.Label(pg, "최소 비약 수", 12, "muted")
    el:SetPoint("TOPLEFT", 454, -180)
    pg.prepMin = W.EditBox(pg, 40, 22, { numeric = true, onCommit = function(t)
        BRL.DB:SetSetting("consumables.minElixirs", math.max(1, math.min(5, tonumber(t) or 1)))
    end })
    pg.prepMin:SetPoint("TOPLEFT", 560, -176)
    local pn = W.Paragraph(pg, "만료 임박 기준은 버프 설정의 만료 경고(분)를 따릅니다. 물약·주문서처럼 사용 시 사라지는 소모품은 점검할 수 없습니다.", 420, 11)
    pn:SetPoint("TOPLEFT", 454, -208)
    check(pg, 454, 246, "우두머리 전투 실패 시 전멸 복구 창 (사망자·영혼석·재버프·도핑)", "consumables.wipeRecovery")
    T.SetTextColor(pn, "muted")

    -- 경매 / 정산
    local pa = panel("auction")
    local a1 = W.Section(pa, "경매 기본값")
    a1:SetPoint("TOPLEFT", 4, 0)
    local function moneyRow(y, label, path)
        local l = W.Label(pa, label, 12, "muted")
        l:SetPoint("TOPLEFT", 8, -y - 4)
        local eb = W.EditBox(pa, 120, 22, { onCommit = function(t)
            local v = Money.Parse(t)
            if v then BRL.DB:SetSetting(path, v) else BRL:Print("금액 형식 오류") end
        end })
        eb:SetPoint("TOPLEFT", 140, -y)
        eb.path = path
        return eb
    end
    pa.start = moneyRow(24, "기본 시작가", "auction.startPrice")
    pa.inc = moneyRow(52, "기본 최소 증가액", "auction.minIncrement")
    local dl = W.Label(pa, "기본 경매 시간(초)", 12, "muted")
    dl:SetPoint("TOPLEFT", 8, -84)
    pa.dur = W.EditBox(pa, 60, 22, { numeric = true, onCommit = function(t) BRL.DB:SetSetting("auction.defaultDuration", math.max(5, tonumber(t) or 30)) end })
    pa.dur:SetPoint("TOPLEFT", 140, -80)
    local snl = W.Label(pa, "막판 입찰 연장(초)", 12, "muted")
    snl:SetPoint("TOPLEFT", 8, -112)
    pa.snipe = W.EditBox(pa, 60, 22, { numeric = true, onCommit = function(t) BRL.DB:SetSetting("auction.antiSnipeSeconds", math.max(0, tonumber(t) or 0)) end })
    pa.snipe:SetPoint("TOPLEFT", 140, -108)
    local cl2 = W.Label(pa, "카운트(초)", 12, "muted")
    cl2:SetPoint("TOPLEFT", 220, -84)
    pa.count = W.EditBox(pa, 40, 22, { numeric = true, onCommit = function(t)
        BRL.DB:SetSetting("auction.countdownFrom", math.max(3, math.min(10, tonumber(t) or 5)))
    end })
    pa.count:SetPoint("TOPLEFT", 300, -80)
    W.SetTooltip(pa.count, "경매 카운트 초", { "[카운트] 버튼과 마감 카운트다운에 쓰는 초 (3~10, 기본 5)" })
    local chl = W.Label(pa, "공지 채널", 12, "muted")
    chl:SetPoint("TOPLEFT", 8, -140)
    pa.announce = W.Dropdown(pa, 130, { { value = "RAID_WARNING", text = "공격대 경보" }, { value = "RAID", text = "공격대" } },
        function(v) BRL.DB:SetSetting("auction.announceChannel", v) end)
    pa.announce:SetPoint("TOPLEFT", 140, -136)
    check(pa, 8, 172, "채팅 입찰 자동 인식", "auction.chatBids", { "금액만 입력한 공격대/파티/귓속말 메시지를 입찰로 인식합니다.", "우두머리 전투 중 채팅 제한 시에는 인식되지 않으니 수동 입력하세요." })
    check(pa, 8, 196, "공격대원 입찰만 인정", "auction.requireGroupMember")
    check(pa, 8, 220, "최고 입찰 공지", "auction.announceBids")
    check(pa, 8, 244, "마감 카운트다운 공지", "auction.countdownAnnounce")
    check(pa, 8, 268, "종료 시 자동 낙찰 확정 (기본: 공대장 확인)", "auction.autoConfirmAward")
    check(pa, 220, 108, "카운트 중 새 입찰 시 카운트 취소", "auction.cancelCountOnBid")
    local bc = W.Label(pa, "입찰 인식 채널:", 12, "muted")
    bc:SetPoint("TOPLEFT", 8, -300)
    local chans = { { "RAID", "공격대" }, { "RAID_LEADER", "공격대장" }, { "RAID_WARNING", "경보" }, { "PARTY", "파티" }, { "PARTY_LEADER", "파티장" }, { "WHISPER", "귓속말" } }
    for i, c in ipairs(chans) do
        check(pa, 8 + (i - 1) * 90, 322, c[2], "auction.bidChannels." .. c[1])
    end
    local a2 = W.Section(pa, "정산 기본값")
    a2:SetPoint("TOPLEFT", 450, 0)
    local rl = W.Label(pa, "분배 단위", 12, "muted")
    rl:SetPoint("TOPLEFT", 454, -28)
    pa.rounding = W.Dropdown(pa, 140, { { value = 1, text = "코퍼까지" }, { value = 100, text = "실버까지" }, { value = 10000, text = "골드 단위" } },
        function(v) BRL.DB:SetSetting("settlement.rounding", v) end)
    pa.rounding:SetPoint("TOPLEFT", 560, -24)
    local rml = W.Label(pa, "잔돈 처리", 12, "muted")
    rml:SetPoint("TOPLEFT", 454, -56)
    pa.remainder = W.Dropdown(pa, 140, { { value = "keep", text = "잔돈 보관" }, { value = "carry", text = "다음 정산 이월" }, { value = "leader", text = "공대장 지급" } },
        function(v) BRL.DB:SetSetting("settlement.remainderMode", v) end)
    pa.remainder:SetPoint("TOPLEFT", 560, -52)
    pa.carryInfo = W.Label(pa, "", 12, "gold")
    pa.carryInfo:SetPoint("TOPLEFT", 454, -88)
    local rcl = W.Label(pa, "보고서 기본 채널", 12, "muted")
    rcl:SetPoint("TOPLEFT", 454, -116)
    pa.report = W.Dropdown(pa, 140, { { value = "RAID", text = "공격대" }, { value = "GUILD", text = "길드" }, { value = "PARTY", text = "파티" } },
        function(v) BRL.DB:SetSetting("chat.reportChannel", v) end)
    pa.report:SetPoint("TOPLEFT", 560, -112)
    local note = W.Paragraph(pa, "모든 보너스/수수료/공제의 기본값은 0이며, 기본 분배 방식은 전원 균등 분배입니다. 정산별 설정은 골드 정산 화면에서 변경합니다.", 420, 11)
    note:SetPoint("TOPLEFT", 454, -150)
    T.SetTextColor(note, "muted")
    local a3 = W.Section(pa, "경매 진행 보조")
    a3:SetPoint("TOPLEFT", 450, -196)
    check(pa, 454, 222, "연속 경매 (낙찰/유찰 후 다음 경매 자동 시작)", "auction.autoNext")
    local anl = W.Label(pa, "연속 경매 대기(초)", 12, "muted")
    anl:SetPoint("TOPLEFT", 454, -250)
    pa.autoDelay = W.EditBox(pa, 50, 22, { numeric = true, onCommit = function(t)
        BRL.DB:SetSetting("auction.autoNextDelay", math.max(3, math.min(60, tonumber(t) or 8)))
    end })
    pa.autoDelay:SetPoint("TOPLEFT", 600, -246)

    -- 데이터 관리
    local pd = panel("data")
    pd.info = W.Paragraph(pd, "", 880, 12)
    pd.info:SetPoint("TOPLEFT", 4, 0)
    pd.backups = W.List(pd, {
        columns = {
            { title = "#", width = 30, align = "CENTER", render = function(b) return b.index end },
            { title = "일시", width = 140, render = function(b) return U.FormatDateTime(b.at) end },
            { title = "설명", width = 0, render = function(b) return b.label end },
            { title = "크기", width = 90, align = "RIGHT", render = function(b) return U.FormatNumber(b.size) .. "B" end },
            { title = "버전", width = 70, render = function(b) return tostring(b.version) end },
        },
    })
    pd.backups:SetPoint("TOPLEFT", 4, -70)
    pd.backups:SetSize(880, 170)
    local db1 = CreateFrame("Frame", nil, pd)
    db1:SetPoint("TOPLEFT", 4, -246)
    db1:SetSize(880, 26)
    local fd = W.Flow(db1, 0, 1, 4)
    fd:Add(W.Button(db1, "지금 백업", 80, 24, function() BRL.Migration:CreateBackup("수동 백업") UI:RequestRefresh() end, { kind = "primary" }))
    fd:Add(W.Button(db1, "백업 검증", 80, 24, function()
        local b = pd.backups:GetSelected()
        if not b then return end
        local ok, msg = BRL.Migration:VerifyBackup(b.index)
        D.Message((ok and "백업 정상: " or "백업 이상: ") .. tostring(msg))
    end))
    fd:Add(W.Button(db1, "백업으로 복구", 100, 24, function()
        local b = pd.backups:GetSelected()
        if not b then return end
        D.Confirm("선택한 백업(" .. U.FormatDateTime(b.at) .. ")으로 모든 데이터를 복구할까요?\n현재 상태는 '복구 직전 자동 백업'으로 보관됩니다.", function()
            local ok, err = BRL.Migration:RestoreBackup(b.index)
            D.Message(ok and "복구 완료" or ("복구 실패: " .. tostring(err)))
        end, { danger = true, title = "데이터 복구" })
    end))
    local ex = W.Section(pd, "내보내기 / 가져오기 (복사·붙여넣기)")
    ex:SetPoint("TOPLEFT", 4, -286)
    local db2 = CreateFrame("Frame", nil, pd)
    db2:SetPoint("TOPLEFT", 4, -310)
    db2:SetSize(880, 60)
    local fe = W.Flow(db2, 0, 1, 4)
    local function session() return BRL.Session:GetActive() end
    fe:Add(W.Button(db2, "거래 로그 CSV", 104, 24, function() D.CopyText("거래 로그 CSV", BRL.TradeJournal:ExportCSV()) end))
    fe:Add(W.Button(db2, "골드 장부 CSV", 104, 24, function() D.CopyText("골드 장부 CSV", BRL.Ledger:ExportCSV(session() and session().id)) end))
    fe:Add(W.Button(db2, "경매 기록 CSV", 104, 24, function() D.CopyText("경매 기록 CSV", BRL.Auctions:ExportCSV(session() and session().id)) end))
    fe:Add(W.Button(db2, "정산 보고서", 90, 24, function()
        local s = session()
        local st = s and BRL.Settlement:ForSession(s.id)
        if st then D.CopyText("상세 정산 보고서", BRL.Reports:ToText(BRL.Reports:BuildDetailed(st.id))) else D.Message("정산이 없습니다.") end
    end))
    fe:Add(W.Button(db2, "전체 백업 문자열", 120, 24, function()
        D.CopyText("전체 데이터 백업 문자열", BRL.Serializer.Export("full", BRL.Migration:Snapshot()), { hint = "이 문자열을 메모장 등에 보관하세요. 체크섬으로 손상 여부를 검증합니다." })
    end))
    fe:NewLine(28)
    fe:Add(W.Button(db2, "설정 내보내기", 100, 24, function() D.CopyText("설정 내보내기", BRL.Serializer.Export("settings", BRL.acct)) end))
    fe:Add(W.Button(db2, "설정 가져오기", 100, 24, function()
        D.Paste("설정 가져오기", function(text)
            local obj, err = BRL.Serializer.Import(text, "settings")
            if not obj then return false, err end
            BRL.Migration:CreateBackup("설정 가져오기 전 자동 백업")
            for k, v in pairs(obj.data) do BRL.acct[k] = v end
            U.ApplyDefaults(BRL.acct, BRL.DB.ACCOUNT_DEFAULTS)
            BRL:Print("설정을 가져왔습니다.")
            return true
        end)
    end))
    fe:Add(W.Button(db2, "백업 문자열 검증", 120, 24, function()
        D.Paste("백업 문자열 검증", function(text)
            local obj, err = BRL.Serializer.Import(text)
            if not obj then return false, err end
            local issues = BRL.Migration:Validate(obj.data)
            D.Message(string.format("정상 형식 (%s, v%s, %s)\n무결성 문제: %d건", obj.kind, tostring(obj.version), U.FormatDateTime(obj.at), #issues))
            return true
        end)
    end))
    fe:Add(W.Button(db2, "백업 문자열로 복원", 130, 24, function()
        D.Paste("전체 데이터 복원", function(text)
            local obj, err = BRL.Serializer.Import(text, "full")
            if not obj then return false, err end
            D.Confirm("붙여넣은 백업으로 전체 데이터를 덮어쓸까요? 현재 상태는 자동 백업됩니다.", function()
                BRL.Migration:CreateBackup("문자열 복원 전 자동 백업")
                local db = BRL.db
                local backups = db.backups
                for k in pairs(db) do if k ~= "backups" and k ~= "errorLog" then db[k] = nil end end
                for k, v in pairs(obj.data) do db[k] = v end
                db.backups = backups
                BRL.DB:Init()
                BRL.Migration:Run(db)
                BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "all")
                D.Message("복원 완료")
            end, { danger = true })
            return true
        end)
    end))
    local dz = W.Section(pd, "주의")
    dz:SetPoint("TOPLEFT", 4, -384)
    local dn = W.Paragraph(pd, "WoW 애드온은 파일을 직접 쓸 수 없어 내보내기는 복사 창으로 제공됩니다. 데이터는 로그아웃/UI 재시작 시 WTF\\Account\\<계정>\\SavedVariables\\BigRaidLeader.lua 에 저장됩니다. 정산이 끝나도 원본 거래 로그는 삭제되지 않습니다.", 880, 11)
    dn:SetPoint("TOPLEFT", 4, -406)
    T.SetTextColor(dn, "muted")
    W.Button(pd, "공유 문자열 가져오기", 140, 22, function() BRL.UIActions.ShareImport() end,
        { tooltip = { "공략/파티 편성/전술표 공유 문자열을 가져옵니다.", "종류는 자동으로 판별합니다." } }):SetPoint("TOPLEFT", 4, -446)

    -- 진단 (자가 진단 + API/이벤트 지원 + 무결성 + 오류 기록 통합)
    local pc = panel("compat")
    pc.build = W.Label(pc, "", 12, "gold")
    pc.build:SetPoint("TOPLEFT", 4, 0)
    pc.summary = W.Label(pc, "", 12, "text")
    pc.summary:SetPoint("TOPLEFT", 4, -18)
    local bd = CreateFrame("Frame", nil, pc)
    bd:SetPoint("TOPLEFT", 4, -38)
    bd:SetSize(880, 26)
    local fdg = W.Flow(bd, 0, 1, 4)
    fdg:Add(W.Button(bd, "자가 진단 (복사)", 120, 24, function() pc.last = BRL.Diagnostics:Show() UI:RequestRefresh() end,
        { kind = "primary", tooltip = { "환경·API·이벤트·거래 기록·저장 데이터 무결성·정산 잔액·오류 기록을 한 번에 점검합니다.", "/brl 진단" } }))
    fdg:Add(W.Button(bd, "무결성 상세", 90, 24, function()
        local lines = {}
        for _, i in ipairs(BRL.Migration:Validate()) do lines[#lines + 1] = "[" .. i.severity .. "] " .. i.message .. " " .. tostring(i.entity or "") end
        D.CopyText("데이터 무결성 검사", #lines > 0 and table.concat(lines, "\n") or "문제 없음")
    end))
    fdg:Add(W.Button(bd, "오류 기록", 80, 24, function()
        local lines = {}
        for _, e in ipairs(BRL.db.errorLog or {}) do lines[#lines + 1] = U.FormatDateTime(e.at) .. " " .. e.context .. ": " .. e.message end
        D.CopyText("오류 기록", #lines > 0 and table.concat(lines, "\n\n") or "오류 기록 없음")
    end))
    fdg:Add(W.Button(bd, "거래 이벤트 추적", 110, 24, function() BRL.UIActions.TradeTraces() end))
    pc.list = W.List(pc, {
        columns = {
            { title = "API / 이벤트", width = 0, render = function(r) return r.name end },
            { title = "지원", width = 120, align = "CENTER", render = function(r)
                if r.value then return r.value end
                return r.ok and T.Color("green", "지원") or T.Color("red", "미지원")
            end },
        },
    })
    pc.list:SetPoint("TOPLEFT", 4, -70)
    pc.list:SetPoint("BOTTOMRIGHT", -4, 34)
    local pcn = W.Paragraph(pc, "미지원 항목이 있으면 해당 기능은 안전하게 비활성화되거나 수동 입력으로 대체됩니다. 문제 보고 시 [자가 진단] 결과를 함께 전달하세요.", 880, 11)
    pcn:SetPoint("BOTTOMLEFT", 4, 8)
    T.SetTextColor(pcn, "muted")

    page.tabs:Select("general")
end

local function refresh(page)
    for _, cb in ipairs(page.checks) do cb:SetChecked(BRL.DB:GetSetting(cb.path) and true or false) end
    if page.tab == "general" then
        local pg = page.panels.general
        pg.prepMode:SetValue(BRL.acct.consumables.mainMode, true)
        if not pg.prepMin.edit.hasFocus then pg.prepMin:SetText(tostring(BRL.acct.consumables.minElixirs or 1)) end
    elseif page.tab == "auction" then
        local pa = page.panels.auction
        local function setMoney(eb, v) if not eb.edit.hasFocus then eb:SetText(Money.Format(v, { short = true })) end end
        setMoney(pa.start, BRL.acct.auction.startPrice)
        setMoney(pa.inc, BRL.acct.auction.minIncrement)
        if not pa.dur.edit.hasFocus then pa.dur:SetText(tostring(BRL.acct.auction.defaultDuration)) end
        if not pa.snipe.edit.hasFocus then pa.snipe:SetText(tostring(BRL.acct.auction.antiSnipeSeconds or 0)) end
        if not pa.count.edit.hasFocus then pa.count:SetText(tostring(BRL.acct.auction.countdownFrom or 5)) end
        if not pa.autoDelay.edit.hasFocus then pa.autoDelay:SetText(tostring(BRL.acct.auction.autoNextDelay or 8)) end
        pa.announce:SetValue(BRL.acct.auction.announceChannel, true)
        pa.rounding:SetValue(BRL.acct.settlement.rounding, true)
        pa.remainder:SetValue(BRL.acct.settlement.remainderMode, true)
        pa.report:SetValue(BRL.acct.chat.reportChannel, true)
        pa.carryInfo:SetText("현재 이월 잔돈: " .. Money.Format(BRL.char.carryover or 0))
    elseif page.tab == "data" then
        local pd = page.panels.data
        local list = {}
        for i, b in ipairs(BRL.db.backups or {}) do list[#list + 1] = { index = i, at = b.at, label = b.label, size = b.size, version = b.version } end
        pd.backups:SetData(list, true)
        local counts = {}
        for _, t in ipairs({ { "trades", "거래" }, { "auctions", "경매" }, { "awards", "낙찰" }, { "ledger", "장부" }, { "settlements", "정산" }, { "sessions", "세션" } }) do
            counts[#counts + 1] = t[2] .. " " .. U.Count(BRL.db[t[1]])
        end
        pd.info:SetText(string.format("저장 스키마 v%d · 애드온 v%s · 레코드: %s · 감사 로그 %d건\n백업은 하루 1회 자동 생성되며 최대 %d개까지 보관합니다. 정산 확정/데이터 복구/마이그레이션 전에도 자동 백업됩니다.",
            BRL.db.schemaVersion or 0, BRL.VERSION, table.concat(counts, ", "), #BRL.db.audit, BRL.Migration.MAX_BACKUPS))
    elseif page.tab == "compat" then
        local pc = page.panels.compat
        pc.build:SetText("클라이언트: " .. API.GetBuildText())
        local rep = pc.last or BRL.Diagnostics:Run()
        pc.last = rep
        pc.summary:SetText(string.format("자가 진단 (%s): %s · %s", U.FormatClock(rep.at),
            rep.errors > 0 and T.Color("red", "오류 " .. rep.errors .. "건") or T.Color("green", "오류 없음"),
            rep.warnings > 0 and T.Color("yellow", "주의 " .. rep.warnings .. "건") or T.Color("green", "주의 없음")))
        pc.list:SetData(API.RunCompatibilityCheck())
    end
end

UI:RegisterPage("settings", { title = L.MENU_SETTINGS, order = 15, build = build, refresh = refresh })
