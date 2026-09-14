# 교대시계 (Shiftbell)

교대 근무자를 위한 알람·근무일정 앱. Flutter + Kotlin Native, Google Play 배포 중.

- 규칙적/불규칙 근무표와 근무별 알람(전날/당일/다음날), 10일치 자동 갱신, 잠금화면 알람·스누즈·자동 종료
- 달력(테마 9종)·메모·OT·근로시간, 홈 화면 달력/수면 위젯
- 일정관리 탭(일정 알림, 카테고리 자동분류), 컨디션 매니저(근거 기반 조언), 수면 기록·자동 추정
- 친구 근무표 공유(앱 코드 / 웹 링크), 기기 로컬 백업·복원

## 개발

```bash
flutter pub get
flutter install --release --flavor dev      # 테스트 앱(교대시계 (테스트)) 설치 — flavor 필수
flutter test                                 # Dart 테스트
cd android && sh ./gradlew testDevDebugUnitTest   # Kotlin 테스트
```

> flavor 없이 `flutter run`/`install`을 실행하면 스토어 설치본이 지워질 수 있습니다.

운영 빌드(광고 ID 주입 필요):

```bash
flutter build appbundle --release --flavor prod --dart-define=ADMOB_BANNER_ID=<배너 광고 단위 ID>
# AdMob 앱 ID는 ~/.gradle/gradle.properties 의 ADMOB_APP_ID
```

## 문서

| 문서 | 내용 |
|---|---|
| `CLAUDE.md` | 구조·규칙·설계 결정 전체(작업 전에 먼저 읽을 것) |
| `업데이트_가이드.md` | 버전 올리기·배포·새해 공휴일 추가 |
| `출시전_코드감사_2026-09-13.md` / `출시전_코드감사_검토결과_v4_2026-09-13.md` | 출시 전 코드 감사 원본과 수정 계획(#1~#31) |
| `출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md` | 감사 수정 실행 계획 |
| `docs/release_audit/` | 감사 수정 진행 기록·인계·테스트 결과·실기기 테스트 목록 |
| `ml/카테고리_가이드.md` | 일정 카테고리 정의와 우선순위 |
