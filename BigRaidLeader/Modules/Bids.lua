-- BIG RAID LEADER - 입찰 (Bid)
-- 채팅 입찰 자동 인식 + 공대장 수동 입력.
-- 12.x 채팅 잠금 중 메시지는 Secret Value 로 전달되므로 인식하지 않고 수동 입력으로 대체한다.
local _, BRL = ...
local U, API, DB, Money = BRL.Util, BRL.API, BRL.DB, BRL.Money

local Bids = BRL:NewModule("Bids")

local CHAT_EVENTS = {
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID_LEADER", CHAT_MSG_RAID_WARNING = "RAID_WARNING",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY_LEADER", CHAT_MSG_WHISPER = "WHISPER",
}

function Bids:OnEnable()
    for event in pairs(CHAT_EVENTS) do
        BRL.Events:Register(event, self, "OnChat")
    end
end

function Bids:Get(id) return DB:Get("bids", id) end

function Bids:ForAuction(auctionId)
    return DB:List("bids", function(b) return b.auctionId == auctionId end, "seq")
end

local seq = 0
local function nextSeq()
    seq = seq + 1
    return U.Clock() * 1000 + seq
end

-- 채팅 문장에서 입찰 금액 추출. 금액만 있는 메시지(또는 "입찰"/"bid" 접두어)만 인정.
function Bids:ParseAmount(msg)
    if type(msg) ~= "string" then return nil end
    local s = U.Trim(U.StripColors(msg)):lower()
    if s == "" or #s > 40 then return nil end
    s = s:gsub("^!?bid%s*", ""):gsub("^입찰%s*", "")
    s = U.Trim(s)
    if not s:match("^%d") then return nil end
    local amount = Money.Parse(s)
    if not amount or amount <= 0 then return nil end
    return amount
end

-- 입찰 검증 및 기록. source: "chat"|"manual"|"sync"
-- 반환: bid(accepted 여부 포함), 사유
function Bids:Place(auctionId, bidderKey, amount, source, meta)
    local auc = BRL.Auctions:Get(auctionId)
    if not auc then return nil, "경매 없음" end
    meta = meta or {}
    if source == "manual" then
        local session = BRL.Session:Get(auc.sessionId)
        local ok, why = BRL.Perm:CanEditSession(session)
        if not ok then return nil, why end
    end
    bidderKey = API.NormalizeName(bidderKey)
    if not bidderKey then return nil, "입찰자 이름 오류" end
    local bid = DB:Insert("bids", {
        auctionId = auc.id, bidderKey = bidderKey, bidderName = API.ShortName(bidderKey),
        amount = amount, at = U.Now(), seq = nextSeq(), source = source or "manual",
        channel = meta.channel, rawText = meta.rawText, accepted = false,
    })
    local reason
    if auc.status ~= "active" and not (source == "manual" and auc.status == "ended" and meta.allowEnded) then
        reason = "진행 중인 경매가 아닙니다"
    elseif not Money.IsValid(amount) or amount <= 0 then
        reason = "금액 오류"
    elseif amount < BRL.Auctions:NextMinimum(auc) then
        if auc.highAmount and amount == auc.highAmount then
            reason = "같은 금액 입찰 (먼저 입찰한 사람이 우선)"
        else
            reason = "최소 입찰가 미달 (최소 " .. Money.Format(BRL.Auctions:NextMinimum(auc)) .. ")"
        end
    elseif BRL.acct.auction.requireGroupMember and source == "chat" and API.IsInGroup() and not self:IsGroupMember(bidderKey) then
        reason = "공격대원이 아닙니다"
    end
    if reason then
        bid.rejectReason = reason
        DB:Audit("bid.reject", "bid", bid.id, { auction = auc.id, bidder = bidderKey, amount = amount, reason = reason })
        BRL.Events:Fire(BRL.Events.MSG.AUCTION_CHANGED)
        return bid, reason
    end
    bid.accepted = true
    DB:Audit("bid.accept", "bid", bid.id, { auction = auc.id, bidder = bidderKey, amount = amount, source = source })
    BRL.Auctions:ApplyBid(auc, bid)
    return bid
end

function Bids:IsGroupMember(key)
    for _, m in ipairs(API.GetGroupRoster()) do
        if m.key == key then return true end
    end
    return false
end

-- 입찰 철회 (공대장 처리)
function Bids:Retract(bidId, reason)
    local bid = self:Get(bidId)
    if not bid or bid.retracted then return false end
    local auc = BRL.Auctions:Get(bid.auctionId)
    if not auc then return false end
    local ok, why = BRL.Perm:CanEditSession(BRL.Session:Get(auc.sessionId))
    if not ok then return false, why end
    if auc.status ~= "active" and auc.status ~= "ended" then return false, "진행/확정 대기 중인 경매만 가능합니다" end
    bid.retracted = true
    bid.retractReason = reason
    DB:Audit("bid.retract", "bid", bid.id, { reason = reason })
    BRL.Auctions:RecalculateHigh(auc)
    return true
end

function Bids:OnChat(event, msg, author)
    local cfg = BRL.acct.auction
    if not cfg.chatBids then return end
    local channel = CHAT_EVENTS[event]
    if not channel or not cfg.bidChannels[channel] then return end
    -- Secret Value(채팅 잠금 중)는 비교/저장하지 않는다
    if API.IsSecret(msg) or API.IsSecret(author) then return end
    local auc = BRL.Auctions:GetActive()
    if not auc then return end
    -- 경매를 진행하는 본인(공대장) 클라이언트에서만 인식
    if auc.createdBy ~= BRL.playerKey then return end
    local amount = self:ParseAmount(msg)
    if not amount then return end
    local key = API.NormalizeName(author)
    if not key then return end
    local bid, reason = self:Place(auc.id, key, amount, "chat", { channel = channel, rawText = msg })
    if bid and not bid.accepted and channel == "WHISPER" and reason then
        BRL.ChatOut:Send("[BRL] 입찰 거부: " .. reason, "WHISPER", key)
    end
end

function Bids:History(auctionId)
    local list = self:ForAuction(auctionId)
    table.sort(list, function(a, b) return (a.seq or 0) > (b.seq or 0) end)
    return list
end
