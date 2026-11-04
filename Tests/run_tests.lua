-- BIG RAID LEADER 자동 테스트 실행기
-- 사용법: lua5.1 Tests/run_tests.lua Tests/test_*.lua
package.path = "./Tests/?.lua;" .. package.path
local M = dofile("Tests/mock_wow.lua")

local T = { passed = 0, failed = 0, failures = {}, current = nil }
_G.T = T

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: 기대값 %s, 실제값 %s", msg or "eq", fmt(expected), fmt(actual)), 2)
    end
end

function T.ok(v, msg)
    if not v then error((msg or "ok") .. ": 참이어야 함", 2) end
end

function T.no(v, msg)
    if v then error((msg or "no") .. ": 거짓이어야 함 (" .. fmt(v) .. ")", 2) end
end

function T.contains(haystack, needle, msg)
    if type(haystack) == "table" then haystack = table.concat(haystack, "\n") end
    if not tostring(haystack):find(needle, 1, true) then
        error(string.format("%s: %q 포함 필요\n---\n%s", msg or "contains", needle, tostring(haystack)), 2)
    end
end

function T.test(name, fn)
    T.current = name
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
        io.write("  [통과] ", name, "\n")
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = { name = name, err = err }
        io.write("  [실패] ", name, "\n    ", tostring(err):gsub("\n", "\n    "), "\n")
    end
end

-- 애드온 로드 (1회)
local BRL
local function boot()
    M.SetGroup(nil)
    BRL = M.Boot("BigRaidLeader")
    _G.BRL = BRL
end

-- 데이터와 모듈 상태 초기화
function T.fresh(opts)
    opts = opts or {}
    M.ClearSent()
    M.timers = {}
    M.combat = false
    M.lockdown = false
    M.leaderSecret = false
    M.money = 1000000 * 10000
    M.trade = { partner = nil, playerMoney = 0, targetMoney = 0, playerItems = {}, targetItems = {} }
    M.bags = {}
    M.noItemCount = false
    M.protectedTradeMoney = false
    M.tradeMoneySet = nil
    M.player.rank = 2
    M.SetGroup(opts.group)
    _G.BigRaidLeaderDB = nil
    BRL.DB:Init()
    BRL.db.schemaVersion = BRL.DB.SCHEMA_VERSION
    for k, v in pairs(BRL.Data.DefaultRequiredBuffs) do BRL.acct.buffs.required[k] = v end
    BRL.acct.trade.notifyScreen = false
    BRL.TradeTracker.current = nil
    BRL.TradeTracker.pending = nil
    BRL.TradeTracker.lastFinalized = nil
    BRL.Auctions:StopTicker()
    BRL.ChatOut:Clear()
    BRL.ChatOut.lastSend = -100
    BRL.ChatOut.scheduled = false
    BRL.Groups.applying = nil
    BRL.BossPlans.timer = nil
    if BRL.UI.frame then BRL.UI.frame:Hide() end
    if BRL.PrepReport.frame then BRL.PrepReport.frame:Hide() end
    BRL.CombatPrep.last = nil
    BRL.CombatPrep.pendingWipe = nil
    BRL.Auctions.autoNext = nil
    if BRL.HUD.frame then BRL.HUD.frame:Hide() end
    if BRL.HUD.ticker and BRL.HUD.ticker.Cancel then BRL.HUD.ticker:Cancel() end
    BRL.HUD.ticker = nil
    if BRL.TradeAssist.frame then BRL.TradeAssist.frame:Hide() BRL.TradeAssist.frame.dismissed = nil end
    BRL.Readiness.check = { active = false, results = {}, startedAt = nil }
    BRL.Composition.cache = nil
    M.auras = {}
    BRL.Perm.override = opts.role
    return BRL
end

-- 공격대 구성 헬퍼: n명, 공대장 포함
function T.raid(n, opts)
    opts = opts or {}
    local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }
    local members = { { name = M.player.name, class = "WARRIOR", rank = opts.leaderRank or 2, subgroup = 1 } }
    for i = 2, n do
        members[i] = { name = "대원" .. i, class = classes[(i % #classes) + 1], rank = 0, subgroup = math.floor((i - 1) / 5) + 1 }
    end
    return members
end

boot()
print(string.format("BIG RAID LEADER v%s 로드 완료 (%d개 파일)", BRL.VERSION, #M.files))

for _, file in ipairs(arg) do
    print("\n== " .. file .. " ==")
    local chunk, err = loadfile(file)
    if not chunk then
        T.failed = T.failed + 1
        print("  [실패] 로드 오류: " .. tostring(err))
    else
        local ok, e = xpcall(chunk, debug.traceback)
        if not ok then
            T.failed = T.failed + 1
            print("  [실패] 실행 오류: " .. tostring(e))
        end
    end
end

print(string.format("\n결과: 통과 %d / 실패 %d", T.passed, T.failed))
if #BRL.errors > 0 then
    print(string.format("애드온 내부 오류 기록 %d건:", #BRL.errors))
    for _, e in ipairs(BRL.errors) do print("  - " .. e.context .. ": " .. e.message:sub(1, 400)) end
end
os.exit(T.failed == 0 and 0 or 1)
