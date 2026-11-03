-- BIG RAID LEADER - 애드온 간 데이터 공유 (선택 기능)
-- * 공대장 혼자 설치해도 모든 기능이 동작한다. 통신 실패 시 로컬 기능 유지.
-- * 공대장/부공대장 → 공대원 방향의 "공개 정보"만 전송한다 (공지, 본인 역할, 메모, 경매 현황, 본인 분배액).
-- * 다른 플레이어의 장부 수정 요청 메시지는 존재하지 않으며, 알 수 없는 메시지는 모두 거부한다.
-- * 채팅 잠금(우두머리 전투 등) 중에는 대기열에 보관했다가 잠금 해제 후 전송한다.
local _, BRL = ...
local U, API, Money = BRL.Util, BRL.API, BRL.Money

local Sync = BRL:NewModule("Sync")

Sync.queue = {}
Sync.partial = {}
Sync.versions = {}
Sync.rejected = 0
Sync.received = { notices = {}, roles = nil, auction = nil, awards = {}, payout = nil, notes = {} }

local SEP = "\t" -- DBM 등 다수 애드온이 사용하는 구분자
local MAX = 240

-- 메시지 유형 → 허용 발신 권한
local ALLOWED = {
    VQ = "any", VR = "any", RD = "any",
    NT = "officer", RL = "officer", NO = "officer",
    AU = "leader", AW = "leader", PY = "leader",
}

local function enabled() return BRL.acct.sync.enabled end

function Sync:OnEnable()
    BRL.Events:Register("CHAT_MSG_ADDON", self, "OnAddonMessage")
    BRL.Events:Register("ADDON_RESTRICTION_STATE_CHANGED", self, function() self:Drain() end)
    BRL.Events:Register("PLAYER_REGEN_ENABLED", self, function() self:Drain() end)
end

local function escape(s)
    s = tostring(s == nil and "" or s)
    return (s:gsub(SEP, " "))
end

local function encode(kind, ...)
    local parts = { kind }
    for i = 1, select("#", ...) do parts[#parts + 1] = escape((select(i, ...))) end
    return table.concat(parts, SEP)
end

local function groupChannel()
    if API.IsInRaid() then return "RAID" end
    if API.IsInGroup() then return "PARTY" end
    return nil
end

-- 전송 (길면 분할)
function Sync:Send(kind, payload, channel, target)
    if not enabled() then return false end
    channel = channel or groupChannel()
    if not channel then return false end
    local msg = payload
    if #msg <= MAX then
        self.queue[#self.queue + 1] = { msg = msg, channel = channel, target = target }
    else
        self.seq = (self.seq or 0) + 1
        local id = U.Base36(self.seq)
        local chunks = {}
        local i = 1
        while i <= #msg do
            local piece = U.Utf8Truncate(msg:sub(i), MAX - 20)
            if piece == "" then piece = msg:sub(i, i) end
            chunks[#chunks + 1] = piece
            i = i + #piece
        end
        for n, c in ipairs(chunks) do
            self.queue[#self.queue + 1] = { msg = table.concat({ "MP", id, n, #chunks }, SEP) .. SEP .. c, channel = channel, target = target }
        end
    end
    self:Drain()
    return true, kind
end

function Sync:Drain()
    if #self.queue == 0 then return end
    if API.InChatLockdown() then
        API.After(3, function() self:Drain() end)
        return
    end
    local now = U.Clock()
    if self.lastSend and now - self.lastSend < 0.2 then
        if not self.scheduled or (now - (self.scheduledAt or 0)) > 2 then
            self.scheduled = true
            self.scheduledAt = now
            API.After(0.2, function() self.scheduled = false self:Drain() end)
        end
        return
    end
    local item = table.remove(self.queue, 1)
    local ok, why = API.SendAddonRaw(BRL.COMM_PREFIX, item.msg, item.channel, item.target)
    self.lastSend = now
    if not ok and why == "lockdown" then table.insert(self.queue, 1, item) end
    if #self.queue > 0 then
        self.scheduled = true
        self.scheduledAt = now
        API.After(0.2, function() self.scheduled = false self:Drain() end)
    end
end

---------------------------------------------------------------------------
-- 송신 헬퍼
---------------------------------------------------------------------------
function Sync:QueryVersions()
    self.versions = {}
    self.versions[BRL.playerKey] = BRL.VERSION
    return self:Send("VQ", encode("VQ"))
end

function Sync:SendNotice(text)
    if not BRL.Perm:Require("sync.broadcast") then return false end
    return self:Send("NT", encode("NT", text))
end

function Sync:SendNotes(planKey)
    if not BRL.Perm:Require("sync.broadcast") then return false end
    for _, c in ipairs(BRL.Command.NOTE_CATEGORIES) do
        local text = BRL.Command:GetNote(planKey, c.key)
        if text ~= "" then self:Send("NO", encode("NO", c.key, text)) end
    end
    return true
end

-- 각 공대원에게 본인 파티/역할/임무 전송
function Sync:SendRoles(planKey)
    if not BRL.acct.sync.shareRoles or not BRL.Perm:Require("sync.broadcast") then return false end
    local n = 0
    for _, m in ipairs(BRL.Roster:GetMembers()) do
        if m.key ~= BRL.playerKey then
            local duties = BRL.Roles:DutiesFor(planKey, m.key)
            local g = BRL.Groups:Locate(m.key) or m.subgroup
            self:Send("RL", encode("RL", m.role or "", g or "", table.concat(duties, ", ")), "WHISPER", m.key)
            n = n + 1
        end
    end
    return n
end

function Sync:BroadcastAuction(auc)
    if not BRL.acct.sync.shareAuction or not BRL.Perm:Can("sync.finance") then return false end
    return self:Send("AU", encode("AU", auc.itemLink, auc.status, auc.highAmount or 0, auc.highBidder and API.ShortName(auc.highBidder) or "",
        math.floor(BRL.Auctions:Remaining(auc)), BRL.Auctions:NextMinimum(auc)))
end

function Sync:BroadcastAward(aw)
    if not BRL.acct.sync.shareAuction or not BRL.Perm:Can("sync.finance") then return false end
    return self:Send("AW", encode("AW", aw.itemLink, aw.winnerName, aw.amount))
end

-- 공대원별 분배 예정액/지급 상태 (본인에게만 귓속말)
function Sync:SendPayouts(settlementId)
    if not BRL.acct.sync.sharePayout or not BRL.Perm:Require("sync.finance") then return 0 end
    local n = 0
    for _, ob in ipairs(BRL.Settlement:Obligations(settlementId)) do
        if ob.memberKey ~= BRL.playerKey and ob.kind == "share" then
            local s = BRL.Payments:ObligationStatus(ob)
            self:Send("PY", encode("PY", ob.amount, s.paid, s.status), "WHISPER", ob.memberKey)
            n = n + 1
        end
    end
    return n
end

-- 준비 상태 보고 (공대원 → 공대장)
function Sync:SendReadyReport()
    local mn = API.GetOwnDurability()
    local leader
    for _, m in ipairs(API.GetGroupRoster()) do if m.isLeader then leader = m.key end end
    if not leader or leader == BRL.playerKey then return false end
    return self:Send("RD", encode("RD", mn or ""), "WHISPER", leader)
end

---------------------------------------------------------------------------
-- 수신
---------------------------------------------------------------------------
local function decode(msg)
    local parts = {}
    for p in (msg .. SEP):gmatch("(.-)" .. SEP) do parts[#parts + 1] = p end
    return parts
end

function Sync:OnAddonMessage(_, prefix, msg, channel, sender)
    if prefix ~= BRL.COMM_PREFIX then return end
    if API.IsSecret(msg) or API.IsSecret(sender) or type(msg) ~= "string" then return end
    local senderKey = API.NormalizeName(sender)
    if not senderKey or senderKey == BRL.playerKey then return end
    local parts = decode(msg)
    if parts[1] == "MP" then
        local id, n, total = parts[2], tonumber(parts[3]), tonumber(parts[4])
        if not id or not n or not total or total > 50 then self.rejected = self.rejected + 1 return end
        local body = msg:match("^MP" .. SEP .. "[^" .. SEP .. "]*" .. SEP .. "[^" .. SEP .. "]*" .. SEP .. "[^" .. SEP .. "]*" .. SEP .. "(.*)$") or ""
        local k = senderKey .. ":" .. id
        self.partial[k] = self.partial[k] or { total = total, chunks = {}, at = U.Clock() }
        self.partial[k].chunks[n] = body
        local p = self.partial[k]
        for i = 1, p.total do if not p.chunks[i] then return end end
        self.partial[k] = nil
        return self:OnAddonMessage(_, prefix, table.concat(p.chunks), channel, sender)
    end
    self:Handle(parts, senderKey, channel)
end

function Sync:Handle(parts, senderKey, channel)
    local kind = parts[1]
    local need = ALLOWED[kind]
    if not need then
        self.rejected = self.rejected + 1   -- 알 수 없는/수정 요청 메시지 거부
        return
    end
    local role = BRL.Perm:SenderRole(senderKey)
    if need == "leader" and role ~= BRL.Perm.LEADER then self.rejected = self.rejected + 1 return end
    if need == "officer" and role ~= BRL.Perm.LEADER and role ~= BRL.Perm.ASSISTANT then self.rejected = self.rejected + 1 return end
    if (need == "leader" or need == "officer") and not BRL.acct.sync.acceptFromLeader then return end
    local R = self.received
    if kind == "VQ" then
        self:Send("VR", encode("VR", BRL.VERSION), "WHISPER", senderKey)
    elseif kind == "VR" then
        self.versions[senderKey] = parts[2]
    elseif kind == "NT" then
        table.insert(R.notices, 1, { from = senderKey, text = parts[2], at = U.Now() })
        while #R.notices > 20 do table.remove(R.notices) end
        BRL:Print("|cffffd100[공격대 공지]|r %s", parts[2] or "")
    elseif kind == "NO" then
        R.notes[parts[2] or "shared"] = { text = parts[3], from = senderKey, at = U.Now() }
    elseif kind == "RL" then
        R.roles = { role = parts[2], group = tonumber(parts[3]), duties = parts[4], from = senderKey, at = U.Now() }
    elseif kind == "AU" then
        R.auction = { item = parts[2], status = parts[3], high = tonumber(parts[4]) or 0, bidder = parts[5],
            remaining = tonumber(parts[6]) or 0, nextMin = tonumber(parts[7]) or 0, at = U.Now(), clock = U.Clock() }
    elseif kind == "AW" then
        table.insert(R.awards, 1, { item = parts[2], winner = parts[3], amount = tonumber(parts[4]) or 0, at = U.Now() })
        while #R.awards > 50 do table.remove(R.awards) end
    elseif kind == "PY" then
        R.payout = { amount = tonumber(parts[2]) or 0, paid = tonumber(parts[3]) or 0, status = parts[4], from = senderKey, at = U.Now() }
        BRL.char.lastPayout = R.payout
        BRL:Print("|cffffd100[분배 안내]|r 분배 예정액 %s / 지급 %s (%s)", Money.Format(R.payout.amount), Money.Format(R.payout.paid), BRL.Label("PAY_", R.payout.status))
    elseif kind == "RD" then
        if BRL.Perm:GetRole() == BRL.Perm.LEADER or BRL.Perm:GetRole() == BRL.Perm.ASSISTANT then
            BRL.Readiness:StoreReport(senderKey, { durability = tonumber(parts[2]) })
        end
    end
    BRL.Events:Fire(BRL.Events.MSG.SYNC_RECEIVED, kind, senderKey)
end
