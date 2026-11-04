-- BIG RAID LEADER - 공유 문자열 (내보내기/가져오기)
-- 공략(보스 계획·배치도·타임라인), 파티 편성, 전술표(임무·순서표)를
-- 체크섬이 붙은 문자열로 주고받는다. 다른 공대장/다른 캐릭터와 계획을 나눌 때 사용한다.
-- 가져오기는 미리보기 → 확인 후 적용이며, 적용 전 자동 백업한다. 금융 데이터는 공유 대상이 아니다.
local _, BRL = ...
local U = BRL.Util

local Share = BRL:NewModule("Share")

local function ops() return BRL.db.raidOps end

-- kind → { name, export(key) → data, describe(data), apply(data, key) }
Share.KINDS = {
    boss = {
        name = "공략",
        export = function(key)
            local p = BRL.BossPlans:Get(key)
            if not p then return nil, "보스 정보 없음" end
            local data = U.DeepCopy(p)
            data.encounterId, data.edited = nil, nil
            return data, p.name
        end,
        describe = function(d)
            return string.format("%s (기술 %d · 단계 %d · 타임라인 %d · 배치도 %d)", tostring(d.name), #(d.abilities or {}), #(d.phases or {}),
                #(d.timeline or {}), U.Count(d.layouts or {}))
        end,
        apply = function(d, key)
            key = key or d.key
            if not key then return false, "보스 키 없음" end
            if not BRL.Data.Bosses[key] and not (BRL.db.bossPlans[key]) then
                -- 다른 사람의 사용자 보스 → 새 사용자 보스로 추가
                key = "CUSTOM_" .. BRL.NewId("B")
                d.custom = true
            end
            local stored = U.DeepCopy(d)
            stored.key = nil
            BRL.db.bossPlans[key] = stored
            BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "boss", key)
            return true, key
        end,
    },
    groups = {
        name = "파티 편성",
        export = function(name)
            if name then
                local t = ops().groupTemplates[name]
                if not t then return nil, "편성 템플릿 없음" end
                return { name = name, plan = U.DeepCopy(t.plan) }, name
            end
            return { name = "현재 편성 계획", plan = U.DeepCopy(BRL.Groups:GetPlan()) }, "현재 편성 계획"
        end,
        describe = function(d)
            local n = 0
            for _, g in pairs(d.plan and d.plan.groups or {}) do n = n + #g end
            return string.format("%s (%d명 배치)", tostring(d.name), n)
        end,
        apply = function(d)
            local name = d.name or "가져온 편성"
            if name == "현재 편성 계획" then name = "가져온 편성 " .. U.FormatDate(U.Now()) end
            ops().groupTemplates[name] = { plan = U.DeepCopy(d.plan), at = U.Now(), imported = true }
            BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "groups")
            return true, name
        end,
    },
    roles = {
        name = "전술표",
        export = function(planKey)
            planKey = planKey or "default"
            return { planKey = planKey, assignments = U.DeepCopy(ops().assignments[planKey] or {}), orders = U.DeepCopy(ops().orders[planKey] or {}) }, planKey
        end,
        describe = function(d)
            local n = 0
            for _, list in pairs(d.assignments or {}) do n = n + #list end
            return string.format("전술표 %s (임무 배정 %d건 · 순서표 %d개)", tostring(d.planKey), n, U.Count(d.orders or {}))
        end,
        apply = function(d, planKey)
            planKey = planKey or d.planKey or "default"
            ops().assignments[planKey] = U.DeepCopy(d.assignments or {})
            ops().orders[planKey] = U.DeepCopy(d.orders or {})
            BRL.Events:Fire(BRL.Events.MSG.DATA_CHANGED, "roles")
            return true, planKey
        end,
    },
}

function Share:Export(kind, key)
    local k = self.KINDS[kind]
    if not k then return nil, "알 수 없는 공유 종류" end
    local data, label = k.export(key)
    if not data then return nil, label end
    return BRL.Serializer.Export("share_" .. kind, { kind = kind, key = key, label = label, data = data }), label
end

-- 미리보기: 반환 obj{kind, key, data, label}, 설명
function Share:Preview(text)
    local obj, err = BRL.Serializer.Import(text)
    if not obj then return nil, err end
    local kind = type(obj.kind) == "string" and obj.kind:match("^share_(%w+)$")
    local k = kind and self.KINDS[kind]
    if not k or type(obj.data) ~= "table" or type(obj.data.data) ~= "table" then
        return nil, "공유 문자열이 아닙니다 (" .. tostring(obj.kind) .. ")"
    end
    local payload = obj.data
    payload.kind = kind
    return payload, k.name .. ": " .. k.describe(payload.data) .. " · 만든 버전 v" .. tostring(obj.version)
end

-- 적용. targetKey 를 주면 그 키(전술표/징표/메모/보스)에 덮어쓴다
function Share:Apply(payload, targetKey)
    if not BRL.Perm:Require("raid.plan") then return false, "권한 없음" end
    local k = payload and self.KINDS[payload.kind]
    if not k then return false, "알 수 없는 공유 종류" end
    BRL.Migration:CreateBackup("공유 문자열 가져오기 전 자동 백업")
    local ok, where = k.apply(U.DeepCopy(payload.data), targetKey)
    if ok then BRL.DB:Audit("share.import", "share", tostring(where), { kind = payload.kind }) end
    return ok, where
end
