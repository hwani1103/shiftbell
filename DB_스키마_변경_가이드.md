# DB 스키마 변경 가이드

현재 스키마 버전: **v20**

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

## 2. 왜 위험했나 — 실제로 세 번 터진 버그

### 구조

Native 코드 10개 파일(`AlarmActivity`, `AlarmOverlayService`, `AlarmRefreshEngine`,
`CalendarWidgetScheduleResolver`, `AlarmGuardReceiver`, `CustomAlarmReceiver`,
`DirectBootReceiver`, `AlarmPlayer`, `AlarmActionHelper`)이 전부
`DatabaseHelper.getReadableDatabaseWithRetry()` / `getWritableDatabaseWithRetry()`라는
**게이트 하나**를 통과해야 DB를 읽고 쓴다.

그 게이트는 `isDatabaseReady()`를 확인하는데, 조건은:

```
디스크 DB 파일의 실제 버전 == DatabaseHelper.kt의 DATABASE_VERSION
```

**정확히 같을 때만** 열린다. 이 검사는 원래 안전장치다 — Flutter가 마이그레이션을 끝내기
전에 Native가 DB를 먼저 열면, `SQLiteOpenHelper`가 `onUpgrade`가 비어 있어도
`db.setVersion()`을 실행해 **실제 마이그레이션 없이 버전만 최신으로 찍어버리기** 때문이다.
그러면 Flutter가 나중에 열 때 "이미 최신"으로 오판하고 자기 마이그레이션을 통째로 건너뛴다.

### 사고

Flutter 쪽 `database_service.dart`의 `version:`만 올리고 Kotlin 쪽
`DatabaseHelper.kt`의 `DATABASE_VERSION`을 안 올리면, 두 값이 어긋난다.
Flutter가 DB를 한 번이라도 열어 파일을 새 버전으로 올린 순간부터 게이트는 **영구히 닫힌다.**

그런데 게이트가 닫혀도 **예외가 나거나 앱이 죽지 않는다.** 호출부들은 조용히 `null`을 받고
그냥 `return`한다. Flutter는 자기 sqflite 연결을 쓰므로 멀쩡히 동작한다.
**앱 화면은 정상인데 Native 기능만 전부 죽는다** — 그래서 원인 짐작이 거의 불가능하다.

### 증상 대조표

이런 증상이 보이면 **제일 먼저 이 두 상수부터 확인할 것.**

| 증상 | 실제로 일어난 일 |
|---|---|
| 홈 위젯이 스케줄 유무와 무관하게 항상 "근무 스케줄을 먼저 설정해주세요" | `CalendarWidgetScheduleResolver.readSchedule()`이 null → "스케줄 없음"으로 판단 |
| 알람은 정상적으로 울리는데 화면의 **시각이 빈칸** | `AlarmActivity` / `AlarmOverlayService`가 early return, 시간 문자열이 초기값 `""` 그대로 |
| 설정에서 "고정 알람 수정"을 저장해도 알람이 안 바뀜 | `AlarmRefreshEngine.doRefresh()`가 `"⚠️ DB 파일 없음 - 갱신 중단"` 로그만 남기고 no-op |
| 달력에서 근무를 길게 눌러 재배정하면 "되는" 것처럼 보임 | 그 경로만 Dart가 sqflite로 직접 쓰기 때문 — 게이트를 안 거침. **오진 유발 주의** |
| 자정이 지나도, 앱을 열어도 10일치 알람이 안 늘어남 | 위와 같은 `AlarmRefreshEngine` no-op |

### 재발 이력

| 시점 | 버전 | 계기 |
|---|---|---|
| — | Kotlin 13 / Flutter 14 | 최초 발견 |
| 2026-08-12 | Kotlin 15 / Flutter 16 | 친구공유 커밋(`friends` 테이블 추가) — 위젯이 죽음 |
| 2026-08-20 | Kotlin 17 / Flutter 18 | 근무명 색상 복원(`custom_shift_colors`) — 위젯 + 알람화면 + 고정알람수정이 한꺼번에 |

세 번째에 "다음엔 안 잊어버리기"로는 못 막는다고 판단해서 빌드 가드를 넣었다.

---

## 3. 지금은 빌드가 막아준다

`android/app/build.gradle.kts`의 `checkDartKotlinSync` 태스크가 두 값을 정규식으로
직접 읽어 비교하고, 다르면 `GradleException`으로 **빌드를 실패시킨다.**
모든 variant의 `pre*Build`에 `dependsOn`으로 걸려 있어서, 값이 어긋난 APK/AAB는 애초에
만들어지지 않는다.

현재 검사하는 쌍:

| 값 | Kotlin | Dart |
|---|---|---|
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` | `database_service.dart` `version:` |
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
- **Dart/Kotlin 양쪽에 각각 하드코딩되는 상수 쌍을 새로 만들면 `checkPair()` 호출을 하나
  더 추가할 것.** 주석으로 "맞춰야 함"이라고 적어두는 건 이미 세 번 실패한 방법이다.

---

## 4. 변경 절차

### 4-1. 한 커밋 안에서 같이 할 것

1. **`lib/services/database_service.dart`**
   - `version: 18` → `19`
   - `_onCreate()`에 새 테이블/컬럼 추가 (반드시 `CREATE TABLE IF NOT EXISTS`)
   - `_onUpgrade()` 맨 끝에 새 블록 추가:
     ```dart
     if (oldVersion < 19) {
       try {
         await db.execute('ALTER TABLE ... ADD COLUMN ...');
       } catch (e) {
         print('⚠️ 컬럼 추가 스킵(이미 존재 가능성): $e');
       }
       print('✅ DB 업그레이드 완료 (v$oldVersion → v19): ...');
     }
     ```
2. **`android/app/src/main/kotlin/com/hwani1103/shiftbell/DatabaseHelper.kt`**
   - `DATABASE_VERSION = 18` → `19`
   - Native가 그 컬럼/테이블을 읽어야 한다면 읽는 코드도 여기서 같이
3. **`CLAUDE.md`**의 DB 스키마 절, 이 문서의 맨 위 "현재 스키마 버전"도 갱신

### 4-2. 지켜야 할 규칙

- **`_onCreate`와 `_onUpgrade` 둘 다 고칠 것.** `_onCreate`는 신규 설치용,
  `_onUpgrade`는 기존 사용자용이다. 하나만 고치면 둘 중 한쪽 사용자만 깨진다 —
  그리고 보통 개발 중엔 신규 설치로 테스트하니까 **기존 사용자 쪽이 조용히 깨진다.**
- **`_onUpgrade`의 기존 블록은 절대 수정/삭제하지 말 것.** v2부터 v18까지 17개 블록이
  순서대로 쌓여 있다. 아주 오래된 버전에서 올라오는 사용자가 이 사슬을 전부 통과한다.
- **모든 `CREATE`에 `IF NOT EXISTS`, `ALTER`는 try/catch.** `onOpen`의 방어 로직이
  `_onCreate`를 다시 부를 수 있어서, 두 번 실행돼도 죽지 않아야 한다.
  (실제로 `table date_overtime already exists` 예외로 앱이 스플래시에서 죽은 적 있음)
- **컬럼 삭제/이름 변경은 하지 말 것.** SQLite가 제대로 지원하지 않고, 테이블 재생성
  경로는 이 앱의 Native/Flutter 이중 접근 구조에서 특히 위험하다. 안 쓰는 컬럼은 그냥 두자.
- **`alarm_history` / `alarm_creation_log`는 마이그레이션에서도 건드리지 말 것.**
  영구 보존 테이블이다.

### 4-3. 검증

```bash
flutter analyze
cd android && ./gradlew :app:checkDartKotlinSync    # 두 상수 일치 확인
cd .. && flutter install --release --flavor dev      # ⚠️ 반드시 --flavor dev
```

**기기에서 확인할 것 (신규 설치만으로는 부족하다):**

1. **업그레이드 경로** — 기존 데이터가 있는 dev 앱을 지우지 말고 그 위에 덮어 설치.
   근무표·알람·메모가 그대로 남아 있는지 확인. (신규 설치는 `_onCreate`만 타므로
   `_onUpgrade` 버그를 절대 못 잡는다)
2. **홈 위젯** — 위젯을 새로 추가해서 근무/색상이 제대로 나오는지.
   "설정해주세요"가 뜨면 게이트가 닫힌 것이다.
3. **알람 갱신** — 설정에서 고정 알람을 하나 추가하고 저장한 뒤 logcat 확인:
   ```
   adb logcat -s AlarmRefreshEngine DatabaseHelper
   ```
   `✅ diff 갱신 완료: +N -M` 이 나와야 정상.
   `⏭️ DB 버전 불일치(disk=..., native=...)` 가 보이면 상수가 어긋난 것.
4. **알람 화면** — 알람이 실제로 울릴 때 **시각이 빈칸이 아닌지**.

---

## 5. 현재 스키마 (v20)

| 테이블 | 용도 |
|---|---|
| `shift_schedule` | 근무 패턴/시작일/근무명/색상 (v18에서 `custom_shift_colors` 추가) |
| `shift_alarm_templates` | 근무별 고정 알람 템플릿 (근무당 최대 5개) |
| `alarms` | 실제 등록된 알람 (10일치 롤링) |
| `alarm_types` | 알람 타입 프리셋 (소리/볼륨/진동/지속시간) |
| `alarm_history` | 알람 이력 — **영구 보존, 자동 삭제 금지** |
| `alarm_creation_log` | 알람 생성 로그 — **영구 보존, 자동 삭제 금지** |
| `date_memos` | 날짜별 메모(달력 탭) |
| `date_schedules` | 일정관리 탭 전용 (v20 신규 - `date_memos`와 완전히 별개 CRUD) |
| `date_overtime` | 날짜별 OT/특근 |
| `friends` | 친구 공유 (v17에서 Firestore `ownerId` 기반으로 재설계) |

### 최근 변경

- **v16** — `friends` 테이블 추가 (친구공유)
- **v17** — `friends`를 Firestore `ownerId` 기반으로 재설계
- **v18** — `shift_schedule.custom_shift_colors` 추가 (근무명 색상 직접 지정)
- **v19** — `shift_alarm_templates`/`alarms`/`alarm_history`/`alarm_creation_log`에
  `day_offset`(INTEGER, 기본값 0) 추가 - 고정 알람을 근무 배정일 기준 전날(-1)/
  당일(0)/다음날(+1)로 등록하는 기능
- **v20** — `date_schedules` 테이블 신설(일정관리 탭 영구 저장). Native는 이
  테이블을 아직 안 읽음(위젯에 일정 표시 기능 없음) - 그래도 `DATABASE_VERSION`은
  반드시 같이 올림(§2 "Native가 안 쓰니까 안 올려도 된다"는 착각 참고).
  `predicted_category`/`is_user_corrected` 컬럼은 메모_자동분류_ML_계획.md
  Phase 5의 카테고리 자동배정 결과 기록용.

---

## 6. 참고

- 왜 이 검사가 존재하는지에 대한 가장 자세한 설명: `DatabaseHelper.kt` 상단 주석
  (`DATABASE_VERSION` 선언부와 `databaseFileExists()` / `onDiskVersion()` /
  `isDatabaseReady()` 주석). 사고 때마다 덧붙여 쓴 기록이라 맥락이 다 남아 있다.
- 빌드 가드 구현: `android/app/build.gradle.kts`의 `checkDartKotlinSync`
- `onDowngrade`는 Flutter 쪽에 지정되어 있지 않다. 즉 **더 낮은 버전의 앱을 덮어 설치하면
  DB 열기가 실패한다.** Play Store 정상 업데이트 경로에서는 일어나지 않지만, 개발 중
  구버전 APK를 수동 설치할 때는 주의할 것.
