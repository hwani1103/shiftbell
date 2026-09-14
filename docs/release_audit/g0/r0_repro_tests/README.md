# R0-T — R0 재현 테스트 초안

작성일: 2026-09-14  
기준: `release/g0` `c06ffea`  
대상 발견: `docs/release_audit/g0/review_codex.md` R0-01~R0-04

이 디렉터리는 **실행하지 않은 Flutter 테스트 초안**이다. `shiftbell-g0`의 제품 파일은 `git show c06ffea:<path>`로 읽었고 수정하지 않았다. 병행 예외 조건에 따라 빌드, 테스트, `pub get`, `analyze`, 에뮬레이터를 실행하지 않았으며 `task_board.md`, `contracts.md`, 제품 코드도 수정하지 않았다.

기존 `test/release_audit/g0/g0_support.dart`의 실제 SQLite FFI 방식과 `startup_gate_test.dart`의 주입 가능한 초기화 Future·가상 시간 방식을 따랐다. 구현을 테스트 안에 복사하지 않고 `DatabaseService.instance.database`와 `StartupGate` 공개 진입점을 호출한다.

## 파일과 현재 실패 지점

| 파일 | 발견 | `c06ffea`의 실패 이유 | 수정 후 통과 조건 |
|---|---|---|---|
| `r0_01_device_protected_path_test.dart` | R0-01 | MethodChannel 오류를 삼키고 일반 DB를 만들어 두 호출이 성공함 | 경로 조회 실패가 DB open 성공으로 바뀌지 않고, 일반 경로 DB도 생성하지 않음 |
| `r0_02_startup_timeout_test.dart` | R0-02 | 완료되지 않는 필수 Future가 30초 뒤에도 `slow`이며 재시도 버튼이 없음 | 유한한 상한 뒤 실패/복구 상태가 되고, 재시도는 새 시도 한 번만 실행 |
| `r0_03_preset_repair_test.dart` | R0-03 | 첫 프리셋만 커밋된 뒤 재시도에서 `presetCount > 0`으로 2·3을 건너뜀 | 부분 실패 뒤 재시도하면 필수 프리셋 ID 1·2·3이 모두 존재 |
| `r0_04_database_init_error_test.dart` | R0-04 | 첫 호출자가 받은 오류 외에 구독자 없는 Completer 오류가 Zone으로 한 번 더 전달됨 | 호출자가 오류를 한 번 받고 Zone 미처리 오류는 0개 |

각 `.dart` 파일 머리에는 요청한 **수정 전 기대 결과(FAIL 이유)**와 **수정 후 기대 결과**를 주석으로 적었다.

## 주입 지점 판단

- R0-01: 기존 `kAlarmChannel`의 테스트 messenger와 FFI `setDatabasesPath`로 충분하다. 새 제품 주입 지점이 필요하지 않다.
- R0-02: `StartupGate.initialize`는 이미 주입 가능하지만 **복구 timeout 값은 주입할 수 없다**. 초안은 가상 시간 30초 안에 복구 상태가 되어야 한다는 외부 동작만 검사한다. 수정안의 정책 시간이 더 길다면 `StartupGate`에 `requiredTimeout` 같은 테스트 가능한 `Duration`을 추가하고 이 테스트에서 짧게 주입해야 한다. Timer 자체나 내부 State를 공개할 필요는 없다.
- R0-03: 별도 제품 주입 지점 없이 SQLite trigger로 두 번째 프리셋 insert만 실패시킨다. trigger를 제거한 뒤 같은 공개 DB getter를 다시 호출하므로 실제 재시도 동작을 본다.
- R0-04: 별도 제품 주입 지점 없이 `user_version=25` 임시 DB로 확정적인 초기화 오류를 만들고 `runZonedGuarded`로 이중 오류만 관찰한다.

## 후속 배치와 실행

Claude가 수정 코드를 다시 동결한 뒤 이 초안을 `test/release_audit/g0/`로 옮기거나 테스트 경로에 포함시켜 검토한다. 상대 import `../../../../test/release_audit/g0/g0_support.dart`는 현재 문서 위치에서 직접 실행할 때의 경로다. 테스트 디렉터리로 옮기면 import를 `g0_support.dart`로 바꾼다.

실행 시 네 파일은 각각 별도 테스트 라이브러리로 유지한다. `DatabaseService`가 프로세스 전역 singleton이므로 여러 재현을 한 파일에 합쳐 순서 의존성을 만들지 않는다. 먼저 `c06ffea`에서 의도한 실패 지점을 확인하고, 수정 SHA에서 같은 assertion이 통과하는지 비교하되 결과 기록은 실제 실행 뒤에만 PASS/FAIL로 갱신한다.

