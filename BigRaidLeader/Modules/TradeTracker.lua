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
    -- 재시작 직후 GetMoney 기준은 신뢰할 수 없으므로 금액 검증을 하지 않는다
    sess.moneyAtOpen = nil
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
        if exp == 0 or delta == nil or delta == exp or (U.Clock() - (sess.closedClock or 0)) > 1 then
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

    local status, verification
    if reason == "interrupted" then
        status, verification = "unverified", "interrupted"
    elseif s.complete and s.cancel then
        if moneyMatch and exp ~= 0 then status, verification = "completed", "message+money"
        else status, verification = "unverified", "conflict" end
    elseif s.complete then
        status = "completed"
        if exp ~= 0 and moneyMatch then verification = "message+money"
        elseif exp ~= 0 and delta ~= nil and not moneyMatch then verification = "message_money_mismatch"
        else verification = "message" end
    elseif s.cancel then
        status, verification = "cancelled", "cancel_signal"
    elseif moneyMatch and exp ~= 0 then
        status, verification = "completed", "money"
    elseif exp ~= 0 and delta == 0 then
        status, verification = "cancelled", "money_unchanged"
    else
        status, verification = "unverified", "no_signal"
    end

    if self.pending == sess then self.pending = nil end
    if self.current == sess then self.current = nil end
    if BRL.db and BRL.db.activeTrade == sess then BRL.db.activeTrade = nil end

    -- 아무것도 오가지 않은 취소 거래는 기록하지 않음
    if status == "cancelled" and snapshotEmpty(chosen) then
        BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, nil)
        return nil
    end

    local rec = BRL.TradeJournal:RecordFromTracker(sess, chosen, status, verification, {
        reason = reason, moneyDelta = delta, cancelReason = s.cancelReason,
    })
    if rec and status == "unverified" then
        self.lastFinalized = { id = rec.id, clock = U.Clock() }
    else
        self.lastFinalized = nil
    end
    BRL.Events:Fire(BRL.Events.MSG.TRADE_STATE, nil)
    return rec
end

function Tracker:GetCurrent()
    return self.current or self.pending
end
