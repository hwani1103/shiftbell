# DB 스키마 변경 가이드

현재 스키마 버전: **v24**

> **2026-09-14 구조 변경 (G0, `출시전_코드감사_검토결과_v4` #1/#8/#31)**
> 이제 **Native(Kotlin)도 직접 마이그레이션한다.** 버전별 SQL은 `assets/db/migrations.json`
> **하나에만** 있고 Dart·Kotlin이 같은 실행기 규칙으로 실행한다. 스키마를 바꿀 때는 §4 절차를 따를 것.
> §2는 v23까지의 구조에서 생긴 사고 기록이다(원인을 이해하는 데 필요해서 남겨둠).

이 앱은 **Flutter(sqflite)와 Kotlin(SQLiteOpenHelper)이 같은 SQLite 파일을 각자 연다**.
그래서 스키마 변경이 다른 앱보다 까다롭고, 실제로 같은 실수가 세 번 재발해서
"알람이 안 보이고 위젯이 안 되는" 증상을 만들었다. 이 문서는 그 전말과 절차를 정리한다.

---

## 1. 언제 스키마를 바꾸나

**앱을 껐다 켜도 남아야 하는 새 데이터를 저장할 때만.**

| 바꿔야 함 | 바꿀 필요 없음 |
|---|---|
| 새 테이블이 필요하다 (메모 기능 → `date_memos`) | 화면 배치·색상·문구 변경 |
| 기존 테이블에 새 칸이 필요하다 (`shift_schedule.custom_shift_colors`) | 계산 로직 변경 |
| 기존 칸의 의미/타입이 바뀐다 | 이미 있는 칸을 새로운 방식으로 읽기만 함 |
| 인덱스를 추가/제거한다 | 설정값 저장 (→ SharedPreferences로 충분한 경우) |

애매하면 기준은 하나다: **`CREATE TABLE` / `ALTER TABLE`을 써야 하나?** 아니라면 버전은 그대로.

---

## 2. (v23까지) 왜 위험했나 — 실제로 세 번 터진 버그

### 구조 (v23까지)

Native 코드 파일(`AlarmActivity`, `AlarmOverlayService`, `AlarmRefreshEngine`,
`CalendarWidgetScheduleResolver`, `AlarmGuardReceiver`, `CustomAlarmReceiver`,
`DirectBootReceiver`, `AlarmPlayer`, `AlarmActionHelper`, 수면/일정 알림 쪽)이 전부
`DatabaseHelper.getReadableDatabaseWithRetry()` / `getWritableDatabaseWithRetry()`라는
**게이트 하나**를 통과해야 DB를 읽고 쓴다.

v23까지 그 게이트는 `isDatabaseReady()`에서 다음을 확인했다:

```
디스크 DB 파일의 실제 버전 == DatabaseHelper.kt의 DATABASE_VERSION
```

**정확히 같을 때만** 열렸다. 당시 Native의 `onUpgrade`는 빈 함수였고, `SQLiteOpenHelper`는
`onUpgrade`가 비어 있어도 `db.setVersion()`을 실행해 **실제 마이그레이션 없이 버전만 최신으로
찍어버리기** 때문에 생긴 안전장치였다.

### 사고

Flutter 쪽 `database_service.dart`의 `version:`만 올리고 Kotlin 쪽
`DatabaseHelper.kt`의 `DATABASE_VERSION`을 안 올리면, 두 값이 어긋난다.
Flutter가 DB를 한 번이라도 열어 파일을 새 버전으로 올린 순간부터 게이트는 **영구히 닫힌다.**

그런데 게이트가 닫혀도 **예외가 나거나 앱이 죽지 않는다.** 호출부들은 조용히 `null`을 받고
그냥 `return`한다. Flutter는 자기 sqflite 연결을 쓰므로 멀쩡히 동작한다.
**앱 화면은 정상인데 Native 기능만 전부 죽는다** — 그래서 원인 짐작이 거의 불가능하다.

그리고 상수가 맞아도 이 구조 자체가 **출시 전 감사 C01**의 원인이었다: 업데이트 후 사용자가
앱을 다시 열지 않으면(또는 잠금 해제 전에 재부팅하면) Flutter가 마이그레이션을 못 하므로 Native가
DB를 전혀 못 써서, 알람 재생 설정·스누즈·이력·10일치 갱신이 앱을 열 때까지 망가졌다.
→ 2026-09-14에 §3-1 구조로 교체.

### 증상 대조표

이런 증상이 보이면 **제일 먼저 버전 상수 세 곳부터 확인할 것** (§3).

| 증상 | 실제로 일어난 일 |
|---|---|
| 홈 위젯이 스케줄 유무와 무관하게 항상 "근무 스케줄을 먼저 설정해주세요" | `CalendarWidgetScheduleResolver.readSchedule()`이 null → "스케줄 없음"으로 판단 |
| 알람은 정상적으로 울리는데 화면의 **시각이 빈칸** | `AlarmActivity` / `AlarmOverlayService`가 early return, 시간 문자열이 초기값 `""` 그대로 |
| 설정에서 "고정 알람 수정"을 저장해도 알람이 안 바뀜 | `AlarmRefreshEngine.doRefresh()`가 `"⚠️ DB 파일 없음 - 갱신 중단"` 로그만 남기고 no-op |
| 달력에서 근무를 길게 눌러 재배정하면 "되는" 것처럼 보임 | 그 경로만 Dart가 sqflite로 직접 쓰기 때문 — 게이트를 안 거침. **오진 유발 주의** |
| 자정이 지나도, 앱을 열어도 10일치 알람이 안 늘어남 | 위와 같은 `AlarmRefreshEngine` no-op |

v24부터는 같은 증상이 보이면 logcat의 `DatabaseHelper`/`DbMigrationRunner` 태그에서
마이그레이션 실패(`❌`, 예외) 또는 `⏭️ 디스크 DB(vN)가 Native(vM)보다 높음` 로그를 먼저 확인한다.

### 재발 이력

| 시점 | 버전 | 계기 |
|---|---|---|
| — | Kotlin 13 / Flutter 14 | 최초 발견 |
| 2026-08-12 | Kotlin 15 / Flutter 16 | 친구공유 커밋(`friends` 테이블 추가) — 위젯이 죽음 |
| 2026-08-20 | Kotlin 17 / Flutter 18 | 근무명 색상 복원(`custom_shift_colors`) — 위젯 + 알람화면 + 고정알람수정이 한꺼번에 |

세 번째에 "다음엔 안 잊어버리기"로는 못 막는다고 판단해서 빌드 가드를 넣었다.

---

## 3. 빌드가 막아주는 것

`android/app/build.gradle.kts`의 `checkDartKotlinSync` 태스크가 값들을 정규식으로
직접 읽어 비교하고, 다르면 `GradleException`으로 **빌드를 실패시킨다.**
모든 variant의 `pre*Build`에 `dependsOn`으로 걸려 있어서, 값이 어긋난 APK/AAB는 애초에
만들어지지 않는다.

현재 검사하는 쌍:

| 값 | Kotlin | 비교 대상 |
|---|---|---|
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` | `database_service.dart` `version:` |
| DB SQL 원본 목표 버전 (2026-09-14) | `DatabaseHelper.kt` `DATABASE_VERSION` | `assets/db/migrations.json` `"targetVersion"` |
| 알람 갱신 윈도우(일) | `AlarmRefreshEngine.kt` `DAYS_AHEAD` | `alarm_limits.dart` `kAlarmRefreshWindowDays` |

수동 확인:

```bash
cd android && ./gradlew :app:checkDartKotlinSync
```

**한계 — 이건 알아둘 것:**
- Gradle 빌드를 거칠 때만 작동한다. Dart 코드만 고치고 **hot reload**로 확인하는 중이면
  안 걸린다. 스키마를 바꿨으면 반드시 한 번은 전체 빌드를 돌릴 것.
- 정규식으로 값을 뽑으므로, 해당 코드를 리팩토링해서 형태가 바뀌면 "패턴에 맞는 값을 못
  찾음"으로 빌드가 실패한다. 그럴 땐 `checkPair()`의 정규식도 같이 고쳐야 한다.
- 버전 숫자만 검사한다. `migrations.json`에 그 버전의 SQL이 실제로 들어 있는지·`repair`와
  `_onCreate`가 같은 최종 형태인지는 **테스트**로 확인해야 한다(§4-3).
- **Dart/Kotlin 양쪽에 각각 하드코딩되는 상수 쌍을 새로 만들면 `checkPair()` 호출을 하나
  더 추가할 것.** 주석으로 "맞춰야 함"이라고 적어두는 건 이미 세 번 실패한 방법이다.

### 3-1. 현재 구조 (v24~)

**SQL 단일 원본:** `assets/db/migrations.json` (`pubspec.yaml` assets에 등록 — 빠지면 Native 마이그레이션이 전부 실패)

| 구역 | 내용 | 실행 시점 |
|---|---|---|
| `migrations` | 버전별 증분 SQL (v2~최신 전 구간, 파괴적 SQL 포함 가능) | 업그레이드할 때 `oldVersion` 다음부터 목표까지 순서대로 |
| `repair` | 최신 스키마의 **비파괴** 최종 형태 | DB를 열 때마다 — 없는 테이블/컬럼/인덱스만 채움 |

**실행기 (두 언어가 같은 규칙):** `lib/services/db_migration_runner.dart` ↔ `DbMigrationRunner.kt`
- 한 항목 = SQL 한 문장 (`;` 금지 — Android `execSQL`은 첫 문장만 실행하고 나머지를 조용히 버림)
- `ALTER TABLE t ADD COLUMN c`는 `PRAGMA table_info`로 컬럼이 **실제로 있을 때만** 건너뜀
- 그 외 SQL 실패는 **던진다** → 호출자의 트랜잭션이 버전 갱신까지 함께 롤백 → 다음 접근 때 재시도
- `repair`는 `CREATE TABLE IF NOT EXISTS` / `CREATE [UNIQUE] INDEX IF NOT EXISTS` /
  `ALTER TABLE ... ADD COLUMN` 세 가지만 허용. 다른 문이 있으면 **아무것도 실행하지 않고** 오류.
  `CREATE TABLE`이 먼저 와야 하고, 인덱스/ALTER 대상 테이블의 `CREATE TABLE`이 반드시 있어야 함.
  과거 마이그레이션을 재실행하지 않는 이유: v17의 `DROP TABLE friends`, v8~v11의 `UPDATE`

**Native (`DatabaseHelper.kt`) 게이트:**

| 디스크 상태 | 동작 |
|---|---|
| 파일 없음 | 스킵 (신규 설치 생성은 Flutter 전담) |
| `user_version = 0` | 스킵 (Flutter가 생성 중이거나 비정상 파일) |
| 디스크 < Native | 열면서 `onUpgrade`가 마이그레이션 (잠금 해제 전 부팅·알람 수신 등 **첫 Native 접근 어디서든**) |
| 디스크 == Native | 진행 (`onOpen`에서 repair) |
| 디스크 > Native | 스킵 (다운그레이드 방지) |
| 버전 확인 실패 | 최신이라 가정하지 않고 헬퍼 open에 맡김 (낮으면 마이그레이션, 0/높음이면 예외) |

- `onCreate` / `onDowngrade`는 **예외** — 버전만 찍히는 경로 차단
- `SQLiteOpenHelper`는 버전을 쓰기 잠금 밖에서 읽으므로 `onUpgrade` 안에서 버전을 다시 읽고,
  그사이 Flutter가 이미 올렸으면 건너뜀. (sqflite는 스스로 잠금 안에서 다시 읽음)
- `onOpen`에서 SQL 원본 자체를 못 읽으면 repair만 건너뛰고 DB는 계속 씀(알람 재생을 막지 않기 위해)

**Dart (`database_service.dart`):** `onCreate`=신규 설치(`_onCreate`, 이 파일에 직접 작성),
`onUpgrade`=공통 실행기, `onDowngrade`=예외, `onOpen`=repair + 프리셋 알람 타입이 비었으면 재삽입.
SQL 원본을 못 읽거나 마이그레이션이 실패하면 예외가 앱 시작 게이트(`lib/screens/startup_gate.dart`)까지
올라가 시작 실패 화면 + 다시 시도가 표시된다.

---

## 4. 변경 절차

### 4-1. 한 커밋 안에서 같이 할 것

1. **`assets/db/migrations.json`**
   - `migrations` 맨 끝에 `{"version": N, "note": "...", "sql": ["...", "..."]}` 추가
   - `repair`에 최종 형태 반영
     - 새 테이블 → `CREATE TABLE IF NOT EXISTS 최종형` (다른 CREATE TABLE들과 같은 구역, 인덱스/ALTER보다 앞)
     - 기존 테이블에 새 컬럼 → 그 테이블의 `CREATE TABLE IF NOT EXISTS` 최종형을 고치고 + `ALTER TABLE t ADD COLUMN ...` 항목 추가
     - 새 인덱스 → `CREATE INDEX IF NOT EXISTS ...`
   - `"targetVersion": N`
2. **`lib/services/database_service.dart`**
   - `version:` → N
   - `_onCreate()`에 같은 최종 형태 추가 (반드시 `CREATE TABLE IF NOT EXISTS`)
3. **`android/app/src/main/kotlin/com/hwani1103/shiftbell/DatabaseHelper.kt`**
   - `DATABASE_VERSION` → N
   - Native가 그 컬럼/테이블을 읽어야 한다면 읽는 코드도 여기서 같이
4. **`CLAUDE.md`**의 DB 스키마 절, 이 문서의 맨 위 "현재 스키마 버전"과 §5도 갱신

### 4-2. 지켜야 할 규칙

- **`migrations`의 기존 항목은 절대 수정/삭제하지 말 것.** 아주 오래된 버전(스토어에 나간 v12 등)에서
  올라오는 사용자가 이 사슬을 전부 통과한다.
- **`_onCreate`, `migrations`, `repair` 세 곳을 다 고칠 것.** `_onCreate`는 신규 설치용,
  `migrations`는 기존 사용자용, `repair`는 컬럼이 빠진 DB 복구용이다. 하나만 고치면 그쪽 사용자만 깨진다 —
  보통 개발 중엔 신규 설치로 테스트하니까 **기존 사용자 쪽이 조용히 깨진다.**
- **ALTER를 try/catch로 감싸지 말 것.** 실행기가 실제 컬럼 존재를 확인한다. 예전처럼 모든 예외를
  "이미 있을 수 있음"으로 삼키면 버전만 최신이고 컬럼은 없는 DB가 생긴다(감사 H16).
- **`NOT NULL` 컬럼을 추가하면 `DEFAULT`를 반드시 줄 것** (SQLite 제약).
- **한 항목에 SQL 한 문장.** 세미콜론으로 여러 문장을 넣으면 실행기가 거부한다.
- **Dart 로직이 필요한 데이터 변환(기존 값을 읽어 가공)은 이 구조로 표현할 수 없다.** 그런 변경이
  필요해지면 Native가 먼저 여는 경로까지 포함해 별도로 설계할 것.
- **컬럼 삭제/이름 변경은 하지 말 것.** SQLite가 제대로 지원하지 않고, 테이블 재생성
  경로는 이 앱의 Native/Flutter 이중 접근 구조에서 특히 위험하다. 안 쓰는 컬럼은 그냥 두자.
- **`alarm_history` / `alarm_creation_log`는 마이그레이션에서도 건드리지 말 것.**
  영구 보존 테이블이다.

### 4-3. 검증

```bash
flutter analyze
cd android && ./gradlew :app:checkDartKotlinSync    # 버전 3쌍 일치 확인
./gradlew :app:testDevDebugUnitTest                 # 마이그레이션 fixture 테스트 (docs/release_audit/g0 참고)
cd .. && flutter install --release --flavor dev     # ⚠️ 반드시 --flavor dev
```

**테스트로 확인할 것:**
- 스토어에 나간 버전(v12·v14·v15·v17·v18)과 직전 버전에서 올린 결과 == `_onCreate`로 새로 만든 DB
  (`PRAGMA table_info`뿐 아니라 인덱스·제약까지)
- 중간 SQL 실패 시 버전·스키마가 함께 롤백되는지
- 컬럼이 빠진 최신 버전 DB를 repair가 채우고 `friends` 등 기존 데이터가 그대로인지

**기기에서 확인할 것 (신규 설치만으로는 부족하다):**

1. **업그레이드 경로** — 기존 데이터가 있는 dev 앱을 지우지 말고 그 위에 덮어 설치.
   근무표·알람·메모가 그대로 남아 있는지 확인. (신규 설치는 `_onCreate`만 타므로
   업그레이드 버그를 절대 못 잡는다)
2. **앱을 열지 않은 채 Native가 먼저 여는 경우** — 덮어 설치 후 앱을 실행하지 말고 재부팅(잠금 해제 전
   포함) 또는 알람 수신까지 기다린 뒤 logcat 확인:
   ```
   adb logcat -s DatabaseHelper DbMigrationRunner
   ```
   `🔧 Native 마이그레이션 시작 vA → vB` → `✅ Native 마이그레이션 완료` 가 나와야 정상.
3. **홈 위젯** — 위젯을 새로 추가해서 근무/색상이 제대로 나오는지.
4. **알람 갱신** — 설정에서 고정 알람을 하나 추가하고 저장한 뒤 `AlarmRefreshEngine` 로그에서
   `✅ diff 갱신 완료: +N -M` 확인.
5. **알람 화면** — 알람이 실제로 울릴 때 **시각이 빈칸이 아닌지**.

---

## 5. 현재 스키마 (v24)

| 테이블 | 용도 |
|---|---|
| `shift_schedule` | 근무 패턴/시작일/근무명/색상 (v18에서 `custom_shift_colors` 추가) |
| `shift_alarm_templates` | 근무별 고정 알람 템플릿 (근무당 최대 5개) |
| `alarms` | 실제 등록된 알람 (10일치 롤링) |
| `alarm_types` | 알람 타입 프리셋 (소리/볼륨/진동/지속시간) |
| `alarm_history` | 알람 이력 — **영구 보존, 자동 삭제 금지** |
| `alarm_creation_log` | 알람 생성 로그 — **영구 보존, 자동 삭제 금지** |
| `alarm_overrides` | 개별 알람 예외(v24 신규) - 템플릿으로 생성된 알람 하나의 삭제(`skip`)·타입 변경(`set_type`)을 원본으로 저장해 자동 갱신이 원복하지 않게 함. 슬롯 키 `(slot_time, shift_type, day_offset)` UNIQUE |
| `date_memos` | 날짜별 메모(달력 탭) |
| `date_schedules` | 일정관리 탭 전용 (v20 신규 - `date_memos`와 완전히 별개 CRUD, v23에서 `notify_enabled`/`notify_offset_minutes` 추가 - Native가 재부팅 재예약을 위해 직접 읽음) |
| `date_overtime` | 날짜별 OT/특근 |
| `friends` | 친구 공유 (v17에서 Firestore `ownerId` 기반으로 재설계) |
| `condition_shift_times` | 컨디션 매니저 전용(v21 신규) - 근무명별 출퇴근 시각. 알람/근무패턴 로직은 안 읽음 |
| `sleep_records` | 실제 수면 기록/자동 추정 전용(v22 신규) - 수동/자동 감지된 수면 1건씩. Native(SleepDetectionReceiver.kt/SleepWidgetActionReceiver.kt)가 직접 읽고 씀 |
| `sleep_expected_bedtime` | 실제 수면 기록 전용(v22 신규) - 근무별(또는 휴무) 평균 취침 시각. 입력 기능은 2026-09-01 삭제, 빈 테이블로 스키마만 유지 |

### 최근 변경

- **v16** — `friends` 테이블 추가 (친구공유)
- **v17** — `friends`를 Firestore `ownerId` 기반으로 재설계
- **v18** — `shift_schedule.custom_shift_colors` 추가 (근무명 색상 직접 지정)
- **v19** — `shift_alarm_templates`/`alarms`/`alarm_history`/`alarm_creation_log`에
  `day_offset`(INTEGER, 기본값 0) 추가 - 고정 알람을 근무 배정일 기준 전날(-1)/
  당일(0)/다음날(+1)로 등록하는 기능
- **v20** — `date_schedules` 테이블 신설(일정관리 탭 영구 저장).
  `predicted_category`/`is_user_corrected` 컬럼은 메모_자동분류_ML_계획.md
  Phase 5의 카테고리 자동배정 결과 기록용.
- **v21** — `condition_shift_times` 테이블 신설(컨디션 매니저 1차 버전 -
  컨디션매니저_설계.md 참고). Native는 이 테이블을 전혀 읽지 않음.
- **v22** — `sleep_records`/`sleep_expected_bedtime` 테이블 신설(실제 수면 기록/
  자동 추정 - 수면기록_자동추정_설계.md 참고). Native가 직접 읽고 씀.
- **(되돌려짐) v23 시도(1차)** — `date_schedules.slot_minutes` 컬럼을 추가하려 했으나
  `start_minutes`만으로 항상 계산 가능한 파생값으로 정정되어 되돌림(`lib/models/date_schedule.dart`의
  `computeSlotMinutes()` 참고).
- **v23(2026-09-12)** — `date_schedules`에 `notify_enabled INTEGER NOT NULL
  DEFAULT 0`/`notify_offset_minutes INTEGER NOT NULL DEFAULT 0` 추가. 일정관리
  탭 "일정에 맞춰서 알림받기" 실제 구현. Native(`ScheduleNotificationScheduler.kt`)가
  재부팅 직후 `date_schedules`를 조회해서 재예약함.
- **v24(2026-09-14)** — `alarm_overrides` 테이블 신설(개별 알람 예외, 출시전 감사 #31·D10).
  컬럼: `slot_time`(`yyyy-MM-dd'T'HH:mm:ss`, Locale.US, 초 00), `shift_type`, `day_offset`(-1/0/1),
  `action`(`skip`/`set_type`), `alarm_type_id`(`set_type`일 때만), `origin_date`, `origin_shift`, `created_at`.
  인덱스 `origin_date`, `origin_shift`. **같은 변경에서 마이그레이션 구조 자체를 교체**(§3-1) —
  옛 `_onUpgrade`의 SQL은 `migrations.json`으로 옮김. 예외를 읽고 쓰는 동작은 G1(#31)에서 구현.

---

## 6. 참고

- 실행기 규칙: `lib/services/db_migration_runner.dart` / `DbMigrationRunner.kt` 상단 주석
- 게이트와 사고 맥락: `DatabaseHelper.kt` 상단 주석 (`DATABASE_VERSION` 선언부와 `onUpgrade` /
  `databaseFileExists()` / `onDiskVersion()` / `isDatabaseReady()` 주석)
- 빌드 가드 구현: `android/app/build.gradle.kts`의 `checkDartKotlinSync`
- 설계 근거: `출시전_코드감사_검토결과_v4_2026-09-13.md` #1·#8·#31, 공통 계약 `docs/release_audit/contracts.md`
- **다운그레이드:** Dart(`onDowngrade`)와 Native(`onDowngrade`) 모두 예외를 던진다. 즉 **더 낮은
  버전의 앱을 덮어 설치하면 앱은 시작 실패 화면, Native DB 접근은 스킵**된다. Play Store 정상 업데이트
  경로에서는 일어나지 않지만, 개발 중 구버전 APK를 수동 설치할 때는 주의할 것. (v23까지 문서에는
  "DB 열기가 실패한다"고 적혀 있었으나, 실제로는 sqflite가 버전을 조용히 낮게 찍었다)
