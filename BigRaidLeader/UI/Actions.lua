-- BIG RAID LEADER - UI 공용 동작 (대화상자 흐름)
local _, BRL = ...
local D, Money, API, U, T = BRL.Dialogs, BRL.Money, BRL.API, BRL.Util, BRL.Theme

local A = {}
BRL.UIActions = A

local function report(ok, err)
    if not ok and err then BRL:Print("|cffff5555실패|r: %s", tostring(err)) end
    return ok
end
A.Report = report

---------------------------------------------------------------------------
-- 거래 → 낙찰 수금 연결
---------------------------------------------------------------------------
function A.LinkTradeToAward(tr)
    local J, P = BRL.TradeJournal, BRL.Payments
    if not J:IsCounted(tr) then
        D.Message("완료가 확인되지 않은 거래(" .. J:StatusLabel(tr) .. ")는 경매금으로 연결할 수 없습니다.\n거래 로그에서 수동 확인 후 연결하세요.")
        return
    end
    local avail = P:TradeAvailableIn(tr)
    if avail <= 0 then D.Message("이 거래에는 연결 가능한 받은 골드가 없습니다.") return end
    local items = {}
    local awards = BRL.DB:List("awards", function(a) return a.status == "active" end, "awardedAt")
    table.sort(awards, function(a, b)
        local am, bm = a.winnerKey == tr.partnerKey, b.winnerKey == tr.partnerKey
        if am ~= bm then return am end
        return (a.awardedAt or 0) < (b.awardedAt or 0)
    end)
    for _, aw in ipairs(awards) do
        local st = P:AwardStatus(aw)
        if st.outstanding > 0 then
            items[#items + 1] = {
                value = aw.id,
                text = (aw.winnerKey == tr.partnerKey and "|cff5cf272★|r " or "|cff9e9a8f(대리)|r ") .. BRL.Data.ColorName(aw.winnerName, aw.winnerClass) .. " - " .. (aw.itemLink or aw.itemName or "?"),
                sub = "미수 " .. Money.Format(st.outstanding),
            }
        end
    end
    if #items == 0 then D.Message("미수금이 남은 낙찰이 없습니다.") return end
    D.Select("경매금 수금 연결 - 낙찰 선택", items, function(awardId)
        local aw = BRL.Auctions:GetAward(awardId)
        local st = P:AwardStatus(aw)
        local default = math.min(avail, st.outstanding)
        D.Input("연결 금액", {
            { key = "amount", label = "연결 금액", type = "money", default = default, required = true },
        }, function(v)
            local res, err = P:AllocateAuction(tr.id, awardId, v.amount)
            if res then return true end
            if err == "overpay" then
                D.Confirm(string.format("낙찰 미수금(%s)보다 %s 많습니다. 초과 입금으로 기록할까요?",
                    Money.Format(st.outstanding), Money.Format(v.amount - st.outstanding)), function()
                    report(P:AllocateAuction(tr.id, awardId, v.amount, { allowOverpay = true }))
                end, { title = "초과 입금 경고", danger = true })
                return true
            end
            return false, err
        end, { description = string.format("거래 미연결 금액: %s / 낙찰 미수금: %s", Money.Format(avail), Money.Format(st.outstanding)) })
    end, { description = string.format("%s 님과의 거래 (연결 가능 %s). ★ = 거래 상대의 낙찰, (대리) = 다른 사람 낙찰 대리 입금",
        tr.partnerName or "?", Money.Format(avail)) })
end

---------------------------------------------------------------------------
-- 거래 → 분배금 지급 연결 (개인/파티 대표)
---------------------------------------------------------------------------
function A.LinkTradeToPayout(tr)
    local J, P = BRL.TradeJournal, BRL.Payments
    if not J:IsCounted(tr) then
        D.Message("완료가 확인되지 않은 거래(" .. J:StatusLabel(tr) .. ")는 분배 지급으로 연결할 수 없습니다.")
        return
    end
    local avail = P:TradeAvailableOut(tr)
    if avail <= 0 then D.Message("이 거래에는 연결 가능한 지급 골드가 없습니다.") return end
    local items = {}
    local obs = BRL.DB:List("payouts", function(o) return not o.voided end, "subgroup")
    table.sort(obs, function(a, b)
        local am, bm = a.memberKey == tr.partnerKey, b.memberKey == tr.partnerKey
        if am ~= bm then return am end
        if (a.subgroup or 0) ~= (b.subgroup or 0) then return (a.subgroup or 0) < (b.subgroup or 0) end
        return (a.name or "") < (b.name or "")
    end)
    for _, ob in ipairs(obs) do
        local st = P:ObligationStatus(ob)
        if st.remaining > 0 then
            items[#items + 1] = {
                value = ob.id,
                text = (ob.memberKey == tr.partnerKey and "|cff5cf272★|r " or "") .. (ob.subgroup or 1) .. "파티 " .. BRL.Data.ColorName(ob.name, ob.class) .. (ob.kind == "fee" and " (수수료)" or ""),
                sub = "남은 " .. Money.Format(st.remaining),
            }
        end
    end
    if #items == 0 then D.Message("미지급 분배가 없습니다. 정산을 먼저 확정하세요.") return end
    D.Select("분배 지급 연결 - 대상 선택", items, function(obId)
        local ob = BRL.DB:Get("payouts", obId)
        local st = P:ObligationStatus(ob)
        local default = math.min(avail, st.remaining)
        D.Input("지급 연결 금액", {
            { key = "amount", label = "연결 금액", type = "money", default = default, required = true },
        }, function(v)
            local opts = {}
            local function try()
                local res, err, info = P:AllocatePayout(tr.id, obId, v.amount, opts)
                if res then return true end
                if err == "proxy" then
                    D.Confirm(string.format("%s 님의 분배금을 %s 님에게 지급(대표 수령)한 것으로 기록할까요?",
                        API.ShortName(info.member), API.ShortName(info.recipient)), function()
                        opts.proxy = true
                        report(try())
                    end, { title = "대표 수령 확인" })
                    return true
                elseif err == "overpay" then
                    D.Confirm("남은 지급액보다 큰 금액입니다. 초과 지급으로 기록할까요? (지급 확인 필요로 표시)", function()
                        opts.allowOverpay = true
                        report(try())
                    end, { title = "초과 지급 경고", danger = true })
                    return true
                end
                return false, err
            end
            return try()
        end, { description = string.format("거래 미연결 지급액: %s / 남은 분배액: %s", Money.Format(avail), Money.Format(st.remaining)) })
    end, { description = "한 번의 거래 금액은 여러 명에게 나누어 연결할 수 있지만, 연결 합계는 거래 금액을 넘을 수 없습니다 (중복 지급 방지)." })
end

function A.LinkRefund(tr)
    local P = BRL.Payments
    local avail = P:TradeAvailableOut(tr)
    local items = {}
    for _, aw in ipairs(BRL.DB:List("awards", function(a) return a.status == "cancelled" end, "awardedAt")) do
        local st = P:AwardStatus(aw)
        if (st.refundDue or 0) > 0 then
            items[#items + 1] = { value = aw.id, text = aw.winnerName .. " - " .. (aw.itemName or "?"), sub = "환불 필요 " .. Money.Format(st.refundDue) }
        end
    end
    if #items == 0 then D.Message("환불이 필요한 낙찰 취소 건이 없습니다.") return end
    D.Select("경매금 환불 연결", items, function(awardId)
        local st = P:AwardStatus(BRL.Auctions:GetAward(awardId))
        D.Input("환불 금액", { { key = "amount", label = "환불 금액", type = "money", default = math.min(avail, st.refundDue), required = true } }, function(v)
            return P:AllocateRefund(tr.id, awardId, v.amount)
        end)
    end)
end

---------------------------------------------------------------------------
-- 거래 기록 관리
---------------------------------------------------------------------------
function A.PurposeItems()
    local items = {}
    for _, p in ipairs(BRL.TradeJournal.PURPOSES) do items[#items + 1] = { value = p, text = BRL.TradeJournal:PurposeLabel(p) } end
    return items
end

function A.ChangePurpose(tr)
    D.Input("거래 목적 변경", {
        { key = "purpose", label = "거래 목적", type = "dropdown", items = A.PurposeItems(), default = tr.purpose },
        { key = "reason", label = "변경 사유", type = "text" },
    }, function(v)
        return BRL.TradeJournal:SetPurpose(tr.id, v.purpose, v.reason ~= "" and v.reason or nil)
    end, { description = "개인 거래와 분류되지 않은 거래는 공대 장부에 반영되지 않습니다." })
end

function A.AdjustTrade(tr)
    local eff = BRL.TradeJournal:Effective(tr)
    D.Input("거래 금액 정정 (수동 조정)", {
        { key = "received", label = "받은 골드", type = "money", default = eff.received },
        { key = "given", label = "지급 골드", type = "money", default = eff.given },
        { key = "reason", label = "정정 사유", type = "text", required = true },
    }, function(v)
        return BRL.TradeJournal:Adjust(tr.id, v.given, v.received, v.reason)
    end, { description = "원본 기록(받은 " .. Money.Format(tr.targetMoney) .. " / 지급 " .. Money.Format(tr.playerMoney) .. ")은 그대로 보존되고, 정정 금액과 사유가 수정 이력에 남습니다." })
end

function A.ConfirmTrade(tr)
    D.Reason("거래 수동 확인", function(reason)
        return BRL.TradeJournal:ConfirmManually(tr.id, reason)
    end, "게임에서 거래 완료를 확인하지 못한 기록입니다. 실제로 거래가 완료되었는지(가방/골드) 직접 확인한 뒤에만 승인하세요. 승인하면 확정 금액으로 합산됩니다.")
end

function A.VoidTrade(tr)
    D.Reason("거래 기록 취소", function(reason)
        return BRL.TradeJournal:Void(tr.id, reason)
    end, "기록은 삭제되지 않고 '기록 취소' 상태로 보존됩니다. 언제든 복원할 수 있습니다.")
end

function A.AddManualTrade()
    D.Input("수동 거래 기록 (누락된 거래 추가)", {
        { key = "partner", label = "거래 상대", type = "text", required = true, placeholder = "캐릭터명 또는 이름-서버" },
        { key = "received", label = "받은 골드", type = "money" },
        { key = "given", label = "지급 골드", type = "money" },
        { key = "purpose", label = "거래 목적", type = "dropdown", items = A.PurposeItems(), default = "unclassified" },
        { key = "note", label = "기록 사유", type = "text", required = true },
    }, function(v)
        local rec, err = BRL.TradeJournal:AddManual({ partner = v.partner, received = v.received or 0, given = v.given or 0, purpose = v.purpose, note = v.note })
        if not rec then return false, err end
        return true
    end, { description = "수동 기록은 '수동 확인' 상태로 저장되며 자동 기록과 구분됩니다." })
end

function A.TradeDetail(tr)
    local J = BRL.TradeJournal
    local eff = J:Effective(tr)
    local lines = {
        "거래 ID: " .. tr.id,
        "일시: " .. U.FormatDateTime(tr.at) .. (tr.openedAt and (" (창 열림 " .. U.FormatClock(tr.openedAt) .. ")") or ""),
        "상대: " .. tostring(tr.partnerKey) .. (tr.partnerGuid and ("  [" .. tr.partnerGuid .. "]") or ""),
        "받은 골드: " .. Money.Format(eff.received) .. "   지급 골드: " .. Money.Format(eff.given),
        "상태: " .. J:StatusLabel(tr) .. " (검증: " .. J:VerificationLabel(tr.verification) .. ")",
        "목적: " .. J:PurposeLabel(tr.purpose) .. "   세션: " .. tostring(tr.sessionId and (BRL.Session:Get(tr.sessionId) or {}).name or "-"),
        "기록 방식: " .. (tr.source == "manual" and "수동" or (tr.source == "self" and "본인 지급 (공대장 본인 낙찰 등)" or "자동")),
    }
    if tr.adjusted then lines[#lines + 1] = "원본 금액: 받은 " .. Money.Format(tr.targetMoney) .. " / 지급 " .. Money.Format(tr.playerMoney) .. " (정정 사유: " .. tostring(tr.adjusted.reason) .. ")" end
    if tr.moneyDelta then lines[#lines + 1] = "실제 보유 골드 변화: " .. Money.Format(tr.moneyDelta, { sign = true }) end
    if tr.note then lines[#lines + 1] = "메모: " .. tr.note end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[받은 아이템]"
    for _, it in ipairs(tr.targetItems or {}) do lines[#lines + 1] = "  " .. (it.link or it.name) .. " x" .. (it.count or 1) end
    lines[#lines + 1] = "[지급 아이템]"
    for _, it in ipairs(tr.playerItems or {}) do lines[#lines + 1] = "  " .. (it.link or it.name) .. " x" .. (it.count or 1) end
    local links = BRL.Payments:LinksForTrade(tr.id)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[연결]"
    for _, a in ipairs(links.awards) do
        local aw = BRL.Auctions:GetAward(a.awardId)
        lines[#lines + 1] = string.format("  %s %s → %s (%s)%s", a.kind == "refund" and "환불" or "수금", Money.Format(a.amount),
            aw and (aw.winnerName .. " " .. (aw.itemName or "")) or "?", a.id, a.proxy and " [대리]" or "")
    end
    for _, a in ipairs(links.payouts) do
        local ob = BRL.DB:Get("payouts", a.obligationId)
        lines[#lines + 1] = string.format("  지급 %s → %s (%s)%s", Money.Format(a.amount), ob and ob.name or "?", a.id, a.proxy and " [대표 수령]" or "")
    end
    if tr.eventTrace and #tr.eventTrace > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[거래 이벤트 추적]" .. (tr.finalizeReason and (" 판정 사유: " .. tostring(tr.finalizeReason)) or "")
        for _, l in ipairs(BRL.TradeTracker:FormatEvents(tr.eventTrace)) do lines[#lines + 1] = "  " .. l end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[수정 이력]"
    for _, h in ipairs(tr.history or {}) do
        lines[#lines + 1] = string.format("  %s %s: %s → %s %s", U.FormatDateTime(h.at), h.field,
            type(h.old) == "table" and "(표)" or tostring(h.old), type(h.new) == "table" and "(표)" or tostring(h.new), h.reason and ("- " .. h.reason) or "")
    end
    D.CopyText("거래 상세 - " .. (tr.partnerName or "?"), U.StripColors(table.concat(lines, "\n")))
end

-- 지휘 명령 목록 (전투 지휘 화면 · HUD 공용). opts: pull(초), breakMin(분), bossKey
local function briefingBoss(opts)
    local key = opts and opts.bossKey
    if not key or key == "default" then key = BRL.RaidProgress:GetCurrentBoss() end
    if not key then
        local active = BRL.BossPlans:ActivePlanKey()
        if active ~= "default" then key = active end
    end
    return key
end
A.COMMANDS = {
    { key = "ready", label = "준비 확인", hud = "준비 확인", primary = true, run = function() BRL.Command:ReadyCheck() end },
    { key = "pull", label = "풀링 카운트다운", primary = true,
        hud = function() return "풀링 " .. BRL.acct.command.pullSeconds .. "초" end,
        run = function(opts) A.PullWithCheck((opts and opts.pull) or BRL.acct.command.pullSeconds) end },
    { key = "cancelpull", label = "풀링 취소", hud = "풀링 취소", primary = true, run = function() BRL.Command:CancelPull() end },
    { key = "stop", label = "공격 중지", hud = "공격 중지", run = function() BRL.Command:Stop() end },
    { key = "retreat", label = "후퇴", hud = "후퇴", run = function() BRL.Command:Retreat() end },
    { key = "regroup", label = "전투 재정비", hud = "재정비", run = function() BRL.Command:Regroup() end },
    { key = "break", label = "휴식 시작",
        hud = function() return BRL.Command:BreakRemaining() and "휴식 종료" or ("휴식 " .. BRL.acct.command.breakMinutes .. "분") end,
        run = function(opts)
            -- HUD 에서는 한 버튼으로 시작/종료 전환
            if opts and opts.toggle and BRL.Command:BreakRemaining() then return BRL.Command:BreakEnd() end
            return BRL.Command:BreakStart((opts and opts.breakMin) or BRL.acct.command.breakMinutes)
        end },
    { key = "breakend", label = "휴식 종료", run = function() BRL.Command:BreakEnd() end },
    { key = "prep", label = "전투 준비 (도핑 점검)", hud = "전투 준비", perm = false, run = function() BRL.CombatPrep:Run() end },
    { key = "briefing", label = "보스 공략 안내", hud = "공략 안내", run = function(opts)
        local key = briefingBoss(opts)
        if not key then BRL:Print("보스를 선택하거나 공략 화면에서 [준비 적용]으로 현재 보스를 지정하세요.") return end
        BRL.Command:BossBriefing(key)
    end },
    { key = "pullcheck", hud = "풀링 판정", perm = false, run = function() A.ShowPullCheck() end },
}
function A.Command(key, opts)
    for _, c in ipairs(A.COMMANDS) do
        if c.key == key then return c.run(opts) end
    end
end

-- 풀링: 판정이 "보류"면 사유를 보여주고 확인 후 진행 (공대장 판단 우선)
function A.PullWithCheck(seconds)
    seconds = seconds or BRL.acct.command.pullSeconds
    local pc = BRL.CombatPrep:PullCheck()
    if pc.verdict == "stop" and pc.label ~= "전투 중" then
        D.Confirm("풀링 보류 사유:\n· " .. table.concat(pc.reasons, "\n· ") .. "\n\n그래도 " .. seconds .. "초 풀링을 시작할까요?", function()
            BRL.Command:Pull(seconds)
        end, { danger = true, title = "풀링 판정: 보류", acceptText = "그래도 풀링" })
        return false
    end
    return BRL.Command:Pull(seconds)
end

-- 풀링 판정 결과 창
function A.ShowPullCheck()
    local pc = BRL.CombatPrep:PullCheck()
    local body = T.Color(pc.color, pc.label) .. (#pc.reasons > 0 and ("\n\n· " .. table.concat(pc.reasons, "\n· ")) or "\n\n준비 확인 · 도핑 · 역할 모두 정상입니다.")
    D.Confirm(body, function() A.SendLines(BRL.CombatPrep:PullCheckLines(pc), "풀링 판정") end,
        { title = "풀링 판정", acceptText = "공격대에 알리기", cancelText = "닫기" })
    return pc
end

-- 보스 준비 적용 (현재 보스 + 보스 편성/전술표/징표/메모/필수 버프)
function A.ApplyBossPrep(bossKey)
    if not bossKey then BRL:Print("보스를 선택하세요.") return end
    local res, err = BRL.BossPlans:ApplyPrep(bossKey)
    if not res then BRL:Print(tostring(err)) return end
    local text = table.concat(BRL.BossPlans:PrepLines(res), "\n")
    if res.groupTemplate and BRL.Perm:Can("raid.groups.apply") and API.IsInRaid() then
        D.Confirm(text .. "\n\n불러온 편성대로 실제 파티를 이동할까요?", function() BRL.Groups:Apply() end,
            { title = "보스 준비 적용", acceptText = "파티에 적용", cancelText = "나중에" })
    else
        D.Message(text, "보스 준비 적용")
    end
    return res
end

-- 공유 문자열 메뉴 (내보내기/가져오기)
-- textFn: 사람이 읽는 텍스트 복사(디스코드 등) 항목을 함께 보여줄 때
function A.ShareMenu(kind, key, title, textFn)
    local def = BRL.Share.KINDS[kind]
    if not def then return end
    local items = {
        { value = "export", text = "공유 문자열 만들기 (내보내기)", sub = "다른 공대장의 애드온으로 가져가기" },
        { value = "import", text = "공유 문자열 붙여넣기 (가져오기)" },
    }
    if textFn then table.insert(items, 1, { value = "text", text = "텍스트로 복사", sub = "디스코드/메모장에 붙여넣기" }) end
    D.Select((title or def.name) .. " 공유", items, function(v)
        if v == "text" then
            D.CopyText((title or def.name) .. " - 텍스트", textFn())
        elseif v == "export" then
            local str, label = BRL.Share:Export(kind, key)
            if not str then D.Message(tostring(label)) return end
            D.CopyText(def.name .. " 공유 - " .. tostring(label), str, { hint = "Ctrl+C 로 복사해 다른 공대장에게 전달하세요. 금융 기록은 포함되지 않습니다." })
        else
            A.ShareImport(key)
        end
    end)
end

function A.ShareImport(targetKey)
    D.Paste("공유 문자열 가져오기", function(text)
        local payload, desc = BRL.Share:Preview(text)
        if not payload then return false, desc end
        local where = targetKey and (payload.kind == "roles" or payload.kind == "markers" or payload.kind == "notes")
            and ("\n적용 대상: " .. tostring(targetKey) .. " (현재 화면의 전술표)") or ""
        D.Confirm(desc .. where .. "\n\n가져올까요? (가져오기 전 자동 백업)", function()
            local useKey = (payload.kind == "roles" or payload.kind == "markers" or payload.kind == "notes") and targetKey or nil
            local ok, res = BRL.Share:Apply(payload, useKey)
            D.Message(ok and ("가져오기 완료: " .. tostring(res)) or ("가져오기 실패: " .. tostring(res)))
        end, { title = "공유 문자열 가져오기" })
        return true
    end, "BRL:share_ 로 시작하는 문자열을 붙여넣으세요.")
end

-- 미수금 알림 (미수금 안내 공지 + 독촉 귓속말 통합)
function A.Dunning()
    local s = BRL.Session:GetActive()
    if not s then D.Message("공격대 세션이 없습니다.") return end
    local debtors = BRL.Payments:Debtors(s.id)
    if #debtors == 0 then D.Message("미수금이 남은 낙찰자가 없습니다.") return end
    local lines, total = {}, 0
    for _, d in ipairs(debtors) do
        lines[#lines + 1] = string.format("%s %s (%s)", d.name, Money.Format(d.outstanding), table.concat(d.items, ", "))
        total = total + d.outstanding
    end
    D.Select("미수금 알림", {
        { value = "whisper", text = "각자에게 귓속말 (권장)", sub = "같은 사람은 60초 안에 다시 보내지 않음" },
        { value = "raid", text = "공격대 채팅에 목록 공지" },
    }, function(v)
        if v == "raid" then
            A.SendLines(BRL.Payments:DebtorLines(s.id), "미수금 안내")
        else
            local sent, skipped = BRL.Payments:SendDunning(s.id)
            BRL:Print("독촉 귓속말 %d명 전송%s", sent, skipped > 0 and (" (최근 전송/본인 " .. skipped .. "명 제외)") or "")
        end
    end, { description = string.format("미수금 %d명 · 총 %s\n%s", #debtors, Money.Format(total), table.concat(lines, "\n")) })
end

-- 최근 거래 이벤트 추적 (기록되지 않은 거래 포함)
function A.TradeTraces()
    local J = BRL.TradeJournal
    local lines = { "최근 거래 " .. #BRL.TradeTracker:RecentTraces() .. "건 (최대 10건, 기록되지 않은 빈 거래 포함)", "" }
    for i, tr in ipairs(BRL.TradeTracker:RecentTraces()) do
        lines[#lines + 1] = string.format("#%d %s  %s  %s / %s%s", i, U.FormatDateTime(tr.at), tostring(tr.partnerKey or "알 수 없음"),
            BRL.Label("TRADE_", tr.status), J:VerificationLabel(tr.verification), tr.recorded and "" or "  [기록 안 함]")
        lines[#lines + 1] = string.format("   받은 %s / 준 %s / 아이템 %d개%s%s", Money.Format(tr.received), Money.Format(tr.given), tr.items or 0,
            tr.moneyDelta and ("  실제 골드 변화 " .. Money.Format(tr.moneyDelta, { sign = true })) or "",
            tr.itemCheck and ("  가방 검증 " .. tr.itemCheck) or "")
        for _, l in ipairs(BRL.TradeTracker:FormatEvents(tr.events, tr.openedClock)) do lines[#lines + 1] = "     " .. l end
        lines[#lines + 1] = ""
    end
    D.CopyText("거래 이벤트 추적", U.StripColors(table.concat(lines, "\n")),
        { hint = "거래가 잘못 기록되면 이 내용을 복사해 문제 보고에 첨부하세요." })
end

---------------------------------------------------------------------------
-- 경매
---------------------------------------------------------------------------
function A.AddAuction(link)
    local cfg = BRL.acct.auction
    local _, _, quality = API.GetItemInfo(link or "")
    local preset = quality and BRL.Data.AuctionPresets[quality] or {}
    D.Input("경매 등록", {
        { key = "link", label = "아이템", type = "text", default = link or "", required = true, acceptItems = true, placeholder = "Shift+클릭 또는 드래그" },
        { key = "quantity", label = "수량", type = "number", default = 1 },
        { key = "startPrice", label = "시작가", type = "money", default = preset.startPrice or cfg.startPrice },
        { key = "minIncrement", label = "최소 입찰 증가액", type = "money", default = preset.minIncrement or cfg.minIncrement },
        { key = "buyout", label = "즉시 낙찰가(선택)", type = "money", allowEmpty = true },
        { key = "duration", label = "경매 시간(초)", type = "number", default = cfg.defaultDuration },
    }, function(v)
        local function add(allowDup)
            return BRL.Auctions:Add(v.link, {
                quantity = v.quantity, startPrice = v.startPrice, minIncrement = v.minIncrement,
                buyout = v.buyout or 0, duration = v.duration, allowDuplicate = allowDup,
            })
        end
        local auc, err = add(false)
        if auc then return true end
        if err == "duplicate" then
            D.Confirm("같은 아이템이 이미 대기/진행 중입니다. 같은 아이템이 여러 개 드랍된 경우에만 추가로 등록하세요.\n추가 등록할까요?", function()
                report(add(true))
            end, { title = "동일 아이템 중복 등록" })
            return true
        end
        return false, err
    end)
end

function A.ManualBid(auc)
    D.Input("수동 입찰 입력", {
        { key = "name", label = "입찰자", type = "text", required = true },
        { key = "amount", label = "입찰 금액", type = "money", required = true, default = BRL.Auctions:NextMinimum(auc) },
    }, function(v)
        local bid, why = BRL.Bids:Place(auc.id, v.name, v.amount, "manual", { allowEnded = true })
        if bid and bid.accepted then return true end
        return false, why
    end, { description = "다음 최소 입찰가: " .. Money.Format(BRL.Auctions:NextMinimum(auc)) })
end

-- 공대장 본인 낙찰금: 본인 지갑 → 공대 금액 (거래 로그 "본인 지급")
function A.PayAwardFromSelf(aw)
    local P = BRL.Payments
    if aw.winnerKey ~= BRL.playerKey then D.Message("공대장 본인이 낙찰받은 아이템만 본인 지급으로 기록할 수 있습니다.") return end
    local st = P:AwardStatus(aw)
    if st.outstanding <= 0 then D.Message("이미 낙찰금이 모두 기록되었습니다.") return end
    D.Input("본인 낙찰금 기록", {
        { key = "amount", label = "낙찰금", type = "money", default = st.outstanding, required = true },
    }, function(v)
        local res, err = P:PayAwardFromSelf(aw.id, v.amount)
        if res then BRL:Print("본인 낙찰금 %s을 거래 로그에 '본인 지급'으로 기록했습니다.", Money.Format(v.amount)) return true end
        if err == "overpay" then return false, "미수금(" .. Money.Format(st.outstanding) .. ")보다 큽니다" end
        return false, err
    end, { description = string.format("%s\n본인 지갑의 골드를 공대 금액으로 낸 것으로 거래 로그에 기록하고 낙찰 수금에 연결합니다. (거래 창 없음, 장부 수입에 반영)", aw.itemName or "?") })
end

function A.CancelAward(aw)
    local st = BRL.Payments:AwardStatus(aw)
    D.Reason("낙찰 취소", function(reason)
        return BRL.Auctions:CancelAward(aw.id, reason)
    end, string.format("%s - %s %s\n이미 수금한 %s 은(는) '환불 필요'로 표시됩니다. 환불 거래를 연결해 정리하세요.",
        aw.itemName or "?", aw.winnerName or "?", Money.Format(aw.amount), Money.Format(st.collected)))
end

function A.ChangeAwardAmount(aw)
    D.Input("낙찰 금액 수정", {
        { key = "amount", label = "낙찰 금액", type = "money", default = aw.amount, required = true },
        { key = "reason", label = "수정 사유", type = "text", required = true },
    }, function(v) return BRL.Auctions:ChangeAwardAmount(aw.id, v.amount, v.reason) end)
end

---------------------------------------------------------------------------
-- 공통
---------------------------------------------------------------------------
function A.SendLines(lines, title)
    local items = {
        { value = "RAID", text = "공격대" }, { value = "RAID_WARNING", text = "공격대 경보" }, { value = "PARTY", text = "파티" },
        { value = "GUILD", text = "길드" }, { value = "OFFICER", text = "길드 관리자" }, { value = "COPY", text = "복사 창(디스코드/메모장)" },
    }
    D.Select(title or "출력 채널 선택", items, function(ch)
        if ch == "COPY" then
            D.CopyText(title or "출력", BRL.Reports:ToText(lines))
        else
            BRL.ChatOut:SendLines(lines, ch)
        end
    end, { description = "긴 내용은 255바이트 단위로 자동 분할되어 순서대로 전송됩니다." })
end

function A.MemberItems(includeNone)
    local items = {}
    if includeNone then items[1] = { value = false, text = "(없음)" } end
    for _, m in ipairs(BRL.Roster:Sorted("class")) do
        items[#items + 1] = { value = m.key, text = BRL.Data.ColorName(m.short, m.class) }
    end
    return items
end
