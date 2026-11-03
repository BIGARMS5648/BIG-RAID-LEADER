-- BIG RAID LEADER - 초기화 / 슬래시 명령 (TOC 마지막에 로드)
local ADDON_NAME, BRL = ...
local U, API, Money = BRL.Util, BRL.API, BRL.Money

local Init = {}
BRL.Init = Init

local function onAddonLoaded(_, _, name)
    if name ~= ADDON_NAME then return end
    BRL.DB:Init()
    BRL.Migration:Run(BRL.db)
    if not next(BRL.acct.buffs.required) then
        for k, v in pairs(BRL.Data.DefaultRequiredBuffs) do BRL.acct.buffs.required[k] = v end
    end
    BRL:InitializeModules()
    BRL.Events:Unregister("ADDON_LOADED", Init)
end

local function onLogin()
    BRL.DB:RebindCharacter()
    BRL.Perm:OnEnable()
    API.RegisterAddonPrefix(BRL.COMM_PREFIX)
    BRL:EnableModules()
    BRL.Migration:AutoBackup()
    BRL.Events:Register("PLAYER_REGEN_DISABLED", Init, function() BRL.Events:Fire(BRL.Events.MSG.COMBAT_CHANGED, true) end)
    BRL.Events:Register("PLAYER_REGEN_ENABLED", Init, function() BRL.Events:Fire(BRL.Events.MSG.COMBAT_CHANGED, false) end)
    local iface = API.GetInterfaceVersion()
    BRL:Print("v%s 로드됨 - |cffffffff/brl|r 로 창을 엽니다. (Interface %s)", BRL.VERSION, tostring(iface or "?"))
end

BRL.Events:Register("ADDON_LOADED", Init, onAddonLoaded)
BRL.Events:Register("PLAYER_LOGIN", Init, onLogin)

---------------------------------------------------------------------------
-- 슬래시 명령: /brl
---------------------------------------------------------------------------
local HELP = {
    "|cffd4af37BIG RAID LEADER|r 명령어",
    "/brl - 메인 창 열기/닫기",
    "/brl <메뉴> - 메뉴 바로 열기 (대시보드, 모집, 공대원, 편성, 역할, 준비, 버프, 지휘, 공략, 경매, 거래, 장부, 정산, 통계, 설정)",
    "/brl 경매 [아이템링크] [시작가] - 경매 등록",
    "/brl 입찰 <이름> <금액> - 진행 중 경매에 수동 입찰",
    "/brl 준비 - 준비 확인 / /brl 풀 [초] - 풀링 카운트다운",
    "/brl 세션 [이름] - 새 공격대 세션",
    "/brl 백업 - 데이터 백업 / /brl 검사 - 데이터 무결성 검사",
    "/brl 호환성 - API 지원 여부 확인",
}

local PAGE_ALIASES = {
    ["대시보드"] = "dashboard", dashboard = "dashboard", dash = "dashboard",
    ["모집"] = "recruit", recruit = "recruit",
    ["공대원"] = "roster", roster = "roster",
    ["편성"] = "groups", ["파티"] = "groups", groups = "groups",
    ["역할"] = "roles", roles = "roles",
    ["준비"] = "ready", ready = "ready",
    ["버프"] = "buffs", buffs = "buffs", ["야영지"] = "buffs",
    ["지휘"] = "command", command = "command",
    ["공략"] = "boss", boss = "boss",
    ["경매"] = "auction", auction = "auction",
    ["거래"] = "trades", trades = "trades", trade = "trades",
    ["장부"] = "ledger", ledger = "ledger",
    ["정산"] = "settlement", settlement = "settlement",
    ["통계"] = "stats", stats = "stats",
    ["설정"] = "settings", settings = "settings", config = "settings",
}

function Init:Slash(msg)
    msg = U.Trim(msg or "")
    if msg == "" then
        if BRL.UI then BRL.UI:Toggle() end
        return
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    local lower = cmd:lower()
    if lower == "help" or cmd == "도움말" or cmd == "?" then
        for _, l in ipairs(HELP) do BRL:Print(l) end
        return
    end
    if cmd == "준비" and rest == "" then
        if BRL.Perm:Require("raid.command") then BRL.Command:ReadyCheck() end
        return
    end
    if cmd == "풀" or lower == "pull" then
        if BRL.Perm:Require("raid.command") then BRL.Command:Pull(tonumber(rest) or BRL.acct.command.pullSeconds) end
        return
    end
    if cmd == "경매" and rest ~= "" then
        local link = rest:match("(|c%x+|H.-|h|r)") or rest:match("(|H.-|h)")
        if not link then BRL:Print("아이템 링크를 함께 입력하세요 (Shift+클릭).") return end
        local after = rest:gsub(link:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"), "")
        local price = Money.Parse(U.Trim(after))
        local auc, err = BRL.Auctions:Add(link, { startPrice = price })
        if auc then BRL:Print("경매 등록: %s", link) else BRL:Print("경매 등록 실패: %s", tostring(err == "duplicate" and "이미 등록된 아이템" or err)) end
        return
    end
    if cmd == "입찰" or lower == "bid" then
        local name, amountText = rest:match("^(%S+)%s+(.+)$")
        local auc = BRL.Auctions:GetActive()
        local amount = amountText and Money.Parse(amountText)
        if not auc then BRL:Print("진행 중인 경매가 없습니다.") return end
        if not name or not amount then BRL:Print("사용법: /brl 입찰 <이름> <금액>") return end
        local bid, why = BRL.Bids:Place(auc.id, name, amount, "manual")
        if bid and bid.accepted then BRL:Print("입찰 등록: %s %s", name, Money.Format(amount))
        else BRL:Print("입찰 거부: %s", tostring(why)) end
        return
    end
    if cmd == "세션" or lower == "session" then
        local s = BRL.Session:Create({ name = rest ~= "" and rest or nil })
        if s then BRL:Print("새 공격대 세션: %s", s.name) end
        return
    end
    if cmd == "백업" or lower == "backup" then
        local b = BRL.Migration:CreateBackup("수동 백업 (/brl 백업)")
        if b then BRL:Print("백업 완료 (%s바이트, 체크섬 %d)", U.FormatNumber(b.size), b.checksum) end
        return
    end
    if cmd == "검사" or lower == "validate" then
        local issues = BRL.Migration:Validate()
        if #issues == 0 then BRL:Print("데이터 무결성 검사: 문제 없음") return end
        BRL:Print("데이터 무결성 검사: %d개 항목", #issues)
        for i = 1, math.min(10, #issues) do
            BRL:Print(" - [%s] %s %s", issues[i].severity, issues[i].message, tostring(issues[i].entity or ""))
        end
        return
    end
    if cmd == "호환성" or lower == "compat" then
        BRL:Print("클라이언트: %s", API.GetBuildText())
        for _, r in ipairs(API.RunCompatibilityCheck()) do
            if not r.ok then BRL:Print(" |cffff5555미지원|r %s", r.name) end
        end
        BRL:Print("미지원 항목만 표시했습니다. 전체 목록: 설정 > 호환성")
        return
    end
    if lower == "debug" then
        BRL.acct.debug = not BRL.acct.debug
        BRL:Print("디버그: %s", BRL.acct.debug and "켜짐" or "꺼짐")
        return
    end
    local page = PAGE_ALIASES[cmd] or PAGE_ALIASES[lower]
    if page and BRL.UI then
        BRL.UI:Open(page)
        return
    end
    for _, l in ipairs(HELP) do BRL:Print(l) end
end

_G.SLASH_BIGRAIDLEADER1 = "/brl"
_G.SLASH_BIGRAIDLEADER2 = "/bigraidleader"
_G.SLASH_BIGRAIDLEADER3 = "/빅레이드"
if _G.SlashCmdList then
    _G.SlashCmdList.BIGRAIDLEADER = function(msg) Init:Slash(msg) end
end

-- 키 바인딩 이름
_G.BINDING_HEADER_BIGRAIDLEADER = "BIG RAID LEADER"
_G.BINDING_NAME_BRL_TOGGLE = "메인 창 열기/닫기"
_G.BINDING_NAME_BRL_READYCHECK = "준비 확인"
_G.BINDING_NAME_BRL_PULL = "풀링 카운트다운"
_G.BINDING_NAME_BRL_CANCELPULL = "풀링 취소"
_G.BINDING_NAME_BRL_AUCTION = "경매 화면 열기"

function _G.BigRaidLeader_Binding(action)
    if action == "READY" then
        if BRL.Perm:Require("raid.command") then BRL.Command:ReadyCheck() end
    elseif action == "PULL" then
        if BRL.Perm:Require("raid.command") then BRL.Command:Pull(BRL.acct.command.pullSeconds) end
    elseif action == "CANCELPULL" then
        if BRL.Perm:Require("raid.command") then BRL.Command:CancelPull() end
    elseif action == "AUCTION" then
        if BRL.UI then BRL.UI:Open("auction") end
    end
end
