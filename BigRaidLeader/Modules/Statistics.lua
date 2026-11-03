-- BIG RAID LEADER - 공격대 통계 (전투 진행 / 경매 / 정산)
local _, BRL = ...
local DB = BRL.DB

local Stats = BRL:NewModule("Statistics")

function Stats:Combat(sessionId)
    return BRL.RaidProgress:Summary(sessionId)
end

function Stats:Auction(sessionId)
    local s = { items = 0, awarded = 0, unsold = 0, cancelled = 0, queued = 0, total = 0, average = 0,
        top = nil, collected = 0, outstanding = 0, collectRate = 0 }
    for _, a in pairs(DB:T("auctions")) do
        if a.sessionId == sessionId then
            s.items = s.items + 1
            if a.status == "unsold" then s.unsold = s.unsold + 1
            elseif a.status == "cancelled" then s.cancelled = s.cancelled + 1
            elseif a.status == "queued" then s.queued = s.queued + 1 end
        end
    end
    for _, aw in pairs(DB:T("awards")) do
        if aw.sessionId == sessionId and aw.status == "active" then
            s.awarded = s.awarded + 1
            s.total = s.total + aw.amount
            if not s.top or aw.amount > s.top.amount then s.top = aw end
        end
    end
    local coll = BRL.Payments:SessionCollection(sessionId)
    s.collected, s.outstanding = coll.collected, coll.outstanding
    s.average = s.awarded > 0 and math.floor(s.total / s.awarded) or 0
    s.collectRate = s.total > 0 and math.floor(coll.collected * 1000 / s.total + 0.5) / 10 or 0
    return s
end

function Stats:Settlement(sessionId)
    local st = BRL.Settlement:ForSession(sessionId)
    local sum = BRL.Ledger:Summary(sessionId)
    local s = { collected = sum.collected, distributed = 0, deductions = 0, headcount = 0, average = 0,
        paidCount = 0, unpaidCount = 0, unpaid = sum.unpaid, balance = sum.balance, status = st and st.status or nil }
    if st then
        local r = st.result or BRL.Settlement:Compute(st, "confirmed")
        s.distributed = r.distributed
        s.deductions = r.ledgerExpenses + r.operating + r.deductions + r.leaderFee + r.reserve
        s.headcount = r.headcount
        s.average = r.headcount > 0 and math.floor(r.distributed / r.headcount) or 0
        local pay = BRL.Settlement:PaymentState(st.id)
        s.paidCount, s.unpaidCount = pay.paidCount, pay.unpaidCount
    end
    return s
end

-- 전체 기간 요약 (세션 목록)
function Stats:History()
    local out = {}
    for _, s in ipairs(BRL.Session:List()) do
        local a = self:Auction(s.id)
        local st = BRL.Settlement:ForSession(s.id)
        out[#out + 1] = { session = s, auctionTotal = a.total, collected = a.collected, items = a.awarded,
            settlement = st and st.status or "-" }
    end
    return out
end
