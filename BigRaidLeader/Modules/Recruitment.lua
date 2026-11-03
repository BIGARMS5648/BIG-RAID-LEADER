-- BIG RAID LEADER - 공격대 모집 / 지원자 관리
-- 공개 채널 모집 문구 전송과 초대는 반드시 공대장의 버튼 클릭으로만 수행한다 (자동 채팅/자동 초대 없음).
local _, BRL = ...
local U, API = BRL.Util, BRL.API

local Rec = BRL:NewModule("Recruitment")

local function store() return BRL.db.raidOps.recruitment end
local function changed() BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "recruit") end

Rec.DEFAULT_MESSAGE = "[모집] {raid} {size}인 ({have}/{size}) 구함: {need} / 귓속말 주세요"

function Rec:OnEnable()
    BRL.Events:Register("CHAT_MSG_WHISPER", self, "OnWhisper")
    BRL.Events:On(BRL.Events.MSG.ROSTER_CHANGED, self, function(_, count, prev) self:OnRosterChanged(count, prev) end)
end

function Rec:NewTemplate(raidKey)
    local raid = BRL.Data.Raids[raidKey or "HYJAL_SUMMIT"] or BRL.Data.Raids.HYJAL_SUMMIT
    local size = raid.size
    local roleQuotas
    if size <= 10 then roleQuotas = { TANK = 2, HEALER = 2, MELEE = 3, RANGED = 3 }
    elseif size <= 20 then roleQuotas = { TANK = 2, HEALER = 5, MELEE = 6, RANGED = 7 }
    else roleQuotas = { TANK = 4, HEALER = 10, MELEE = 13, RANGED = 13 } end
    return {
        name = raid.name .. " 모집", raidKey = raid.key, size = size, message = self.DEFAULT_MESSAGE,
        roleQuotas = roleQuotas, classQuotas = {}, channel = "GUILD", note = "",
    }
end

function Rec:GetCurrent()
    local s = store()
    if not s.current then s.current = self:NewTemplate((BRL.Session:GetActive() or {}).raidKey) end
    return s.current
end

function Rec:SetField(field, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    local cur = self:GetCurrent()
    if field == "raidKey" then
        local raid = BRL.Data.Raids[value]
        if raid then cur.raidKey, cur.size = value, raid.size end
    else
        cur[field] = value
    end
    changed()
    return true
end

function Rec:SetQuota(kind, key, value)
    if not BRL.Perm:Require("raid.plan") then return false end
    local cur = self:GetCurrent()
    local t = kind == "class" and cur.classQuotas or cur.roleQuotas
    value = math.max(0, math.floor(tonumber(value) or 0))
    t[key] = value > 0 and value or nil
    changed()
    return true
end

function Rec:SaveTemplate(name)
    if not BRL.Perm:Require("raid.plan") then return false end
    name = U.Trim(name or "")
    if name == "" then return false end
    store().templates[name] = U.DeepCopy(self:GetCurrent())
    store().templates[name].name = name
    return true
end

function Rec:LoadTemplate(name)
    if not BRL.Perm:Require("raid.plan") then return false end
    local t = store().templates[name]
    if not t then return false end
    store().current = U.DeepCopy(t)
    changed()
    return true
end

function Rec:DeleteTemplate(name)
    store().templates[name] = nil
    return true
end

function Rec:Templates() return U.Keys(store().templates) end

-- 모집 진행 상황
function Rec:Progress()
    local cur = self:GetCurrent()
    local counts = BRL.Roster:Counts()
    local solo = BRL.Roster:GetMembers()[1] and BRL.Roster:GetMembers()[1].solo
    local have = solo and 0 or counts.total
    local res = { have = have, size = cur.size, roles = {}, classes = {}, missingRoles = {}, missingClasses = {} }
    for _, role in ipairs(BRL.Data.Roles) do
        local q = cur.roleQuotas[role] or 0
        local h = solo and 0 or (counts[role] or 0)
        res.roles[role] = { quota = q, have = h, need = math.max(0, q - h) }
        if q > h then res.missingRoles[#res.missingRoles + 1] = { role = role, need = q - h } end
    end
    for class, q in pairs(cur.classQuotas) do
        local h = solo and 0 or (counts.byClass[class] or 0)
        res.classes[class] = { quota = q, have = h, need = math.max(0, q - h) }
        if q > h then res.missingClasses[#res.missingClasses + 1] = { class = class, need = q - h } end
    end
    table.sort(res.missingClasses, function(a, b) return a.class < b.class end)
    res.open = math.max(0, cur.size - have)
    return res
end

function Rec:NeedText()
    local p = self:Progress()
    local parts = {}
    for _, r in ipairs(p.missingRoles) do parts[#parts + 1] = BRL.Label("CR_", r.role) .. " " .. r.need end
    for _, c in ipairs(p.missingClasses) do parts[#parts + 1] = BRL.Data.ClassName(c.class) .. " " .. c.need end
    if #parts == 0 and p.open > 0 then parts[1] = "전 직업 " .. p.open end
    if #parts == 0 then return "모집 완료" end
    return table.concat(parts, ", ")
end

function Rec:BuildMessage()
    local cur = self:GetCurrent()
    local p = self:Progress()
    local raid = BRL.Data.Raids[cur.raidKey]
    local msg = cur.message or self.DEFAULT_MESSAGE
    local roles = {}
    for _, role in ipairs(BRL.Data.Roles) do
        local r = p.roles[role]
        if r.quota > 0 then roles[#roles + 1] = BRL.Label("CR_", role) .. " " .. r.have .. "/" .. r.quota end
    end
    local repl = {
        raid = raid and raid.name or "공격대", size = tostring(cur.size), have = tostring(p.have),
        need = self:NeedText(), roles = table.concat(roles, " "), note = cur.note or "",
    }
    msg = msg:gsub("{(%w+)}", function(k) return repl[k] or ("{" .. k .. "}") end)
    return U.SanitizeChat(msg)
end

-- 채널 사양: "GUILD" | "SAY" | "YELL" | "CHANNEL:<번호>"  (반드시 버튼 클릭 핸들러에서 호출)
function Rec:Send(channelSpec)
    if not BRL.Perm:Require("raid.invite") then return false end
    local msg = self:BuildMessage()
    local chatType, target = channelSpec, nil
    local num = channelSpec and channelSpec:match("^CHANNEL:(%d+)$")
    if num then chatType, target = "CHANNEL", tonumber(num) end
    store().active = true
    store().lastSentAt = U.Now()
    changed()
    return BRL.ChatOut:SendNow(msg, chatType or "GUILD", target)
end

function Rec:IsActive() return store().active and true or false end

function Rec:SetActive(active)
    store().active = active and true or false
    changed()
end

-- 모집 종료 공지
function Rec:CloseNotice(channelSpec)
    if not BRL.Perm:Require("raid.invite") then return false end
    store().active = false
    changed()
    local cur = self:GetCurrent()
    local raid = BRL.Data.Raids[cur.raidKey]
    local msg = string.format("[모집 마감] %s %d인 모집이 마감되었습니다. 감사합니다.", raid and raid.name or "공격대", cur.size)
    if channelSpec then
        local num = channelSpec:match("^CHANNEL:(%d+)$")
        if num then return BRL.ChatOut:SendNow(msg, "CHANNEL", tonumber(num)) end
        return BRL.ChatOut:SendNow(msg, channelSpec)
    end
    return true
end

---------------------------------------------------------------------------
-- 지원자 (귓속말)
---------------------------------------------------------------------------
local APPLY_WORDS = { "1", "참", "참여", "신청", "가능", "지원", "inv", "invite", "초대", "자리" }

local function detect(list, msg)
    local lower = msg:lower()
    for key, words in pairs(list) do
        for _, w in ipairs(words) do
            if lower:find(w, 1, true) then return key end
        end
    end
    return nil
end

function Rec:LooksLikeApplication(msg)
    local lower = U.Trim(msg):lower()
    if lower == "" or #lower > 120 then return false end
    for _, w in ipairs(APPLY_WORDS) do
        if lower == w or lower:find(w, 1, true) then return true end
    end
    return detect(BRL.Data.ClassKeywords, lower) ~= nil or detect(BRL.Data.RoleKeywords, lower) ~= nil
end

function Rec:OnWhisper(_, msg, author)
    if not self:IsActive() then return end
    if API.IsSecret(msg) or API.IsSecret(author) then return end
    if type(msg) ~= "string" or not self:LooksLikeApplication(msg) then return end
    -- 경매 입찰 귓속말은 지원으로 보지 않음
    if BRL.Auctions:GetActive() and BRL.Bids:ParseAmount(msg) then return end
    self:AddApplicant(author, msg)
end

function Rec:AddApplicant(name, msg, class, role)
    local key = API.NormalizeName(name)
    if not key then return nil end
    local list = store().applicants
    local a = list[key]
    local detectedClass = class or detect(BRL.Data.ClassKeywords, msg or "")
    local detectedRole = role or detect(BRL.Data.RoleKeywords, msg or "")
    if a then
        a.count = (a.count or 1) + 1
        a.msg = msg or a.msg
        a.at = U.Now()
        a.duplicate = true
        a.class = a.class or detectedClass
        a.role = a.role or detectedRole
    else
        a = { key = key, name = API.ShortName(key), msg = msg, class = detectedClass, role = detectedRole,
            at = U.Now(), status = "pending", count = 1 }
        list[key] = a
    end
    a.inGroup = BRL.Roster:IsMember(key)
    changed()
    return a
end

function Rec:Applicants(statusFilter)
    local out = {}
    for _, a in pairs(store().applicants) do
        if not statusFilter or a.status == statusFilter then out[#out + 1] = a end
    end
    table.sort(out, function(x, y) return (x.at or 0) < (y.at or 0) end)
    return out
end

function Rec:Approve(key, whisper)
    if not BRL.Perm:Require("raid.invite") then return false end
    local a = store().applicants[key]
    if not a then return false end
    if BRL.Roster:IsMember(key) then a.status = "approved" a.inGroup = true changed() return true end
    if API.IsInGroup() and not API.IsInRaid() and API.GetNumGroupMembers() >= 5 then API.ConvertToRaid() end
    API.InviteUnit(key)
    a.status = "approved"
    a.decidedAt = U.Now()
    if whisper then BRL.ChatOut:Send("[BRL] 초대를 보냈습니다. 수락해 주세요.", "WHISPER", key) end
    changed()
    return true
end

function Rec:Reject(key, whisper)
    if not BRL.Perm:Require("raid.invite") then return false end
    local a = store().applicants[key]
    if not a then return false end
    a.status = "rejected"
    a.decidedAt = U.Now()
    if whisper then BRL.ChatOut:Send("[BRL] 지원 감사합니다. 이번 공격대는 자리가 없습니다.", "WHISPER", key) end
    changed()
    return true
end

function Rec:Hold(key)
    if not BRL.Perm:Require("raid.invite") then return false end
    local a = store().applicants[key]
    if not a then return false end
    a.status = "hold"
    changed()
    return true
end

function Rec:Remove(key)
    store().applicants[key] = nil
    changed()
end

function Rec:ClearApplicants()
    store().applicants = {}
    changed()
end

-- 인원 이탈 시 재모집 안내
function Rec:OnRosterChanged(count, prev)
    if not prev or prev == 0 or not count then return end
    if count < prev and API.IsInRaid() and BRL.Perm:GetRole() == BRL.Perm.LEADER then
        local cur = self:GetCurrent()
        if count < (cur.size or 0) then
            self.refillSuggested = true
            BRL:Print("공대원 이탈 감지 (%d/%d). 공격대 모집 화면에서 재모집할 수 있습니다.", count, cur.size)
            changed()
        end
    end
end
