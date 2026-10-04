"""Evidence-based updates only; never promote a partly executed sequence wholesale."""
import csv,pathlib,collections
root=pathlib.Path(__file__).resolve().parents[1]
p=root/'docs/next_version/전수검증_자료_2026-09-30/기능_상태전이.csv'
with p.open(encoding='utf-8-sig',newline='') as f:
 reader=csv.DictReader(f); fields=reader.fieldnames; rows=list(reader)
updates={
 'START-002':('수정 후 부분 확인','격리 API33 온라인 콜드 시작 am start-W 3086ms, 비행기모드 콜드 시작 3048ms. 오프라인에서 Jua 원격 폰트 실패의 처리되지 않은 오류 재현 후 공식 OFL 폰트 앱 자산에 포함. 새APK 오프라인 재시작/Startup core ready, 폰트 예외 없음; 로컬 네트워크금지 폰트로드1PASS. 느린 네트워크·제보자의 운영기기 재현은 미완.'),
 'START-005':('부분 확인','오프라인 첫 Jua 글꼴 로드가 원격 다운로드 예외를 냈음. 공식 글꼴 자산 포함 후 네트워크금지 로드1PASS·새APK 오프라인 기동시 폰트 오류 없음. 큰 DB/분류기 CPU·I/O의 단계별 측정은 미완.'),
 'RING-001':('부분 확인','격리 API33 secure PIN 잠금에서 실제 OS 무음 알람→AlarmActivity 전체화면→화면 X 탭, 해당 행 삭제·종료 이력1·DBOS0. 세 소리 유형의 물리 체감은 미완. locked_ring_*'),
 'RING-002':('부분 확인','격리 API33 secure PIN 잠금에서 실제 OS 울림→화면 +5m 버튼. 누른 시점+약300초 스누즈 행1·이력1·OS1, 정리 후0. 실제 300초 재울림은 기존 실기기 해제 화면에서 확인, 잠금 경로 후속 재울림은 미완. locked_snooze_*'),
 'ENGLISH-002':('PASS','실기기 OS 12↔24 전환의 편집 전/도중/재개와 저장값 유지 확인. 추가 alarm_time_format_test.dart 6PASS: 양 형식 전체24시각×전날/당일/다음날, 편집 도중 전환, 구형 Flutter값 재개 보정, 정오/자정 변환, 대형 글씨 화면.'),
 'ENGLISH-003':('PASS','실제 en-US 설정→Help 진입과 Privacy Policy 진입/표시, ko-KR 원복 확인. 기존 도움말27개·개인정보8개 문구 전수, 권한/오류/백업 화면 증거와 대조. 두 화면에는 외부 링크 코드가 없어 추가 왕복 조건 없음.'),
 'FRIEND-023':('수정 후 부분 확인','공개 웹 현재 버전은 새 탭 첫 조회 정상이나 Flutter 라우터가 ?code=를 지워 새로고침 시 근무표가 사라짐. web_main 초기 라우트에 URL 보존 수정. 로컬 새 웹빌드에서 코드 URL/색상/근무표 새로고침 유지 확인; 운영 배포 뒤 재검증 필요. web_local_reload_*'),
 'FRIEND-024':('수정 후 부분 확인','공개 웹 네트워크 차단 시 오류 안내 확인. 로컬 수정 웹빌드에서 차단→오류→차단 해제→새로고침 후 동일 근무표 복귀, ?code= 유지. 운영 배포 뒤 재검증 필요. web_local_blocked_*'),
 'DELETE-007':('PASS','실제 OS 울림→알림 receiver 스누즈→새 회차 울림. 옛 회차 끄기/스누즈 Intent 재전달해도 현재 울림 유지·이력 추가 없음. root 명시 receiver 전송이며 저장된 PendingIntent 객체 탭은 아님. race_old_round_ignored'),
 'RING-012':('PASS','API33 실제 두 번째 울림 회차에 알림 receiver 끄기/스누즈 동시 adb 전송. 첫 유효 결과1/회차별 이력1, 종료 후 DBOS0. UI 두 버튼 실제 동시 탭 대신 동일 Native 수신 경로. race_*'),
 'ONETAP-004':('부분 확인','API33 실제5월31일/12월31일23:50에서 내일00:00/23:59 할당. 날짜·assigned_day·실제 OS2 일치. 원터치 패널 경계날 UI 탭은 미완. onetap_month/year_boundary_*'),
 'ONETAP-015':('부분 확인','추가 로컬 SQLite+채널 실패 주입1PASS. 원터치 삭제 이력1, 대체 고정 행1 유지, reservationFailed=true/fixedReplacement=false 및 Native 재시도 요청 확인. 실제 기기 예약 거부 UI는 미완. replacement_failure_test.log'),
 'BACKUP-025':('PASS','격리 API33 dev 삭제→재설치, Downloads 원본 바이트 보존. 실제 온보딩 SAF 직접선택→복구. 근무표/템플릿/예외/메모/일정/수면/친구 원본 일치, DBOS10/작업완료. reinstall_restore_result.json'),
 'FRIEND-002':('부분 확인','실기기 실제 서버에 동일세대 A→B→A 패턴/날짜배정 업로드, 서버 강제조회·수신자 디코딩·dirty=false 일치. 서버 시험문서 삭제. 근무편집 UI 연속경로는 별도 미완. friend_actual_server_aba'),
 'FRIEND-019':('부분 확인','실제 서버 변경 후 FriendNotifier 2분 이내 자동refresh는 캐시 유지, force refresh는 최신 배정 반영. 로컬등록·서버 시험문서 정리. 실제 화면 왕복/당김 UI는 별도 미완. friend_cache_actual_server'),
 'RING-022':('수정 후 PASS','API33 am force-stop 후 앱 열기: 기존 DB11/OS1만 복구되던 문제 수정. 첫 Activity 재개에서 백그라운드 전체재조정. 새APK 강제중지 OS0→재실행 OS11, 혼합 DB·예외 전부 동일. startup_fixed_result.json'),
 'REFRESH-001':('수정 후 PASS','API33 강제중지→실제 Activity 콜드 시작. fixed/custom/snoozed+skip/set_type DB 그대로 OS11 복구. 당일 갱신완료 표시에 의한 전체 예약 복구 생략 수정. startup_fixed_*'),
 'DST-006':('부분 확인','API33 첫01:04 스누즈/둘째01:04 고정 DB와 OS 서로 다른 epoch로 동시 유지. 다음알람·이력의 동일표시 구분 UI는 미완. fixed_fold_two_occurrences_os'),
 'DST-007':('부분 확인','API33 NY→London→Seoul→NY 스누즈 절대시각 DBOS1 유지. 현재 시간대 표시 UI는 미완. mixed fixed 옛 예약 잔류는 REFRESH007 별도 결함.'),
 'REFRESH-008':('PASS','API33 실제 시계 변경 후 혼합 fixed/custom/snoozed+skip/set_type 전체행·DBOS11 동일. mixed_lifecycle_time_*; 과거로 넘어가는 고정 예약 정책은 REFRESH007 별도 검토.'),
 'BACKUP-008':('수정 후 PASS','실제 SAF 빈파일/잘린JSON/다른앱JSON 거절. 초과16MiB 무안내 수정 후 실제 오류안내/데이터·OS1 불변. schema999 실제 확인버튼→검증거절, 복원작업·잠금 없음/원본파일 불변. bad_picker_*, unsupported_*, backup_picker_result_test 2PASS'),
 'DST-008':('부분 확인','첫 회차01:04-04 스누즈 실제 백업 덮어쓰기→격리 API33 실제 재부팅 후 ID54/epoch1793509440000 DB·OS 보존. 일반 프로세스 종료 전용 경로는 별도 미완. dst_restore_*/dst_boot_result.json'),
 'REFRESH-016':('PASS','기존10일/11일 및 창밖배정 로컬 검사에 더해 API33 실제12월31일→1월1일 자정. 미래9일 유지/마지막1일만 추가, 첫날skip·custom·snoozed 보존 DBOS10→11. year_midnight_*'),
 'REFRESH-002':('PASS','API33 실제 연말 자정 고정+custom+snoozed+skip+set_type 혼합 모두 보존, 롤링1일만 추가 DBOS11. 삭제한 custom/snoozed 부활 없음. year_midnight_complete_*'),
 'BACKUP-007':('부분 확인','실제 SAF 뒤로가기 반복 후 dev MainActivity 복귀까지 확인. 전체 tables/preferences 동일 DBOS1. 권한 회수는 별도 미완. export_picker_before/after, picker_cancel_os'),
 'DST-009':('PASS','격리 API33 실제 NY 봄02:30 고정→03:30. Native 생성/Dart Alarm.fromMap/실제 OS10예약 일치, 중복 없음. emulator_audit_2026-10-02/fixed_gap_*'),
 'DST-010':('PASS','격리 API33 실제 NY 가을01:04 고정은 둘째06:04UTC로1건. Native 생성/Dart/OS10 일치. 별도 첫회차 스누즈도 함께 보존. fixed_fold_*'),
 'DST-011':('PASS(현 정책)','격리 API33 offset없는 legacy snoozed01:04 입력. 호환 정책 둘째시각으로 Dart/NativeOS 일치. 원래 첫/둘째 회차 복구라고 주장하지 않음. legacy_fold_*'),
 'REFRESH-007':('부분 확인','격리 API33 NY→London 기존 결함을 시간대 변경 시 지난 fixed의 OS 예약만 취소하도록 수정. 2026-10-03 USB 서울→Kiritimati 시험: 미래 고정1 예약 확인 후 시간대 변경 방송으로 OS 취소, 강제갱신 후에도 취소 유지, 지난 DB행 보존. 원본 시간대/자동설정 복귀 및 원본 DB/OS1 일치. 혼합 fixed/custom/snoozed/예외 전체 조합은 미완. tz_probe_result.json'),
 'ALARM-016':('PASS','실제 날짜 상세→고정알람→삭제 확인 버튼 연타. 대상만 삭제, 이력1/skip1, 나머지 예약 유지 DBOS3. 시험 템플릿 정리 후 원본1. date_double_*, date_fixed_clean_os'),
 'DELETE-003':('PASS','실기기 앱 재진입/Native 갱신/실제 재부팅 삭제 유지에 더해 격리 API33에서 6월30일→7월1일 실제 자정 Guard/날짜변경 갱신 확인. DBOS0, 템플릿0. build/emulator_audit_2026-10-02/midnight_*'),
 'ALARM-005':('PASS','실제 다음알람 원터치 종류2→3→1 및 매번 탭 재진입. DB/표시 일치, 원래 알람·원터치 설정·고정 예외 유지. next_flow_type_*'),
 'ALARM-007':('PASS','실제 원터치 삭제 확인 취소→재진입. DB/전체이력/예외/설정 동일, DBOS2 일치. next_flow_cancel_*'),
 'ALARM-008':('PASS','실제 원터치 삭제 확인 버튼 연타. 대상만 삭제, 이력1, 원래 알람 보존 DBOS1. next_flow_deleted/final_os'),
 'ALARM-011':('PASS','설정 칸 연결된 미래 스누즈에서 실제 삭제 확인 취소→재진입. 전체 DB/이력/설정 불변 DBOS2. 직접 생성 스누즈는 확인창 없는 기존 경로. next_snooze_flow_*'),
 'FRIEND-001':('PASS','실제 화면 이름입력→공유시작→복사아이콘. clipboard가 본인 SB2 코드와 일치. share_ui_*'),
 'FRIEND-007':('PASS','실제 UI 오프라인 중지→stop_pending→HOME/am kill→온라인 콜드 시작. 수동 retry 없이 off/dirty=false 및 서버 문서 삭제 확인. share_stop_*'),
 'FRIEND-011':('PASS','실제 입력창 빈값/SB1/빈SB2/슬래시/중복코드 5경로 거절 안내, DB1 유지. friend_invalid_ui_*'),
 'FRIEND-012':('PASS','실제 오프라인 추가 버튼 연타, DB1/목록 유지. 기존 provider 동시호출 UNIQUE 검증과 대조. friend_double_add_after/ friend_double_ui_count'),
 'FRIEND-013':('PASS','실제 offline 추가 UI에서 미조회 등록/네트워크 안내, 삭제로 단정하지 않음. friend_double_add_after'),
 'FRIEND-026':('PASS','기존 로컬 Firestore 규칙 FS02/03/04/05/07 거부 및 FS01/06 허용 증거 대조 완료. build/full_audit_2026-09-30/firestore.log. 운영 배포 없음, OBS4건은 별도 정책위험.'),
 'FRIEND-016':('PASS','본인 서버 시험 문서의 assignedDates 자료형 손상→실제 목록 invalid 오류→수정 후 정상→서버 삭제 후 등록 해제. friend_payload_ui_*; 시험 문서/친구 정리 완료.'),
 'FRIEND-027':('PASS','friend_payload_ui_start에서 실제 서버 문서 전체 키를 명시적 허용 목록과 대조. 메모·수면·알람·급여 키 없음.'),
 'ENGLISH-007':('PASS','최종 사용자 정책 영어16/한글6. 실제 KO/EN 입력16자 경계, KO→EN→KO 저장 유지, IME/17자 차단. names16_*/names_final_*, name_policy_final_tests.log. 전체근무표2줄·메인1줄 축소.'),
 'ALARM-012':('PASS','실제 EN 스누즈 삭제 연타. 대상만 삭제, 다른 8개 예약 유지, 이력1건. export_snooze_double_*/snooze_double_delete_os'),
 'ALARM-037':('PASS','설정 고정알람 수정에서 임시 야간09:00 추가 후 팝업·화면 뒤로가기. DB 원본 동일. export_fixed_back_after'),
 'ALARM-038':('PASS','실제 설정 저장 연타 직후 HOME. 템플릿1개만 추가, DB/OS10 일치. fixed_double_save_*'),
 'RING-005':('PASS','KO 잠금 해제 오버레이 1/2/3종 실제 발생 및 X종료. 이력 각1, 다른 예약 보존. overlay_type_* (음량 체감 제외)'),
 'RING-007':('PASS','실제 오버레이 +5m 충돌: 기존 대상 유지/현재만 종료/충돌 이력1. overlay_collision_*'),
 'REFRESH-005':('PASS','원터치·실제 스누즈·고정·set_type/skip 혼합으로 실제 APK 덮어쓰기. 전체행/예외 동일, DB/OS9. mixed_update_*'),
 'REFRESH-004':('PASS','실제 재부팅 후 혼합 미래 예약9개가 원래 epoch와 전부 일치. boot_unlocked_comparison.json. 잠금전 CE 예외 수정 후 두 번째 재부팅도 완료, 일정알림 복구/삭제 알람 부활 없음.'),
 'BACKUP-001':('PASS','직접/자동 저장과 파일 읽기 검증, 기존 슬롯 실기기 증거에 추가. backup_changes_and_queue'),
 'BACKUP-002':('PASS','직접 저장 중 메모 편집 후 자동/직접 큐. 완료파일 최신 편집 포함. backup_changes_and_queue'),
 'BACKUP-003':('PASS','내용동일 skip, 설정만/메모만 변경시 자동백업시각 변경. backup_changes_and_queue'),
 'BACKUP-005':('부분 확인','구버전 저장시각 fallback/slot_v2 메타 이행 실기기 통과. 실제 옛 파일 삭제 조건은 미완. backup_changes_and_queue'),
 'FRIEND-021':('PASS','실제 KO공유→SDK오프라인→Android EN전환 stop_pending→온라인 서버삭제→KO복귀 재공유없음. friend_locale_*'),
 'DEV2-006':('PASS','원터치+개별고정 skip/set_type+복원+Native갱신. 예외·원터치·메모·수면·영구이력 유지/DBOS8. mixed_restore_roundtrip_*'),
 'DEV2-007':('PASS','실제 EN전환/offline stop_pending+실제스누즈+복원: ID/절대시각/공유의도·세대 유지, 온라인 삭제/KO복귀 확인. combined_*/friend_locale_*'),
}
for ident in ['DST-001','DST-002','DST-003','DST-004','DST-005']:
 updates[ident]=('부분 확인','격리 API33 실제 OS 발생→현재 회차 알림 receiver 스누즈→목표 epoch 재발생 통과. 300초 실제 대기/잠금·오버레이·알림 UI 각각은 미완. 에뮬레이터_DST_검증_2026-10-02.txt')
for ident in ['ALARM-025','ALARM-026','ALARM-027','ALARM-032','ALARM-033','ALARM-034']:
 updates[ident]=('부분 확인','API33 1월1일 배정 전날/당일/다음날 x00:00/23:59 Native 실제 생성 날짜·offset·DB 검증, 마지막 OS2 일치. 각 온보딩/설정 UI 입력 경로는 미완. offset_year_boundary_*')
# Determine IDs from the real catalog: onboarding and settings are separate rows.
for r in rows:
 if r['ID']=='ENGLISH-007':
  r['기대결과']='영어 공백 포함16/한글6 입력 제한; 언어 전환 시 이름 유지. 전체근무표 최대2줄 후 축소, 메인달력1줄 전체 축소.'
 if r['ID']=='ENGLISH-006':
  r['기대결과']=r['기대결과'].replace('10자 이내','최종 영어16자/한글6자 이내')
 if r['ID'] in updates:
  status,note=updates[r['ID']]
  # Avoid guessing a row number for the two settings cases.
  if r['ID']=='ALARM-037' and '저장하지 않고' not in r['준비와조작']:continue
  if r['ID']=='ALARM-038' and '저장 버튼 연타' not in r['준비와조작']:continue
  r['상태']=status;r['Codex판정']=status+': 2026-10-02 '+note
  r['증거']='build/usb_audit_2026-10-02/ (비공개); docs/next_version/USB_재검증_2026-10-02.txt'
  if r['ID']=='REFRESH-007':
   r['Codex판정']=status+': '+note
   r['증거']='build/usb_audit_2026-10-03/ (비공개); docs/next_version/시간대_고정예약_실기기검증_2026-10-03.txt'
with p.open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
print(collections.Counter(r['상태'] for r in rows))
