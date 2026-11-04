-- BIG RAID LEADER - 골드 경매 (Auction / Award)
-- 낙찰 금액은 "수금 예정 금액"일 뿐이며 실제 수령 골드로 합산하지 않는다.
-- 실제 수금은 완료 확인된 거래를 낙찰에 연결(Payments)해야 반영된다.
local _, BRL = ...
local U, API, DB, Money, L = BRL.Util, BRL.API, BRL.DB, BRL.Money, BRL.L

local A = BRL:NewModule("Auctions")

A.ticker = nil
A.lastAnnouncedSecond = nil

local function changed()
    BRL.Events:Fire(BRL.Events.MSG.AUCTION_CHANGED)
    BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "auctions")
end

function A:OnEnable()
    -- 접속/재시작 시 진행 중이던 경매는 일시정지 상태(ended 대기)로 전환하여 공대장이 판단
    for _, auc in pairs(DB:T("auctions")) do
        if auc.status == "active" then
            auc.status = "ended"
            auc.endReason = "interrupted"
            auc.endedAt = U.Now()
        end
    end
end

function A:Get(id) return DB:Get("auctions", id) end

local function sessionFor(auc)
    return auc and auc.sessionId and BRL.Session:Get(auc.sessionId)
end

local function requireEdit(auc)
    local session = auc and sessionFor(auc) or BRL.Session:GetActive()
    local ok, why = BRL.Perm:CanEditSession(session)
    if not ok then
        BRL:Print("%s: %s", L.NO_PERMISSION, why or "")
        return false, why
    end
    return true
end

function A:List(sessionId, statusFilter)
    return DB:List("auctions", function(a)
        if sessionId and a.sessionId ~= sessionId then return false end
        if statusFilter and not statusFilter[a.status] then return false end
        return true
    end, "order")
end

function A:Queue(sessionId)
    return self:List(sessionId, { queued = true })
end

function A:GetActive()
    for _, a in pairs(DB:T("auctions")) do
        if a.status == "active" then return a end
    end
    return nil
end

-- 확정 대기 중인 경매
function A:GetPendingConfirm(sessionId)
    return self:List(sessionId, { ended = true })
end

local function nextOrder(sessionId)
    local max = 0
    for _, a in pairs(DB:T("auctions")) do
        if a.sessionId == sessionId and (a.order or 0) > max then max = a.order end
    end
    return max + 1
end

---------------------------------------------------------------------------
-- 등록
---------------------------------------------------------------------------
-- opts: quantity, startPrice, minIncrement, buyout, duration, allowDuplicate, note
function A:Add(itemLink, opts)
    opts = opts or {}
    if type(itemLink) ~= "string" or itemLink == "" then return nil, "아이템 링크가 필요합니다" end
    local session = BRL.Session:GetActive()
    if not session or session.status ~= "open" then
        session = BRL.Session:Create({})
        if not session then return nil, "공격대 세션을 만들 수 없습니다" end
    end
    if not requireEdit({ sessionId = session.id }) then return nil, "권한 없음" end
    local cfg = BRL.acct.auction
    local startPrice = opts.startPrice or cfg.startPrice
    local minInc = opts.minIncrement or cfg.minIncrement
    local buyout = opts.buyout or 0
    if not Money.IsValid(startPrice) or not Money.IsValid(minInc) or not Money.IsValid(buyout) then
        return nil, "금액 오류"
    end
    if minInc <= 0 then return nil, "최소 입찰 증가액은 0보다 커야 합니다" end
    if buyout > 0 and buyout < startPrice then return nil, "즉시 낙찰가는 시작가 이상이어야 합니다" end
    -- 동일 아이템 중복 등록 확인
    if not opts.allowDuplicate then
        for _, a in pairs(DB:T("auctions")) do
            if a.sessionId == session.id and a.itemLink == itemLink and (a.status == "queued" or a.status == "active" or a.status == "ended") then
                return nil, "duplicate"
            end
        end
    end
    local name, _, quality, icon = API.GetItemInfo(itemLink)
    local auc = DB:Insert("auctions", {
        sessionId = session.id,
        itemLink = itemLink,
        itemName = name or U.ItemNameFromLink(itemLink),
        itemId = U.ItemIdFromLink(itemLink),
        quality = quality,
        icon = icon or API.GetItemIcon(itemLink),
        quantity = math.max(1, math.floor(tonumber(opts.quantity) or 1)),
        startPrice = startPrice,
        minIncrement = minInc,
        buyout = buyout,
        duration = math.max(5, math.floor(tonumber(opts.duration) or cfg.defaultDuration)),
        status = "queued",
        order = nextOrder(session.id),
        relistOf = opts.relistOf,
        note = opts.note,
    })
    DB:Audit("auction.add", "auction", auc.id, { item = itemLink, startPrice = startPrice })
    changed()
    return auc
end

function A:Update(id, fields)
    local auc = self:Get(id)
    if not auc then return false, "경매 없음" end
    if not requireEdit(auc) then return false, "권한 없음" end
    if auc.status ~= "queued" and auc.status ~= "active" then return false, "대기/진행 중인 경매만 수정할 수 있습니다" end
    for _, k in ipairs({ "startPrice", "minIncrement", "buyout" }) do
        if fields[k] ~= nil and not Money.IsValid(fields[k]) then return false, "금액 오류" end
    end
    if auc.status == "active" and fields.startPrice and auc.highBidId then
        return false, "입찰이 있는 경매의 시작가는 변경할 수 없습니다"
    end
    for k, v in pairs(fields) do
        if k == "startPrice" or k == "minIncrement" or k == "buyout" or k == "duration" or k == "quantity" or k == "note" then
            DB:AddHistory(auc, k, auc[k], v)
            auc[k] = v
        end
    end
    changed()
    return true
end

function A:Move(id, delta)
    local auc = self:Get(id)
    if not auc or auc.status ~= "queued" then return false end
    if not requireEdit(auc) then return false end
    local queue = self:Queue(auc.sessionId)
    for i, a in ipairs(queue) do
        if a.id == id then
            local j = i + delta
            if j < 1 or j > #queue then return false end
            local other = queue[j]
            auc.order, other.order = other.order, auc.order
            changed()
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- 진행
---------------------------------------------------------------------------
function A:Remaining(auc)
    if not auc or auc.status ~= "active" or not auc.endsClock then return 0 end
    return math.max(0, auc.endsClock - U.Clock())
end

function A:NextMinimum(auc)
    if not auc.highAmount then return auc.startPrice end
    return auc.highAmount + auc.minIncrement
end

function A:Start(id)
    local auc = self:Get(id)
    if not auc then return false, "경매 없음" end
    if not requireEdit(auc) then return false, "권한 없음" end
    if auc.status ~= "queued" then return false, "대기 중인 경매만 시작할 수 있습니다" end
    local active = self:GetActive()
    if active then return false, "이미 진행 중인 경매가 있습니다: " .. (active.itemName or "?") end
    if self.autoNext then
        self.autoNext = nil
        self.autoNextToken = (self.autoNextToken or 0) + 1
    end
    auc.status = "active"
    auc.startedAt = U.Now()
    auc.endsClock = U.Clock() + auc.duration
    auc.highBidId, auc.highAmount, auc.highBidder = nil, nil, nil
    auc.countEndsClock, auc.preCountEnds = nil, nil
    self.lastAnnouncedSecond = nil
    DB:Audit("auction.start", "auction", auc.id)
    local parts = { string.format("[경매 시작] %s", auc.itemLink) }
    if auc.quantity > 1 then parts[#parts + 1] = "x" .. auc.quantity end
    parts[#parts + 1] = "시작가 " .. Money.Format(auc.startPrice)
    parts[#parts + 1] = "최소 증가 " .. Money.Format(auc.minIncrement)
    if auc.buyout and auc.buyout > 0 then parts[#parts + 1] = "즉시 낙찰 " .. Money.Format(auc.buyout) end
    parts[#parts + 1] = auc.duration .. "초"
    BRL.ChatOut:Announce(table.concat(parts, " / "))
    -- 입찰 방법 안내는 세션 첫 경매(또는 30분 만)에만 — 매 경매마다 반복하지 않음
    local session = BRL.Session:Get(auc.sessionId)
    if BRL.acct.auction.chatBids and session and (not session.bidHintAt or U.Now() - session.bidHintAt > 1800) then
        session.bidHintAt = U.Now()
        BRL.ChatOut:Send("입찰은 공격대 채팅" .. (BRL.acct.auction.bidChannels.WHISPER and " 또는 귓속말" or "") .. "로 금액만 입력하세요 (예: 1500)")
    end
    self:StartTicker()
    changed()
    return true
end

function A:StartNext(sessionId)
    self:CancelAutoNext()
    local q = self:Queue(sessionId or (BRL.Session:GetActive() or {}).id)
    if #q == 0 then return false, "대기 중인 경매가 없습니다" end
    return self:Start(q[1].id)
end

---------------------------------------------------------------------------
-- 연속 경매: 낙찰/유찰 후 N초 뒤 다음 대기 경매 자동 시작 (설정 auction.autoNext)
---------------------------------------------------------------------------
function A:AutoNextDelay()
    return math.max(3, math.min(60, math.floor(tonumber(BRL.acct.auction.autoNextDelay) or 8)))
end

function A:ScheduleAutoNext(sessionId)
    if not BRL.acct.auction.autoNext then return false end
    if self:GetActive() then return false end
    local q = self:Queue(sessionId or (BRL.Session:GetActive() or {}).id)
    if #q == 0 then
        if self.autoNext then self:CancelAutoNext() end
        BRL.ChatOut:Send("[경매] 대기 중인 경매가 모두 끝났습니다.")
        return false
    end
    local delay = self:AutoNextDelay()
    self.autoNextToken = (self.autoNextToken or 0) + 1
    local token = self.autoNextToken
    self.autoNext = { at = U.Clock() + delay, auctionId = q[1].id, sessionId = q[1].sessionId }
    BRL.ChatOut:Send(string.format("[경매] 다음 경매 %d초 후 시작: %s (남은 %d건)", delay, q[1].itemLink or q[1].itemName or "?", #q))
    API.After(delay, function()
        if self.autoNextToken ~= token or not self.autoNext then return end
        self.autoNext = nil
        if not BRL.acct.auction.autoNext or self:GetActive() then return end
        if API.InCombat() then
            BRL:Print("전투 중이라 다음 경매 자동 시작을 보류했습니다. [다음 경매 시작]을 눌러 주세요.")
            return
        end
        local auc = self:Get(q[1].id)
        if auc and auc.status == "queued" then
            local ok, err = self:Start(auc.id)
            if not ok then BRL:Print("다음 경매 자동 시작 실패: %s", tostring(err)) end
        end
        changed()
    end)
    changed()
    return true
end

function A:CancelAutoNext()
    if not self.autoNext then return false end
    self.autoNext = nil
    self.autoNextToken = (self.autoNextToken or 0) + 1
    changed()
    return true
end

function A:AutoNextRemaining()
    if not self.autoNext then return nil end
    return math.max(0, math.ceil(self.autoNext.at - U.Clock()))
end

function A:StartTicker()
    if self.ticker then return end
    self.ticker = API.NewTicker(0.25, function() self:Tick() end)
end

function A:StopTicker()
    if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
    self.ticker = nil
end

function A:Tick()
    local auc = self:GetActive()
    if not auc then self:StopTicker() return end
    local rem = self:Remaining(auc)
    local sec = math.ceil(rem)
    local cfg = BRL.acct.auction
    if auc.countEndsClock then
        -- 카운트: 4, 3, 2, 1 (시작 숫자는 BeginCount 에서 공지)
        if sec > 0 and sec ~= self.lastAnnouncedSecond then
            self.lastAnnouncedSecond = sec
            BRL.ChatOut:Announce(tostring(sec))
        end
    elseif cfg.countdownAnnounce and sec <= self:CountSeconds() and sec > 0 then
        -- 시간 만료 직전에는 수동 카운트와 같은 형식으로 자동 카운트 (같은 [카운트 취소] 로 멈춤)
        self:BeginCount(auc, sec, true)
    end
    BRL.Events:Fire(BRL.Events.MSG.AUCTION_TICK, auc, rem)
    if rem <= 0 then self:End(auc.id, (auc.countEndsClock and not auc.countAuto) and "count" or "timer") end
end

---------------------------------------------------------------------------
-- 수동 카운트 ("카운트 5, 4, 3, 2, 1" → 입찰 마감) / 카운트 취소
---------------------------------------------------------------------------
function A:CountSeconds()
    return math.max(3, math.min(10, math.floor(tonumber(BRL.acct.auction.countdownFrom) or 5)))
end

function A:IsCounting(auc)
    auc = auc or self:GetActive()
    return auc ~= nil and auc.status == "active" and auc.countEndsClock ~= nil
end

function A:StartCount(id)
    local auc = id and self:Get(id) or self:GetActive()
    if not auc or auc.status ~= "active" then return false, "진행 중인 경매가 없습니다" end
    if not requireEdit(auc) then return false, "권한 없음" end
    if auc.countEndsClock then return false, "이미 카운트 중입니다" end
    return self:BeginCount(auc, self:CountSeconds(), false)
end

-- 카운트 시작 공통 (수동: n초로 단축 / 자동: 남은 시간 그대로)
function A:BeginCount(auc, n, auto)
    if auto then
        auc.preCountEnds = nil
        auc.countEndsClock = auc.endsClock
    else
        auc.preCountEnds = auc.endsClock
        auc.countEndsClock = U.Clock() + n
        auc.endsClock = auc.countEndsClock
    end
    auc.countAuto = auto or nil
    self.lastAnnouncedSecond = n
    DB:Audit("auction.count.start", "auction", auc.id, { seconds = n, high = auc.highAmount, bidder = auc.highBidder, auto = auto or nil })
    local top = auc.highBidder and (API.ShortName(auc.highBidder) .. " " .. Money.Format(auc.highAmount)) or "입찰 없음"
    BRL.ChatOut:Announce(string.format("[카운트] %s 최고 %s - %d", auc.itemLink, top, n))
    self:StartTicker()
    changed()
    return true
end

-- reason: "manual"(공대장) | "bid"(카운트 중 새 입찰)
function A:CancelCount(id, reason)
    local auc = id and self:Get(id) or self:GetActive()
    if not auc or auc.status ~= "active" then return false, "진행 중인 경매가 없습니다" end
    if reason ~= "bid" and not requireEdit(auc) then return false, "권한 없음" end
    local now = U.Clock()
    local resume = math.max(10, self:CountSeconds() * 2)
    if auc.countEndsClock then
        auc.endsClock = math.max(auc.preCountEnds or 0, now + resume)
        auc.countEndsClock, auc.preCountEnds, auc.countAuto = nil, nil, nil
    elseif self:Remaining(auc) <= self:CountSeconds() then
        -- 시간 만료 직전 자동 카운트다운도 취소 가능
        auc.endsClock = now + resume
    else
        return false, "진행 중인 카운트가 없습니다"
    end
    self.lastAnnouncedSecond = nil
    DB:Audit("auction.count.cancel", "auction", auc.id, { reason = reason or "manual" })
    -- 새 입찰로 취소되면 이 한 줄이 최고 입찰 공지를 겸한다
    BRL.ChatOut:Announce(reason == "bid" and string.format("[카운트 취소] 새 입찰 %s %s (다음 최소 %s) - 입찰 계속",
            API.ShortName(auc.highBidder or "?"), Money.Format(auc.highAmount or 0), Money.Format(self:NextMinimum(auc)))
        or "[카운트 취소] 입찰 계속")
    changed()
    return true
end

function A:ExtendTime(id, seconds)
    local auc = self:Get(id)
    if not auc or auc.status ~= "active" then return false end
    if not requireEdit(auc) then return false end
    auc.endsClock = math.max(auc.endsClock, U.Clock()) + seconds
    self.lastAnnouncedSecond = nil
    BRL.ChatOut:Send(string.format("%s 경매 시간 %d초 연장", auc.itemLink, seconds))
    changed()
    return true
end

-- 입찰 반영 (Bids 모듈에서 호출)
function A:ApplyBid(auc, bid)
    auc.highBidId = bid.id
    auc.highAmount = bid.amount
    auc.highBidder = bid.bidderKey
    local cfg = BRL.acct.auction
    local countCancelled = false
    if auc.countEndsClock and cfg.cancelCountOnBid ~= false then countCancelled = self:CancelCount(auc.id, "bid") == true end
    local rem = self:Remaining(auc)
    if cfg.antiSnipeSeconds and cfg.antiSnipeSeconds > 0 and rem < cfg.antiSnipeSeconds then
        auc.endsClock = U.Clock() + cfg.antiSnipeSeconds
        self.lastAnnouncedSecond = nil
    end
    if cfg.announceBids and not countCancelled then
        BRL.ChatOut:Send(string.format("최고 입찰: %s %s (다음 최소 %s)", bid.bidderName or "?",
            Money.Format(bid.amount), Money.Format(self:NextMinimum(auc))))
    end
    if auc.buyout and auc.buyout > 0 and bid.amount >= auc.buyout then
        self:End(auc.id, "buyout")
    end
    changed()
end

-- 입찰 취소 등으로 최고가 재계산
function A:RecalculateHigh(auc)
    local best
    for _, b in ipairs(BRL.Bids:ForAuction(auc.id)) do
        if b.accepted and not b.retracted then
            if not best or b.amount > best.amount or (b.amount == best.amount and b.at < best.at) then best = b end
        end
    end
    auc.highBidId = best and best.id or nil
    auc.highAmount = best and best.amount or nil
    auc.highBidder = best and best.bidderKey or nil
    changed()
end

function A:End(id, reason)
    local auc = self:Get(id)
    if not auc or auc.status ~= "active" then return false end
    auc.status = "ended"
    auc.endReason = reason or "manual"
    auc.endedAt = U.Now()
    auc.endsClock = nil
    auc.countEndsClock, auc.preCountEnds, auc.countAuto = nil, nil, nil
    DB:Audit("auction.end", "auction", auc.id, { reason = auc.endReason, high = auc.highAmount, bidder = auc.highBidder })
    if not self:GetActive() then self:StopTicker() end
    if not auc.highBidId then
        self:MarkUnsold(id, true)
        return true
    end
    if BRL.acct.auction.autoConfirmAward then
        self:ConfirmAward(id) -- [낙찰] 공지가 마감 공지를 겸함
    else
        BRL.ChatOut:Send(string.format("[입찰 마감] %s 최고 입찰 %s %s - 공대장 확인 후 낙찰 확정",
            auc.itemLink, API.ShortName(auc.highBidder), Money.Format(auc.highAmount)))
    end
    changed()
    return true
end

-- 낙찰 확정. bidId 생략 시 최고 입찰.
function A:ConfirmAward(id, bidId)
    local auc = self:Get(id)
    if not auc then return nil, "경매 없음" end
    if not requireEdit(auc) then return nil, "권한 없음" end
    if auc.status == "active" then self:End(id, "manual") end
    if auc.status ~= "ended" then return nil, "종료된 경매만 낙찰 확정할 수 있습니다" end
    local bid = BRL.Bids:Get(bidId or auc.highBidId)
    if not bid or bid.auctionId ~= auc.id or not bid.accepted or bid.retracted then return nil, "유효한 입찰이 없습니다" end
    local class
    for _, m in ipairs(API.GetGroupRoster()) do if m.key == bid.bidderKey then class = m.class end end
    local award = DB:Insert("awards", {
        auctionId = auc.id,
        sessionId = auc.sessionId,
        winnerKey = bid.bidderKey,
        winnerName = API.ShortName(bid.bidderKey),
        winnerClass = class,
        amount = bid.amount,
        bidId = bid.id,
        itemLink = auc.itemLink,
        itemName = auc.itemName,
        quantity = auc.quantity,
        awardedAt = U.Now(),
        status = "active",
        delivered = false,
    })
    auc.status = "awarded"
    auc.awardId = award.id
    DB:Audit("award.create", "award", award.id, { auction = auc.id, winner = award.winnerKey, amount = award.amount })
    BRL.ChatOut:Announce(string.format("[낙찰] %s → %s %s", auc.itemLink, award.winnerName, Money.Format(award.amount)))
    changed()
    BRL.Events:Fire(BRL.Events.MSG.LEDGER_CHANGED)
    if award.winnerKey == BRL.playerKey then
        BRL.Events:Fire(BRL.Events.MSG.SELF_AWARD, award) -- 기록 확인 창 (전투 중이면 채팅 안내)
    end
    self:ScheduleAutoNext(auc.sessionId)
    return award
end

function A:MarkUnsold(id, silentPerm)
    local auc = self:Get(id)
    if not auc then return false end
    if not silentPerm and not requireEdit(auc) then return false end
    if auc.status ~= "ended" and auc.status ~= "active" and auc.status ~= "queued" then return false end
    if auc.status == "active" then auc.endsClock = nil end
    auc.status = "unsold"
    auc.endedAt = auc.endedAt or U.Now()
    DB:Audit("auction.unsold", "auction", auc.id)
    BRL.ChatOut:Send(string.format("[유찰] %s", auc.itemLink))
    if not self:GetActive() then self:StopTicker() end
    changed()
    self:ScheduleAutoNext(auc.sessionId)
    return true
end

function A:Cancel(id, reason)
    local auc = self:Get(id)
    if not auc then return false end
    if not requireEdit(auc) then return false end
    if auc.status == "awarded" or auc.status == "cancelled" or auc.status == "unsold" then
        return false, "이미 종료된 경매입니다 (낙찰 취소는 낙찰 목록에서 하세요)"
    end
    local wasActive = auc.status == "active"
    auc.status = "cancelled"
    auc.cancelReason = reason
    auc.endsClock = nil
    DB:Audit("auction.cancel", "auction", auc.id, { reason = reason })
    if wasActive then BRL.ChatOut:Send(string.format("[경매 취소] %s", auc.itemLink)) end
    if not self:GetActive() then self:StopTicker() end
    changed()
    return true
end

-- 재경매: 동일 아이템으로 새 경매를 대기열에 추가
function A:Relist(id)
    local auc = self:Get(id)
    if not auc then return nil end
    local ok = auc.status == "unsold" or auc.status == "cancelled"
    if auc.status == "awarded" then
        local aw = DB:Get("awards", auc.awardId)
        ok = aw and aw.status == "cancelled"
    end
    if not ok then return nil, "유찰/취소/낙찰 취소된 경매만 재경매할 수 있습니다" end
    return self:Add(auc.itemLink, {
        quantity = auc.quantity, startPrice = auc.startPrice, minIncrement = auc.minIncrement,
        buyout = auc.buyout, duration = auc.duration, relistOf = auc.id, allowDuplicate = true,
    })
end

---------------------------------------------------------------------------
-- 낙찰 관리
---------------------------------------------------------------------------
function A:GetAward(id) return DB:Get("awards", id) end

function A:Awards(sessionId, includeCancelled)
    return DB:List("awards", function(a)
        if sessionId and a.sessionId ~= sessionId then return false end
        if not includeCancelled and a.status == "cancelled" then return false end
        return true
    end, "awardedAt")
end

function A:AwardsForPlayer(key, sessionId)
    return DB:List("awards", function(a)
        return a.winnerKey == key and a.status == "active" and (not sessionId or a.sessionId == sessionId)
    end, "awardedAt")
end

-- 낙찰 취소. 이미 수금한 금액은 환불 필요로 표시된다.
function A:CancelAward(awardId, reason)
    local aw = self:GetAward(awardId)
    if not aw then return false, "낙찰 없음" end
    if not requireEdit(aw) then return false, "권한 없음" end
    if aw.status ~= "active" then return false, "이미 취소된 낙찰입니다" end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "취소 사유를 입력하세요" end
    aw.status = "cancelled"
    aw.cancelReason = reason
    aw.cancelledAt = U.Now()
    DB:AddHistory(aw, "status", "active", "cancelled", reason)
    DB:Audit("award.cancel", "award", aw.id, { reason = reason })
    BRL.Events:Fire(BRL.Events.MSG.LEDGER_CHANGED)
    changed()
    return true
end

function A:ChangeAwardAmount(awardId, amount, reason)
    local aw = self:GetAward(awardId)
    if not aw then return false, "낙찰 없음" end
    if not requireEdit(aw) then return false, "권한 없음" end
    if not Money.IsValid(amount) or amount <= 0 then return false, "금액 오류" end
    reason = U.Trim(reason or "")
    if reason == "" then return false, "수정 사유를 입력하세요" end
    DB:AddHistory(aw, "amount", aw.amount, amount, reason)
    DB:Audit("award.amount", "award", aw.id, { old = aw.amount, new = amount, reason = reason })
    aw.amount = amount
    BRL.Events:Fire(BRL.Events.MSG.LEDGER_CHANGED)
    changed()
    return true
end

function A:SetDelivered(awardId, delivered)
    local aw = self:GetAward(awardId)
    if not aw then return false end
    if not requireEdit(aw) then return false end
    DB:AddHistory(aw, "delivered", aw.delivered, delivered)
    aw.delivered = delivered and true or false
    aw.deliveredAt = delivered and U.Now() or nil
    changed()
    return true
end

-- 결과 공지 문구
function A:ResultLines(sessionId)
    local lines = { "[BIG RAID LEADER 경매 결과]" }
    local total = 0
    for _, aw in ipairs(self:Awards(sessionId)) do
        local st = BRL.Payments:AwardStatus(aw)
        lines[#lines + 1] = string.format("%s → %s %s (%s)", aw.itemLink or aw.itemName, aw.winnerName,
            Money.Format(aw.amount), BRL.Label("AWARD_", st.status))
        total = total + aw.amount
    end
    lines[#lines + 1] = "총 낙찰액: " .. Money.Format(total)
    return lines
end

function A:ExportCSV(sessionId)
    local csv = BRL.TradeJournal.CSV
    local lines = { "경매ID,아이템,수량,상태,시작가,최고입찰,낙찰자,낙찰금액,수금액,미수금,아이템전달,낙찰시각" }
    for _, auc in ipairs(self:List(sessionId)) do
        local aw = auc.awardId and DB:Get("awards", auc.awardId)
        local st = aw and BRL.Payments:AwardStatus(aw)
        lines[#lines + 1] = table.concat({
            csv(auc.id), csv(auc.itemName), csv(auc.quantity), csv(BRL.Label("AUC_", auc.status)), csv(auc.startPrice),
            csv(auc.highAmount or ""), csv(aw and aw.winnerKey or ""), csv(aw and aw.amount or ""),
            csv(st and st.collected or ""), csv(st and st.outstanding or ""), csv(aw and (aw.delivered and "Y" or "N") or ""),
            csv(aw and U.FormatDateTime(aw.awardedAt) or ""),
        }, ",")
    end
    return table.concat(lines, "\n")
end
