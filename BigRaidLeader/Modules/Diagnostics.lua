-- BIG RAID LEADER - 자가 진단
-- 문제 보고용: 환경/API 지원/이벤트/거래 추적/저장 데이터 무결성/정산 검증/오류 기록을 한 번에 점검한다.
-- 점검만 하며 데이터를 고치지 않는다.
local _, BRL = ...
local U, API, Money = BRL.Util, BRL.API, BRL.Money

local Diag = BRL:NewModule("Diagnostics")

-- 거래 기록에 꼭 필요한 API (없으면 자동 기록이 불가능하거나 검증이 약해짐)
Diag.CRITICAL = {
    "GetMoney", "GetPlayerTradeMoney", "GetTargetTradeMoney", "GetTradePlayerItemInfo", "GetTradeTargetItemInfo",
}
Diag.IMPORTANT = {
    "GetTradePlayerItemLink", "GetTradeTargetItemLink", "GetRaidRosterInfo", "UnitIsGroupLeader",
    "C_Timer.After", "C_Timer.NewTicker",
}

local LEVEL_MARK = { ok = "[정상]", info = "[정보]", warn = "[주의]", error = "[오류]" }

local function section(report, title)
    local s = { title = title, items = {} }
    report.sections[#report.sections + 1] = s
    return function(level, text)
        s.items[#s.items + 1] = { level = level, text = text }
        if level == "warn" then report.warnings = report.warnings + 1 end
        if level == "error" then report.errors = report.errors + 1 end
    end
end

function Diag:Run()
    local report = { at = U.Now(), sections = {}, warnings = 0, errors = 0 }
    local db = BRL.db or {}

    -- 1. 환경
    local add = section(report, "환경")
    add("info", "애드온 v" .. tostring(BRL.VERSION) .. " / 클라이언트 " .. API.GetBuildText())
    local iface = API.GetInterfaceVersion()
    add(iface and iface >= 16000 and iface < 17000 and "ok" or "warn", "인터페이스 " .. tostring(iface) .. " (WoW: Forever 16001 기준 개발)")
    add("info", "캐릭터 " .. tostring(BRL.playerKey))
    local role = BRL.Perm:GetRole()
    if BRL.Perm:IsOperator(role) then
        add("ok", "권한: " .. (role == "leader" and "공격대장" or "그룹 밖 (준비/정산 가능)"))
    elseif role == "unknown" then
        add("warn", "권한 정보를 읽을 수 없음 (보안 값) - 편집이 잠깁니다")
    else
        add("warn", "공대장이 아님 (" .. BRL.Perm:RoleLabel(role) .. ") - 공대장 전용 애드온이므로 운영 기능이 잠깁니다")
    end
    add("info", string.format("그룹 %s · 인원 %d · 전투 %s · 채팅 잠금 %s", API.IsInRaid() and "공격대" or (API.IsInGroup() and "파티" or "없음"),
        API.GetNumGroupMembers() or 0, API.InCombat() and "예" or "아니오", API.InChatLockdown() and "예" or "아니오"))

    -- 2. API 지원
    add = section(report, "API 지원")
    local missing, critical = {}, {}
    for _, r in ipairs(API.RunCompatibilityCheck()) do
        if not r.ok and not r.value then missing[#missing + 1] = r.name end
    end
    for _, path in ipairs(self.CRITICAL) do
        if not API.Has(path) then critical[#critical + 1] = path end
    end
    if #critical > 0 then add("error", "거래 기록 필수 API 미지원: " .. table.concat(critical, ", ") .. " → 수동 기록만 가능") end
    for _, path in ipairs(self.IMPORTANT) do
        if not API.Has(path) then add("warn", "주요 API 미지원: " .. path) end
    end
    if type(_G.ERR_TRADE_COMPLETE) ~= "string" then add("warn", "ERR_TRADE_COMPLETE 전역 문자열 없음 → 골드/가방 변화로만 완료 판정") end
    if not API.Has("C_Item.GetItemCount") and not API.Has("GetItemCount") then add("warn", "가방 수량 API 없음 → 아이템 거래 수량 검증 비활성") end
    if #missing == 0 then add("ok", "점검 대상 API 모두 지원") else add("info", "미지원 " .. #missing .. "개: " .. table.concat(missing, ", ")) end

    -- 3. 이벤트
    add = section(report, "이벤트")
    local unsupported = {}
    for event in pairs(BRL.Events.unsupported or {}) do unsupported[#unsupported + 1] = event end
    table.sort(unsupported)
    if #unsupported == 0 then add("ok", "등록한 이벤트 모두 지원") else
        local tradeMissing = false
        for _, e in ipairs(unsupported) do if e:find("^TRADE_") or e == "PLAYER_MONEY" then tradeMissing = true end end
        add(tradeMissing and "error" or "warn", "미지원 이벤트: " .. table.concat(unsupported, ", "))
    end

    -- 4. 거래 추적
    add = section(report, "거래 자동 기록")
    add(BRL.acct.trade.autoRecord and "ok" or "warn", "자동 기록 " .. (BRL.acct.trade.autoRecord and "켜짐" or "꺼짐 (설정 > 일반/거래)"))
    local cur = BRL.TradeTracker:GetCurrent()
    if cur then add("info", "진행 중 거래: " .. tostring(cur.partnerKey or "?")) end
    if db.activeTrade and not cur then add("warn", "저장된 미완료 거래가 남아 있음 (다음 접속 시 확인 불가로 정리됨)") end
    local unverified = #BRL.TradeJournal:Query({ group = "unverified" })
    if unverified > 0 then add("warn", "확인 불가 거래 " .. unverified .. "건 - 거래 로그에서 수동 확인/취소 표시 필요") else add("ok", "확인 불가 거래 없음") end
    local traces = BRL.TradeTracker:RecentTraces()
    if traces[1] then
        local t = traces[1]
        add("info", string.format("마지막 거래 판정: %s %s → %s (%s)", U.FormatDateTime(t.at), tostring(t.partnerKey or "?"),
            BRL.Label("TRADE_", t.status), BRL.TradeJournal:VerificationLabel(t.verification)))
    end

    -- 5. 저장 데이터
    add = section(report, "저장 데이터")
    if BRL.readOnlyData then add("error", "저장 데이터가 읽기 전용 상태 (스키마가 더 최신이거나 마이그레이션 실패)") end
    local schema = db.schemaVersion or 0
    add(schema == BRL.DB.SCHEMA_VERSION and "ok" or "warn", "스키마 v" .. schema .. " (현재 v" .. BRL.DB.SCHEMA_VERSION .. ")")
    local counts = {}
    for _, name in ipairs({ "sessions", "trades", "auctions", "awards", "ledger", "settlements", "payouts" }) do
        counts[#counts + 1] = name .. " " .. U.Count(db[name] or {})
    end
    add("info", "레코드: " .. table.concat(counts, ", "))
    local issues = BRL.Migration:Validate()
    local errs, warns = 0, 0
    for _, i in ipairs(issues) do
        if i.severity == "error" then errs = errs + 1 else warns = warns + 1 end
    end
    if errs + warns == 0 then add("ok", "무결성 검사 문제 없음") else
        add(errs > 0 and "error" or "warn", string.format("무결성 검사: 오류 %d건 / 주의 %d건", errs, warns))
        for i = 1, math.min(5, #issues) do add("info", "  - " .. issues[i].message .. " " .. tostring(issues[i].entity or "")) end
    end
    local last = db.backups and db.backups[1]
    if not last then add("warn", "백업 없음 (설정 > 데이터 관리 > 지금 백업)")
    elseif U.Now() - (last.at or 0) > 3 * 86400 then add("warn", "마지막 백업이 3일 이상 지남: " .. U.FormatDateTime(last.at))
    else add("ok", "마지막 백업 " .. U.FormatDateTime(last.at) .. " (" .. #db.backups .. "개 보관)") end

    -- 6. 현재 세션 / 정산
    add = section(report, "현재 세션")
    local session = BRL.Session:GetActive()
    if not session then
        add("info", "활성 세션 없음")
    else
        local sum = BRL.Ledger:Summary(session.id)
        add("info", string.format("%s · 경매 %s · 수금 %s · 장부 잔액 %s", session.name or session.id, Money.Format(sum.totalAwarded),
            Money.Format(sum.collected), Money.Format(sum.balance)))
        local active = BRL.Auctions:GetActive()
        if active and active.sessionId == session.id and not BRL.Auctions.ticker then
            add("warn", "진행 중 경매가 있지만 타이머가 멈춰 있음 (경매 화면에서 낙찰/유찰/취소)")
        end
        local st = BRL.Settlement:ForSession(session.id)
        if st and st.status ~= "draft" then
            local checks = BRL.Settlement:Validate(st.id)
            for _, c in ipairs(checks) do
                if c.label == "최종 잔액 확인" or c.label == "총수입 확인" then
                    add(c.ok and "ok" or "error", c.label .. ": " .. tostring(c.detail))
                end
            end
        end
    end

    -- 7. 오류 기록
    add = section(report, "오류 기록")
    local log = db.errorLog or {}
    if #log == 0 then add("ok", "기록된 Lua 오류 없음") else
        add("warn", "Lua 오류 " .. #log .. "건 (최근 3건)")
        for i = #log, math.max(1, #log - 2), -1 do
            local e = log[i]
            add("info", "  " .. U.FormatDateTime(e.at) .. " " .. tostring(e.context) .. ": " .. tostring(e.message):gsub("\n.*", ""))
        end
    end
    local q = #(BRL.ChatOut.queue or {})
    if q > 5 then add("warn", "채팅 출력 대기열 " .. q .. "줄 (채팅 잠금/전송 제한)") end
    return report
end

function Diag:Lines(report)
    report = report or self:Run()
    local lines = {
        "==== BIG RAID LEADER 자가 진단 ====",
        "일시: " .. U.FormatDateTime(report.at) .. " / 오류 " .. report.errors .. "건 · 주의 " .. report.warnings .. "건",
    }
    for _, s in ipairs(report.sections) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[" .. s.title .. "]"
        for _, it in ipairs(s.items) do lines[#lines + 1] = (LEVEL_MARK[it.level] or "") .. " " .. it.text end
    end
    return lines
end

function Diag:Text(report)
    return U.StripColors(table.concat(self:Lines(report), "\n"))
end

-- 채팅창 요약 + 복사 창
function Diag:Show()
    local report = self:Run()
    BRL:Print("자가 진단: 오류 %d건, 주의 %d건", report.errors, report.warnings)
    if BRL.Dialogs and BRL.Dialogs.CopyText then
        BRL.Dialogs.CopyText("자가 진단 결과", self:Text(report), { hint = "문제 보고 시 이 내용을 함께 전달하세요. 개인 정보(캐릭터 이름)가 포함됩니다." })
    end
    return report
end
