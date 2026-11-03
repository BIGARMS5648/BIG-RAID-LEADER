-- BIG RAID LEADER - 골드 정산 보고서 (SettlementReport)
-- 상세/간략/디스코드 보고서, 채팅 분할 출력, 확정 시 버전별 스냅샷 보관.
local _, BRL = ...
local U, DB, Money = BRL.Util, BRL.DB, BRL.Money

local R = BRL:NewModule("Reports")

local function raidName(session)
    if not session then return "-" end
    local raid = session.raidKey and BRL.Data.Raids[session.raidKey]
    return raid and raid.name or session.name or "-"
end

local function statusLabel(st)
    if not st then return "-" end
    return BRL.Label("SETTLE_", st.status)
end

local function resultFor(st, basis)
    if st.result and st.locked then return st.result end
    return BRL.Settlement:Compute(st, basis or "confirmed")
end

function R:BuildBrief(stId)
    local st = BRL.Settlement:Get(stId)
    if not st then return {} end
    local session = BRL.Session:Get(st.sessionId)
    local r = resultFor(st)
    local pay = BRL.Settlement:PaymentState(stId)
    local lines = {
        "[BIG RAID LEADER 정산]",
        "공격대: " .. raidName(session),
        "총 경매액: " .. Money.Format(r.totalAwarded),
        "실제 수금: " .. Money.Format(r.collected),
    }
    if r.outstanding > 0 then lines[#lines + 1] = "미수금: " .. Money.Format(r.outstanding) end
    if r.otherIncome > 0 then lines[#lines + 1] = "기타 수입: " .. Money.Format(r.otherIncome) end
    if r.carryIn > 0 then lines[#lines + 1] = "이월 잔돈: " .. Money.Format(r.carryIn) end
    local opTotal = r.operating + r.ledgerExpenses
    if opTotal > 0 then lines[#lines + 1] = "운영비: " .. Money.Format(opTotal) end
    if r.deductions > 0 then lines[#lines + 1] = "기타 공제: " .. Money.Format(r.deductions) end
    if r.leaderFee > 0 then lines[#lines + 1] = "공대장 수수료: " .. Money.Format(r.leaderFee) end
    if r.reserve > 0 then lines[#lines + 1] = "예비금: " .. Money.Format(r.reserve) end
    lines[#lines + 1] = "분배 가능: " .. Money.Format(r.distributable)
    lines[#lines + 1] = "분배 인원: " .. r.headcount .. "명"
    if r.equalShares then
        lines[#lines + 1] = "1인당 분배: " .. Money.Format(r.perPerson)
    else
        lines[#lines + 1] = "평균 분배: " .. Money.Format(r.perPerson) .. " (차등 분배)"
    end
    if (r.kept or 0) + (r.carryOut or 0) > 0 then
        lines[#lines + 1] = "잔돈: " .. Money.Format(r.kept + r.carryOut) .. (r.carryOut > 0 and " (다음 정산 이월)" or " (보관)")
    end
    if st.status ~= "draft" then lines[#lines + 1] = "미지급: " .. Money.Format(pay.unpaid) end
    lines[#lines + 1] = "정산 상태: " .. (st.status == "draft" and ("예상(" .. (r.basis == "estimated" and "전원 완납 가정" or "현재 수금 기준") .. ")") or statusLabel(st))
    return lines
end

function R:BuildDetailed(stId)
    local st = BRL.Settlement:Get(stId)
    if not st then return {} end
    local session = BRL.Session:Get(st.sessionId)
    local r = resultFor(st)
    local pay = BRL.Settlement:PaymentState(stId)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("==== BIG RAID LEADER 상세 정산 보고서 ====")
    add("공격대: " .. raidName(session) .. " (" .. (session and session.name or "-") .. ")")
    add("진행 날짜: " .. U.FormatDateTime(session and session.startedAt))
    add("보고서 버전: v" .. (st.version or 0) .. " / 상태: " .. statusLabel(st) .. " / 생성: " .. U.FormatDateTime(U.Now()))
    add("참가 인원: " .. U.Count(session and session.attendance or {}) .. "명 / 분배 인원: " .. r.headcount .. "명")
    add("")
    add("[경매 내역]")
    local awards = BRL.Auctions:Awards(st.sessionId, true)
    for _, aw in ipairs(awards) do
        local s = BRL.Payments:AwardStatus(aw)
        add(string.format("- %s | %s | %s | 수금 %s | %s%s", U.StripColors(U.ItemNameFromLink(aw.itemLink) or aw.itemName or "?"),
            aw.winnerName or "?", Money.Format(aw.amount), Money.Format(s.collected), BRL.Label("AWARD_", s.status),
            aw.status == "cancelled" and (" (취소: " .. tostring(aw.cancelReason) .. ")") or ""))
    end
    if #awards == 0 then add("- (없음)") end
    local unsold = BRL.Auctions:List(st.sessionId, { unsold = true })
    if #unsold > 0 then
        local names = {}
        for _, a in ipairs(unsold) do names[#names + 1] = U.StripColors(a.itemName or "?") end
        add("유찰: " .. table.concat(names, ", "))
    end
    add("")
    add("[수입]")
    add("총 경매액: " .. Money.Format(r.totalAwarded))
    add("실제 수금액: " .. Money.Format(r.collected))
    add("미수금: " .. Money.Format(r.outstanding))
    add("기타 수입: " .. Money.Format(r.otherIncome))
    add("이월 잔돈 사용: " .. Money.Format(r.carryIn))
    add("총수입(분배 기준): " .. Money.Format(r.gross))
    add("")
    add("[공제]")
    add("장부 지출(운영/기타): " .. Money.Format(r.ledgerExpenses))
    for _, c in ipairs(st.config.operatingCosts or {}) do add("운영비 - " .. c.label .. ": " .. Money.Format(c.amount)) end
    for _, c in ipairs(st.config.deductions or {}) do add("공제 - " .. c.label .. ": " .. Money.Format(c.amount)) end
    add("공대장 수수료: " .. Money.Format(r.leaderFee))
    add("예비금: " .. Money.Format(r.reserve))
    add("분배 가능 금액: " .. Money.Format(r.distributable))
    add("")
    add("[개인별 분배액]")
    local payByKey = {}
    for _, row in ipairs(pay.rows) do
        if row.ob.kind == "share" then payByKey[row.ob.memberKey] = row end
    end
    local rows = {}
    for _, row in ipairs(r.rows) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if a.subgroup ~= b.subgroup then return (a.subgroup or 9) < (b.subgroup or 9) end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        local p = payByKey[row.key]
        local extra = {}
        if row.bonus > 0 then extra[#extra + 1] = "보너스 " .. Money.Format(row.bonus) end
        if row.manual then extra[#extra + 1] = "수동 지정" end
        if row.remainderAdd > 0 then extra[#extra + 1] = "잔돈 " .. Money.Format(row.remainderAdd) end
        add(string.format("%d파티 %s: %s%s%s", row.subgroup or 1, row.name, Money.Format(row.total),
            #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "",
            p and (" - " .. BRL.Label("PAY_", p.status) .. (p.remaining > 0 and (" 남은 " .. Money.Format(p.remaining)) or "")) or ""))
    end
    add("")
    add("[파티별 지급액]")
    local parties = {}
    for g, party in pairs(st.status == "draft" and r.parties or pay.parties) do parties[#parties + 1] = { g = g, p = party } end
    table.sort(parties, function(a, b) return a.g < b.g end)
    for _, e in ipairs(parties) do
        local party = e.p
        if party.paidCount then
            add(string.format("%d파티: %d명 / 총 %s / 완료 %d명 / 미지급 %d명 / 남은 %s", e.g, party.count,
                Money.Format(party.total), party.paidCount, party.unpaidCount, Money.Format(party.remaining)))
        else
            add(string.format("%d파티: %d명 / 총 %s", e.g, party.count, Money.Format(party.total)))
        end
    end
    if st.status ~= "draft" then
        add("")
        local paid, unpaid = {}, {}
        for _, row in ipairs(pay.rows) do
            local label = (row.ob.name or "?") .. (row.ob.kind == "fee" and "(수수료)" or "")
            if row.remaining == 0 then paid[#paid + 1] = label else unpaid[#unpaid + 1] = label .. " " .. Money.Format(row.remaining) end
        end
        add("지급 완료: " .. (#paid > 0 and table.concat(paid, ", ") or "-"))
        add("미지급: " .. (#unpaid > 0 and table.concat(unpaid, ", ") or "-"))
        add("미지급 총액: " .. Money.Format(pay.unpaid))
    end
    add("잔돈: " .. Money.Format((r.kept or 0) + (r.carryOut or 0)) .. ((r.carryOut or 0) > 0 and " (다음 정산 이월)" or ""))
    local summary = BRL.Ledger:Summary(st.sessionId)
    add("장부 잔액: " .. Money.Format(summary.balance))
    if #r.warnings > 0 then
        add("")
        add("[경고]")
        for _, w in ipairs(r.warnings) do add("- " .. w) end
    end
    if #r.errors > 0 then
        add("[오류]")
        for _, e in ipairs(r.errors) do add("- " .. e) end
    end
    return lines
end

function R:BuildDiscord(stId)
    local brief = self:BuildBrief(stId)
    local st = BRL.Settlement:Get(stId)
    local out = { "**" .. (brief[1] or "[BIG RAID LEADER 정산]") .. "**", "```" }
    for i = 2, #brief do out[#out + 1] = U.StripColors(brief[i]) end
    out[#out + 1] = "```"
    if st then
        local r = resultFor(st)
        out[#out + 1] = "**개인별 분배**"
        out[#out + 1] = "```"
        local rows = {}
        for _, row in ipairs(r.rows) do rows[#rows + 1] = row end
        table.sort(rows, function(a, b)
            if a.subgroup ~= b.subgroup then return (a.subgroup or 9) < (b.subgroup or 9) end
            return a.name < b.name
        end)
        for _, row in ipairs(rows) do
            out[#out + 1] = string.format("%d파티 %-12s %s", row.subgroup or 1, row.name, Money.Format(row.total))
        end
        out[#out + 1] = "```"
    end
    return out
end

function R:ToText(lines)
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = U.StripColors(l):gsub("|H.-|h(.-)|h", "%1") end
    return table.concat(out, "\n")
end

-- 채팅 출력 (255바이트 분할은 ChatOut 에서 처리)
function R:SendToChat(lines, channel, target)
    if not channel then channel = BRL.acct.chat.reportChannel or "RAID" end
    if BRL.ChatOut.QUEUEABLE[channel] then
        BRL.ChatOut:SendLines(lines, channel, target)
        return true
    end
    -- 공개 채널 등은 클릭 시점 즉시 전송
    for _, l in ipairs(lines) do
        local ok = BRL.ChatOut:SendNow(l, channel, target)
        if not ok then return false end
    end
    return true
end

-- 버전별 보고서 스냅샷
function R:Snapshot(st)
    local rep = DB:Insert("reports", {
        settlementId = st.id, sessionId = st.sessionId, version = st.version or 0, status = st.status,
        at = U.Now(), brief = self:ToText(self:BuildBrief(st.id)), detailed = self:ToText(self:BuildDetailed(st.id)),
    })
    return rep
end

function R:History(stId)
    return DB:List("reports", function(r) return r.settlementId == stId end, "at", true)
end

-- 공격대원용: 개인 분배 예정액/지급 상태 안내 문구
function R:MemberPayoutLine(ob)
    local s = BRL.Payments:ObligationStatus(ob)
    return string.format("[BRL] %s님 분배 예정액 %s / 지급 %s / 상태: %s", ob.name or "?", Money.Format(ob.amount),
        Money.Format(s.paid), BRL.Label("PAY_", s.status))
end
