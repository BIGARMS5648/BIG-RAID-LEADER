-- BIG RAID LEADER - 골드 정산 화면 (골드팟 자동 정산 · 분배 · 지급 · 보고서)
local _, BRL = ...
local T, W, L, U, Money, API = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money, BRL.API
local UI, D, A = BRL.UI, BRL.Dialogs, BRL.UIActions

local S, P, R = BRL.Settlement, BRL.Payments, BRL.Reports

-- 분배 의무 → 지급 거래 연결
function A.LinkObligationToTrade(ob)
    local st = P:ObligationStatus(ob)
    if st.remaining <= 0 then D.Message("남은 지급액이 없습니다.") return end
    if ob.memberKey == BRL.playerKey then
        D.Confirm("본인(공대장) 몫 " .. Money.Format(st.remaining) .. "을 거래 없이 지급 완료로 처리할까요?\n(장부에 '공대장 골드 분배' 지출로 기록됩니다)", function()
            A.Report(P:PaySelf(ob.id))
        end, { title = "공대장 본인 몫" })
        return
    end
    local items = {}
    local trades = BRL.TradeJournal:Query({})
    table.sort(trades, function(a, b)
        local am, bm = a.partnerKey == ob.memberKey, b.partnerKey == ob.memberKey
        if am ~= bm then return am end
        return (a.at or 0) > (b.at or 0)
    end)
    for _, tr in ipairs(trades) do
        if BRL.TradeJournal:IsCounted(tr) and (tr.purpose == "payout" or tr.purpose == "unclassified") then
            local avail = P:TradeAvailableOut(tr)
            if avail > 0 then
                items[#items + 1] = { value = tr.id, text = (tr.partnerKey == ob.memberKey and "|cff20ff20★|r " or "|cff9d9d9d(대표)|r ") .. (tr.partnerName or "?") .. " " .. U.FormatDateTime(tr.at), sub = "미연결 " .. Money.Format(avail) }
            end
        end
    end
    if #items == 0 then D.Message("연결 가능한 지급 거래가 없습니다. 먼저 " .. (ob.name or "?") .. " 님에게 거래로 골드를 지급하세요.") return end
    D.Select("지급 거래 선택 - " .. (ob.name or "?"), items, function(tradeId)
        local tr = BRL.TradeJournal:Get(tradeId)
        local avail = P:TradeAvailableOut(tr)
        D.Input("지급 연결 금액", { { key = "amount", label = "금액", type = "money", default = math.min(avail, st.remaining), required = true } }, function(v)
            local opts = {}
            local function try()
                local res, err, info = P:AllocatePayout(tradeId, ob.id, v.amount, opts)
                if res then return true end
                if err == "proxy" then
                    D.Confirm(string.format("%s 님의 분배금을 %s 님이 대표 수령한 것으로 기록할까요?", API.ShortName(info.member), API.ShortName(info.recipient)), function()
                        opts.proxy = true
                        A.Report(try())
                    end)
                    return true
                elseif err == "overpay" then
                    D.Confirm("남은 지급액보다 큰 금액입니다. 초과 지급으로 기록할까요?", function() opts.allowOverpay = true A.Report(try()) end, { danger = true })
                    return true
                end
                return false, err
            end
            return try()
        end)
    end)
end

local function build(page)
    UI:PageHeader(page, L.MENU_SETTLEMENT, "실제 수금 기준 확정 정산 · 정수 코퍼 계산")
    page.status = W.Label(page, "", 12, "gold")
    page.status:SetPoint("TOPLEFT", 4, -28)

    -- 설정 패널
    local cfg = W.Panel(page, T.colors.panel2, T.colors.borderDim)
    cfg:SetPoint("TOPLEFT", 4, -52)
    cfg:SetSize(270, 420)
    page.cfg = cfg
    local y = 8
    local function row(label, widget, h)
        local l = W.Label(cfg, label, 11, "muted")
        l:SetPoint("TOPLEFT", 8, -y - 4)
        widget:SetPoint("TOPLEFT", 120, -y)
        y = y + (h or 26)
        return widget
    end
    local function st() return page.st end
    local function setCfg(path, v)
        if not st() then return end
        local ok, err = S:SetConfig(st().id, path, v)
        if not ok and err then BRL:Print(err) end
    end
    cfg.rounding = row("분배 단위", W.Dropdown(cfg, 140, {
        { value = 1, text = "코퍼까지" }, { value = 100, text = "실버까지" }, { value = 10000, text = "골드 단위(절사)" },
    }, function(v) setCfg("rounding", v) end))
    cfg.remainder = row("잔돈 처리", W.Dropdown(cfg, 140, {
        { value = "keep", text = "잔돈 보관" }, { value = "carry", text = "다음 정산 이월" }, { value = "leader", text = "공대장에게 지급" },
    }, function(v) setCfg("remainderMode", v) end))
    local function pctBox(path)
        return W.EditBox(cfg, 60, 22, { placeholder = "%", onCommit = function(t)
            local v = tonumber(t) or 0
            setCfg(path, math.floor(v * 100 + 0.5))
        end })
    end
    local function moneyBox(path)
        return W.EditBox(cfg, 100, 22, { placeholder = "골드", onCommit = function(t)
            local v = (t == "" and 0) or Money.Parse(t)
            if v then setCfg(path, v) else BRL:Print("금액 형식 오류") end
        end })
    end
    cfg.feePct = row("공대장 수수료 %", pctBox("leaderFeeBp"))
    cfg.feeFixed = row("공대장 수수료(고정)", moneyBox("leaderFeeFixed"))
    cfg.resPct = row("예비금 %", pctBox("reserveBp"))
    cfg.resFixed = row("예비금(고정)", moneyBox("reserveFixed"))
    cfg.tankBonus = row("탱커 추가 보상", moneyBox("roleBonus.TANK"))
    cfg.healBonus = row("힐러 추가 보상", moneyBox("roleBonus.HEALER"))
    cfg.carry = W.CheckBox(cfg, "이월 잔돈 포함", function(v) setCfg("includeCarryIn", v) end)
    cfg.carry:SetPoint("TOPLEFT", 8, -y - 2)
    y = y + 26
    local cl = W.Section(cfg, "운영비 / 기타 공제")
    cl:SetPoint("TOPLEFT", 8, -y)
    y = y + 22
    cfg.costs = W.List(cfg, {
        noHeader = true,
        columns = {
            { title = "", width = 0, render = function(c) return (c.list == "operatingCosts" and "운영비: " or "공제: ") .. c.label end },
            { title = "", width = 90, align = "RIGHT", render = function(c) return Money.Format(c.amount, { goldOnly = c.amount % 10000 == 0 }) end },
        },
    })
    cfg.costs:SetPoint("TOPLEFT", 8, -y)
    cfg.costs:SetSize(254, 90)
    y = y + 96
    local cb = CreateFrame("Frame", nil, cfg)
    cb:SetPoint("TOPLEFT", 8, -y)
    cb:SetSize(254, 24)
    local fc = W.Flow(cb, 0, 1, 4)
    local function addCost(list)
        if not st() then return end
        D.Input(list == "operatingCosts" and "운영비 추가" or "기타 공제 추가", {
            { key = "label", label = "항목", type = "text", required = true },
            { key = "amount", label = "금액", type = "money", required = true },
        }, function(v) return S:AddCost(st().id, list, v.label, v.amount) end)
    end
    fc:Add(W.Button(cb, "+운영비", 64, 22, function() addCost("operatingCosts") end, { perm = "finance.edit" }))
    fc:Add(W.Button(cb, "+공제", 54, 22, function() addCost("deductions") end, { perm = "finance.edit" }))
    fc:Add(W.Button(cb, "삭제", 50, 22, function()
        local c = cfg.costs:GetSelected()
        if c and st() then S:RemoveCost(st().id, c.list, c.index) end
    end, { perm = "finance.edit" }))

    -- 분배표
    page.list = W.List(page, {
        columns = {
            { title = "파티", width = 34, align = "CENTER", render = function(r) return r.subgroup or "-" end },
            { title = "공대원", width = 104, render = function(r)
                return (r.include == false and "|cff9d9d9d(제외)|r " or "") .. BRL.Data.ColorName(r.name, r.class) .. (r.kind == "fee" and " |cffffd100(수수료)|r" or "")
            end },
            { title = "역할", width = 46, render = function(r) return ({ TANK = "탱커", HEALER = "힐러", MELEE = "근딜", RANGED = "원딜" })[r.role or ""] or "-" end },
            { title = "분배액", width = 100, align = "RIGHT", render = function(r) return r.total and Money.Format(r.total, { goldOnly = r.total % 10000 == 0 }) or "-" end },
            { title = "추가", width = 74, align = "RIGHT", render = function(r)
                local x = {}
                if (r.bonus or 0) > 0 then x[#x + 1] = "+" .. Money.Format(r.bonus, { goldOnly = true }) end
                if r.manual then x[#x + 1] = "수동" end
                if (r.bonusBp or 0) > 0 then x[#x + 1] = "+" .. (r.bonusBp / 100) .. "%" end
                if (r.remainderAdd or 0) > 0 then x[#x + 1] = "잔돈" end
                return table.concat(x, " ")
            end },
            { title = "지급", width = 92, align = "RIGHT", render = function(r) return r.paid and Money.Format(r.paid, { goldOnly = r.paid % 10000 == 0 }) or "" end },
            { title = "상태", width = 0, render = function(r)
                if not r.payStatus then return "" end
                return T.StatusText(r.payStatus, BRL.Label("PAY_", r.payStatus)) .. ((r.remaining or 0) > 0 and (" " .. Money.Format(r.remaining, { goldOnly = true })) or "")
            end },
        },
        onDoubleClick = function(r) page.editParticipant(r) end,
        tooltip = function(r) return r.name, { "더블클릭: 참가자 설정(제외/가중치/보너스/수동 금액)", r.ob and "지급 연결 수: " .. #P:AllocationsForObligation(r.ob.id) or nil } end,
    })
    -- 오른쪽 아래: 버튼 줄 → 계산 요약 → 파티별 → 경고 (위에서 아래로 이어 붙여 줄 수가 늘어도 겹치지 않게)
    page.list:SetPoint("TOPLEFT", 282, -52)
    page.list:SetPoint("BOTTOMRIGHT", -4, 226)
    page.summary = W.Paragraph(page, "", 600, 12)
    page.parties = W.Paragraph(page, "", 600, 11)
    page.warn = W.Paragraph(page, "", 600, 11)

    page.editParticipant = function(r)
        local stt = page.st
        if not stt or r.kind == "fee" then return end
        local p = stt.config.participants[r.key]
        if not p then return end
        local roles = { { value = false, text = "-" } }
        for _, x in ipairs(BRL.Data.Roles) do roles[#roles + 1] = { value = x, text = BRL.Label("CR_", x) } end
        D.Input(p.name .. " 정산 설정", {
            { key = "include", label = "분배 대상", type = "check", checkLabel = "포함", default = p.include },
            { key = "subgroup", label = "파티", type = "number", default = p.subgroup },
            { key = "role", label = "역할", type = "dropdown", items = roles, default = p.role or false },
            { key = "weight", label = "분배 비율(%)", type = "number", default = p.weight or 100 },
            { key = "bonusBp", label = "비율 추가 지급(%)", type = "number", default = (p.bonusBp or 0) / 100 },
            { key = "bonusFixed", label = "고정 추가 지급", type = "money", default = p.bonusFixed or 0 },
            { key = "manual", label = "수동 지정 금액", type = "money", default = p.manualAmount, allowEmpty = true },
        }, function(v)
            return S:SetParticipant(stt.id, r.key, {
                include = v.include, subgroup = math.max(1, math.min(8, math.floor(v.subgroup or 1))), role = v.role or nil,
                weight = math.max(0, math.floor(v.weight or 100)), bonusBp = math.max(0, math.floor((v.bonusBp or 0) * 100 + 0.5)),
                bonusFixed = v.bonusFixed or 0, manualAmount = v.manual or false,
            })
        end, { description = "수동 지정 금액을 비우면 균등 분배 대상이 됩니다. 기본값: 균등 분배, 모든 보너스 0." })
    end

    local function sel() return page.list:GetSelected() end
    local bar1 = CreateFrame("Frame", nil, page)
    bar1:SetPoint("BOTTOMLEFT", 282, 194)
    bar1:SetSize(600, 26)
    page.summary:SetPoint("TOPLEFT", bar1, "BOTTOMLEFT", 0, -6)
    page.parties:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -5)
    page.warn:SetPoint("TOPLEFT", page.parties, "BOTTOMLEFT", 0, -5)
    local f1 = W.Flow(bar1, 0, 1, 4)
    f1:Add(W.Button(bar1, "정산 만들기", 84, 24, function()
        local s = BRL.Session:GetActive()
        if not s then D.Message("공격대 세션이 없습니다.") return end
        A.Report(S:Ensure(s.id))
    end, { perm = "finance.edit" }))
    f1:Add(W.Button(bar1, "참가자 동기화", 96, 24, function()
        if page.st then
            local ok, n = S:SyncParticipants(page.st.id)
            if ok then BRL:Print("참가자 %d명 추가", n or 0) end
        end
    end, { perm = "finance.edit" }))
    f1:Add(W.Button(bar1, "참가자 추가", 84, 24, function()
        if not page.st then return end
        D.Input("참가자 추가", { { key = "name", label = "이름", type = "text", required = true }, { key = "subgroup", label = "파티", type = "number", default = 1 } },
            function(v) return S:AddParticipant(page.st.id, v.name, { subgroup = v.subgroup }) end)
    end, { perm = "finance.edit" }))
    f1:Add(W.Button(bar1, "제외/포함", 76, 24, function()
        local r = sel()
        if r and page.st and r.kind ~= "fee" then
            local p = page.st.config.participants[r.key]
            if p then S:SetParticipant(page.st.id, r.key, { include = not p.include }) end
        end
    end, { perm = "finance.edit" }))
    f1:Add(W.Button(bar1, "정산 확정(잠금)", 110, 24, function()
        local stt = page.st
        if not stt then return end
        local res, why, warnings = S:Finalize(stt.id)
        if res then BRL:Print("정산 확정 v%d", stt.version) return end
        if why == "warnings" then
            D.Confirm("다음 경고가 있습니다:\n\n- " .. table.concat(warnings, "\n- ") .. "\n\n그래도 확정할까요? (확정 후에도 잠금 해제하여 수정할 수 있습니다)", function()
                A.Report(S:Finalize(stt.id, { force = true }))
            end, { title = "정산 확정 경고", danger = true })
        else
            D.Message("정산을 확정할 수 없습니다:\n" .. tostring(why))
        end
    end, { kind = "primary", perm = "finance.edit" }))
    f1:Add(W.Button(bar1, "잠금 해제", 76, 24, function()
        if page.st then D.Reason("정산 잠금 해제", function(r) return S:Unlock(page.st.id, r) end, "수정 후 다시 확정하면 보고서 버전이 갱신됩니다. 기존 지급 기록은 유지됩니다.") end
    end, { perm = "finance.edit" }))

    local _, f2 = UI.BottomBar(page)
    f2:Add(W.Button(f2.parent, "지급 거래 연결", 104, 24, function()
        local r = sel()
        if r and r.ob then A.LinkObligationToTrade(r.ob) else D.Message("정산을 확정한 뒤 분배 대상을 선택하세요.") end
    end, { kind = "primary", perm = "finance.edit" }))
    f2:Add(W.Button(f2.parent, "지급 보류", 70, 24, function()
        local r = sel()
        if r and r.ob then P:SetHold(r.ob.id, not r.ob.hold, "공대장 처리") end
    end, { perm = "finance.edit" }))
    f2:Add(W.Button(f2.parent, "지급 내역/해제", 100, 24, function()
        local r = sel()
        if not r or not r.ob then return end
        local items = {}
        for _, a in ipairs(P:AllocationsForObligation(r.ob.id)) do
            items[#items + 1] = { value = a.id, text = Money.Format(a.amount) .. (a.tradeId and (" · 거래 " .. a.tradeId) or " · 본인 몫") .. (a.proxy and " [대표]" or ""), sub = U.FormatDateTime(a.at) }
        end
        if #items == 0 then D.Message("지급 기록이 없습니다.") return end
        D.Select("지급 연결 해제", items, function(id) D.Reason("연결 해제", function(x) return P:UnlinkPayout(id, x) end) end)
    end, { perm = "finance.edit" }))
    f2:Add(W.Button(f2.parent, "검증", 50, 24, function()
        if not page.st then return end
        local checks = S:Validate(page.st.id)
        local lines = {}
        for _, c in ipairs(checks) do lines[#lines + 1] = (c.ok and "[통과] " or "[확인] ") .. c.label .. " - " .. tostring(c.detail or "") end
        D.CopyText("정산 완료 검증", table.concat(lines, "\n"))
    end))
    f2:Add(W.Button(f2.parent, "정산 종료", 70, 24, function()
        local stt = page.st
        if not stt then return end
        local ok, why, issues = S:Close(stt.id)
        if ok then BRL:Print("정산 종료: %s", BRL.Label("SETTLE_", stt.status)) return end
        if why == "issues" then
            D.Confirm("미결 항목이 남아 있습니다:\n- " .. table.concat(issues, "\n- ") .. "\n\n종료해도 기록은 그대로 유지됩니다. 종료할까요?", function()
                A.Report(S:Close(stt.id, true))
            end, { title = "정산 종료 경고", danger = true })
        else
            D.Message(tostring(why))
        end
    end, { perm = "finance.edit" }))
    f2:Add(W.Button(f2.parent, "간략 보고서", 84, 24, function() if page.st then A.SendLines(R:BuildBrief(page.st.id), "간략 정산 보고서") end end))
    f2:Add(W.Button(f2.parent, "상세 보고서", 84, 24, function() if page.st then D.CopyText("상세 정산 보고서", R:ToText(R:BuildDetailed(page.st.id))) end end))
    f2:Add(W.Button(f2.parent, "디스코드", 70, 24, function() if page.st then D.CopyText("디스코드 게시용", R:ToText(R:BuildDiscord(page.st.id))) end end))
    f2:Add(W.Button(f2.parent, "이력", 50, 24, function()
        if not page.st then return end
        local lines = {}
        for _, rep in ipairs(R:History(page.st.id)) do
            lines[#lines + 1] = string.format("v%d (%s) %s", rep.version, BRL.Label("SETTLE_", rep.status), U.FormatDateTime(rep.at))
            lines[#lines + 1] = rep.brief
            lines[#lines + 1] = ""
        end
        D.CopyText("정산 보고서 버전 기록", #lines > 0 and table.concat(lines, "\n") or "확정된 보고서가 없습니다.")
    end))
end

local function refresh(page)
    local s = BRL.Session:GetActive()
    page.st = s and S:ForSession(s.id) or nil
    local stt = page.st
    if not stt then
        page.status:SetText(s and "정산이 없습니다. [정산 만들기]를 누르세요." or "공격대 세션이 없습니다.")
        page.list:SetData({})
        page.summary:SetText("")
        page.parties:SetText("")
        page.warn:SetText("")
        page.cfg.costs:SetData({})
        return
    end
    local c = stt.config
    local cfg = page.cfg
    cfg.rounding:SetValue(c.rounding, true)
    cfg.remainder:SetValue(c.remainderMode, true)
    local function setBox(box, text) if not box.edit.hasFocus then box:SetText(text) end end
    setBox(cfg.feePct, (c.leaderFeeBp or 0) > 0 and tostring(c.leaderFeeBp / 100) or "")
    setBox(cfg.resPct, (c.reserveBp or 0) > 0 and tostring(c.reserveBp / 100) or "")
    local function goldText(v) if not v or v == 0 then return "" end return Money.Format(v, { short = true }) end
    setBox(cfg.feeFixed, goldText(c.leaderFeeFixed))
    setBox(cfg.resFixed, goldText(c.reserveFixed))
    setBox(cfg.tankBonus, goldText(c.roleBonus.TANK))
    setBox(cfg.healBonus, goldText(c.roleBonus.HEALER))
    cfg.carry:SetChecked(c.includeCarryIn)
    cfg.carry.label:SetText("이월 잔돈 포함 (" .. Money.Format(stt.carryInTaken or BRL.char.carryover or 0) .. ")")
    local costs = {}
    for i, x in ipairs(c.operatingCosts) do costs[#costs + 1] = { list = "operatingCosts", index = i, label = x.label, amount = x.amount } end
    for i, x in ipairs(c.deductions) do costs[#costs + 1] = { list = "deductions", index = i, label = x.label, amount = x.amount } end
    cfg.costs:SetData(costs)

    local r = (stt.locked and stt.result) or S:Compute(stt)
    local pay = S:PaymentState(stt.id)
    local obByKey = {}
    for _, row in ipairs(pay.rows) do obByKey[row.ob.memberKey .. "|" .. row.ob.kind] = row end
    local rows = {}
    for _, row in ipairs(r.rows) do
        local x = U.ShallowCopy(row)
        x.include = true
        local pr = obByKey[row.key .. "|share"]
        if pr then x.ob, x.paid, x.remaining, x.payStatus = pr.ob, pr.paid, pr.remaining, pr.status end
        rows[#rows + 1] = x
    end
    for key, p in pairs(c.participants) do
        if not p.include then rows[#rows + 1] = { key = key, name = p.name, class = p.class, subgroup = p.subgroup, role = p.role, include = false } end
    end
    for _, pr in ipairs(pay.rows) do
        if pr.ob.kind == "fee" then
            rows[#rows + 1] = { key = pr.ob.memberKey, name = pr.ob.name, class = pr.ob.class, subgroup = pr.ob.subgroup, kind = "fee",
                total = pr.ob.amount, ob = pr.ob, paid = pr.paid, remaining = pr.remaining, payStatus = pr.status }
        end
    end
    table.sort(rows, function(a, b)
        if (a.subgroup or 9) ~= (b.subgroup or 9) then return (a.subgroup or 9) < (b.subgroup or 9) end
        return (a.name or "") < (b.name or "")
    end)
    page.list:SetData(rows, true)
    page.status:SetText(string.format("상태: %s · 버전 v%d%s · 기준: %s", BRL.Label("SETTLE_", stt.status), stt.version or 0,
        stt.locked and T.Color("blue", " · 잠금") or "", (stt.locked and "확정 시점 실제 수금") or "현재 실제 수금"))
    page.summary:SetText(string.format("총수입 %s (수금 %s + 기타 %s + 이월 %s) − 장부지출 %s − 운영비 %s − 공제 %s − 수수료 %s − 예비금 %s\n= 분배 가능 %s · 분배 인원 %d명 · %s %s · 잔돈 %s%s",
        Money.Format(r.gross), Money.Format(r.auctionBase), Money.Format(r.otherIncome), Money.Format(r.carryIn), Money.Format(r.ledgerExpenses),
        Money.Format(r.operating), Money.Format(r.deductions), Money.Format(r.leaderFee), Money.Format(r.reserve),
        T.Color("goldBright", Money.Format(math.max(0, r.distributable))), r.headcount, r.equalShares and "1인당" or "평균", T.Color("goldBright", Money.Format(r.perPerson)),
        Money.Format(r.kept + r.carryOut), r.carryOut > 0 and " (이월)" or ""))
    local parties = {}
    local src = (stt.status ~= "draft") and pay.parties or r.parties
    for g = 1, 8 do
        local pt = src[g]
        if pt then
            if pt.paidCount then
                parties[#parties + 1] = string.format("%d파티 %d명 %s (완료 %d/미지급 %d, 남은 %s)", g, pt.count, Money.Format(pt.total, { goldOnly = true }), pt.paidCount, pt.unpaidCount, Money.Format(pt.remaining, { goldOnly = true }))
            else
                parties[#parties + 1] = string.format("%d파티 %d명 %s", g, pt.count, Money.Format(pt.total, { goldOnly = true }))
            end
        end
    end
    page.parties:SetText(table.concat(parties, " · "))
    local msgs = {}
    for _, e in ipairs(r.errors) do msgs[#msgs + 1] = T.Color("red", "오류: " .. e) end
    for _, w in ipairs(r.warnings) do msgs[#msgs + 1] = T.Color("yellow", w) end
    if stt.status ~= "draft" then
        msgs[#msgs + 1] = string.format("지급 완료 %d명 · 미지급 %d명 · 미지급금 %s", pay.paidCount, pay.unpaidCount, Money.Format(pay.unpaid))
    end
    page.warn:SetText(table.concat(msgs, " · "))
    UI:SetPermBanner(page, "finance.edit")
end

UI:RegisterPage("settlement", { title = L.MENU_SETTLEMENT, order = 13, build = build, refresh = refresh })
