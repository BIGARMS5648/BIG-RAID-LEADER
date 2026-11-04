-- BIG RAID LEADER - 지역화 (기본 언어: 한국어)
local _, BRL = ...

local L = setmetatable({}, { __index = function(_, k) return tostring(k) end })
BRL.L = L

-- 메뉴
L.MENU_DASHBOARD = "대시보드"
L.MENU_RECRUIT = "공격대 모집"
L.MENU_ROSTER = "공대원 관리"
L.MENU_GROUPS = "파티 편성"
L.MENU_ROLES = "역할 배정"
L.MENU_READY = "전투 준비"   -- 준비 확인 + 버프·도핑 + 야영지 + 필수 버프 (통합 화면)
L.MENU_BUFFS = "버프 및 야영지"
L.MENU_COMMAND = "전투 지휘"
L.MENU_BOSS = "보스 공략"
L.MENU_AUCTION = "전리품 경매"
L.MENU_TRADES = "거래 로그"
L.MENU_LEDGER = "골드 장부"
L.MENU_SETTLEMENT = "골드 정산"
L.MENU_SETTINGS = "설정"

-- 권한
L.ROLE_LEADER = "공대장"
L.ROLE_ASSISTANT = "부공대장"
L.ROLE_MEMBER = "공대원"
L.ROLE_SOLO = "개인(파티 없음)"
L.ROLE_UNKNOWN = "확인 불가"
L.NO_PERMISSION = "권한이 없습니다"
L.LEADER_ONLY = "공대장 전용 기능입니다."
L.IN_COMBAT_BLOCKED = "전투 중에는 사용할 수 없습니다. 전투 종료 후 다시 시도하세요."
L.CHAT_LOCKDOWN = "현재 채팅 제한(우두머리 전투 등) 중이라 메시지를 보낼 수 없습니다. 제한이 풀리면 자동 전송됩니다."

-- 전투 역할
L.CR_TANK = "탱커"
L.CR_HEALER = "힐러"
L.CR_MELEE = "근접 딜러"
L.CR_RANGED = "원거리 딜러"
L.CR_NONE = "미지정"

-- 거래 목적
L.PURPOSE_auction_payment = "경매금 수금"
L.PURPOSE_payout = "공대원 골드 분배"
L.PURPOSE_personal = "공대장 개인 거래"
L.PURPOSE_raid_expense = "기타 공대 지출"
L.PURPOSE_raid_income = "기타 공대 수입"
L.PURPOSE_refund = "경매금 환불"
L.PURPOSE_unclassified = "분류되지 않은 거래"

-- 거래 상태
L.TRADE_open = "거래 중"
L.TRADE_completed = "완료 확인"
L.TRADE_cancelled = "취소"
L.TRADE_unverified = "확인 불가"
L.TRADE_manual = "수동 확인"
L.TRADE_adjusted = "수동 조정"
L.TRADE_voided = "기록 취소"
L.TRADE_self = "본인 지급"

-- 경매 상태
L.AUC_queued = "대기"
L.AUC_active = "진행 중"
L.AUC_ended = "종료(확정 대기)"
L.AUC_awarded = "낙찰"
L.AUC_unsold = "유찰"
L.AUC_cancelled = "취소"

-- 낙찰 상태
L.AWARD_unpaid = "수금 전"
L.AWARD_partial = "부분 입금"
L.AWARD_paid = "완납"
L.AWARD_overpaid = "초과 입금"
L.AWARD_cancelled = "낙찰 취소"
L.AWARD_refund_due = "환불 필요"
L.AWARD_refunded = "환불 완료"

-- 지급 상태
L.PAY_pending = "지급 전"
L.PAY_partial = "부분 지급"
L.PAY_paid = "지급 완료"
L.PAY_check = "지급 확인 필요"
L.PAY_hold = "지급 보류"

-- 장부 분류
L.LEDGER_auction_payment = "경매 낙찰금"
L.LEDGER_extra_auction = "추가 경매 수입"
L.LEDGER_other_income = "기타 공대 수입"
L.LEDGER_adjust_income = "수동 조정 수입"
L.LEDGER_payout_member = "공대원 골드 분배"
L.LEDGER_payout_leader = "공대장 골드 분배"
L.LEDGER_operating = "정산 운영비"
L.LEDGER_other_expense = "기타 공대 지출"
L.LEDGER_adjust_expense = "수동 조정 지출"
L.LEDGER_refund = "경매금 환불"

-- 정산 상태
L.SETTLE_draft = "작성 중"
L.SETTLE_confirmed = "확정 정산"
L.SETTLE_paying = "지급 진행 중"
L.SETTLE_completed = "완료"
L.SETTLE_closed_with_issues = "미결 항목 있음(종료)"

-- 징표
L.MARKER_1 = "별"
L.MARKER_2 = "동그라미"
L.MARKER_3 = "다이아몬드"
L.MARKER_4 = "세모"
L.MARKER_5 = "달"
L.MARKER_6 = "네모"
L.MARKER_7 = "엑스"
L.MARKER_8 = "해골"

-- 일반
L.YES = "예"
L.NO = "아니오"
L.OK = "확인"
L.CANCEL = "취소"
L.SAVE = "저장"
L.DELETE = "삭제"
L.EDIT = "수정"
L.ADD = "추가"
L.CLOSE = "닫기"
L.UNKNOWN = "확인 불가"

function BRL.Label(prefix, key)
    if key == nil then return "-" end
    local v = rawget(L, prefix .. tostring(key))
    return v or tostring(key)
end
