-- BIG RAID LEADER - 공격대 통계 화면
local _, BRL = ...
local T, W, L, U, Money = BRL.Theme, BRL.Widgets, BRL.L, BRL.Util, BRL.Money
local UI, D = BRL.UI, BRL.Dialogs

local ST = BRL.Statistics

local function build(page)
    UI:PageHeader(page, L.MENU_STATS, "전투 진행 · 경매 · 정산 통계 (현재 세션)")
    page.combat = W.Paragraph(page, "", 280, 12)
    page.combat:SetPoint("TOPLEFT", 4, -52)
    page.auction = W.Paragraph(page, "", 290, 12)
    page.auction:SetPoint("TOPLEFT", 300, -52)
    page.settle = W.Paragraph(page, "", 290, 12)
    page.settle:SetPoint("TOPLEFT", 604, -52)
    local s1 = W.Section(page, "전투 진행")
    s1:SetPoint("TOPLEFT", 4, -30)
    local s2 = W.Section(page, "경매")
    s2:SetPoint("TOPLEFT", 300, -30)
    local s3 = W.Section(page, "정산")
    s3:SetPoint("TOPLEFT", 604, -30)
    local s4 = W.Section(page, "보스별 진행")
    s4:SetPoint("TOPLEFT", 4, -232)
    page.bosses = W.List(page, {
        columns = {
            { title = "보스", width = 0, render = function(r) return r.plan.name end },
            { title = "시도", width = 50, align = "CENTER", render = function(r) return r.progress.attempts or 0 end },
            { title = "전멸", width = 50, align = "CENTER", render = function(r) return r.progress.wipes or 0 end },
            { title = "처치", width = 50, align = "CENTER", render = function(r) return r.killed and T.Color("green", "✔") or "" end },
            { title = "처치 시간", width = 80, align = "CENTER", render = function(r) return r.bestKill and U.FormatDuration(r.bestKill) or "-" end },
        },
    })
    page.bosses:SetPoint("TOPLEFT", 4, -256)
    page.bosses:SetSize(440, 300)
    local s5 = W.Section(page, "지난 공격대 세션")
    s5:SetPoint("TOPLEFT", 456, -232)
    page.history = W.List(page, {
        columns = {
            { title = "세션", width = 0, render = function(h) return h.session.name end },
            { title = "경매액", width = 90, align = "RIGHT", render = function(h) return Money.Format(h.auctionTotal, { goldOnly = true }) end },
            { title = "수금", width = 90, align = "RIGHT", render = function(h) return Money.Format(h.collected, { goldOnly = true }) end },
            { title = "정산", width = 70, render = function(h) return h.settlement ~= "-" and BRL.Label("SETTLE_", h.settlement) or "-" end },
        },
        onDoubleClick = function(h) BRL.Session:SetActive(h.session.id) end,
        tooltip = function(h) return h.session.name, { U.FormatDateTime(h.session.startedAt), "더블클릭: 이 세션 보기" } end,
    })
    page.history:SetPoint("TOPLEFT", 456, -256)
    page.history:SetSize(428, 300)
    local _, f = UI.BottomBar(page)
    f:Add(W.Button(f.parent, "통계 복사", 80, 24, function()
        D.CopyText("공격대 통계", U.StripColors(page.combat:GetText() .. "\n\n" .. page.auction:GetText() .. "\n\n" .. page.settle:GetText()))
    end))
end

local function refresh(page)
    local s = BRL.Session:GetActive()
    local c = ST:Combat(s and s.id)
    page.combat:SetText(table.concat({
        string.format("보스 처치: %d / %d (%d%%)", c.killed, c.total, c.percent),
        "총 시도: " .. c.attempts .. "회",
        "총 전멸: " .. c.wipes .. "회",
        "공격대 진행 시간: " .. (c.elapsed and U.FormatDuration(c.elapsed) or "-"),
    }, "\n"))
    page.bosses:SetData(c.rows, true)
    if s then
        local a = ST:Auction(s.id)
        page.auction:SetText(table.concat({
            "경매 아이템: " .. a.items .. "개 (대기 " .. a.queued .. ")",
            "낙찰: " .. a.awarded .. " · 유찰: " .. a.unsold .. " · 취소: " .. a.cancelled,
            "총 낙찰 금액: " .. Money.Format(a.total),
            "평균 낙찰 금액: " .. Money.Format(a.average),
            "최고가: " .. (a.top and (U.StripColors(a.top.itemName or "?") .. " " .. Money.Format(a.top.amount)) or "-"),
            "실제 수금 비율: " .. a.collectRate .. "%",
            "총 미수금: " .. Money.Format(a.outstanding),
        }, "\n"))
        local st = ST:Settlement(s.id)
        page.settle:SetText(table.concat({
            "전체 수금액: " .. Money.Format(st.collected),
            "전체 분배액: " .. Money.Format(st.distributed),
            "공제 총액: " .. Money.Format(st.deductions),
            "분배 대상 인원: " .. st.headcount .. "명",
            "평균 분배액: " .. Money.Format(st.average),
            "지급 완료: " .. st.paidCount .. "명 · 미지급: " .. st.unpaidCount .. "명",
            "미지급 총액: " .. Money.Format(st.unpaid),
            "정산 잔액(장부): " .. Money.Format(st.balance),
        }, "\n"))
    else
        page.auction:SetText("공격대 세션 없음")
        page.settle:SetText("")
    end
    page.history:SetData(ST:History(), true)
end

UI:RegisterPage("stats", { title = L.MENU_STATS, order = 14, build = build, refresh = refresh })
