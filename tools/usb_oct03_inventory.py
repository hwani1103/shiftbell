"""Add October 3 evidence without replacing prior audits or claiming UI equivalence."""
import csv,collections,pathlib,json
root=pathlib.Path(__file__).resolve().parents[1]
p=root/'docs/next_version/전수검증_자료_2026-09-30/기능_상태전이.csv'
with p.open(encoding='utf-8-sig',newline='') as f:
    reader=csv.DictReader(f);fields=reader.fieldnames;rows=list(reader)
updates={
'ALARM-028':('PASS','실제 온보딩 0→1→5/상한 표시·삭제→재추가→전부 삭제/빈 저장. 로컬 실제 위젯 추가 비활성 검증. onboarding_flow_retry/onboarding_finish'),
'ALARM-030':('PASS','새 APK 실제 시간편집→확인→시스템 Back→재진입 시0개, 원본 근무표/템플릿/알람 동일. work_onboarding_final'),
'ALARM-031':('PASS','실제 설정 완료 두 번 탭 직후 HOME. 근무표1/템플릿1/고정10, DB10 OS10 중복 없음. onboarding_commit'),
'RING-008':('PASS','실제 OS 울림 오버레이 +5m/X 좌표에 두 adb 입력 동시 전송. 회차 종료/이력1/결과1/DBOS1. 화면 입력은 Android에서 직렬 처리됨. overlay_race_ui'),
'RING-009':('PASS','소리+진동/진동/무음 실제 OS 발생 후 알림의 알람 끄기 버튼 탭. 각 삭제·종료·이력1 및 원본예약 유지. 실제 청각·진동 체감 제외. notification_types_retry'),
'RING-010':('PASS','알림 실제 5분 후 버튼→시계 변경 없이300초 대기→새 회차 실제 발생. 종료는 알림 receiver 경합으로 확인; 실제 끄기 UI는 별도3종 검사. notification_flow/notification_wait_native/notification_race'),
'RING-019':('부분 확인','같은 ID의 실제 스누즈 재울림에서 이전 회차 끄기/스누즈 receiver는 새 회차·이력을 건드리지 않음. 서로 다른 ID A→B 인계 UI는 별도 미실행. notification_rounds.json'),
'RING-021':('PASS','개발 앱 최근카드 실제 제거 완료1790961653000 < 예약1790961730342, 그 뒤 실제 울림 회차20. 다른 앱 카드는 유지. recents_verified/recents_result.json; 이전 잘못된 순서 시험은 제외'),
'REFRESH-007':('수정 후 PASS','고정+원터치+실제 스누즈+skip/set_type을 NY→London→Seoul 이동. 세 지역 DB9 OS9 및 스누즈/예외 원본 동일. 과거 고정 OS취소는 별도Kiritimati 실증, Native 혼합5행 회귀도 통과. mixed_zones_retry'),
'START-003':('부분 확인','로컬 실제 SQLite 공유 open 실패→재시도 및 gate 이전 시도 늦은 성공/오류·dispose·크기변경 통과. 실기기 DB open 고장 강제 주입은 하지 않음. startup_database_retry/startup_gate_test'),
'START-004':('부분 확인','UMP 지연/실패와 SDK 초기화 virtual1분 지연 동안 핵심화면 탭/늦은 광고 현재 폭/폐기 후 결과 통과. 실제 광고사업자 지연 강제 주입 아님. ad_sdk_delay/ad_startup_layout'),
'START-005':('부분 확인','USB 기본3회 core291/335/334ms, 메모20000개3회332/338/345ms. 분류기 새 인스턴스+asset cache evict103ms/warm0. 오프라인 자산폰트 회귀 통과. 다른 운영기기/배포빌드 제보 재현과 OS cold disk 아님. startup_*'),
'START-001':('부분 확인','수정 APK 업데이트 설치 및 dev 프로세스 콜드6회 측정. 원본 보존 위해 이 폰 앱 삭제 첫설치는 하지 않음; 이전격리재설치 기록 별도. startup_*'),
'BASIC-001':('PASS','실제 MemoNotifier 생성→수정→개발 PID kill -9→재실행 수정값 유지→삭제. 최종 원본 메모2개 복구. basic_final_prepare/verify'),
'BASIC-002':('수정 후 PASS','이미 캐시된 날짜 간 이동 시 옛 카드 잔류 결함 수정. 로컬 실패→수정후통과, 새 APK에서 생성→날짜/시각 이동→알림예약/재예약→OFF→삭제, DB/캐시 일치. 서비스 경로 실기기 검증. basic_final_prepare'),
'BASIC-003':('부분 확인','실제 수동 추가/겹침 탐지/시각 수정/삭제, AUTO 후보 겹침 확정거절→비겹침 수정 확정 통과. 거부 학습을 사용자 폰에 남기지 않도록 AUTO삭제는 DB정리; 후보 거절 학습은 로컬 Native회귀. sleep_final_retry'),
'BASIC-004':('부분 확인','실기기 19→07 자정넘김720분 저장, 다른근무 추가/초기화 시 원래근무 유지. OT10동시+30분=300/연말분리/외부0 캐시제거. 집계기간 조합은 로컬 회귀. 현재 제품 휴게입력 모델 없음. work_onboarding_final/basic_final_prepare'),
'FRIEND-017':('수정 후 PASS','기존100명 실기기/레이아웃 증거 + 이번0/1/10명 실제 화면·10명 스크롤·마지막 삭제 취소/확인→0개. 이번은 Firebase gate 임시OFF 로컬 fixture, 서버수신 검증은 기존 별도. friend_counts'),
'BACKUP-018':('부분 확인','로컬 실제 SQLite+모의 Native에 연속 epoch5회/스누즈 ID충돌/stop_pending 조합 추가 통과. 기존 USB복원과 별개로 실제5연속회차 주입은 미실행. AUD-B07b'),
'DEV2-005':('부분 확인','Play 채널 모의 unavailable/cooldown/통신실패재시도/중복요청/동일버전억제/새버전안내/폐기후응답4검사 통과. adb 설치 dev APK이므로 실제 Play 배포트랙 업데이트는 미실행. update_play_check_test'),
'DEV2-003':('부분 확인','현재 DiagReport 자동파일 저장만 있고 앱 내 공유시트 진입 코드 없음. 기존 실제 생성/민감본문 검사+이후 다수 실제울림 통과. OS파일관리자 공유취소는 앱 진입경로가 아니므로 별도 미실행.'),
}
for r in rows:
    if r['ID'] in updates:
        status,note=updates[r['ID']];r['상태']=status;r['Codex판정']=status+': 2026-10-03 '+note
        r['증거']='docs/next_version/잔여검증_실행기록_2026-10-03.txt; build/local_audit_2026-10-03 및 build/usb_audit_2026-10-03_remaining (비공개); 이전 증거는 10-02 기록'
with p.open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
counts=collections.Counter(r['상태'] for r in rows)
print(json.dumps(dict(counts),ensure_ascii=False))
