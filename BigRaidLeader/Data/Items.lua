-- BIG RAID LEADER - 아이템 관련 데이터
local _, BRL = ...
BRL.Data = BRL.Data or {}

BRL.Data.QualityNames = {
    [0] = "하급", [1] = "일반", [2] = "고급", [3] = "희귀", [4] = "영웅", [5] = "전설",
}

-- 등급별 기본 경매 설정 제안 (코퍼). 공대장이 경매 등록 시 변경 가능.
BRL.Data.AuctionPresets = {
    [2] = { startPrice = 10 * 10000, minIncrement = 10 * 10000 },
    [3] = { startPrice = 50 * 10000, minIncrement = 50 * 10000 },
    [4] = { startPrice = 100 * 10000, minIncrement = 50 * 10000 },
    [5] = { startPrice = 1000 * 10000, minIncrement = 500 * 10000 },
}

-- 빠른 금액 버튼 (골드)
BRL.Data.QuickBidSteps = { 50, 100, 500, 1000 }

function BRL.Data.QualityName(q)
    return BRL.Data.QualityNames[q] or "-"
end
