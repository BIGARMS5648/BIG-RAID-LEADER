-- BIG RAID LEADER - UI 공용 동작 (대화상자 흐름)
local _, BRL = ...
local D, Money, API, U = BRL.Dialogs, BRL.Money, BRL.API, BRL.Util

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
        "상태: " .. J:StatusLabel(tr) .. " (검증: " .. tostring(tr.verification) .. ")",
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
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[수정 이력]"
    for _, h in ipairs(tr.history or {}) do
        lines[#lines + 1] = string.format("  %s %s: %s → %s %s", U.FormatDateTime(h.at), h.field,
            type(h.old) == "table" and "(표)" or tostring(h.old), type(h.new) == "table" and "(표)" or tostring(h.new), h.reason and ("- " .. h.reason) or "")
    end
    D.CopyText("거래 상세 - " .. (tr.partnerName or "?"), U.StripColors(table.concat(lines, "\n")))
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
