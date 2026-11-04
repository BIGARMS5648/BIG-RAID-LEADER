-- BIG RAID LEADER - 경매 통계 (지난 세션 목록 · 구매자 기록)
local _, BRL = ...
local DB = BRL.DB

local Stats = BRL:NewModule("Statistics")

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

-- 구매자 기록: 모든 세션의 낙찰을 구매자별로 집계
-- 반환 목록 항목: key, name, class, count, total, average, max, outstanding, sessions, last, items{name, amount, at, session, outstanding}
function Stats:Buyers(query)
    local by = {}
    local function entry(key, name, class)
        local b = by[key]
        if not b then
            b = { key = key, name = name or BRL.API.ShortName(key), class = class, count = 0, total = 0, max = 0, outstanding = 0,
                sessions = 0, sessionSeen = {}, last = 0, items = {} }
            by[key] = b
        end
        if class and not b.class then b.class = class end
        return b
    end
    local function add(b, sessionKey, item, amount, at, outstanding, sessionName)
        b.count = b.count + 1
        b.total = b.total + (amount or 0)
        if (amount or 0) > b.max then b.max = amount end
        b.outstanding = b.outstanding + (outstanding or 0)
        if not b.sessionSeen[sessionKey] then
            b.sessionSeen[sessionKey] = true
            b.sessions = b.sessions + 1
        end
        if (at or 0) > b.last then b.last = at end
        b.items[#b.items + 1] = { name = item, amount = amount, at = at, session = sessionName, outstanding = outstanding }
    end
    for _, aw in pairs(DB:T("awards")) do
        if aw.status == "active" and aw.winnerKey then
            local st = BRL.Payments:AwardStatus(aw)
            local s = BRL.Session:Get(aw.sessionId)
            add(entry(aw.winnerKey, aw.winnerName, aw.winnerClass), aw.sessionId,
                BRL.Util.StripColors(BRL.Util.ItemNameFromLink(aw.itemLink) or aw.itemName or "?"), aw.amount, aw.awardedAt, st.outstanding, s and s.name)
        end
    end
    local out = {}
    for _, b in pairs(by) do
        b.sessionSeen = nil
        b.average = b.count > 0 and math.floor(b.total / b.count) or 0
        table.sort(b.items, function(x, y) return (x.at or 0) > (y.at or 0) end)
        if not query or query == "" or BRL.Util.MatchSearch(b.name .. " " .. b.key, query) then out[#out + 1] = b end
    end
    table.sort(out, function(x, y)
        if x.total ~= y.total then return x.total > y.total end
        return x.key < y.key
    end)
    return out
end
