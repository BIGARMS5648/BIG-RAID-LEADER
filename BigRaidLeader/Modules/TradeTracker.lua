-- BIG RAID LEADER - 거래 자동 추적 (상태 기계)
-- 원칙
--  * 거래 창이 닫혔다는 이유만으로 완료 처리하지 않는다.
--  * 완료 신호: ERR_TRADE_COMPLETE 시스템 메시지(1차) + 보유 골드 변화 일치(교차 검증)
--  * 취소 신호: ERR_TRADE_CANCELLED 등 / TRADE_REQUEST_CANCEL / 골드 변화 없음
--  * 신호가 불충분하면 "확인 불가"로 기록하고 수입으로 합산하지 않는다.
--  * 확정 처리(Finalize)는 멱등적이며 이벤트 중복/순서 변경에 안전하다.
--  * 진행 중 거래는 SavedVariables 에 보존하여 UI 재시작 시에도 기록이 사라지지 않는다.
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Tracker = BRL:NewModule("TradeTracker")

Tracker.current = nil     -- 거래 창이 열려 있는 세션
Tracker.pending = nil     -- 창이 닫히고 결과 판정을 기다리는 세션
Tracker.lastFinalized = nil

local MAX_EVENTS = 40
local MAX_TRACES = 10

local function logEvent(sess, name, a, b)
    if not sess then return end
    sess.events = sess.events or {}
    if #sess.events < MAX_EVENTS then
        sess.events[#sess.events + 1] = { e = name, t = U.Clock(), a = a, b = b }
    end
end

local function snapshotEmpty(snap)
    return not snap or ((snap.playerMoney or 0) == 0 and (snap.targetMoney or 0) == 0
        and #(snap.playerItems or {}) == 0 and #(snap.targetItems or {}) == 0)
end
Tracker.SnapshotEmpty = snapshotEmpty

local function persist(sess)
    if BRL.db then BRL.db.activeTrade = sess end
end

function Tracker:OnEnable()
    local E = BRL.Events
    E:Register("TRADE_SHOW", self, "OnTradeShow")
    E:Register("TRADE_CLOSED", self, "OnTradeClosed")
    E:Register("TRADE_MONEY_CHANGED", self, "OnTradeChanged")
    E:Register("TRADE_PLAYER_ITEM_CHANGED", self, "OnTradeChanged")
    E:Register("TRADE_TARGET_ITEM_CHANGED", self, "OnTradeChanged")
    E:Register("TRADE_UPDATE", self, "OnTradeChanged")
    E:Register("TRADE_ACCEPT_UPDATE", self, "OnTradeAcceptUpdate")
    E:Register("TRADE_REQUEST_CANCEL", self, "OnTradeRequestCancel")
    E:Register("UI_INFO_MESSAGE", self, "OnUIMessage")
    E:Register("UI_ERROR_MESSAGE", self, "OnUIMessage")
    E:Register("CHAT_MSG_SYSTEM", self, "OnSystemMessage")
    E:Register("PLAYER_MONEY", self, "OnPlayerMoney")
    E:Register("BAG_UPDATE_DELAYED", self, "OnBagUpdate")
    self:RecoverInterrupted()
end

function Tracker:IsEnabled()
    return BRL.acct and BRL.acct.trade.autoRecord
end

-- UI 재시작/접속 종료로 중단된 거래 복구: 결과를 알 수 없으므로 "확인 불가"로 기록
function Tracker:RecoverInterrupted()
    local sess = BRL.db and BRL.db.activeTrade
    if type(sess) ~= "table" or sess.finalized then
        if BRL.db then BRL.db.activeTrade = nil end
        return
    end
    sess.signals = sess.signals or {}
    sess.interrupted = true
    -- 재시작 직후 GetMoney/가방 기준은 신뢰할 수 없으므로 금액·아이템 검증을 하지 않는다
    sess.moneyAtOpen = nil
    sess.itemBase, sess.itemExp = nil, nil
    self:Finalize(sess, "interrupted")
end

function Tracker:OnTradeShow()
    if not self:IsEnabled() then return end
    -- 직전 거래 판정이 남아 있으면 먼저 확정
    if self.pending then self:Finalize(self.pending, "next_trade") end
    if self.current and not self.current.finalized then
        self.current.signals.closed = true
        self:Finalize(self.current, "reopened")
    end
    local partner, guid, class = API.GetTradePartner()
    local sess = {
        id = BRL.NewId("TR"),
        openedAt = U.Now(),
        openedClock = U.Clock(),
        partnerKey = partner,
        partnerGuid = guid,
        partnerClass = class,
        moneyAtOpen = API.GetMoney(),
        live = API.GetTradeSnapshot(),
        acceptSnap = nil,
        lastNonEmpty = nil,
        playerAccepted = false,
        targetAccepted = false,
        signals = { complete = false, cancel = false, closed = false },
        events = {},
    }
    if not snapshotEmpty(sess.live) then sess.lastNonEmpty = U.DeepCopy(sess.live) end
    logEvent(sess, "TRADE_SHOW")
    self.current = sess
    persist(sess)
    BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, sess)
end

function Tracker:RefreshLive(sess)
    if not sess then return end
    local snap = API.GetTradeSnapshot()
    sess.live = snap
    if not snapshotEmpty(snap) then sess.lastNonEmpty = U.DeepCopy(snap) end
    if not sess.partnerKey then
        sess.partnerKey, sess.partnerGuid, sess.partnerClass = API.GetTradePartner()
    end
end

function Tracker:OnTradeChanged(event)
    local sess = self.current
    if not sess then return end
    logEvent(sess, event)
    self:RefreshLive(sess)
    persist(sess)
    BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, sess)
end

function Tracker:OnTradeAcceptUpdate(_, playerAccepted, targetAccepted)
    local sess = self.current
    if not sess then return end
    local p = (playerAccepted == 1 or playerAccepted == true)
    local t = (targetAccepted == 1 or targetAccepted == true)
    logEvent(sess, "TRADE_ACCEPT_UPDATE", p, t)
    sess.playerAccepted, sess.targetAccepted = p, t
    self:RefreshLive(sess)
    if p or t then
        -- 수락 시점의 내용 = 완료될 경우의 최종 내용 (이후 변경 시 서버가 수락을 해제함)
        sess.acceptSnap = U.DeepCopy(sess.live)
        if snapshotEmpty(sess.acceptSnap) and sess.lastNonEmpty then
            sess.acceptSnap = U.DeepCopy(sess.lastNonEmpty)
        end
        sess.everAccepted = true
        if p and t then sess.bothAccepted = true end
        self:CaptureItemBaseline(sess, sess.acceptSnap)
    else
        sess.acceptSnap = nil
    end
    persist(sess)
    BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, sess)
end

function Tracker:OnTradeRequestCancel()
    local sess = self.current or self.pending
    if not sess then return end
    logEvent(sess, "TRADE_REQUEST_CANCEL")
    sess.signals.cancel = true
    sess.signals.cancelReason = "request_cancel"
    if sess.signals.closed then self:TryFinalize(sess) end
end

-- 시스템 메시지로 완료/취소 판별
function Tracker:HandleMessage(msg, source)
    if API.IsTradeCompleteMessage(msg) then
        local sess = self.pending or self.current
        if sess then
            logEvent(sess, "COMPLETE_MSG", source)
            sess.signals.complete = true
            if sess.signals.closed then self:TryFinalize(sess) end
        elseif self.lastFinalized and (U.Clock() - self.lastFinalized.clock) < 10 then
            -- 판정이 끝난 뒤 늦게 도착한 완료 메시지: 확인 불가 → 완료로 승격
            BRL.TradeJournal:UpgradeToCompleted(self.lastFinalized.id, "late_complete_message")
            self.lastFinalized = nil
        end
        return true
    elseif API.IsTradeCancelMessage(msg) then
        local sess = self.current or self.pending
        if sess then
            logEvent(sess, "CANCEL_MSG", source)
            sess.signals.cancel = true
            sess.signals.cancelReason = msg
            if sess.signals.closed then self:TryFinalize(sess) end
        end
        return true
    end
    return false
end

function Tracker:OnUIMessage(event, _, msg)
    -- UI_INFO_MESSAGE / UI_ERROR_MESSAGE (messageType, message)
    self:HandleMessage(msg, event)
end

function Tracker:OnSystemMessage(_, msg)
    self:HandleMessage(msg, "CHAT_MSG_SYSTEM")
end

function Tracker:OnTradeClosed()
    local sess = self.current
    if not sess then return end -- TRADE_CLOSED 중복 수신
    logEvent(sess, "TRADE_CLOSED")
    sess.signals.closed = true
    sess.closedClock = U.Clock()
    self.current = nil
    self.pending = sess
    persist(sess)
    if not self:TryFinalize(sess) then
        local grace = (BRL.acct and BRL.acct.trade.closeGraceSeconds) or 3
        local id = sess.id
        API.After(grace, function()
            if self.pending and self.pending.id == id then self:Finalize(self.pending, "grace_timeout") end
        end)
    end
end

-- 가방 변화 (거래 아이템 이동 확인)
function Tracker:OnBagUpdate()
    local sess = self.pending
    if not sess then return end
    logEvent(sess, "BAG_UPDATE_DELAYED")
    self:TryFinalize(sess)
end

---------------------------------------------------------------------------
-- 아이템 수량 교차 검증
--  수락 시점의 거래 아이템별 예상 증감(받은 수 - 준 수)과 가방 기준 수량을 기록하고,
--  거래 후 가방 수량 변화가 예상과 일치하는지 확인한다. 골드가 없는 아이템 거래의
--  완료 메시지 누락 대비용 보조 신호이며, 수량을 읽을 수 없으면 사용하지 않는다.
---------------------------------------------------------------------------
local function itemExpectations(snap)
    if not snap then return nil end
    local exp, any, nonZero = {}, false, false
    for _, side in ipairs({ { snap.targetItems, 1 }, { snap.playerItems, -1 } }) do
        for _, it in ipairs(side[1] or {}) do
            local id = U.ItemIdFromLink(it.link)
            if not id then return nil end
            exp[id] = (exp[id] or 0) + side[2] * (it.count or 1)
            any = true
        end
    end
    if not any then return nil end
    for _, d in pairs(exp) do if d ~= 0 then nonZero = true end end
    if not nonZero then return nil end -- 같은 아이템을 같은 수만큼 주고받으면 판별 불가
    return exp
end

function Tracker:CaptureItemBaseline(sess, snap)
    local exp = itemExpectations(snap)
    if not exp then sess.itemExp, sess.itemBase = nil, nil return end
    local base = {}
    for id in pairs(exp) do
        local n = API.GetItemCount(id)
        if n == nil then sess.itemExp, sess.itemBase = nil, nil return end
        base[id] = n
    end
    sess.itemExp, sess.itemBase = exp, base
end

-- 반환: "match" | "unchanged" | "mismatch" | nil(판별 불가)
function Tracker:ItemCheck(sess)
    if not sess.itemExp or not sess.itemBase then return nil end
    local allMatch, allZero = true, true
    for id, want in pairs(sess.itemExp) do
        local now = API.GetItemCount(id)
        local base = sess.itemBase[id]
        if now == nil or base == nil then return nil end
        local d = now - base
        if d ~= want then allMatch = false end
        if d ~= 0 then allZero = false end
    end
    if allMatch then return "match" end
    if allZero then return "unchanged" end
    return "mismatch"
end

function Tracker:OnPlayerMoney()
    local sess = self.pending
    if not sess then return end
    logEvent(sess, "PLAYER_MONEY")
    self:TryFinalize(sess)
end

-- 실제 골드 변화량 (거래 시작 시점 대비)
function Tracker:MoneyDelta(sess)
    if not sess.moneyAtOpen then return nil end
    local now = API.GetMoney()
    if not now then return nil end
    return now - sess.moneyAtOpen
end

local function expectedDelta(snap)
    if not snap then return nil end
    return (snap.targetMoney or 0) - (snap.playerMoney or 0)
end

-- 결정적 신호가 있으면 즉시 확정. 반환: 확정 여부
function Tracker:TryFinalize(sess)
    if sess.finalized or not sess.signals.closed then return sess.finalized end
    local s = sess.signals
    if s.cancel and not s.complete then
        self:Finalize(sess, "cancel_signal")
        return true
    end
    if s.complete then
        -- 골드가 오가는 거래는 PLAYER_MONEY 반영 후 확정하여 금액 교차 검증 결과를 남김
        local snap = sess.acceptSnap or sess.live
        local exp = expectedDelta(snap)
        local delta = self:MoneyDelta(sess)
        local late = (U.Clock() - (sess.closedClock or 0)) > 1
        local moneyReady = exp == 0 or delta == nil or delta == exp
        -- 골드가 없는 아이템 거래는 가방 반영(BAG_UPDATE_DELAYED)까지 잠시 기다려 아이템 검증 결과를 남김
        local itemsReady = exp ~= 0 or not sess.itemExp or self:ItemCheck(sess) == "match"
        if (moneyReady and itemsReady) or late then
            self:Finalize(sess, "complete_signal")
            return true
        end
        -- 다음 PLAYER_MONEY 또는 유예 타이머에서 확정
        return false
    end
    -- 완료 메시지 없이 골드 변화가 정확히 일치하는 경우(메시지 누락)
    local delta = self:MoneyDelta(sess)
    if delta and delta ~= 0 then
        for _, snap in ipairs({ sess.acceptSnap, sess.live, sess.lastNonEmpty }) do
            local exp = expectedDelta(snap)
            if exp and exp ~= 0 and exp == delta then
                self:Finalize(sess, "money_match")
                return true
            end
        end
    end
    -- 완료 메시지 없이 아이템 수량 변화가 정확히 일치 (골드 없는 거래)
    if (expectedDelta(sess.acceptSnap) or 0) == 0 and self:ItemCheck(sess) == "match" then
        self:Finalize(sess, "items_match")
        return true
    end
    return false
end

-- 최종 판정 (멱등)
function Tracker:Finalize(sess, reason)
    if not sess or sess.finalized then return nil end
    sess.finalized = true
    logEvent(sess, "FINALIZE", reason)
    local s = sess.signals or {}
    local delta = self:MoneyDelta(sess)

    -- 최종 내용 선택: 실제 골드 변화와 일치하는 스냅샷 우선
    local candidates = { sess.acceptSnap, sess.live, sess.lastNonEmpty }
    local chosen = sess.acceptSnap or sess.live or sess.lastNonEmpty or API.GetTradeSnapshot()
    if snapshotEmpty(chosen) and sess.lastNonEmpty then chosen = sess.lastNonEmpty end
    local moneyMatch = false
    if delta ~= nil then
        for _, snap in ipairs(candidates) do
            if snap and expectedDelta(snap) == delta then
                chosen = snap
                moneyMatch = true
                break
            end
        end
    end
    local exp = expectedDelta(chosen) or 0
    local itemCheck = (reason ~= "interrupted") and self:ItemCheck(sess) or nil

    local status, verification
    if reason == "interrupted" then
        status, verification = "unverified", "interrupted"
    elseif s.complete and s.cancel then
        if moneyMatch and exp ~= 0 then status, verification = "completed", "message+money"
        elseif exp == 0 and itemCheck == "match" then status, verification = "completed", "message+items"
        else status, verification = "unverified", "conflict" end
    elseif s.complete then
        status = "completed"
        if exp ~= 0 and moneyMatch then verification = "message+money"
        elseif exp ~= 0 and delta ~= nil and not moneyMatch then verification = "message_money_mismatch"
        elseif itemCheck == "match" then verification = "message+items"
        else verification = "message" end
    elseif s.cancel then
        status, verification = "cancelled", "cancel_signal"
    elseif moneyMatch and exp ~= 0 then
        status, verification = "completed", "money"
    elseif exp ~= 0 and delta == 0 then
        status, verification = "cancelled", "money_unchanged"
    elseif exp == 0 and itemCheck == "match" then
        status, verification = "completed", "items"
    elseif exp == 0 and itemCheck == "unchanged" then
        status, verification = "cancelled", "items_unchanged"
    else
        status, verification = "unverified", "no_signal"
    end
    sess.itemCheck = itemCheck

    if self.pending == sess then self.pending = nil end
    if self.current == sess then self.current = nil end
    if BRL.db and BRL.db.activeTrade == sess then BRL.db.activeTrade = nil end

    -- 아무것도 오가지 않은 취소 거래는 기록하지 않음 (이벤트 추적에는 남김)
    if status == "cancelled" and snapshotEmpty(chosen) then
        self:AddTrace(sess, chosen, status, verification, reason, nil)
        BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, nil)
        return nil
    end

    local rec = BRL.TradeJournal:RecordFromTracker(sess, chosen, status, verification, {
        reason = reason, moneyDelta = delta, cancelReason = s.cancelReason, itemCheck = itemCheck,
    })
    self:AddTrace(sess, chosen, status, verification, reason, rec)
    if rec and status == "unverified" then
        self.lastFinalized = { id = rec.id, clock = U.Clock() }
    else
        self.lastFinalized = nil
    end
    BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, nil)
    return rec
end

---------------------------------------------------------------------------
-- 최근 거래 이벤트 추적 (기록되지 않은 거래 포함, 최근 10건)
---------------------------------------------------------------------------
function Tracker:AddTrace(sess, snap, status, verification, reason, rec)
    if not BRL.db then return end
    BRL.db.tradeTraces = BRL.db.tradeTraces or {}
    local list = BRL.db.tradeTraces
    snap = snap or {}
    table.insert(list, 1, {
        id = sess.id, at = U.Now(), partnerKey = sess.partnerKey, status = status, verification = verification,
        reason = reason, recorded = rec ~= nil, given = snap.playerMoney or 0, received = snap.targetMoney or 0,
        items = #(snap.playerItems or {}) + #(snap.targetItems or {}), moneyDelta = self:MoneyDelta(sess),
        itemCheck = sess.itemCheck, events = U.DeepCopy(sess.events or {}), openedClock = sess.openedClock,
    })
    while #list > MAX_TRACES do table.remove(list) end
end

function Tracker:RecentTraces()
    return (BRL.db and BRL.db.tradeTraces) or {}
end

-- 이벤트 목록을 사람이 읽을 수 있는 줄로
local EVENT_LABELS = {
    TRADE_SHOW = "거래 창 열림", TRADE_CLOSED = "거래 창 닫힘", TRADE_MONEY_CHANGED = "골드 변경",
    TRADE_PLAYER_ITEM_CHANGED = "내 아이템 변경", TRADE_TARGET_ITEM_CHANGED = "상대 아이템 변경",
    TRADE_UPDATE = "거래 갱신", TRADE_ACCEPT_UPDATE = "수락 상태", TRADE_REQUEST_CANCEL = "거래 요청 취소",
    COMPLETE_MSG = "완료 메시지", CANCEL_MSG = "취소 메시지", PLAYER_MONEY = "보유 골드 변화",
    BAG_UPDATE_DELAYED = "가방 변화", FINALIZE = "판정",
}
function Tracker:FormatEvents(events, startClock)
    local out = {}
    local t0 = startClock or (events and events[1] and events[1].t) or 0
    for _, e in ipairs(events or {}) do
        local extra = ""
        if e.e == "TRADE_ACCEPT_UPDATE" then
            extra = string.format(" (나 %s / 상대 %s)", e.a and "수락" or "-", e.b and "수락" or "-")
        elseif e.a ~= nil then
            extra = " (" .. tostring(e.a) .. ")"
        end
        out[#out + 1] = string.format("+%.2f초  %s%s", (e.t or t0) - t0, EVENT_LABELS[e.e] or e.e, extra)
    end
    if #events >= MAX_EVENTS then out[#out + 1] = "(이벤트 " .. MAX_EVENTS .. "개 이후 생략)" end
    return out
end

function Tracker:GetCurrent()
    return self.current or self.pending
end
