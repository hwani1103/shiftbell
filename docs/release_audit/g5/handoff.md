# G5 handoff

```text
그룹 / 담당 / worktree / branch: G5 / Claude (사용자 지시 2026-09-14) / worktree 없음 / dev
공통 기준 SHA / 최종 소스 SHA: G4 1c5d403 / 06f450b
상태: CODE_FROZEN (구현만. T23 테스트·S10·S12·V5·V7은 미실행)
수정한 감사 번호: #6(L01, D2) #7(H18, D3) #29(M13) 설정 연결(D8 후속 위임 결정), G2-04, V2/V3 안내 문구
실제 변경 파일:
  - lib/constants/ad_config.dart - 광고 단위 ID를 prod+release에서만 --dart-define=ADMOB_BANNER_ID로, 없으면 요청 안 함. dev·debug 테스트 ID. 틴트 = kDebugMode
  - lib/widgets/banner_ad_slot.dart - 광고 단위 ID가 비면 요청 생략
  - android/app/src/main/AndroidManifest.xml, android/app/build.gradle.kts - AdMob 앱 ID manifestPlaceholders(admobAppId): prod는 Gradle 속성 ADMOB_APP_ID, 없으면·dev는 테스트 앱 ID
  - lib/firebase_options.dart(androidDev 추가), lib/services/firebase_bootstrap.dart - dev flavor는 dev 앱 ID + Analytics 수집 끔
  - lib/l10n/app_ko.arb, app_en.arb - privacyIntro/NoCollection/Firebase/Ads/DataRetention/EffectiveDate 수정, privacyAnalyticsTitle/Body 신설, settingsDataBackupSuccessToast(V2), friendStopSharingConfirm(G2-04)
  - lib/screens/privacy_policy_screen.dart - '사용 통계' 섹션 추가
공통 파일/API/ARB 연결 요청 및 반영 SHA: G2-04 06f450b
사용자 결정 확인: D2(광고 운영, 실제 ID는 최종 배포 직전 주입 - 구조만 준비), D3(문구는 코드 사실 기준 초안 확정, Console·DebugView 확인 후 배포일에 최종 확인). D8 후속·D7 후속은 AI 위임 결정(decisions_delegated_2026-09-14.md)
최종 동작과 회귀 금지 규칙 준수: 실제 광고 ID를 소스·dev에 넣지 않음, Firebase 프로젝트·Console·rules 배포 변경 없음, 새 Analytics 이벤트 없음(L02)
추가/변경 테스트와 실제 실행 명령: 없음(T23 보류). 회귀 확인 flutter build apk --flavor dev --debug PASS, flutter test 252/252 PASS, gradlew testDevDebugUnitTest 71/71 PASS (2026-09-14, dev 통합본)
미실행 실기기/Console 항목: S10(E2) S12(E3) V5(E4) V7·Play 데이터 보안(E5) prod release 광고(E1) - device_test_plan.md 세션 E
잔여 위험·다음 그룹 주의사항:
  1. 개인정보 문구는 코드·SDK 문서 기준 - Analytics 자동 수집 항목·보존 기간·광고 개인화 동의(UMP) 필요 여부는 Console·배포 국가 확인 전 미확정. 법적 적합성은 판단 불가
  2. prod release 빌드에 ADMOB_BANNER_ID/ADMOB_APP_ID를 주입하지 않으면 광고 수익 0(요청 안 함) - 배포 체크리스트에 추가 필요(업데이트_가이드.md)
  3. dev 앱은 운영과 같은 Firestore 프로젝트를 씀 - 친구공유 테스트 문서가 운영 컬렉션에 생김(공유 중지로 정리)
  4. appFlavor는 flutter build/run --flavor로 설정됨 - flavor 없이 빌드하면 prod 분기를 타지 않음(광고 테스트 ID·Analytics 켜짐)
  5. M12 레이아웃 수정 없음 - S10 결과에 따라 후속
```

## 진행 기록

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Claude | T21·T22 | #6 #7 #29 G2-04 V2/V3 문구(위 목록), 테스트 보류(사용자 지시) | 06f450b | 세션 E(사용자), T23 |
