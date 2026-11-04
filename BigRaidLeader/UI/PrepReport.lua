-- BIG RAID LEADER - 전투 준비 결과 창 (메인 창 없이도 표시)
local _, BRL = ...
local T, W = BRL.Theme, BRL.Widgets

local PR = {}
BRL.PrepReport = PR

local function check(v) return v and T.Color("green", "O") or T.Color("red", "X") end

function PR:Create()
    if self.frame then return self.frame end
    local f = W.Panel(UIParent, T.colors.bg, T.colors.border)
    _G.BigRaidLeaderPrepReport = f
    table.insert(UISpecialFrames, "BigRaidLeaderPrepReport")
    f:SetSize(600, 460)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    f.title = W.Label(f, "전투 준비 - 도핑 점검", 15, "goldBright")
    f.title:SetPoint("TOPLEFT", 14, -12)
    local close = W.Button(f, "X", 22, 20, function() f:Hide() end, { kind = "subtle" })
    close:SetPoint("TOPRIGHT", -8, -8)
    f.summary = W.Paragraph(f, "", 570, 12)
    f.summary:SetPoint("TOPLEFT", 14, -38)
    f.onlyMissing = W.CheckBox(f, "누락/확인 불가만 보기", function() PR:Render() end)
    f.onlyMissing:SetPoint("TOPRIGHT", -170, -14)
    f.onlyMissing:SetChecked(true)
    f.list = W.List(f, {
        columns = {
            { title = "파티", width = 34, align = "CENTER", render = function(r) return r.member.subgroup or "-" end },
            { title = "공대원", width = 110, render = function(r) return BRL.Data.ColorName(r.member.short, r.member.class) end },
            { title = "음식", width = 44, align = "CENTER", render = function(r) if r.unavailable then return "" end return check(r.food) end },
            { title = "영약", width = 44, align = "CENTER", render = function(r) if r.unavailable then return "" end return check(r.flask) end },
            { title = "비약", width = 44, align = "CENTER", render = function(r)
                if r.unavailable then return "" end
                return r.elixirCount > 0 and T.Color("green", tostring(r.elixirCount)) or T.Color("muted", "0")
            end },
            { title = "상태", width = 0, render = function(r)
                if r.unavailable then return T.Color("muted", BRL.CombatPrep.UNAVAILABLE_LABEL[r.unavailable] or r.unavailable) end
                local parts = {}
                for _, x in ipairs(r.missing) do parts[#parts + 1] = T.Color("red", x) end
                for _, b in ipairs(r.buffsMissing) do parts[#parts + 1] = T.Color("yellow", b.name) end
                for _, e in ipairs(r.expiring) do parts[#parts + 1] = T.Color("yellow", e) end
                return #parts > 0 and table.concat(parts, " ") or T.Color("green", "도핑 완료")
            end },
        },
        tooltip = function(r)
            local lines = {}
            if r.food then lines[#lines + 1] = "음식: " .. table.concat(r.food.names or {}, ", ") end
            if r.flask then lines[#lines + 1] = "영약: " .. table.concat(r.flask.names or {}, ", ") end
            if r.elixir then lines[#lines + 1] = "비약: " .. table.concat(r.elixir.names or {}, ", ") end
            return r.member.short, lines
        end,
    })
    f.list:SetPoint("TOPLEFT", 14, -112)
    f.list:SetPoint("BOTTOMRIGHT", -14, 48)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOMLEFT", 14, 12)
    bar:SetSize(570, 26)
    local fl = W.Flow(bar, 0, 1, 6)
    fl:Add(W.Button(bar, "다시 점검", 80, 24, function() BRL.CombatPrep:Run() end, { kind = "primary" }))
    fl:Add(W.Button(bar, "공격대에 알리기", 110, 24, function()
        BRL.ChatOut:SendLines(BRL.CombatPrep:Lines())
    end, { perm = "raid.command" }))
    fl:Add(W.Button(bar, "누락자 귓속말", 100, 24, function()
        local n = BRL.CombatPrep:WhisperMissing()
        BRL:Print("도핑이 필요한 %d명에게 귓속말을 보냈습니다.", n)
    end, { perm = "raid.command" }))
    fl:Add(W.Button(bar, "준비 확인", 80, 24, function() BRL.Readiness:Start() end, { perm = "raid.command" }))
    fl:Add(W.Button(bar, "복사", 50, 24, function()
        local lines = BRL.CombatPrep:Lines()
        if PR.res and PR.res.wipe then lines = BRL.CombatPrep:WipeLines(PR.res) end
        BRL.Dialogs.CopyText("전투 준비 결과", table.concat(lines, "\n"))
    end))
    f.wipeBtn = fl:Add(W.Button(bar, "복구 순서 공지", 100, 24, function()
        if PR.res and PR.res.wipe then BRL.ChatOut:SendLines(BRL.CombatPrep:WipeLines(PR.res)) end
    end, { perm = "raid.command" }))
    self.frame = f
    return f
end

function PR:Render()
    local f = self.frame
    local res = self.res
    if not f or not res then return end
    local rows = {}
    for _, r in ipairs(res.rows) do
        if not f.onlyMissing:GetChecked() or not r.ok or r.unavailable or #r.expiring > 0 then rows[#rows + 1] = r end
    end
    f.list:SetData(rows, true)
    local lines = {}
    local w = res.wipe
    f.title:SetText(w and "전멸 복구 - 정비 점검" or "전투 준비 - 도핑 점검")
    if f.wipeBtn then if w then f.wipeBtn:Show() else f.wipeBtn:Hide() end end
    if w then
        local function names(ms, color)
            local out = {}
            for _, m in ipairs(ms) do out[#out + 1] = BRL.Data.ColorName(m.short, m.class) end
            return #out > 0 and table.concat(out, ", ") or T.Color(color or "muted", "없음")
        end
        lines[#lines + 1] = T.Color("red", "사망 " .. #w.dead .. "명: ") .. names(w.dead, "green")
        lines[#lines + 1] = T.Color("blue", "영혼석: ") .. names(w.soulstones) .. (#w.deadWithStone > 0 and T.Color("green", " (사망자 중 자가 부활 " .. #w.deadWithStone .. "명)") or "")
        local rb = {}
        for _, e in ipairs(w.rebuff) do rb[#rb + 1] = e.buff.name .. " " .. e.count .. "명" .. (e.provider and (" → " .. BRL.API.ShortName(e.provider)) or "") end
        lines[#lines + 1] = T.Color("yellow", "재버프: ") .. (#rb > 0 and table.concat(rb, ", ") or T.Color("green", "필요 없음"))
    else
        local pc = BRL.CombatPrep:PullCheck()
        lines[#lines + 1] = "풀링 판정: " .. T.Color(pc.color, pc.label) .. (pc.reasons[1] and T.Color("muted", "  " .. table.concat(pc.reasons, " · ")) or "")
    end
    lines[#lines + 1] = string.format("도핑 완료 %s / 점검 %d명  ·  음식 없음 %s  ·  %s 없음 %s  ·  곧 만료 %d  ·  확인 불가 %d",
            T.Color("green", tostring(res.okCount)), res.checked,
            T.Color(#res.noFood > 0 and "red" or "green", tostring(#res.noFood)), BRL.CombatPrep:MainLabel(),
            T.Color(#res.noMain > 0 and "red" or "green", tostring(#res.noMain)), #res.expiring, #res.unavailable)
    local bm = {}
    for _, b in ipairs(BRL.Data.ClassBuffs) do
        local m = res.buffMissing[b.key]
        if m then bm[#bm + 1] = b.name .. " " .. #m.rows .. "명" end
    end
    if #bm > 0 then lines[#lines + 1] = T.Color("yellow", "필수 버프 누락: " .. table.concat(bm, ", ")) end
    lines[#lines + 1] = T.Color("muted", "점검 시각 " .. BRL.Util.FormatClock(res.at) .. " · 물약/주문서 등 사용형 소모품은 점검할 수 없습니다.")
    f.summary:SetText(table.concat(lines, "\n"))
    W.RefreshPermissionButtons()
end

function PR:Show(res)
    self:Create()
    self.res = res
    self.frame:Show()
    self.frame:Raise()
    self:Render()
end
