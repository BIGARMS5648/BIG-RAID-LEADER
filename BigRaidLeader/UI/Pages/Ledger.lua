-- BIG RAID LEADER - 골드 장부 화면
local _, BRL = ...
local T, W, L, U, Money = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money
local UI, D = BRL.UI, BRL.Dialogs

local LG = BRL.Ledger

local TILES = {
    { key = "totalAwarded", label = "총 경매액 (예정)" }, { key = "collected", label = "실제 수금액" },
    { key = "outstanding", label = "미수금" }, { key = "otherIncome", label = "기타 수입" },
    { key = "expense", label = "지출 총액" }, { key = "payoutPaid", label = "실제 지급액" },
    { key = "unpaid", label = "미지급금" }, { key = "balance", label = "현재 장부 잔액" },
    { key = "payoutPlanned", label = "분배 예정액" }, { key = "unallocatedAuctionIncome", label = "미연결 수금" },
}

local function build(page)
    UI:PageHeader(page, L.MENU_LEDGER, "실제 골드 이동(완료 거래)과 장부상 예정 금액을 분리 관리")
    page.tiles = {}
    for i, t in ipairs(TILES) do
        local tile = W.StatTile(page, t.label, 172, 48)
        tile:SetPoint("TOPLEFT", 4 + ((i - 1) % 5) * 178, -28 - math.floor((i - 1) / 5) * 54)
        page.tiles[t.key] = tile
    end
    local flow = W.Flow(page, 4, 140, 6)
    page.kind = flow:Add(W.Dropdown(page, 100, { { value = false, text = "수입/지출" }, { value = "income", text = "수입" }, { value = "expense", text = "지출" } }, function() UI:RequestRefresh() end))
    page.kind:SetValue(false, true)
    page.source = flow:Add(W.Dropdown(page, 110, { { value = false, text = "모든 출처" }, { value = "trade", text = "거래 기록" }, { value = "manual", text = "수동 기록" }, { value = "system", text = "내부 처리" } }, function() UI:RequestRefresh() end))
    page.source:SetValue(false, true)
    page.search = flow:Add(W.EditBox(page, 160, 22, { placeholder = "검색", onChange = function() UI:RequestRefresh() end }))
    page.showVoided = W.CheckBox(page, "취소 기록 포함", function() UI:RequestRefresh() end)
    page.showVoided:SetPoint("TOPLEFT", 400, -143)
    page.list = W.List(page, {
        idKey = "id",
        columns = {
            { title = "일시", width = 96, render = function(e) return date("%m-%d %H:%M", e.at) end },
            { title = "구분", width = 44, align = "CENTER", render = function(e) return e.kind == "income" and T.Color("green", "수입") or T.Color("red", "지출") end },
            { title = "분류", width = 120, render = function(e) return LG:CategoryLabel(e.category) end },
            { title = "금액", width = 120, align = "RIGHT", render = function(e)
                local s = Money.Format(e.amount)
                if e.voided then return T.Color("muted", s .. " (취소)") end
                return e.kind == "income" and T.Color("green", s) or T.Color("red", s)
            end },
            { title = "출처", width = 70, render = function(e) return ({ trade = "거래", manual = "수동", system = "내부" })[e.source] or e.source end },
            { title = "상대/메모", width = 0, render = function(e) return (e.partnerKey and (BRL.API.ShortName(e.partnerKey) .. " · ") or "") .. (e.note or "") end },
        },
        onDoubleClick = function(e) page.detail(e) end,
    })
    page.list:SetPoint("TOPLEFT", 4, -168)
    page.list:SetPoint("BOTTOMRIGHT", -4, 40)
    page.detail = function(e)
        local lines = { "장부 ID: " .. e.id, "세션: " .. tostring(e.sessionId), "일시: " .. U.FormatDateTime(e.at),
            "구분: " .. (e.kind == "income" and "수입" or "지출") .. " / " .. LG:CategoryLabel(e.category), "금액: " .. Money.Format(e.amount),
            "출처: " .. tostring(e.source) .. (e.tradeId and (" (거래 " .. e.tradeId .. ")") or ""), "메모: " .. tostring(e.note or ""),
            e.voided and ("취소됨: " .. tostring(e.voidReason)) or "", "", "[수정 이력]" }
        for _, h in ipairs(e.history or {}) do
            lines[#lines + 1] = U.FormatDateTime(h.at) .. " " .. tostring(h.field) .. " " .. (h.reason or "")
        end
        D.CopyText("장부 상세", table.concat(lines, "\n"))
    end
    local function sel() return page.list:GetSelected() end
    local _, f = UI.BottomBar(page)
    f:Add(W.Button(f.parent, "수동 수입 기록", 104, 24, function() page.addManual("income") end, { kind = "primary", perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "수동 지출 기록", 104, 24, function() page.addManual("expense") end, { perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "수정", 50, 24, function()
        local e = sel()
        if not e then return end
        if e.source ~= "manual" then D.Message("거래에서 생성된 장부 항목은 거래 로그에서 정정하세요 (원본 보존).") return end
        D.Input("장부 기록 수정", {
            { key = "amount", label = "금액", type = "money", default = e.amount, required = true },
            { key = "note", label = "메모", type = "text", default = e.note },
            { key = "reason", label = "수정 사유", type = "text", required = true },
        }, function(v) return LG:EditManual(e.id, v.amount, v.note, v.reason) end)
    end, { perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "취소/복원", 76, 24, function()
        local e = sel()
        if not e then return end
        if e.voided then D.Reason("기록 복원", function(r) return LG:RestoreManual(e.id, r) end)
        else D.Reason("기록 취소", function(r) return LG:VoidManual(e.id, r) end) end
    end, { perm = "finance.edit" }))
    f:Add(W.Button(f.parent, "상세/이력", 76, 24, function() local e = sel() if e then page.detail(e) end end))
    f:Add(W.Button(f.parent, "장부 내보내기(CSV)", 130, 24, function()
        local s = BRL.Session:GetActive()
        D.CopyText("골드 장부 CSV", LG:ExportCSV(s and s.id))
    end))
    page.addManual = function(kind)
        local s = BRL.Session:GetActive()
        if not s then D.Message("공격대 세션이 없습니다.") return end
        local cats = {}
        for _, c in ipairs(kind == "income" and LG.MANUAL_INCOME or LG.MANUAL_EXPENSE) do cats[#cats + 1] = { value = c, text = LG:CategoryLabel(c) } end
        D.Input(kind == "income" and "수동 수입 기록" or "수동 지출 기록", {
            { key = "category", label = "분류", type = "dropdown", items = cats, default = cats[1].value },
            { key = "amount", label = "금액", type = "money", required = true },
            { key = "note", label = "기록 사유", type = "text", required = true },
        }, function(v) local e, err = LG:AddManual(s.id, kind, v.category, v.amount, v.note) return e ~= nil, err end,
        { description = "거래 창을 통하지 않은 골드 이동만 기록하세요. 거래로 오간 골드는 자동 기록됩니다." })
    end
end

local function refresh(page)
    local s = BRL.Session:GetActive()
    if not s then
        for _, t in pairs(page.tiles) do t:SetValue("-", "muted") end
        page.list:SetData({})
        return
    end
    local sum = LG:Summary(s.id)
    for _, t in ipairs(TILES) do
        local v = sum[t.key] or 0
        local color = "goldBright"
        if t.key == "outstanding" or t.key == "unpaid" or t.key == "unallocatedAuctionIncome" then color = v > 0 and "red" or "green" end
        page.tiles[t.key]:SetValue(Money.Format(v, { goldOnly = v % 10000 == 0 }), color)
    end
    page.list:SetData(LG:Entries(s.id, {
        kind = page.kind:GetValue() or nil, source = page.source:GetValue() or nil,
        search = page.search:GetText(), includeVoided = page.showVoided:GetChecked(),
    }), true)
    UI:SetPermBanner(page, "finance.edit")
end

UI:RegisterPage("ledger", { title = L.MENU_LEDGER, order = 12, build = build, refresh = refresh })
