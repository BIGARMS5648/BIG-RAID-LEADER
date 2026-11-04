-- BIG RAID LEADER - 공격대 지휘 / 전술 메모
-- * SetRaidTarget 은 12.x 부터 보호 함수 → 징표 지정은 보안 버튼(SecureActionButton)으로만 수행 (UI 모듈)
-- * 풀링 카운트다운: C_PartyInfo.DoCountdown (전투 중 호출 불가) → 미지원 시 채팅 카운트다운 대체
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Cmd = BRL:NewModule("Command")

Cmd.MARKER_ORDER = { 8, 7, 1, 2, 3, 4, 5, 6 } -- 해골, 엑스, 별, 동그라미, 다이아, 세모, 달, 네모

Cmd.pullTimers = {}

local function ops() return BRL.db.raidOps end
local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "command") end

local function announce(text)
    local ch = (API.IsLeader() or API.IsAssistant()) and API.IsInRaid() and "RAID_WARNING" or nil
    return BRL.ChatOut:Send(text, ch)
end
Cmd.Announce = announce

function Cmd:ReadyCheck()
    return BRL.Readiness:Start()
end

function Cmd:Pull(seconds)
    if not BRL.Perm:Require("raid.command") then return false end
    if not API.GuardCombat() then return false end
    seconds = math.max(3, math.min(60, math.floor(tonumber(seconds) or 10)))
    self:CancelPullTimers()
    if API.DoCountdown(seconds) then
        self.pullMode = "official"
        return true
    end
    -- 대체: 채팅 카운트다운
    self.pullMode = "chat"
    announce(string.format("풀링 %d초 전", seconds))
    local id = {}
    self.pullTimers = id
    for _, s in ipairs({ 5, 4, 3, 2, 1 }) do
        if s < seconds then
            API.After(seconds - s, function() if self.pullTimers == id then BRL.ChatOut:Send(tostring(s), "RAID") end end)
        end
    end
    API.After(seconds, function() if self.pullTimers == id then announce("풀링!") self.pullTimers = {} end end)
    return true
end

function Cmd:CancelPullTimers()
    self.pullTimers = {}
end

function Cmd:CancelPull()
    if not BRL.Perm:Require("raid.command") then return false end
    self:CancelPullTimers()
    if self.pullMode == "official" then API.DoCountdown(0) end
    announce("풀링 취소!")
    return true
end

function Cmd:Stop() if BRL.Perm:Require("raid.command") then announce("공격 중지! 공격 중지!") end end
function Cmd:Retreat() if BRL.Perm:Require("raid.command") then announce("후퇴! 입구 쪽으로 이동!") end end
function Cmd:Regroup() if BRL.Perm:Require("raid.command") then announce("전투 재정비 - 집결 후 버프/마나 회복") end end

function Cmd:BreakStart(minutes)
    if not BRL.Perm:Require("raid.command") then return false end
    minutes = math.max(1, math.min(60, math.floor(tonumber(minutes) or 5)))
    self.breakUntil = U.Clock() + minutes * 60
    local id = {}
    self.breakId = id
    announce(string.format("휴식 시작: %d분 (%s 복귀)", minutes, date("%H:%M", U.Now() + minutes * 60)))
    if minutes > 1 then
        API.After((minutes - 1) * 60, function() if self.breakId == id then announce("휴식 종료 1분 전") end end)
    end
    API.After(minutes * 60, function() if self.breakId == id then announce("휴식 종료 - 자리로 복귀") self.breakId = nil self.breakUntil = nil end end)
    changed()
    return true
end

function Cmd:BreakEnd()
    if not BRL.Perm:Require("raid.command") then return false end
    self.breakId = nil
    self.breakUntil = nil
    announce("휴식 종료 - 자리로 복귀")
    changed()
    return true
end

function Cmd:BreakRemaining()
    if not self.breakUntil then return nil end
    return math.max(0, self.breakUntil - U.Clock())
end

function Cmd:BossBriefing(bossKey)
    if not BRL.Perm:Require("raid.command") then return false end
    BRL.ChatOut:SendLines(BRL.BossPlans:BriefingLines(bossKey))
    return true
end

-- channel: RAID | RAID_WARNING | PARTY | GUILD ... (공개 채널은 UI 클릭에서 SendNow)
function Cmd:Custom(text, channel)
    if not BRL.Perm:Require("raid.command") then return false end
    text = U.Trim(text or "")
    if text == "" then return false end
    if channel == "RAID_WARNING" then return announce(text) end
    return BRL.ChatOut:Send(text, channel)
end

---------------------------------------------------------------------------
-- 저장된 명령
---------------------------------------------------------------------------
function Cmd:SavedCommands() return ops().savedCommands end

function Cmd:SaveCommand(name, text, channel)
    if not BRL.Perm:Require("raid.command") then return false end
    name, text = U.Trim(name or ""), U.Trim(text or "")
    if name == "" or text == "" then return false end
    for _, c in ipairs(ops().savedCommands) do
        if c.name == name then c.text, c.channel = text, channel changed() return true end
    end
    table.insert(ops().savedCommands, { name = name, text = text, channel = channel or "RAID" })
    changed()
    return true
end

function Cmd:DeleteCommand(index)
    if not BRL.Perm:Require("raid.command") then return false end
    table.remove(ops().savedCommands, index)
    changed()
    return true
end

function Cmd:RunCommand(index)
    local c = ops().savedCommands[index]
    if not c then return false end
    return self:Custom(c.text, c.channel)
end

---------------------------------------------------------------------------
-- 징표 이름 (징표 바)
---------------------------------------------------------------------------
function Cmd:MarkerName(i) return BRL.L["MARKER_" .. i] end

---------------------------------------------------------------------------
-- 전술 메모
---------------------------------------------------------------------------
Cmd.NOTE_CATEGORIES = {
    { key = "shared", name = "공격대 공유 메모" },
    { key = "tank", name = "탱커 지시사항" },
    { key = "healer", name = "힐러 지시사항" },
    { key = "dps", name = "딜러 지시사항" },
    { key = "phase", name = "단계별 공략 메모" },
}

Cmd.NOTE_TEMPLATES = {
    { name = "기본 브리핑", text = "★ 핵심: \n탱커: \n힐러: \n딜러: \n주의: " },
    { name = "단계별", text = "1단계: \n2단계: \n3단계: \n전멸 시: " },
    { name = "징표/차단", text = "{rt8} 해골 먼저 처치\n{rt7} 엑스 두 번째\n차단: \n군중제어: " },
}

function Cmd:GetNote(planKey, category)
    if category == "private" then return BRL.char.privateNotes or "" end
    local notes = ops().notes
    planKey = planKey or "default"
    return notes[planKey] and notes[planKey][category] or ""
end

function Cmd:SetNote(planKey, category, text)
    if category == "private" then
        BRL.char.privateNotes = text
        return true
    end
    if not BRL.Perm:Require("raid.plan") then return false end
    local notes = ops().notes
    planKey = planKey or "default"
    notes[planKey] = notes[planKey] or {}
    notes[planKey][category] = text
    changed()
    return true
end

-- "★" 또는 "!" 로 시작하는 줄은 강조 표시
function Cmd:FormatNote(text)
    local out = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        if line:match("^%s*[★!]") then line = "|cffff5555" .. line .. "|r" end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

function Cmd:NoteLines(planKey, category)
    local text = self:GetNote(planKey, category)
    local label = category
    for _, c in ipairs(self.NOTE_CATEGORIES) do if c.key == category then label = c.name end end
    local lines = { "[" .. label .. "]" }
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if U.Trim(line) ~= "" then lines[#lines + 1] = line end
    end
    return lines
end
