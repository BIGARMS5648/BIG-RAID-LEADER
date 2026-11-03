-- BIG RAID LEADER - 권한 관리
-- 권한은 게임이 실제로 부여한 공격대장/부공대장 여부(공식 API)만으로 결정한다.
-- 별도 관리자 직책을 만들지 않으며, 금융 장부의 최종 책임자는 공대장 한 명이다.
local _, BRL = ...
local L = BRL.L
local API = BRL.API

local Perm = {}
BRL.Perm = Perm

Perm.LEADER = "leader"
Perm.ASSISTANT = "assistant"
Perm.MEMBER = "member"
Perm.SOLO = "solo"          -- 그룹이 아님: 본인 데이터 관리(사전 준비/해산 후 정산)
Perm.UNKNOWN = "unknown"    -- 권한 정보 확인 불가 → 민감 작업 차단

-- 테스트용 강제 역할
Perm.override = nil

function Perm:GetRole()
    if self.override then return self.override end
    if not API.IsInGroup() then return self.SOLO end
    local leader = API.IsLeader("player")
    if leader == nil then return self.UNKNOWN end
    if leader then return self.LEADER end
    local assistant = API.IsAssistant("player")
    if assistant == nil then return self.UNKNOWN end
    if assistant then return self.ASSISTANT end
    return self.MEMBER
end

function Perm:RoleLabel(role)
    role = role or self:GetRole()
    if role == self.LEADER then return L.ROLE_LEADER end
    if role == self.ASSISTANT then return L.ROLE_ASSISTANT end
    if role == self.MEMBER then return L.ROLE_MEMBER end
    if role == self.SOLO then return L.ROLE_SOLO end
    return L.ROLE_UNKNOWN
end

-- 행동별 허용 역할
--  finance.edit    : 경매 진행/낙찰, 거래-장부 연결, 장부 수정, 정산 계산/확정
--  finance.view    : 로컬 금융 데이터 열람 (각자 자신의 SavedVariables)
--  raid.plan       : 편성/역할/전술/모집/공략 편집
--  raid.command    : 준비 확인, 풀링, 공격대 경보, 징표 (게임이 부공대장에게 허용하는 범위)
--  raid.groups.apply : 실제 파티 이동 (게임상 공대장/부공대장 가능)
--  raid.invite     : 초대 (게임상 공대장/부공대장 가능)
--  trade.own       : 내 거래 기록/개인 거래 분류
local MATRIX = {
    ["finance.edit"]      = { leader = true, solo = true },
    ["finance.view"]      = { leader = true, solo = true, assistant = true, member = true, unknown = true },
    ["raid.plan"]         = { leader = true, solo = true },
    ["raid.command"]      = { leader = true, assistant = true, solo = true },
    ["raid.groups.apply"] = { leader = true, assistant = true },
    ["raid.invite"]       = { leader = true, assistant = true, solo = true },
    ["trade.own"]         = { leader = true, solo = true, assistant = true, member = true, unknown = true },
    ["sync.broadcast"]    = { leader = true, assistant = true },
    ["sync.finance"]      = { leader = true },
    ["data.manage"]       = { leader = true, solo = true, assistant = true, member = true },
}

function Perm:Can(action, role)
    role = role or self:GetRole()
    local row = MATRIX[action]
    if not row then return false end
    return row[role] and true or false
end

-- 금융 수정 권한 + 세션 소유권 확인
-- 그룹 안: 공대장만 가능. 그룹 밖(해산 후 정산): 세션 생성자(소유자)만 가능.
function Perm:CanEditSession(session, role)
    role = role or self:GetRole()
    if BRL.readOnlyData then return false, "저장 데이터가 읽기 전용 상태입니다." end
    if not self:Can("finance.edit", role) then
        if role == self.UNKNOWN then return false, "권한 정보를 확인할 수 없어 수정이 제한됩니다." end
        return false, L.LEADER_ONLY
    end
    if session and session.owner and session.owner ~= BRL.playerKey then
        return false, "다른 캐릭터(" .. tostring(session.owner) .. ")가 만든 공격대 세션입니다."
    end
    if session and session.locked then
        return false, "정산이 잠긴 세션입니다. 잠금 해제 후 수정하세요."
    end
    return true
end

-- 권한 확인 + 사유 출력
function Perm:Require(action, quiet)
    if BRL.readOnlyData and (action == "finance.edit" or action == "raid.plan") then
        if not quiet then BRL:Print("저장 데이터가 읽기 전용 상태입니다.") end
        return false
    end
    if self:Can(action) then return true end
    if not quiet then
        local role = self:GetRole()
        if role == self.UNKNOWN then
            BRL:Print("%s: 권한 정보를 확인할 수 없어 제한되었습니다.", L.NO_PERMISSION)
        elseif action == "finance.edit" or action == "raid.plan" or action == "sync.finance" then
            BRL:Print("%s: %s (현재: %s)", L.NO_PERMISSION, L.LEADER_ONLY, self:RoleLabel(role))
        else
            BRL:Print("%s (현재: %s)", L.NO_PERMISSION, self:RoleLabel(role))
        end
    end
    return false
end

function Perm:RequireSession(session, quiet)
    local ok, reason = self:CanEditSession(session)
    if not ok and not quiet then BRL:Print("%s: %s", L.NO_PERMISSION, reason or "") end
    return ok, reason
end

-- 다른 플레이어가 보낸 동기화 메시지의 발신자 권한
function Perm:SenderRole(senderKey)
    if not senderKey then return self.UNKNOWN end
    for _, m in ipairs(API.GetGroupRoster()) do
        if m.key == senderKey then
            if m.isLeader then return self.LEADER end
            if m.isAssistant then return self.ASSISTANT end
            return self.MEMBER
        end
    end
    return nil -- 그룹 밖
end

-- 역할 변경 감지
function Perm:OnEnable()
    self.lastRole = self:GetRole()
    local function check()
        local r = self:GetRole()
        if r ~= self.lastRole then
            local old = self.lastRole
            self.lastRole = r
            BRL.Events:Fire(BRL.Events.MSG.ROLE_CHANGED, r, old)
        end
    end
    BRL.Events:Register("GROUP_ROSTER_UPDATE", self, check)
    BRL.Events:Register("PARTY_LEADER_CHANGED", self, check)
    BRL.Events:Register("PLAYER_ROLES_ASSIGNED", self, check)
end
