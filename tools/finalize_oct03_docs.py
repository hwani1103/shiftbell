from pathlib import Path
root=Path(__file__).resolve().parents[1]/'docs/next_version'
(root/'남은작업_간단정리_2026-10-02.txt').write_text('''2026-10-03까지 검증 결과와 다음 작업

최신 결과
- 상세: 잔여검증_실행기록_2026-10-03.txt. 최초 실패/수정/재검사/실기기 증거/남은 제약을 기록했다.
- 중요 상태전이202행: 완료112, 부분확인59, 기기·환경대기14, 사용자직접확인5, 정책검토1, 해당없음9, 기능삭제2.
- 로컬 최종 단언: Flutter 기본802/축소화면78, Android124, Firestore16(OBS4포함), Node12 =1032건 성공. OBS는 결함/허용범위 재현 성공이며 정상 기능 PASS가 아니다. 상태전이202행과 합산하지 않는다.
- 정적분석 lib error0/warning0/info637, 마지막 수정두파일 error0/warning0/info26. 최초 전체실행과 후속 회귀 합산 기준으로 집계했다.

수정하고 확인한 것
- 시간대 이동으로 과거가 된 fixed의 옛 Android 예약 잔류. 과거행/이력은 보존하고 해당 OS예약만 취소. USB 서울→Kiritimati와 혼합 fixed/custom/실제snooze/skip/set_type NY→London→Seoul DB9 OS9 검증. REFRESH007 수정 후 PASS.
- 온보딩 좁은 폭 시각 Row overflow 수정. 일정 날짜 변경 후 옛 날짜 카드 잔류/새 날짜 누락 수정. 로컬 수정 전 실패→수정 후 회귀 및 새 APK 실기기 확인.
- 온보딩0~5/삭제재추가/빈저장/Back취소/완료연타·HOME, 알림3종끄기/실제300초스누즈, 옛회차무시, 알림·오버레이 두액션 최초결과1개, 최근앱제거 뒤 실제발생을 추가 확인했다.
- 메모 저장직후 dev프로세스 종료/재실행 보존, 일정 알림ON·재예약·OFF·삭제/날짜캐시, 수면겹침·후보확정, OT동시증감·연말·캐시, 자정넘김근무시간, 친구0/1/10명·마지막삭제 USB검증.
- 시작: 기본DB core291~335ms/메모2만건332~345ms, 분류기 새인스턴스asset evict103ms/warm0. 이 폰의 dev debug 측정이며 다른 운영기기/release 지연해결로 단정하지 않는다.
- 이전 수정(잠금해제전 수면설정, 스누즈 소수초, 초과백업 안내, 강제중지뒤 전체예약복구, 오프라인Jua 자산폰트, 공유웹 URL·긴근무명, 근무패턴코드 삭제 등)은 유지. 웹 수정은 로컬검증만 했으며 운영배포 안 함.

확인된 문제 / 남은 검증
- 실제 근무조 변경 중 prefs B 저장 후 DB쓰기 전에 dev프로세스를 종료하면 재실행 뒤 myTeam B/DBtodayIndex0 불일치가 남는 결함을 재현했다. 원본은 복구했다. durable journal/재시작복구설계는 Astra 후보3.
- 복원 epoch5회/스누즈ID충돌/stop_pending 복합 로컬검증 완료. USB에서5연속 회차변경을 강제주입한 증거는 아님.
- Firestore OBS4는 구버전/손상·큰payload/오래된세대 재생성·덮어쓰기 허용문제를 재현. 운영규칙 강화는 정책 결정 필요.
- 광고·DB·Play 실패/장기지연은 로컬 모의채널/실제SQLite로 확인했다. 실제 외부서버 지연·운영Play배포 경로와 구분한다.
- Fold/Flip커버/SRTL, 잠금전체화면 추가조합, 재부팅 해제전, 정확한알람 실패주입, 실제 통화/이어폰/Bluetooth/DND/청각·진동체감, 운영Hosting/PWA/Play는 남았다. 이번 폰 전원·잠금방지 지시 때문에 추가 잠금/재부팅을 하지 않았다.
- 부분59에는 이전격리API33의 월말/연말/DST와 일반날USB, 서비스검증과 실제UI의 차이가 포함된다. 미실행 세부조합은 기능_상태전이.csv에 남겼으며 전부 통과/출시승인을 뜻하지 않는다.
- UIAutomator 반복 관찰 중 Flutter debug semantics assertion이 나타났다. 일반사용자 accessibility/release 재현은 미확인, 최종 앱 재시작.

사용자 결정
- 근무표 초기화 순간 친구공유를 즉시 중지할지.
- 초기화 때 영구알람이력 정책, Firebase규칙 강화와 구버전 호환 범위.
- 영어 Diary 테마 제외 여부.
- 검토 뒤 운영 공유웹에 수정본 배포 여부. 현재 운영웹은 기존버전.
- 근무명 길이는 결정 완료: 영어 공백포함16자/한글6자.

기기·빌드·종료
- 최종 APK build/app/outputs/flutter-apk/app-dev-debug.apk SHA256 E3EABAA9D084315B2E4BD54B7B055C96F98EE2FC8D95E71D90C9F67A90C21DD7 설치.
- 최종 원본 복원 뒤 앱재시작, 전체 사용자DB테이블 원본 동일/integrity ok. 원본 ID2 2026-10-03 04:50 KST DB1/OS1 일치, 시험울림 없음.
- 자동/직접 백업 두슬롯 원본으로 저장하고 각각 읽어 테이블·백업설정 동일 확인. 백업시각/해시는 최신값.
- 한국어/공유OFF/Asia/Seoul/자동시간대1. USB충전 배터리84%, stay_on_while_plugged_in=7, Awake/mStayOn=true. 폰 종료 안 함.
- 새 원본/최종복구: 비공개 build/usb_audit_2026-10-03_remaining/final_device_result.json 및 remaining_before_de/ce.tar, remaining_final_de.tar.
- 결과 보고 후 사용자 요청대로 PC종료 진행. 실제 PC전원 꺼짐을 관찰한 기록은 아님.

Codex 인계
- 기능_상태전이.csv가202행 상태·경로·증거 기준. tools/usb_oct03_inventory.py를 마지막에 적용할 것. 10-02 스크립트만 실행하면 최신판정을 덮어쓴다.
- tools/summarize_oct03_tests.py는 기본/축소 구성별 동일 검사 마지막결과를 합친다. 로그는 build/local_audit_2026-10-03.
- 검토 후보: Astra_재검토_후보_2026-10-02.txt. 전체 기능 기준: 전수검증_2026-09-30.md.
- 이전 USB/DST: USB_재검증_2026-10-02.txt, 에뮬레이터_DST_검증_2026-10-02.txt, 시간대_고정예약_실기기검증_2026-10-03.txt. 개인원문은 build 내부에만 보관.
''',encoding='utf-8')
p=root/'Astra_재검토_후보_2026-10-02.txt'
text=p.read_text(encoding='utf-8-sig')
header='2026-10-03 추가 실행 결과 (위 당시 미완 설명보다 우선)'
if header in text:text=text.split(header)[0].rstrip()+'\n'
p.write_text(text+'''
2026-10-03 추가 실행 결과 (위 당시 미완 설명보다 우선)
- 후보1: SQLite+모의Native 복원 epoch5회/스누즈ID충돌/stop_pending 복합검사 AUD-B07b 통과. 실제5연속회차 주입과 구분. 실제300초 알림재울림/옛회차무시/알림·오버레이 최초액션1개는 USB추가 실증.
- 후보2: 로컬 demo Firestore16검사 재실행 성공. OBS4는 현규칙 허용문제를 그대로 재현. 운영배포 안 함.
- 후보3: 실제 SettingsTab._applyScheduleChange에서 prefs B 저장 뒤 SQLite writer를 잠근 상태에 dev PID kill -9. 재실행 myTeam B/DBtodayIndex0 지속. team_crash_interrupt/team_crash_verify.log. durable journal/재시작복구 미해결이며 시험 원본은 전량복구.
- 후보4: 과거fixed 취소 수정 후 혼합 fixed/custom/실제snooze/skip/set_type NY→London→Seoul DB9 OS9/예외보존. Kiritimati 과거취소와 Native5행 보존회귀 완료, REFRESH007 수정 후 PASS. 일반날USB와 이전 격리DST 경계증거를 구분하며 모든커버/잠금조합 완료 아님.
- 후보5: 로컬DB 공유open/실패재시도/이전늦은성공·오류/폐기, UMP·SDK지연, Play실패/버전억제 회귀 완료. USB기본DB core291~335ms/2만메모332~345ms, 분류기 새인스턴스asset evict103ms/warm0. 다른 운영기기/release 지연제보 원인 확정 아님.
- 추가 수정: 온보딩 시각Row overflow, 일정날짜변경 캐시불일치. 로컬 수정전실패→수정후 회귀 및 새APK USB통과.
- 상세: 잔여검증_실행기록_2026-10-03.txt. 최신202행 완료112/부분59/기기환경14/직접5/정책1/해당없음9/삭제2.
''',encoding='utf-8')
print('Summary and Astra evidence updated.')
