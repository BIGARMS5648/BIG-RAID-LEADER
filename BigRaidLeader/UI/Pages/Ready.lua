-- BIG RAID LEADER - 전투 준비 화면의 [준비 확인] 탭
-- (준비 상태 화면은 버프 및 야영지 화면과 합쳐 "전투 준비" 메뉴의 첫 탭이 되었다. 화면 등록은 Buffs.lua)
local _, BRL = ...
local T, W = BRL.Theme, BRL.Widgets
local UI = BRL.UI

local Ready = BRL.Readiness

local P = {}
UI.ReadyPanel = P

function P.Build(panel)
    panel.summary = W.Label(panel, "", 12, "gold")
    panel.summary:SetPoint("TOPLEFT", 4, 0)
    local cols = {
        { title = "파티", width = 36, align = "CENTER", render = function(r) return r.member.subgroup end },
        { title = "공대원", width = 120, render = function(r) return BRL.Data.ColorName(r.member.short, r.member.class) end },
        { title = "준비", width = 76, render = function(r)
            if not r.ready then return T.Color("muted", "-") end
            return T.StatusText(r.ready, Ready.STATUS_LABEL[r.ready])
        end },
        { title = "사망", width = 40, align = "CENTER", render = function(r) return r.dead and T.Color("red", "사망") or "" end },
        { title = "입장", width = 50, align = "CENTER", render = function(r) return r.inInstance and T.Color("green", "O") or T.Color("red", "미입장") end },
        { title = "내구도", width = 56, align = "CENTER", render = function(r)
            if not r.durability then return T.Color("muted", "?") end
            return T.Color(r.lowDurability and "red" or "green", r.durability .. "%")
        end },
        { title = "도핑", width = 110, render = function(r)
            local p = BRL.CombatPrep:RowFor(r.key)
            if not p then return T.Color("muted", "미점검") end
            if p.unavailable then return T.Color("muted", BRL.CombatPrep.UNAVAILABLE_LABEL[p.unavailable] or "?") end
            if p.ok then return T.Color("green", "완료") .. (#p.expiring > 0 and T.Color("yellow", " (만료 임박)") or "") end
            local parts = {}
            for _, x in ipairs(p.missing) do parts[#parts + 1] = x end
            if #p.buffsMissing > 0 then parts[#parts + 1] = "버프" .. #p.buffsMissing end
            return T.Color("red", table.concat(parts, ","))
        end },
    }
    panel.list = W.List(panel, {
        columns = cols,
        tooltip = function(r) return r.member.short, { "내구도는 게임 API로 본인 장비만 확인할 수 있습니다" } end,
    })
    panel.list:SetPoint("TOPLEFT", 4, -20)
    panel.list:SetPoint("BOTTOMRIGHT", -4, 70)
    panel.note = W.Paragraph(panel, "· 음식/영약/비약/필수 버프는 [전투 준비(도핑)]으로 점검합니다. 마법부여/저항 장비/시약은 게임 API로 다른 공대원 상태를 볼 수 없어 표시하지 않습니다.", 880, 11)
    panel.note:SetPoint("BOTTOMLEFT", 4, 36)
    T.SetTextColor(panel.note, "muted")


    local _, f = UI.BottomBar(panel)
    f:Add(W.Button(f.parent, "준비 확인 시작", 110, 24, function() Ready:Start() end, { kind = "primary", perm = "raid.command" }))
    f:Add(W.Button(f.parent, "전투 준비(도핑)", 110, 24, function() BRL.CombatPrep:Run() end, { kind = "primary", tooltip = { "버프를 다시 읽어 음식/영약/비약/필수 버프 누락자를 보여줍니다." } }))
    f:Add(W.Button(f.parent, "풀링 판정", 80, 24, function() BRL.UIActions.ShowPullCheck() end))
    f:Add(W.Button(f.parent, "결과 채팅 출력", 110, 24, function() BRL.UIActions.SendLines(Ready:OutputLines(), "준비 상태 출력") end))
end

function P.Refresh(panel)
    panel.list:SetData(Ready:Rows(), true)
    local s = Ready:Summary()
    if s.checked then
        panel.summary:SetText(string.format("준비 완료 %d · 준비 안 됨 %d · 미응답 %d · 대기 %d · 오프라인 %d · 사망 %d · 미입장 %d · 내구도 낮음 %d%s",
            s.ready, s.notready, s.noresponse, s.waiting, s.offline, s.dead, s.absent, s.lowDurability, s.active and "  (진행 중)" or ""))
    else
        panel.summary:SetText(string.format("준비 확인 미실시 · 오프라인 %d · 사망 %d · 미입장 %d", s.offline, s.dead, s.absent))
    end
end
