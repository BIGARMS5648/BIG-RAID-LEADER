-- BIG RAID LEADER - 골드팟 정산 (Settlement / PayoutObligation)
-- 원칙
--  * 모든 금액은 정수 코퍼로 계산한다. (MulDiv 로 정밀도 손실 없이 분배)
--  * 실제로 받은(수금 연결된) 골드만 분배 가능 금액에 포함한다. (경매에서 미수금은 발생하지 않는 것으로 운영)
--  * 모든 보너스/수수료/공제 기본값은 0, 기본 분배 방식은 전원 균등 분배.
--  * 합계 항등식 검증: 총수입 = 지출 + 공제 + 수수료 + 예비금 + 분배 합계 + 잔돈 + 이월
local _, BRL = ...
local U, DB, Money = BRL.Util, BRL.DB, BRL.Money

local S = BRL:NewModule("Settlement")

local function changed(id)
    BRL.Events:Fire(BRL.Events.MSG.SETTLEMENT_CHANGED, id)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "settlement")
end

local function defaultConfig()
    local acct = BRL.acct.settlement
    return {
        rounding = acct.rounding or 1,
        remainderMode = acct.remainderMode or "keep",
        operatingCosts = {},     -- { {label=, amount=} }
        deductions = {},         -- { {label=, amount=} }
        leaderFeeBp = 0, leaderFeeFixed = 0,
        reserveBp = 0, reserveFixed = 0,
        includeCarryIn = true,
        roleBonus = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0 },
        participants = {},
    }
end

function S:Get(id) return DB:Get("settlements", id) end

function S:ForSession(sessionId)
    local list = DB:List("settlements", function(s) return s.sessionId == sessionId end, "createdAt", true)
    return list[1], list
end

local function requireEdit(st, allowLocked)
    local session = st and BRL.Session:Get(st.sessionId)
    local ok, why = BRL.Perm:CanEditSession(session)
    if not ok then return false, why end
    if st and st.locked and not allowLocked then return false, "확정(잠금)된 정산입니다. 수정하려면 잠금을 해제하세요." end
    return true
end

local function participantFromAttendance(a)
    local role = BRL.Roles and BRL.Roles:GetMemberRole(a.key) or nil
    return {
        key = a.key, name = a.name or BRL.API.ShortName(a.key), class = a.class, subgroup = a.subgroup or 1,
        role = role, include = true, weight = 100, bonusFixed = 0, bonusBp = 0, manualAmount = nil,
    }
end

-- 세션의 정산 생성 (참가자 = 세션 참가 기록)
function S:Create(sessionId)
    local session = BRL.Session:Get(sessionId)
    if not session then return nil, "세션 없음" end
    local ok, why = BRL.Perm:CanEditSession(session)
    if not ok then return nil, why end
    local cfg = defaultConfig()
    for key, a in pairs(session.attendance or {}) do
        cfg.participants[key] = participantFromAttendance(a)
    end
    local st = DB:Insert("settlements", {
        sessionId = sessionId, status = "draft", locked = false, version = 0,
        config = cfg, leaderKey = session.owner,
    })
    DB:Audit("settlement.create", "settlement", st.id, { session = sessionId })
    changed(st.id)
    return st
end

function S:Ensure(sessionId)
    local st = self:ForSession(sessionId)
    if st then return st end
    return self:Create(sessionId)
end

-- 참가 기록에 새로 추가된 인원을 정산 참가자에 반영 (기존 설정 유지)
function S:SyncParticipants(id)
    local st = self:Get(id)
    if not st then return false end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    local session = BRL.Session:Get(st.sessionId)
    local added = 0
    for key, a in pairs(session.attendance or {}) do
        if not st.config.participants[key] then
            st.config.participants[key] = participantFromAttendance(a)
            added = added + 1
        else
            st.config.participants[key].subgroup = a.subgroup or st.config.participants[key].subgroup
        end
    end
    changed(id)
    return true, added
end

function S:AddParticipant(id, key, info)
    local st = self:Get(id)
    if not st then return false end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    key = BRL.API.NormalizeName(key)
    if not key then return false, "이름 오류" end
    if st.config.participants[key] then return false, "이미 참가자입니다" end
    local p = participantFromAttendance({ key = key, name = BRL.API.ShortName(key), class = info and info.class, subgroup = info and info.subgroup or 1 })
    st.config.participants[key] = p
    DB:Audit("settlement.participant.add", "settlement", id, { key = key })
    changed(id)
    return true
end

-- fields: include, weight, bonusFixed, bonusBp, manualAmount(nil=해제), subgroup, role, note
function S:SetParticipant(id, key, fields)
    local st = self:Get(id)
    if not st then return false, "정산 없음" end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    local p = st.config.participants[key]
    if not p then return false, "참가자 없음" end
    for k, v in pairs(fields) do
        if k == "bonusFixed" or k == "manualAmount" then
            if v ~= nil and v ~= false and not Money.IsValid(v) then return false, "금액 오류" end
        elseif k == "weight" or k == "bonusBp" then
            if not Money.IsValid(v) then return false, "비율 오류 (0 이상의 정수)" end
        end
    end
    for k, v in pairs(fields) do
        if v == false and k == "manualAmount" then v = nil end
        DB:AddHistory(st, "participant." .. key .. "." .. k, p[k], v)
        p[k] = v
    end
    changed(id)
    return true
end

-- path: rounding | remainderMode | leaderFeeBp | leaderFeeFixed | reserveBp | reserveFixed | includeCarryIn | roleBonus.TANK ...
function S:SetConfig(id, path, value)
    local st = self:Get(id)
    if not st then return false, "정산 없음" end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    local cfg = st.config
    if path == "rounding" then
        if value ~= 1 and value ~= 100 and value ~= 10000 then return false, "단위 오류" end
    elseif path == "remainderMode" then
        if value ~= "keep" and value ~= "carry" and value ~= "leader" then return false, "잔돈 처리 방식 오류" end
    elseif path == "includeCarryIn" then
        value = value and true or false
    elseif path == "leaderFeeBp" or path == "reserveBp" then
        if not Money.IsValid(value) or value > 10000 then return false, "비율은 0~100% 입니다" end
    elseif path:match("^roleBonus%.") or path == "leaderFeeFixed" or path == "reserveFixed" then
        if not Money.IsValid(value) then return false, "금액 오류" end
    else
        return false, "알 수 없는 설정"
    end
    local role = path:match("^roleBonus%.(%u+)$")
    if role then
        DB:AddHistory(st, path, cfg.roleBonus[role], value)
        cfg.roleBonus[role] = value
    else
        DB:AddHistory(st, path, cfg[path], value)
        cfg[path] = value
    end
    changed(id)
    return true
end

-- 운영비/공제 항목. listName: "operatingCosts" | "deductions"
function S:AddCost(id, listName, label, amount)
    local st = self:Get(id)
    if not st then return false end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    if listName ~= "operatingCosts" and listName ~= "deductions" then return false end
    if not Money.IsValid(amount) or amount <= 0 then return false, "금액 오류" end
    label = U.Trim(label or "")
    if label == "" then label = listName == "operatingCosts" and "운영비" or "공제" end
    table.insert(st.config[listName], { label = label, amount = amount })
    DB:AddHistory(st, listName, nil, { label = label, amount = amount }, "항목 추가")
    changed(id)
    return true
end

function S:RemoveCost(id, listName, index)
    local st = self:Get(id)
    if not st then return false end
    local ok, why = requireEdit(st)
    if not ok then return false, why end
    local list = st.config[listName]
    if not list or not list[index] then return false end
    local removed = table.remove(list, index)
    DB:AddHistory(st, listName, removed, nil, "항목 삭제")
    changed(id)
    return true
end

---------------------------------------------------------------------------
-- 계산 (순수 함수: 데이터를 변경하지 않음)
---------------------------------------------------------------------------
local function sumList(list)
    local t = 0
    for _, v in ipairs(list or {}) do t = t + (v.amount or 0) end
    return t
end

-- 실제 수금 기준으로 계산한다. (basis 인자는 이전 버전 호환용, 항상 "confirmed")
function S:Compute(st, _, summaryOverride)
    local basis = "confirmed"
    local cfg = st.config
    local sum = summaryOverride or BRL.Ledger:Summary(st.sessionId)
    local r = {
        basis = basis, errors = {}, warnings = {}, rows = {}, parties = {},
        rounding = cfg.rounding or 1, remainderMode = cfg.remainderMode or "keep",
    }
    r.totalAwarded = sum.totalAwarded or 0
    r.collected = sum.collected or 0
    r.unallocatedAuctionIncome = sum.unallocatedAuctionIncome or 0
    r.refundDue = sum.refundDue or 0
    r.otherIncome = sum.otherIncome or 0
    local ec = sum.expenseByCat or {}
    r.ledgerExpenses = (ec.operating or 0) + (ec.other_expense or 0) + (ec.adjust_expense or 0)
    r.auctionBase = r.collected
    if cfg.includeCarryIn then
        r.carryIn = st.carryInTaken or (BRL.char and BRL.char.carryover) or 0
    else
        r.carryIn = 0
    end
    r.gross = r.auctionBase + r.otherIncome + r.carryIn
    r.operating = sumList(cfg.operatingCosts)
    r.deductions = sumList(cfg.deductions)
    r.leaderFee = Money.MulDiv(math.max(0, r.gross), cfg.leaderFeeBp or 0, 10000) + (cfg.leaderFeeFixed or 0)
    r.reserve = Money.MulDiv(math.max(0, r.gross), cfg.reserveBp or 0, 10000) + (cfg.reserveFixed or 0)
    r.distributable = r.gross - r.ledgerExpenses - r.operating - r.deductions - r.leaderFee - r.reserve

    -- 참가자 (결정적 순서)
    local keys = {}
    for key, p in pairs(cfg.participants) do
        if p.include then keys[#keys + 1] = key end
    end
    table.sort(keys)
    r.excluded = 0
    for _, p in pairs(cfg.participants) do if not p.include then r.excluded = r.excluded + 1 end end
    r.headcount = #keys

    local fixedTotal, manualTotal, totalWeight = 0, 0, 0
    for _, key in ipairs(keys) do
        local p = cfg.participants[key]
        local roleBonus = (p.role and cfg.roleBonus[p.role]) or 0
        local row = {
            key = key, name = p.name or BRL.API.ShortName(key), class = p.class, subgroup = p.subgroup or 1,
            role = p.role, weight = p.weight or 100, bonusBp = p.bonusBp or 0,
            bonus = (p.bonusFixed or 0) + roleBonus, manual = p.manualAmount, base = 0, remainderAdd = 0, kind = "share",
        }
        fixedTotal = fixedTotal + row.bonus
        if row.manual then
            manualTotal = manualTotal + row.manual
            row.w = 0
        else
            row.w = row.weight * (10000 + row.bonusBp)
            totalWeight = totalWeight + row.w
        end
        r.rows[#r.rows + 1] = row
    end
    r.fixedBonusTotal = fixedTotal
    r.manualTotal = manualTotal
    r.pool = r.distributable - fixedTotal - manualTotal

    if r.gross < 0 then r.errors[#r.errors + 1] = "총수입이 음수입니다" end
    if r.distributable < 0 then
        r.errors[#r.errors + 1] = "지출/공제/수수료/예비금 합계(" .. Money.Format(r.gross - r.distributable) .. ")가 총수입(" .. Money.Format(r.gross) .. ")을 초과합니다"
    elseif r.pool < 0 then
        r.errors[#r.errors + 1] = "보너스/수동 지정 금액 합계가 분배 가능 금액(" .. Money.Format(r.distributable) .. ")을 초과합니다"
    end
    if r.headcount == 0 then r.warnings[#r.warnings + 1] = "분배 대상 인원이 없습니다" end

    local pool = math.max(0, r.pool)
    local shareSum = 0
    if totalWeight > 0 then
        for _, row in ipairs(r.rows) do
            if row.w > 0 then
                row.base = Money.FloorToUnit(Money.MulDiv(pool, row.w, totalWeight), r.rounding)
                shareSum = shareSum + row.base
            end
        end
    elseif pool > 0 and r.headcount > 0 then
        r.warnings[#r.warnings + 1] = "모든 인원이 수동 금액/가중치 0이라 균등 분배분이 잔돈으로 남습니다"
    end
    r.remainder = pool - shareSum
    r.kept, r.carryOut = 0, 0
    local leaderRow
    for _, row in ipairs(r.rows) do if row.key == st.leaderKey then leaderRow = row end end
    if r.remainderMode == "carry" then
        r.carryOut = r.remainder
    elseif r.remainderMode == "leader" and leaderRow then
        leaderRow.remainderAdd = r.remainder
    else
        r.kept = r.remainder
        if r.remainderMode == "leader" and r.remainder > 0 then
            r.warnings[#r.warnings + 1] = "공대장이 분배 대상이 아니어서 잔돈을 보관합니다"
        end
    end

    local distributed = 0
    local equal, firstBase = true, nil
    for _, row in ipairs(r.rows) do
        row.total = row.base + row.bonus + (row.manual or 0) + row.remainderAdd
        distributed = distributed + row.total
        if not row.manual then
            if firstBase == nil then firstBase = row.base elseif firstBase ~= row.base then equal = false end
        end
        local party = r.parties[row.subgroup]
        if not party then
            party = { subgroup = row.subgroup, count = 0, total = 0, members = {} }
            r.parties[row.subgroup] = party
        end
        party.count = party.count + 1
        party.total = party.total + row.total
        party.members[#party.members + 1] = row.key
    end
    r.distributed = distributed
    r.perPerson = (equal and firstBase) or (r.headcount > 0 and math.floor(distributed / r.headcount)) or 0
    r.equalShares = equal and firstBase ~= nil

    -- 합계 항등식 검증
    if #r.errors == 0 then
        local rhs = r.ledgerExpenses + r.operating + r.deductions + r.leaderFee + r.reserve + r.distributed + r.kept + r.carryOut
        if rhs ~= r.gross then
            r.errors[#r.errors + 1] = string.format("합계 불일치: 총수입 %s ≠ 배분 합계 %s", Money.Format(r.gross), Money.Format(rhs))
        end
        for _, row in ipairs(r.rows) do
            if not Money.IsValid(row.total) then r.errors[#r.errors + 1] = "금액 오류: " .. row.name end
        end
    end
    -- 경고
    if r.unallocatedAuctionIncome > 0 then
        r.warnings[#r.warnings + 1] = "낙찰에 연결되지 않은 경매금 수금 " .. Money.Format(r.unallocatedAuctionIncome) .. "이 있습니다 (거래 로그에서 연결하세요)"
    end
    if r.refundDue > 0 then
        r.warnings[#r.warnings + 1] = "낙찰 취소로 환불해야 할 금액 " .. Money.Format(r.refundDue) .. "이 있습니다"
    end
    local unclassified = BRL.TradeJournal:CountUnclassified(st.sessionId)
    if unclassified > 0 then
        r.warnings[#r.warnings + 1] = "분류되지 않은 완료 거래 " .. unclassified .. "건이 있습니다"
    end
    r.valid = #r.errors == 0
    return r
end

---------------------------------------------------------------------------
-- 확정 / 잠금 / 종료
---------------------------------------------------------------------------
function S:Obligations(id, includeVoided)
    return DB:List("payouts", function(o) return o.settlementId == id and (includeVoided or not o.voided) end, "subgroup")
end

-- opts.force: 경고(미연결 수금 등)가 있어도 확정
function S:Finalize(id, opts)
    opts = opts or {}
    local st = self:Get(id)
    if not st then return nil, "정산 없음" end
    local ok, why = requireEdit(st)
    if not ok then return nil, why end
    local r = self:Compute(st, "confirmed")
    if not r.valid then return nil, table.concat(r.errors, "\n") end
    if #r.warnings > 0 and not opts.force then return nil, "warnings", r.warnings end
    BRL.Migration:CreateBackup("정산 확정 전 자동 백업")

    -- 이월 잔돈 사용 (최초 1회만 차감)
    if st.config.includeCarryIn and st.carryInTaken == nil then
        st.carryInTaken = r.carryIn
        BRL.char.carryover = math.max(0, (BRL.char.carryover or 0) - r.carryIn)
    end

    -- 분배 의무 생성/갱신 (기존 지급 연결 보존)
    local existing = {}
    for _, ob in ipairs(self:Obligations(id, true)) do existing[ob.memberKey .. "|" .. ob.kind] = ob end
    local touched = {}
    local function upsert(kind, row, amount)
        local k = row.key .. "|" .. kind
        local ob = existing[k]
        if ob then
            if ob.amount ~= amount then DB:AddHistory(ob, "amount", ob.amount, amount, "정산 재확정 v" .. ((st.version or 0) + 1)) end
            ob.amount, ob.subgroup, ob.name, ob.class, ob.voided = amount, row.subgroup, row.name, row.class, false
        elseif amount > 0 then
            ob = DB:Insert("payouts", {
                settlementId = id, memberKey = row.key, name = row.name, class = row.class, subgroup = row.subgroup or 1,
                kind = kind, amount = amount, voided = false, hold = false, history = {},
            })
        end
        if ob then touched[ob.id] = true end
    end
    for _, row in ipairs(r.rows) do upsert("share", row, row.total) end
    if r.leaderFee > 0 and st.leaderKey then
        local p = st.config.participants[st.leaderKey]
        upsert("fee", { key = st.leaderKey, name = p and p.name or BRL.API.ShortName(st.leaderKey), class = p and p.class, subgroup = p and p.subgroup or 1 }, r.leaderFee)
    end
    for _, ob in pairs(existing) do
        if not touched[ob.id] then
            local paid = BRL.Payments:ObligationStatus(ob).paid
            if paid > 0 then
                if ob.amount ~= 0 then DB:AddHistory(ob, "amount", ob.amount, 0, "정산 대상 제외") end
                ob.amount = 0
                ob.needsCheck = true
            else
                ob.voided = true
            end
        end
    end

    st.result = r
    st.status = "confirmed"
    st.locked = true
    st.version = (st.version or 0) + 1
    st.finalizedAt = U.Now()
    DB:Audit("settlement.finalize", "settlement", id, { version = st.version, distributed = r.distributed, gross = r.gross })
    if BRL.Reports then BRL.Reports:Snapshot(st) end
    changed(id)
    return st, r
end

function S:Unlock(id, reason)
    local st = self:Get(id)
    if not st then return false end
    local ok, why = requireEdit(st, true)
    if not ok then return false, why end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "잠금 해제 사유를 입력하세요" end
    if st.status == "completed" or st.status == "closed_with_issues" then
        self:Reopen(id, reason)
    end
    st.locked = false
    st.status = "draft"
    DB:AddHistory(st, "locked", true, false, reason)
    DB:Audit("settlement.unlock", "settlement", id, { reason = reason })
    changed(id)
    return true
end

-- 지급 현황
function S:PaymentState(id)
    local st = self:Get(id)
    local res = { rows = {}, parties = {}, planned = 0, paid = 0, unpaid = 0, paidCount = 0, unpaidCount = 0, statusCount = {} }
    if not st then return res end
    for _, ob in ipairs(self:Obligations(id)) do
        local obs = BRL.Payments:ObligationStatus(ob)
        local row = { ob = ob, status = obs.status, paid = obs.paid, remaining = obs.remaining, over = obs.over }
        res.rows[#res.rows + 1] = row
        res.planned = res.planned + ob.amount
        res.paid = res.paid + math.min(obs.paid, ob.amount)
        res.unpaid = res.unpaid + obs.remaining
        res.statusCount[obs.status] = (res.statusCount[obs.status] or 0) + 1
        if obs.remaining == 0 and ob.amount > 0 then res.paidCount = res.paidCount + 1
        elseif obs.remaining > 0 then res.unpaidCount = res.unpaidCount + 1 end
        local g = ob.subgroup or 1
        local party = res.parties[g]
        if not party then
            party = { subgroup = g, count = 0, total = 0, paidCount = 0, unpaidCount = 0, remaining = 0 }
            res.parties[g] = party
        end
        party.count = party.count + 1
        party.total = party.total + ob.amount
        party.remaining = party.remaining + obs.remaining
        if obs.remaining == 0 then party.paidCount = party.paidCount + 1 else party.unpaidCount = party.unpaidCount + 1 end
    end
    return res
end

-- 정산 종료. 미지급금/미환불이 남아 있으면 force 필요 (경고 후 기록 유지)
function S:Close(id, force)
    local st = self:Get(id)
    if not st then return false, "정산 없음" end
    local ok, why = requireEdit(st, true)
    if not ok then return false, why end
    if st.status ~= "confirmed" and st.status ~= "paying" then return false, "확정된 정산만 종료할 수 있습니다" end
    local pay = self:PaymentState(id)
    local summary = BRL.Ledger:Summary(st.sessionId)
    local issues = {}
    if pay.unpaid > 0 then issues[#issues + 1] = "미지급금 " .. Money.Format(pay.unpaid) end
    if summary.refundDue > 0 then issues[#issues + 1] = "미환불 " .. Money.Format(summary.refundDue) end
    if #issues > 0 and not force then return false, "issues", issues end
    st.status = (#issues > 0) and "closed_with_issues" or "completed"
    st.closedAt = U.Now()
    st.closeIssues = issues
    if st.result and (st.result.carryOut or 0) > 0 and not st.carryApplied then
        BRL.char.carryover = (BRL.char.carryover or 0) + st.result.carryOut
        st.carryApplied = st.result.carryOut
    end
    DB:Audit("settlement.close", "settlement", id, { status = st.status, issues = issues })
    if BRL.Reports then BRL.Reports:Snapshot(st) end
    changed(id)
    return true
end

function S:Reopen(id, reason)
    local st = self:Get(id)
    if not st then return false end
    if st.carryApplied then
        BRL.char.carryover = math.max(0, (BRL.char.carryover or 0) - st.carryApplied)
        st.carryApplied = nil
    end
    st.status = "confirmed"
    st.closedAt = nil
    DB:Audit("settlement.reopen", "settlement", id, { reason = reason })
    changed(id)
    return true
end

-- 정산 완료 검증 체크리스트
function S:Validate(id)
    local st = self:Get(id)
    if not st then return {} end
    local r = st.result or self:Compute(st, "confirmed")
    local pay = self:PaymentState(id)
    local sum = BRL.Ledger:Summary(st.sessionId)
    local checks = {}
    local function add(label, ok, detail) checks[#checks + 1] = { label = label, ok = ok and true or false, detail = detail } end
    local rhs = r.ledgerExpenses + r.operating + r.deductions + r.leaderFee + r.reserve + r.distributed + r.kept + r.carryOut
    add("총수입 확인", r.gross >= 0 and rhs == r.gross, "총수입 " .. Money.Format(r.gross))
    add("공제 금액 확인", r.distributable >= 0, "지출·공제·수수료·예비금 " .. Money.Format(r.ledgerExpenses + r.operating + r.deductions + r.leaderFee + r.reserve))
    add("분배 인원 확인", r.headcount > 0, r.headcount .. "명 (제외 " .. (r.excluded or 0) .. "명)")
    local amountsOk = true
    for _, row in ipairs(r.rows) do if not Money.IsValid(row.total) then amountsOk = false end end
    add("개인별 분배액 확인", amountsOk and r.valid, r.equalShares and ("1인당 " .. Money.Format(r.perPerson)) or "차등 분배")
    add("지급 완료 여부", st.status ~= "draft" and pay.unpaidCount == 0 and #pay.rows > 0, pay.paidCount .. "명 완료 / " .. pay.unpaidCount .. "명 미지급")
    add("미지급금 확인", st.status ~= "draft" and pay.unpaid == 0, "미지급 " .. Money.Format(pay.unpaid))
    -- 장부 잔액 항등식 (금액 흐름 기준):
    -- 잔액 = 운영비 + 공제 + 예비금 + 잔돈 + 이월 - 이월사용 + 미지급 - 초과지급 + 미환불 + 미연결수금 - 미연결환불 - 미연결지급 - 수동 공대장분배
    local overPay = 0
    for _, row in ipairs(pay.rows) do overPay = overPay + (row.over or 0) end
    local expectedBalance = r.operating + r.deductions + r.reserve + r.kept + r.carryOut - r.carryIn
        + pay.unpaid - overPay + sum.refundDue + sum.unallocatedAuctionIncome
        - (sum.unallocatedRefund or 0) - sum.unallocatedPayout - (sum.manualPayoutLeader or 0)
    if st.status == "draft" then
        add("최종 잔액 확인", true, "정산 확정 후 확인 (현재 장부 잔액 " .. Money.Format(sum.balance) .. ")")
    else
        add("최종 잔액 확인", sum.balance == expectedBalance,
            "장부 잔액 " .. Money.Format(sum.balance) .. " / 정산상 잔액 " .. Money.Format(expectedBalance))
    end
    return checks, r, pay
end

