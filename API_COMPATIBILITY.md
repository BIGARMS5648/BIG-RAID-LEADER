# API 호환성 문서 (WoW: Forever)

이 문서는 BIG RAID LEADER가 사용하는 게임 API와 포에버 클라이언트 환경에 대한 조사 결과, 그리고 각 기능의 대체(fallback) 동작을 정리합니다.

> **중요**: 개발 환경에서는 실제 포에버 클라이언트를 실행할 수 없었습니다. 아래 "지원" 여부는
> 공개 자료(블리자드 발표를 인용한 커뮤니티 자료, Warcraft Wiki의 12.x API 변경 기록 요약)와
> 리테일 12.x API 지식을 바탕으로 한 **예상**입니다. 실제 지원 여부는 게임 안에서
> `/brl 호환성` 또는 **설정 > 호환성** 화면으로 확인하고, 그 결과를 이 문서에 반영해야 합니다.

## 1. 포에버 클라이언트 환경 (조사 결과)

| 항목 | 내용 | 근거/상태 |
|---|---|---|
| 출시 | 2026-11-04(북미)/11-05(한국 시각), 1단계 공격대 2026-12-09~10 개방 | 다수 매체 일치 |
| Interface 버전 | **16001** (게임 버전 1.60.x) | 커뮤니티 자료 일치, 인게임 확인 필요 |
| TOC 접미사 | `_Forever` 는 `_Camelot` 의 별칭 (Camelot = 포에버 내부 코드명). 접미사 없는 `BigRaidLeader.toc` 도 Interface 가 맞으면 로드됨 | Warcraft Wiki TOC 형식 요약 |
| API 계열 | Classic 이 아닌 **Mainline(미드나이트 12.x) API** 사용, Secret Value 포함 | 2026-09 애드온 개발자 대상 공지 요약 |
| Secret Value | 전투/제한 상황에서 일부 값이 Lua 로 "비밀 값"으로 전달되어 비교·연산·저장 불가. `issecretvalue(v)` 로 판별 | Warcraft Wiki "Secret Values" 요약 |
| 채팅 잠금 | `C_ChatInfo.InChatMessagingLockdown()` 이 참인 동안(우두머리 전투, 쐐기, PvP 경기) 애드온의 채팅/애드온 메시지 전송 차단, 수신 채팅 내용은 Secret Value | 12.0/12.0.5/12.0.7 API 변경 요약, 애드온 개발 노트 |
| GUID | 2026-10 이후 다른 플레이어 GUID 난독화 | 커뮤니티 타임라인 요약 (미확인) |
| 전투 로그 | 전투 로그 기반 트리거 차단 | 커뮤니티 자료 |

## 2. 이 애드온의 대응 원칙

1. 모든 게임 API 호출은 `Core/APICompat.lua` 한 곳을 거칩니다. 함수가 없으면 해당 기능을 안전하게 비활성화합니다.
2. Secret Value 는 읽거나 비교하지 않고 "확인 불가"로 처리합니다. (`API.IsSecret`, `API.Safe`)
3. 권한 정보가 Secret/오류로 확인되지 않으면 **권한 = 확인 불가** → 금융/계획 수정 차단.
4. 전투 중 호출이 금지된 기능(준비 확인, 카운트다운, 파티 이동, 초대, 오라 조회)은 `InCombatLockdown()` 으로 미리 차단합니다.
5. 채팅 잠금 중 메시지는 대기열에 보관했다가 잠금이 풀리면 전송합니다. (`ADDON_RESTRICTION_STATE_CHANGED`, `PLAYER_REGEN_ENABLED`, `ENCOUNTER_END` 후 재시도)
6. 보호 함수(SetRaidTarget 등)는 직접 호출하지 않고 보안 버튼(SecureActionButtonTemplate)으로만 사용합니다.
7. 플레이어 식별은 `이름-서버` 키를 기본으로 하고, GUID 는 Secret 이 아닐 때만 보조 정보로 저장합니다.
8. 알 수 없는 이벤트 등록은 `pcall` 로 감싸 실패해도 다른 기능에 영향이 없게 합니다.

## 3. 사용 API 목록

### 3.1 거래 기록 (최우선)

| API / 이벤트 | 용도 | 예상 | 대체 동작 |
|---|---|---|---|
| `TRADE_SHOW` | 거래 창 열림 → 거래 세션 생성 | 지원 | — |
| `TRADE_MONEY_CHANGED`, `TRADE_PLAYER_ITEM_CHANGED`, `TRADE_TARGET_ITEM_CHANGED`, `TRADE_UPDATE` | 제시 골드/아이템 갱신 | 지원 | 수락 시점 스냅샷으로 보완 |
| `TRADE_ACCEPT_UPDATE(player, target)` | 수락 상태, **수락 시점 내용 스냅샷** | 지원 | — |
| `TRADE_REQUEST_CANCEL` | 취소 신호 | 지원 | 시스템 메시지 |
| `TRADE_CLOSED` | 창 닫힘 (중복 수신 가능) → 판정 대기 시작. **이것만으로 완료 처리하지 않음** | 지원 | — |
| `UI_INFO_MESSAGE` / `UI_ERROR_MESSAGE` / `CHAT_MSG_SYSTEM` + `ERR_TRADE_COMPLETE` | **완료 신호(1차)** | 지원 | 골드 변화 검증 |
| `ERR_TRADE_CANCELLED`, `ERR_TRADE_BAG_FULL`, `ERR_TRADE_TARGET_BAG_FULL`, `ERR_TRADE_TOO_FAR` 등 | 취소 신호 | 지원 | 골드 변화 없음으로 취소 추정 |
| `PLAYER_MONEY` + `GetMoney()` | **실제 보유 골드 변화로 교차 검증** | 지원 | 없으면 메시지만으로 판정 |
| `GetPlayerTradeMoney`, `GetTargetTradeMoney` | 내가/상대가 제시한 골드(코퍼) | 지원 | — |
| `GetTradePlayerItemInfo/Link`, `GetTradeTargetItemInfo/Link` (`MAX_TRADE_ITEMS`, `TRADE_ENCHANT_SLOT` 제외) | 거래 아이템 | 지원 | — |
| `UnitName("NPC")`, `TradeFrameRecipientNameText` | 거래 상대 | 지원 | 프레임 텍스트 |

판정 규칙 (`Modules/TradeTracker.lua`):
- 완료 메시지 → **완료 확인** (골드가 오간 경우 실제 골드 변화가 일치하면 `message+money`)
- 완료 메시지 없음 + 실제 골드 변화가 제시 금액과 정확히 일치 → **완료 확인** (`money`)
- 취소 신호 → **취소**, 골드 제시가 있었는데 골드 변화 없음 → **취소** (`money_unchanged`)
- 그 외(아이템만 거래 + 메시지 없음, 완료/취소 신호 충돌, UI 재시작으로 중단) → **확인 불가** (합산 제외, 수동 확인 가능)
- 판정이 끝난 뒤 10초 안에 늦은 완료 메시지가 오면 확인 불가 → 완료로 승격
- 같은 거래 세션은 고유 ID 로 한 번만 기록(멱등), 같은 금액의 반복 거래는 각각 기록

### 3.2 공격대 / 권한

| API | 용도 | 예상 | 대체 |
|---|---|---|---|
| `IsInGroup`, `IsInRaid`, `GetNumGroupMembers`, `GetRaidRosterInfo` | 공대원 목록 | 지원 | 파티는 `party1..4` 유닛 |
| `UnitIsGroupLeader`, `UnitIsGroupAssistant` | 권한 판별 | 지원 | Secret/오류 → 확인 불가(수정 차단) |
| `UnitName`, `UnitFullName`, `GetNormalizedRealmName`, `UnitClass`, `UnitIsAFK`, `UnitIsConnected`, `UnitIsDeadOrGhost`, `UnitGroupRolesAssigned` | 공대원 정보 | 지원 | Secret 이면 해당 칸 확인 불가 |
| `UnitGUID` | 보조 식별자 | 난독화 가능 | 이름-서버 키 사용 |
| `SetRaidSubgroup`, `SwapRaidSubgroup` | 파티 이동 (한 명씩, 0.3초 간격) | 지원(전투 중 불가) | 전투 중 차단/중단 |
| `C_PartyInfo.InviteUnit` / `InviteUnit`, `C_PartyInfo.ConvertToRaid` | 지원자 초대 (클릭 시에만) | 지원 | — |
| `DoReadyCheck`, `READY_CHECK`, `READY_CHECK_CONFIRM`, `READY_CHECK_FINISHED`, `GetReadyCheckStatus` | 준비 확인 | 지원(12.0.5부터 전투 중 호출 불가) | 전투 중 차단 |
| `C_PartyInfo.DoCountdown(sec)` | 공식 풀링 카운트다운 / 0=취소 | 지원(전투 중 불가) | 채팅 카운트다운 |
| `ENCOUNTER_START`, `ENCOUNTER_END` | 보스 시도/처치/전멸 자동 기록, 미확인 보스 이름 갱신 | 지원 | 수동 기록 |
| `GetInventoryItemDurability` | 내 내구도 | 지원 | — |
| `C_UnitAuras.GetAuraDataByIndex` | 버프 점검 / **전투 준비 도핑 점검**(음식·영약·비약, 주문 ID + 이름 키워드, 전투 밖에서만) | 지원 | `UnitBuff`, Secret → 확인 불가 |
| `GetRealZoneText`, `GetInstanceInfo` | 인스턴스 미입장 판단, 공격대 추정 | 지원 | — |

### 3.3 채팅 / 통신

| API | 용도 | 예상 | 대체 |
|---|---|---|---|
| `C_ChatInfo.SendChatMessage` (11.2+) / `SendChatMessage` | 공지/결과 출력 (255바이트 UTF-8 안전 분할) | 지원 | 어느 쪽이든 존재하는 함수 사용 |
| `C_ChatInfo.InChatMessagingLockdown` | 채팅 잠금 확인 | 12.x 지원 | 없으면 잠금 없음으로 간주 |
| 공개 채널/일반/외치기 전송 | 모집 문구 | 하드웨어 이벤트 필요 | **버튼 클릭 시점에 즉시 전송**(대기열 사용 안 함) |
| `C_ChatInfo.RegisterAddonMessagePrefix`, `C_ChatInfo.SendAddonMessage`, `CHAT_MSG_ADDON` | 애드온 간 공유 (접두사 `BRL1`, 탭 구분, 240바이트 분할) | 지원(잠금 중 차단) | 대기열 후 재전송, 실패해도 로컬 기능 유지 |
| `CHAT_MSG_RAID/RAID_LEADER/RAID_WARNING/PARTY/PARTY_LEADER/WHISPER` | 채팅 입찰 인식 | 지원(잠금 중 Secret) | **수동 입찰 입력** |
| `CHAT_MSG_SYSTEM` + `RANDOM_ROLL_RESULT` | 주사위 결과 (한국어 조사 처리) | 지원 | 수동 분배 |
| `GetChannelList` | 모집 채널 목록 | 지원 | 길드/일반/외치기 |
| `ADDON_RESTRICTION_STATE_CHANGED` | 잠금 해제 감지 | 12.x | 2~3초 간격 재시도 |

### 3.4 징표 (보호 함수)

| API | 상태 | 이 애드온의 처리 |
|---|---|---|
| `SetRaidTarget` | 12.0.0 부터 **보호 함수**, SecureActionButton 으로 사용하도록 의도됨 | 직접 호출하지 않음. 별도 창 **징표 바**의 `SecureActionButtonTemplate` 버튼 (`type=raidtarget`, `action=toggle/clear`, `marker=1~8`, `unit=target`) |
| 월드 징표 | 보안 동작 `type=worldmarker` (`action=toggle/clear`) | 징표 바 아래 줄 버튼 |
| 보안 버튼 생성/표시 전환 | 전투 중 불가 | 전투 중 징표 바 생성/열기/닫기 차단, 메인 창과 분리된 독립 창 |

`RegisterForClicks("AnyUp", "AnyDown")` 을 사용합니다(키 다운 사용 설정 대응). 실제 클라이언트에서 한 번 클릭에 한 번만 동작하는지 확인이 필요합니다.

### 3.5 아이템 / UI

| API | 용도 | 대체 |
|---|---|---|
| `C_Item.GetItemInfo` / `GetItemInfo`, `C_Item.GetItemIconByID`, `C_Item.GetItemQualityColor` | 아이템 이름/아이콘/등급 | 링크에서 이름 추출 |
| `GetCursorInfo`, `ClearCursor` | 아이템 드래그 등록 | Shift+클릭/직접 입력 |
| `GetNumLootItems`, `GetLootSlotLink` | 전리품 창에서 경매 등록 | 수동 등록 |
| `ChatEdit_InsertLink` / `ChatFrameUtil.InsertLink` (hooksecurefunc) | Shift+클릭 링크 → 애드온 입력칸 | 드래그/붙여넣기 |
| `CreateFrame` + `BackdropTemplate`, `SetResizeBounds`, `Slider`, `ScrollFrame`, `EditBox` | 자체 UI 위젯 (Blizzard 드롭다운/스크롤 템플릿 미사용) | — |
| `Settings.RegisterCanvasLayoutCategory/RegisterAddOnCategory` | 게임 설정 > 애드온 항목 | 없으면 생략 |
| `RaidNotice_AddMessage`, `PlaySound(SOUNDKIT.*)` | 화면 알림/소리 | `UIErrorsFrame` |
| `C_Timer.After`, `C_Timer.NewTicker`, `GetServerTime`, `GetTime` | 타이머/시각 | `time()` |
| `issecretvalue` | Secret 판별 | 없으면 모든 값을 일반 값으로 처리 |

### 3.6 TOC 필드

```
## Interface: 16001
## SavedVariables: BigRaidLeaderDB
## IconTexture: Interface\Icons\INV_Misc_Coin_02
## AddonCompartmentFunc: BigRaidLeader_OnAddonCompartmentClick
```
`Bindings.xml`(키 바인딩)은 애드온 폴더에서 자동으로 읽힙니다.

## 4. 실제 클라이언트에서 확인해야 할 항목

1. `select(4, GetBuildInfo())` 값이 16001 인지 (다르면 TOC 수정)
2. 거래 완료 시 `UI_INFO_MESSAGE` 로 `ERR_TRADE_COMPLETE` 가 오는지, `TRADE_CLOSED` 와의 순서
3. 거래 취소 시 메시지 종류(`ERR_TRADE_CANCELLED`)
4. `UnitName("NPC")` 가 거래 상대 이름을 주는지 (다른 서버 캐릭터 포함)
5. `C_ChatInfo.InChatMessagingLockdown` 동작 범위 (우두머리 전투 중만인지, 인스턴스 전체인지)
6. 우두머리 전투 밖 공격대 채팅이 Secret 이 아닌지 (채팅 입찰 인식)
7. `C_UnitAuras.GetAuraDataByIndex` 로 다른 공대원 버프를 전투 밖에서 읽을 수 있는지, 주문 ID/이름
8. 야영지 버프의 실제 이름 (기본 데이터는 영어 이름/비공식 한글 번역)
9. 보안 징표 버튼 한 번 클릭 = 한 번 동작
10. `C_PartyInfo.DoCountdown` 사용 가능 여부
11. `ENCOUNTER_START/END` 의 encounterID/이름 제공 여부 (보스 이름 자동 갱신)
12. `RANDOM_ROLL_RESULT` 한국어 문자열 형식
13. 도핑 버프(음식/영약/비약)의 실제 이름과 주문 ID (전투 준비 점검은 오리지널 ID + 한국어/영어 키워드 사용)

> 구성 분석·추천 직업(1.1.0)은 게임 API 를 추가로 사용하지 않고, 공대원 직업(`GetRaidRosterInfo`)과 애드온에서 지정한 역할만으로 계산합니다.
> 시너지 데이터(`Data/Synergy.lua`)는 오리지널 기준이라 포에버의 직업 변경 사항은 목표 구성/사용 불가 직업 설정으로 보정합니다.

## 5. 출처

조사는 2026-11-03 웹 검색 결과 요약을 바탕으로 했습니다. (일부 사이트는 개발 환경 네트워크 정책으로 원문을 직접 열지 못했습니다)
- Warcraft Wiki – TOC format: https://warcraft.wiki.gg/wiki/TOC_format
- Warcraft Wiki – Secret Values: https://warcraft.wiki.gg/wiki/Secret_Values
- Warcraft Wiki – Patch 12.0.0 Planned API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes
- Warcraft Wiki – Patch 12.0.5 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes
- Warcraft Wiki – Patch 12.0.7 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.7/API_changes
- Warcraft Wiki – API SetRaidTarget: https://warcraft.wiki.gg/wiki/API_SetRaidTarget
- ForeverMeta – WoW Forever addons and UI: https://forevermeta.me/en/guides/wow-forever-addons-interface
- WoW Forever Tier List – Addon Restrictions: https://wowforevertierlist.com/addons/restrictions
- Method – WoW Forever Raids: https://www.method.gg/wow-forever/wow-forever-raids-a-look-at-barrow-deeps-hyjal-summit-and-onyxias-lair
- Icy Veins – WoW Forever Camping: https://www.icy-veins.com/wow-forever/camping
- Inven Global – WoW Forever bans GDKP: https://www.invenglobal.com/articles/26259/wow-forever-bans-gdkp-runs
- Master of Warcraft – GDKP ban NA/EU only: https://www.masterofwarcraft.net/2026/10/wow-forever-gdkp-ban-na-eu-only.html
