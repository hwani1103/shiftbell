# R0 — G0 교차 리뷰 (Codex)

작성일: 2026-09-14  
대상: `release/g0`, `git diff dafe06b c06ffea` (`c06ffea` HEAD 확인)  
근거: `출시전_코드감사_검토결과_v4_2026-09-13.md` #1·#8·#31·V4, `출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md` G0 및 회귀 금지 규칙

이 문서는 코드 수정 없는 교차 리뷰 결과다. 병행 예외 조건에 따라 빌드, 테스트, `pub get`, `analyze`, 에뮬레이터 실행은 하지 않았다.

## 발견 사항

### R0-01 — High — Device Protected 경로 조회 실패가 별도 DB로 조용히 전환된다

- **위치:** `lib/services/database_service.dart:50-57`
- **조건:** Android 7 이상에서 `getDeviceProtectedStoragePath` MethodChannel 호출이 일시적으로 `PlatformException` 또는 `MissingPluginException`을 던진다.
- **재현:** 해당 호출이 예외를 던지게 한 뒤 앱을 시작한다. catch가 예외를 성공 경로로 바꾸고 `getDatabasesPath()/shiftbell.db`를 연다. Native의 `DatabaseHelper`는 계속 Device Protected Storage의 `shiftbell.db`를 연다.
- **결과:** Dart와 Native가 서로 다른 DB를 사용한다. Dart 쪽은 빈 신규 DB를 만들 수 있어 기존 근무표·알람이 사라진 것처럼 보이고, Native 알람 수신·스누즈·위젯은 옛 DB를 계속 사용한다. 이후 경로 조회가 회복되어도 이미 두 DB가 갈라져 있다.
- **대조:** #1은 Dart와 모든 Native 진입점이 같은 DB를 열어 마이그레이션하는 것이 전제다. V4는 필수 DB 초기화 실패를 시작 실패 화면과 재시도로 드러내도록 요구한다. 현재 catch는 필수 경로 결정 실패를 숨기므로 두 요구를 모두 우회한다.

### R0-02 — High — 필수 초기화가 끝나지 않으면 재시도할 수 없는 영구 대기 화면이 된다

- **위치:** `lib/screens/startup_gate.dart:74-91`, `lib/main.dart:142-146`
- **조건:** 날짜 포맷 초기화, DB open/migration 또는 알람 초기화 Future가 예외 없이 끝나지 않는다. DB 잠금이나 플랫폼 호출 정지가 한 예다.
- **재현:** `StartupGate.initialize`가 완료되지 않는 Future를 반환하게 한다. `slowThreshold`가 지나면 `_phase`는 `slow`가 되지만 Future에는 timeout이 없고, slow 화면에는 재시도 버튼도 없다.
- **결과:** 앱은 무기한 진행 표시만 보이며 사용자가 초기화를 다시 시작할 수 없다. 실패 Future만 `failed` 상태와 재시도 버튼으로 이어진다.
- **대조:** V4와 실행계획 G0는 필수 초기화의 **실패·지연** 모두에 대해 영구 시작 정지를 막고 재시도 경로를 검증하도록 요구한다. 현재 구현은 지연을 표시할 뿐 복구하지 않는다.

### R0-03 — Medium — 프리셋 복구가 부분 커밋되면 이후 재시도가 누락 행을 복구하지 않는다

- **위치:** `lib/services/database_service.dart:86-95`
- **조건:** `alarm_types`에 프리셋이 하나도 없는 v24 DB를 열고, 세 프리셋을 순차 삽입하는 도중 저장공간 부족 등으로 두 번째 또는 세 번째 insert가 실패한다.
- **재현:** 첫 insert 성공 직후 다음 insert가 실패하도록 주입한다. 첫 insert는 별도 트랜잭션 없이 커밋되고 open은 실패한다. 공간 확보 후 다시 열면 `presetCount > 0`이므로 함수가 즉시 반환한다.
- **결과:** 일부 프리셋만 남은 DB가 정상 open으로 승인된다. 누락된 타입을 참조하는 알람의 표시·재생 설정 조회가 계속 실패하거나 폴백으로 바뀔 수 있다.
- **대조:** #8은 실패를 숨기지 않고 다음 open에서 완성 가능한 상태로 롤백·재시도하도록 요구한다. 복구 insert 전체를 한 트랜잭션으로 묶거나 각 필수 ID를 독립 확인하지 않아 이 성질을 만족하지 못한다.

### R0-04 — Medium — 첫 DB 초기화 실패가 처리된 Future와 별도로 미처리 오류를 만든다

- **위치:** `lib/services/database_service.dart:28-44`
- **조건:** 동시 호출자가 없는 첫 `DatabaseService.instance.database` 호출에서 `_initDatabase()`가 실패한다.
- **재현:** DB open이 예외를 던지게 하고 한 호출자만 getter를 await한다. catch는 호출자에게 예외를 다시 던지는 동시에, 아무도 구독하지 않은 `_initCompleter.future`도 `completeError`로 끝낸다. finally에서 completer 참조까지 지운다.
- **결과:** `StartupGate`가 바깥 Future의 오류를 처리해 실패 화면을 그려도, 내부 Completer 오류는 별도의 미처리 비동기 오류로 Zone에 전달될 수 있다. 실패 화면·재시도라는 V4 처리 경로 밖으로 같은 오류가 한 번 더 샌다.
- **대조:** V4는 필수 초기화 오류를 게이트가 소유해 실패 UI와 재시도로 수렴시키도록 요구한다. 최초 호출자도 공유 Future 자체를 기다리게 하거나, 구독자 없는 Completer에 오류를 완료하지 않아야 한다.

## 요구별 대조 결과

| 요구 | 정적 대조 결과 |
|---|---|
| #1 Native 선행 마이그레이션 | v1~v24 순차 SQL, Native `onCreate`/`onDowngrade` 예외, 잠금 안 버전 재확인, 버전 확인 실패의 최신 간주 제거는 구현됨. R0-01의 Dart 경로 분기 때문에 공통 DB 전제는 완결되지 않음. |
| #8 실패 전파·비파괴 repair | ALTER 전 컬럼 확인, 실행 오류 재전파, repair 트랜잭션과 화이트리스트가 구현됨. 과거 v17 `DROP friends`와 v8~v11 `UPDATE`는 repair에 없음. R0-03의 프리셋 후처리는 같은 재시도 성질을 갖지 않음. |
| #31 v24 스키마 | `alarm_overrides`의 슬롯 UNIQUE 키, `day_offset`/`action`/action별 `alarm_type_id` CHECK, origin 컬럼과 두 인덱스가 `_onCreate`, v24 migration, repair에 일치함. G1 실행 로직은 G0 범위 밖임. |
| V4 시작 복구 | `runApp` 뒤 게이트, throw 시 실패 화면·재시도, release 예외 원문 비노출, 선택 초기화 오류 처리는 구현됨. R0-01·R0-02·R0-04가 남음. |
| G0 회귀 금지 | repair에서 과거 파괴 SQL 재실행 없음, Native 신규 DB 생성 없음, SQL 자산의 release/잠금 해제 전 접근을 자동 테스트로 PASS 처리하지 않음. |

## 판정에서 제외한 알려진 위험

- `user_version=24`인데 v16 형태의 `friends` 테이블이 남은 `REPAIR-REJECT`는 사용자 결정 A로 수용된 위험이므로 새 발견으로 중복 보고하지 않았다.
- release 자산 접근, 잠금 해제 전 부팅, 앱 미실행 울림, Dart/Native 동시 open은 실행 증적이 필요한 항목이다. 이번 R0에서는 금지 조건에 따라 실행 판정을 추가하지 않았다.

## 결론

**CHANGES_REQUESTED.** #31 스키마와 공통 migration/repair 뼈대는 계약과 맞지만, V4 필수 초기화 복구와 공통 DB 경로에 High 2건, 실패 재시도 정합성에 Medium 2건이 남아 있다.
