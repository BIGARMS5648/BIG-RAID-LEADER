# 개발 문서

## 1. 저장소 구조

```
BigRaidLeader/              ← 게임에 설치하는 애드온 폴더
  BigRaidLeader.toc         Interface 16001, 로드 순서
  Bindings.xml              키 바인딩
  README.md                 폴더 안내
  Core/
    Bootstrap.lua           네임스페이스, 유틸, 코퍼 금액 계산(Money), ID, 오류 격리(SafeCall), 모듈 수명주기
    Localization.lua        한국어 문자열/라벨
    APICompat.lua           게임 API 호환 계층 (Secret Value, 전투/채팅 잠금, 거래/공격대/오라 API)
    Events.lua              게임 이벤트 분배 + 내부 메시지 버스
    Database.lua            SavedVariables(BigRaidLeaderDB), 기본값, 레코드 헬퍼, 감사 로그
    Serializer.lua          안전한 직렬화(코드 실행 없음), Base64, 내보내기/가져오기
    Migration.lua           스키마 마이그레이션, 무결성 검증, 백업/복구
    Permissions.lua         권한 (공대장 전용: 그룹 안 공대장 / 그룹 밖만 운영 가능, 그 외 잠김)
    Init.lua                ADDON_LOADED/PLAYER_LOGIN 초기화, /brl 명령 (TOC 마지막)
  Data/                     Classes, Raids, Bosses, Buffs(야영지·도핑 포함), Items, Synergy(구성 시너지·목표 구성)
  Modules/                  비즈니스 로직 (UI 비의존)
    ChatOut  Session  TradeTracker  TradeJournal  Auctions  Bids  Payments  Ledger  Settlement  Reports
    Roles  Roster  Groups  Readiness  Buffs  Campsites  Command  BossPlans  RaidProgress
    Statistics(지난 세션·구매자 기록)  Recruitment  Composition(구성 분석·추천)
    CombatPrep(도핑 점검·풀링 판정·전멸 복구)  Diagnostics(자가 진단)  Share(공유 문자열: 공략/편성/전술표)
  UI/
    Theme  Widgets  Dialogs  MainFrame  Minimap  MarkerBar  Actions  TradePopup  TradeAssist(거래 창 정보 패널)
    HUD(공대장 HUD)  PrepReport  Dashboard
    Pages/  Recruit Roster Groups Roles Ready(준비 확인 탭) Buffs(전투 준비 화면) Command Boss Auction Trades Ledger Settlement Settings
Tests/                      자동 테스트 (배포 제외)
  mock_wow.lua              WoW API 모의 환경
  run_tests.lua             테스트 실행기
  test_*.lua                시나리오 테스트
tools/build.sh              luacheck → 테스트 → ZIP
docs/                       사용 설명서, 문제 해결, 개발 문서
dist/                       배포 ZIP
```

## 2. 아키텍처

- **계층**: `Core` → `Data` → `Modules`(로직) → `UI`(표현). UI 는 모듈 함수를 호출만 하고, 모듈은 UI 를 참조하지 않습니다.
  (예외: 모듈이 내부 메시지를 발생시키면 UI 가 구독해 화면을 갱신)
- **이벤트**: 게임 이벤트는 `BRL.Events:Register(event, owner, handler)` 로 등록하고 하나의 프레임에서 분배합니다.
  핸들러별 `SafeCall` 로 오류가 격리됩니다. 모듈 간 통지는 `BRL.Events:Fire(MSG.*)` 내부 메시지를 사용합니다.
- **모듈 수명주기**: `BRL:NewModule(name)` → `OnInitialize`(SavedVariables 로드 직후) → `OnEnable`(PLAYER_LOGIN).
- **게임 API 격리**: 모든 게임 API 는 `BRL.API` 를 통해 호출합니다. 테스트에서는 모의 환경으로 대체됩니다.
- **순환 의존 방지**: 모듈은 다른 모듈을 파일 로드 시점이 아니라 **실행 시점**에 `BRL.<Module>` 로 참조합니다.

## 3. 데이터 모델 (`BigRaidLeaderDB`)

| 키 | 구조 (명세 20장 대응) |
|---|---|
| `schemaVersion`, `nextId` | 스키마 버전(3), ID 카운터 |
| `account` | **AccountSettings** (거래/경매/정산/버프/지휘/도핑/보관/HUD 설정) |
| `characters[이름-서버]` | **CharacterSettings** (창 위치/크기/배율, 이월 잔돈, 개인 메모) |
| `sessions[id]` | **RaidSession** (이름, 공격대, 인원, 소유자, 참가자 `attendance[key]` = **CurrentRaidMember** 기록) |
| `raidOps.groupPlan`, `groupTemplates`, `pinned` | **RaidGroupLayout** |
| `raidOps.memberRoles`, `assignments`, `orders` | **RoleAssignment** |
| `bossPlans[bossKey]` | **BossPlan** (기본 데이터 위 사용자 편집, 배치도 `layouts[phase].tokens`, 타임라인) |
| `progress[sessionId].bosses[bossKey]` | **BossProgress** |
| `auctions[id]` / `bids[id]` / `awards[id]` | **Auction / Bid / Award** |
| `trades[id]` (+ `playerItems`/`targetItems`) / `tradeOrder` | **TradeTransaction / TradeItem** (원본 + `adjusted` + `history`) |
| `ledger[id]` | **LedgerEntry** (source = trade/manual/system) |
| `auctionAllocations[id]` | **AuctionPaymentAllocation** (kind = payment/refund) |
| `payouts[id]` | **PayoutObligation** (kind = share/fee) |
| `payoutAllocations[id]` | **PayoutAllocation** |
| `settlements[id]` | **Settlement** (config, result 스냅샷, version, locked, carry) |
| `reports[id]` | **SettlementReport** (버전별 간략/상세 텍스트) |
| `audit[]` | **AuditEvent** (누가/언제/무엇을/이전·이후/사유) |
| `activeTrade` | 진행 중 거래 (UI 재시작 복구용) |
| `tradeTraces[]` | 최근 거래 10건 이벤트 추적 (기록 안 된 빈 거래 포함) |
| `raidOps.activePlanKey/activePlanVersion` | [보스 준비 적용] 후 전술표/지휘/버프 화면이 따라가는 활성 전술표 |
| `backups[]` | 직렬화 스냅샷 + 체크섬 (최대 5) |

### 무결성 규칙
- 모든 레코드는 고유 ID (`접두사-시간36진수-카운터36진수`), 테이블 키 = `rec.id`
- 금액은 정수 코퍼(`Money.IsValid`), 음수 금지
- 거래별 수금 연결 합계 ≤ 순수령액, 지급 연결 합계 ≤ 순지급액
- 같은 (거래, 낙찰) / (거래, 분배 의무) 쌍은 한 번만 연결
- 원본 거래는 삭제하지 않음 (취소/정정은 플래그와 이력)
- `Migration:Validate()` 가 위 규칙을 점검

## 4. 금액 계산

- 1골드 = 10,000코퍼, 1실버 = 100코퍼. Lua double 은 2^53 까지 정수를 정확히 표현합니다.
- 비율 분배는 `Money.MulDiv(a, num, den) = floor(a/den)*num + floor((a%den)*num/den)` 로 중간값 오버플로 없이 계산합니다.
- 정산 항등식: `총수입 = 장부지출 + 운영비 + 공제 + 수수료 + 예비금 + 분배합계 + 잔돈(보관) + 이월` 을 매 계산마다 검증합니다.
- 장부 잔액 검증(정산 확정 후): `잔액 = 운영비 + 공제 + 예비금 + 잔돈 + 이월 − 이월사용 + 미지급 − 초과지급 + 미환불 + 미연결수금 − 미연결환불 − 미연결지급 − 수동 공대장분배`

## 5. 거래 추적 상태 기계

```
TRADE_SHOW ─▶ 열림(current) ──변경 이벤트──▶ live 스냅샷 갱신
                 │ TRADE_ACCEPT_UPDATE(한쪽 이상 수락) ─▶ acceptSnap 저장
                 │ TRADE_ACCEPT_UPDATE(0,0) ─▶ acceptSnap 해제
TRADE_CLOSED ─▶ 판정 대기(pending) ──┬─ 취소 신호 ───────────────▶ 취소
                                     ├─ 완료 신호 (+골드 반영) ────▶ 완료 확인
                                     ├─ 골드 변화 = 제시 금액 ──────▶ 완료 확인(money)
                                     └─ 유예 3초 경과 ──┬─ 제시 골드 있는데 변화 없음 ─▶ 취소
                                                         └─ 그 외 ─────────────────────▶ 확인 불가
(재접속 시 activeTrade 남아 있음) ─────────────────────────────────▶ 확인 불가(interrupted)
```
최종 내용은 실제 골드 변화와 일치하는 스냅샷(acceptSnap → live → lastNonEmpty 순)을 사용합니다.

**아이템 수량 교차 검증** (2.0): 수락 시점 스냅샷의 아이템별 예상 증감(받은 수 − 준 수)과 가방 수량(`C_Item.GetItemCount`)을 기록합니다.
창이 닫힌 뒤 `BAG_UPDATE_DELAYED` 마다 다시 비교해, 골드가 없는 거래에서
- 완료 메시지 + 수량 일치 → `message+items` (메시지만 오고 가방 갱신 전이면 최대 1초/유예 시간까지 대기)
- 메시지 없음 + 수량 일치 → 완료 `items` / 메시지 없음 + 변화 없음 → 취소 `items_unchanged`
- 수량을 읽을 수 없거나(미지원/재시작 복구) 예상 증감이 모두 0 이면 사용하지 않음

판정 결과와 이벤트 순서는 `tradeTraces` 에 최근 10건 보관됩니다 (`Tracker:FormatEvents`).

## 5b. 구성 분석 알고리즘 (`Modules/Composition.lua`)

- 공대원(+선택한 지원자)을 **직업×역할 집계**로 바꾼 뒤 시너지마다 `제공자 수 / 필요 수`를 계산합니다.
  - 공격대 버프·보스 약화·생존기·유틸리티: 규모별 고정 필요 수 (`need[10|20|40]`, 야영지 준비 시 `campReduce` 만큼 감소)
  - 파티 버프: `필요 = min(파티 수, ceil(수혜 인원 / 4))`, 같은 제공자를 나눠 쓰는 항목(`shareGroup`, 주술사 질풍/마나샘)은 중요도 순으로 배정
- 점수 = Σ 중요도 × 확보율 + 역할 목표 점수(탱커·힐러 가중) + 목표 직업 구성 점수
- 추천 = 직업별로 가능한 역할 중 점수 증가가 가장 큰 역할을 골라 증가량 순 정렬, 확보가 좋아지는 시너지를 이유로 표시
- 남은 자리 계획 = 추천 1순위를 하나씩 추가하는 탐욕적 반복 (빠른 경로 `Score` 사용, 40인 39자리 ≈ 35ms)
- 같은 입력(공대원 직업·역할·파티, 설정, 야영지 상태)이면 결과를 캐시합니다.

## 5c. 스키마 v3 마이그레이션 (2.1)

- 2.0 의 `archives`(세션 보관)를 체크섬 검증 후 원래 테이블로 되돌리고 `tradeOrder` 를 시각 순으로 재정렬, 손상된 보관 기록은 `archivesDamaged` 로 보존
- 폐기된 기능의 저장값 제거: `lootRecords`, `loot`, `raidOps.markerTemplates`, `raidOps.readyManual`, `account.archive`, `account.trade.whisperPartner`, `account.auction.policyAcknowledged`
- 마이그레이션 전 자동 백업

## 5d. 풀링 판정 (`CombatPrep:PullCheck`)

`go < caution < stop` 중 가장 높은 단계. 보류: 사망자, 준비 안 됨. 주의: 준비 확인 미실시/진행/무응답/5분 경과, 오프라인/다른 지역,
도핑 점검 없음/10분 경과/누락, 필수 버프 누락, 탱커 미지정/힐러 없음(직업 추정이므로 주의), 전멸 후 재점검, 내 내구도 낮음. 전투 중이면 즉시 보류.

## 6. 테스트

```bash
lua5.1 Tests/run_tests.lua Tests/test_*.lua     # 전체
lua5.1 Tests/run_tests.lua Tests/test_trade.lua  # 개별
luacheck BigRaidLeader                           # 정적 검사 (.luacheckrc)
```
- `T.fresh({ group = T.raid(20), role = ... })` 로 데이터/상태 초기화
- `MOCK.Fire(event, ...)` 로 게임 이벤트 주입, `MOCK.Advance(sec)` 로 시간 진행
- `MOCK.trade`, `MOCK.money`, `MOCK.combat`, `MOCK.lockdown`, `MOCK.SECRET` 으로 상황 구성
- `MOCK.bags[itemID]`(가방 수량), `MOCK.noItemCount`(수량 API 미지원), `MOCK.protectedTradeMoney`(SetTradeMoney 차단), `MOCK.tradeMoneySet`

## 7. 기능 추가 가이드

- 새 모듈: `Modules/X.lua` 에 `local X = BRL:NewModule("X")`, TOC 의 Modules 구간에 추가, 이벤트는 `OnEnable` 에서 등록
- 새 화면: `UI/Pages/X.lua` 에 `UI:RegisterPage(key, { title, order, build, refresh })`, TOC 의 UI 구간에 추가
- 권한이 필요한 동작: 모듈에서 `BRL.Perm:Require(action)` 또는 `Perm:CanEditSession(session)` 확인, 버튼에는 `{ perm = action }`
- 금융 데이터 수정: 반드시 `DB:AddHistory` + `DB:Audit` 기록, 금액은 `Money.IsValid` 검증
- 저장 구조 변경: `DB.SCHEMA_VERSION` 증가 + `Migration.steps[n]` 추가 (마이그레이션 전 자동 백업)
- 게임 API 추가: `Core/APICompat.lua` 에 래퍼 작성(존재 확인, Secret 처리), `API.CHECK_LIST` 에 추가

## 8. 배포

```bash
tools/build.sh
```
`dist/BigRaidLeader-<버전>.zip` 에는 `BigRaidLeader/` 폴더만 포함됩니다 (Tests/docs 제외).
버전은 `BigRaidLeader.toc` 의 `## Version:` 과 `CHANGELOG.md` 를 함께 갱신하세요.
