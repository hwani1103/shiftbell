"""Evidence-only reconciliation; never runs a device test or removes old evidence."""
import csv
import collections
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs/next_version'
SOURCE = DOCS / '전수검증_자료_2026-09-30/기능_상태전이.csv'
AUDIT = ROOT / 'build/handoff_reconcile_2026-10-04'
AUDIT.mkdir(parents=True, exist_ok=True)
backup = AUDIT / 'functional_inventory_before.csv'
if not backup.exists():
    backup.write_bytes(SOURCE.read_bytes())
with backup.open(encoding='utf-8-sig', newline='') as f:
    reader = csv.DictReader(f)
    fields = list(reader.fieldnames)
    rows = list(reader)
assert len(rows) == 202 and len({r['ID'] for r in rows}) == 202
byid = {r['ID']: r for r in rows}
ULTRA = 'build/srtl_2026-10-03_ultra/'
FINAL = 'build/srtl_2026-10-03_ultra_final/'

def read_log(path):
    data = (ROOT/path).read_bytes()
    return data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig')

evidence = {
 'RING-019': (ULTRA+'native_overlap_timeout_verified.log', 'PASS locked overlap in both postures',
   'PASS', '실제 잠금 알람 A→다른 ID B 연속 발생을 접힘/펼침에서 확인. A의 옛 끄기 receiver를 보내도 B는 유지되고 B 실제 UI 끄기 후 각 이력1·유령행0·DBOS 일치. 기존 같은 ID 회차 검증만 있던 공백을 충족했다.'),
 'RING-002': (ULTRA+'snooze_rounds.log', 'PASS real snooze',
   None, '잠금 첫 화면 +5m 실제 탭, 시계 변경 없이 약300초 후 새 회차 실제 울림 완료. 이후 펼침/잠금해제 및 notification receiver 경합으로 종료했으므로 재울림 뒤 잠금 UI X 전체동선은 남긴다.'),
 'RING-004': (ULTRA+'snooze_rounds.log', 'one winning final result',
   '부분 확인', '실제 새 회차에 끄기/스누즈 receiver 동시 요청, 최초 유효 결과1 및 이력1 검증. fold(True)가 keyguard를 해제하므로 잠금 상태의 두 액션 검증으로 승격하지 않고 그 마지막 조건을 남긴다.'),
 'RING-001': (ULTRA+'ring_matrix_final.log', 'PASS actual OS delivery',
   None, 'KO/EN·접힘/펼침 잠금 실제 UI 끄기 확인. 도구 kind=1인 잠금 조합이므로 3종 전부 완료는 아니다. 잠금 진동/무음 실제 UI 끄기는 별도 남긴다.'),
 'RING-008': (ULTRA+'overlay_race.log', 'PASS concurrent native button requests',
   None, '실제 오버레이 울림에서 Native 동시 액션 요청 추가 확인, 결과1·DBOS 일치. 이전 USB UI 경합 PASS 증거를 유지.'),
 'RING-012': (ULTRA+'snooze_rounds.log', 'one winning final result',
   None, '실제 두 번째 회차에 notification receiver 동시 요청·옛 회차 무시·최초 유효 결과1 추가 확인.'),
 'RING-017': (ULTRA+'native_overlap_timeout_verified.log', 'native timeout ended one round',
   None, 'SRTL에서 울림 시간을 임시1분으로 정하고 HOME 후 실제 Native 자동 종료·이력1·행삭제 확인, 원래 설정 복구. 기존 기본시간 PASS와 구분되는 추가 증거.'),
 'DELETE-001': (FINAL+'active_delete_reset_final.log', 'all-delete stops active ring too',
   '수정 후 PASS', '실제 울리는 중 전체삭제 누락을 수정한 빌드에서 울림 종료·DBOS0·근무/조 유지·취소이력 유지·강제갱신 뒤 부활 없음 확인.'),
 'DELETE-006': (FINAL+'active_delete_reset_final.log', 'reset stops active ring',
   None, '실제 울리는 중 스케줄 초기화: 울림 정지, 근무/조/템플릿/예외/이력/생성로그 제거, DBOS0, 조 tombstone/갱신 후 부활 없음. 과거 취소 확인 증거와 결합.'),
 'REFRESH-009': (ULTRA+'native_refresh_remaining.log', 'A to B clears old override',
   None, 'Native 근무 A→B→A, 옛 예외 제거·현재 템플릿 복귀를 SRTL에서 추가 확인.'),
 'REFRESH-010': (ULTRA+'native_refresh_remaining.log', 'template transition 23:41 uses current source',
   None, '템플릿 시각 왕복 전환에서 현재 소스 기반 생성 추가 확인.'),
 'REFRESH-011': (ULTRA+'native_refresh_remaining.log', 'swap Native references agree',
   None, '근무명 맞교환 템플릿 identity·Native 참조 일치 추가 확인. 근무시간 설정 참조의 실제 화면 왕복 조건은 남는다.'),
 'REFRESH-012': (ULTRA+'native_refresh_remaining.log', 'concurrent schedule and refresh converge',
   None, '실제 Native/DB 갱신 경합 최종 일정 수렴 추가 확인. 여러 날짜 일괄배정 UI 경로까지 실행한 증거는 아님.'),
 'REFRESH-013': (FINAL+'active_delete_reset_final.log', 'Native repeated refresh is idempotent',
   None, '반복 갱신 멱등성·원터치/예외 보존·DB50OS50 확인. 이력만 삭제해도 미래 예약/근무/조 유지 및 재갱신 때 삭제 이력 부활 없음 추가 확인.'),
 'REFRESH-014': (ULTRA+'native_refresh_remaining.log', 'Native insert failure rolls back old alarms',
   None, 'Native INSERT 실패 롤백 및 실패 제거 후 전체 창 복구를 추가 확인.'),
 'REFRESH-016': (ULTRA+'native_refresh_remaining.log', 'rolling window exactly ten future daily slots',
   None, '현재 창 정확히10일·11번째날 제외 추가 확인. 기존 실제 연말 자정 증거는 유지.'),
 'REFRESH-017': (ULTRA+'native_refresh_remaining.log', 'override retention 31 days',
   None, '29/30/31일 예외 보존/정리 추가 확인.'),
 'REFRESH-018': (ULTRA+'native_refresh_remaining.log', 'same-day wins all three offset collision',
   None, '전날/당일/다음날 같은 시각 충돌에서 당일 우선 추가 확인.'),
}
changes = []
for ident, (path, marker, state, note) in evidence.items():
    assert marker in read_log(path), (ident, path, marker)
    row = byid[ident]
    old = row['상태']
    if state:
        row['상태'] = state
    row['SRTL보완_2026-10-04'] = note
    row['증거'] = (row['증거']+'; '+path).strip('; ')
    row['Codex판정'] += ' | 2026-10-04 증거대조: '+note
    changes.append({'id':ident, 'before':old, 'after':row['상태'], 'evidence':path,
                    'sha256':hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), 'note':note})

# Exact unmet conditions only. A group can share preparation without sharing PASS.
groups = []
def add(ids, owner, missing, method, risk):
    groups.append(dict(ids=ids.split(), owner=owner, missing=missing, method=method, risk=risk))
add('ALARM-002 ALARM-006 ALARM-010 ALARM-014', 'Codex·격리 dev',
 '해당 카드/날짜상세에서 종류별 개별 삭제→실제 자정 트리거 연결 동선',
 '고정/원터치/스누즈를 분리하고 현재 카드 또는 날짜상세로 삭제. 격리 기기의 자정을 통과시켜 DB/OS·skip·이력·대체고정을 비교. 다른 종류 삭제 증거로 대체하지 않음.',
 '강제갱신은 통과했어도 자정 경로에서 삭제된 알람 부활/고정 중복 가능.')
add('ALARM-025 ALARM-026 ALARM-027 ALARM-032 ALARM-033 ALARM-034','Codex·격리 dev',
 '전날/당일/다음날 × 온보딩/설정 입력 UI의 월말·연말 경계',
 '각 ID가 지정한 화면에서 00:00/23:59 입력 후 배정일과 실제 날짜/OS epoch 비교. 기존 API33 생성 엔진 경계 검사는 재사용; UI 연결만 보완.',
 '입력 UI가 offset을 잘못 전달하거나 경계 날짜가 한 날 밀릴 위험.')
add('ONETAP-002','Codex·격리 dev','오늘 지난 시각/현재 시각/1분 뒤를 실제 패널에서 선택',
 '같은 프리셋으로 과거/현재 거절, 미래 생성과 안내를 확인. 시간 경계가 지나면 새 회차로 다시 잡음.', '검사 중 시간이 지나 오판하거나 거절 안내와 DB 결과가 달라질 위험.')
add('ONETAP-003','Codex·격리 dev','어제/모레/다른 달의 실제 날짜 탭 차단',
 '원터치 패널 열린 상태에서 금지 날짜 탭. 일반 날짜 팝업까지 열리지 않는지 확인.', '생성은 막혀도 다른 팝업이 열리는 UI 경로 공백.')
add('ONETAP-004','Codex·격리 dev','월말 밤의 원터치 패널 실제 내일 할당',
 '통제된 날짜로 월말→다음달1일 UI 선택; assigned_day와 OS 예약 비교. 기존 서비스 월말/연말 검사는 재사용.', '화면 날짜와 서비스 날짜 계산 차이.')
add('ONETAP-006','Codex·격리 dev','원터치5개+고정 추가 실제 화면 동선',
 '내일 원터치5칸을 할당한 뒤 고정 추가, 원터치 상한과 총 알람 수를 혼동하지 않는지 확인.', '고정 포함 전체를5개로 제한하는 UI 상한 오류.')
add('ONETAP-009','Codex·격리 dev','삭제한 프리셋 번호 재사용의 UI 재설정 경로',
 '프리셋 삭제 후 같은 슬롯 추가·날짜 할당, 옛 연결/이력이 새 설정을 참조하지 않는지 확인.', '슬롯 재활용 시 과거 ID/이력 연결 혼선.')
add('ONETAP-010 ONETAP-011 ONETAP-012','Codex·격리 dev','고정/원터치 동일분 우선순위의 UI 안내/삭제 후 대체 경로',
 'ID별 순서대로 고정→원터치/원터치→고정/원터치삭제를 실제 UI에서 실행. 중복거절·대체안내·정상 고정1개·허위이력0 확인. 기존 서비스 단언 재사용.', '서비스 결과는 맞아도 안내 또는 날짜 팝업 상태가 잘못 남을 위험.')
add('ONETAP-014 ONETAP-015 REFRESH-015','Codex·전용 실패주입 환경',
 '실제 Native/OS 예약 실패 및 일부 성공 후 재시도',
 '일회성 dev 실패주입 지점으로 원터치 생성, 삭제 후 대체고정, DB커밋후 일부OS실패를 각각 재현. 실패안내·롤백·성공ID 중복없음·재시도 복구 확인. 개인폰 권한을 무작정 끄지 않음.',
 'DB에는 있지만 OS에 없는 알람, 성공으로 거짓 표시, 이미 성공한 예약의 중복.')
add('DELETE-005','Codex·격리 dev','울리는 해당 A를 실제 목록 경로에서 삭제',
 '실제 울림 A 상태에서 앱의 해당 삭제 UI를 사용. 종료·이력1 확인. provider 삭제/전체삭제 통과 증거로 개별목록 UI를 대신하지 않음.', '삭제는 됐어도 울림이 계속되거나 회차 이력이 중복될 위험.')
add('RING-001','Codex·기기 기능 세션','잠금 진동/무음 유형 실제 UI 끄기',
 '소리+진동 잠금 검사는 오늘 완료. 남은 진동/무음만 각각 OS 발생→잠금 UI X→행/이력/예약 정리 확인. 소리 체감은 사용자 항목.', '알람 종류에 따라 잠금 경로가 달라지는 공백.')
add('RING-002','Codex·기기 기능 세션','재울림 후 잠금 화면 X로 끝내는 마지막 경로',
 '첫 잠금 +5m와 실제300초 재울림은 완료. 원장 전체동선을 닫으려면 잠금 유지 회차로 +5m→재울림→그 화면 X까지 기록. 다음 레이아웃 세션에서는 이5분 대기 금지.', '실제 재울림 성공과 잠금 X 연결을 하나의 PASS로 혼동할 위험.')
add('RING-003','Codex·기기 기능 세션','잠금 화면 스누즈 시각에 다른 B가 이미 존재하는 충돌',
 'A+5분에 B 준비 후 잠금 스누즈. A 종료/B 유지/추가스누즈0/안내/이력 확인.', '충돌시 B를 지우거나 중복 스누즈를 만드는 위험.')
add('RING-004','Codex·기기 기능 세션','keyguard 유지 상태에서 두 액션 거의 동시 전달',
 '오늘 receiver 경합은 펼침 뒤 잠금이 풀린 상태였다. 잠금 상태를 확인한 새 회차에서 동시요청·최초결과1 확인. Android 입력 직렬화와 실제 병렬요청 구분.', '공통 처리 통과만으로 잠금 상태 전체검증으로 잘못 세는 공백.')
add('RING-013 RING-014 RING-015 RING-016 DEV2-008','Codex·Flip 별도 기능 세션',
 '실제 Flip 커버의 3종 끄기/재울림/충돌/경합 및 커버↔내부 채널 복원',
 '지원되는 실제 커버 모델/화면을 확보해 ID별 회차를 분리. 3종, 실제300초, B충돌, 동시요청, 접힘전환 후 같은회차/알림채널을 대조. 이번 Fold/Flip 레이아웃 세션에는 넣지 않음.',
 'Fold 접힘을 Flip 커버로 잘못 대체, 커버에서만 버튼 불능/채널 복구 누락.')
add('RING-018','Codex·격리 dev','20분 사전알림 경계의 시각 수정 UI 동선',
 '알림 경계 진입 후 수정·삭제. 표시 시각/알람ID·취소 상태 비교. 기존 Guard/삭제 로그 재사용.', '삭제된 옛 알람의 유령 사전 알림.')
add('RING-020','사용자 직접','실제 오디오 장치·통화·DND·볼륨 체감',
 '본문 H2 그대로 시행. 장치/OS허용 정책과 실제 출력 위치 기록.', 'OS 정책 차이 또는 오디오 경로 누락. SRTL 로그만으로 판단 불가.')
add('REFRESH-003','사용자+Codex 공동','재부팅 후 최초 잠금해제 전 mixed 예약 확인',
 '본문 H3. 고정/원터치/스누즈/예외 준비, 재부팅 뒤 첫 해제 전 실제발생 확인. Codex가 해제 후 DB/OS와 CE 오류를 비교.', 'Direct Boot 저장소 접근 실패/예약 복구 누락.')
add('REFRESH-006','Codex·권한 통제 기기','실제 정확한 알람 권한 거부→재허용 경로',
 '현재 USE_EXACT_ALARM 정책에서 실제 권한 박탈 가능한 OS/설치조건인지 먼저 확인. 불가능하면 appop ignore를 성공한 거부로 세지 말고 적용불가 근거를 남김. 가능한 환경에서 혼합예약 복구 확인.', '권한 재허용 후 일부 알람 미예약 또는 잘못된 시험설계.')
add('REFRESH-011','Codex·격리 dev','근무명 A/B 맞교환 뒤 근무시간 설정 참조의 실제 UI',
 '오늘 템플릿/Native 참조 PASS. 남은 출퇴근/근무시간 설정과 이름 대응을 UI에서 왕복 확인.', '근무 시간만 다른 이름을 가리키는 잔여 참조.')
add('REFRESH-012','Codex·격리 dev','여러 날짜 일괄 배정 UI와 Native 갱신 경합',
 'UI 일괄선택/적용 도중 갱신을 요청하고 최종 커밋 일정에 수렴 확인. 기존 DB경합 단언은 재사용.', '화면 변경 분량과 Native 조회 스냅샷이 다르게 반영될 위험.')
add('DST-001 DST-002 DST-003 DST-004 DST-005','Codex·격리 날짜/시간대 환경',
 'DST 경계의 잠금/오버레이/알림 UI별 실제 회차',
 '각 원장 ID의 New York/London 날짜·첫/둘째 시각을 사용. 이미 검증한 epoch계산과300초 기본 경로 재실행 대신 미실행 UI 조합만 보완. 개인폰 시계변경 금지.', '중복 현지시각의 첫/둘째 offset 혼동 또는 UI표기/예약 불일치.')
add('DST-006 DST-007 DST-008','Codex·격리 날짜/시간대 환경',
 'DST 두시각 공존/이동/프로세스종료의 미실행 세부 연결',
 '원장 기존 Codex판정의 실제 완료부분을 먼저 읽고, 동일표시 서로다른epoch/스누즈중지역이동/프로세스종료·복원 잔여만 실행. 일반 서울 시험으로 DST 완료 처리 금지.', '절대시간은 맞아도 표시·복구에서 반복시각이 한시간 이동할 위험.')
add('BACKUP-005 BACKUP-006','Codex·격리 저장 실패 환경',
 '파일 교체 단계 실패·공간 부족·검증 읽기 실패의 실제 저장 경로',
 '구형단일슬롯→두슬롯 및 MediaStore 교체 실패를 테스트 전용 자료로 주입. 기존 정상파일 hash/성공시각 유지 확인. 개인폰 공간 강제고갈 금지.', '정상백업 소실 또는 실패했는데 마지막 성공시각 갱신.')
add('BACKUP-007','Codex·기기 기능 세션','SAF 접근권한 취소 경로',
 '파일선택 Back 취소는 완료. 문서 제공자 접근권한 취소 뒤 복원 시도 시 원본 DB/설정/예약 불변 확인.', '취소와 권한실패를 같은 경로로 간주하는 공백.')
add('BACKUP-017 BACKUP-018 BACKUP-021','Codex·격리 복원/실패주입 환경',
 '울림 직전 복원·연속5회 epoch 변경·OS정리/재조정 부분 실패의 미실행 조합',
 '기존 restore job 단계별 중단복구 PASS를 재사용. 원장 각 남은 회차경계/5회한계/실제OS정리실패만 주입하고 job보존·잠금해제·재시도·원본보호 비교.', '회차 반복으로 복원 무한루프, 작업 유실, DBOS 불일치.')
add('FRIEND-002 FRIEND-005 FRIEND-008 FRIEND-009 FRIEND-010 FRIEND-019','Codex·서버/수신자 별도 세션',
 '이미 서버서비스로 확인한 변경/ACK/세대/실패/캐시의 실제 앱→수신앱·웹 연결',
 '원장 ID별 순서(변경·복원·중지·재시작·실패·pull to refresh)대로 테스트 계정/코드 사용. 실제 업로드와 수신화면을 같이 대조하고 읽기수도 기록. 로컬fixture로 대체 금지.',
 '늦은 응답이 공유를 부활시키거나 수신자에 오래된 근무표가 최신처럼 보일 위험.')
add('FRIEND-004','사용자 정책 결정','초기화 중 공유를 즉시 중단/빈상태 갱신할지 정책',
 '과거 공유표가 남는 동작을 이미 관찰. 원하는 제품 정책을 정한 뒤 구현/검증. 테스트 실행만으로 닫을 수 없는 행.', '초기화된 사용자와 수신자 상태 불일치.')
add('FRIEND-022 FRIEND-023 FRIEND-024 FRIEND-025','Codex·운영 공유웹/인증/PWA',
 '인증실패복구와 실제 Hosting 배포후 첫열기/재방문/오류/기존PWA 캐시',
 '친구 공유웹의 실제 배포 버전을 확인하고 테스트 코드로 인증실패→회복, 기존탭/새탭/?code 보존, 삭제코드/오프라인→재시도, 실제PWA설치/업데이트를 대조. 관리자웹 차트배포와 무관.',
 '인증 gate 잠김, URL유실, 오래된 정적자산/PWA캐시 잔류.')
add('START-001','Codex·격리 release/시작 측정','최초설치/업데이트/콜드/warm 분리된 측정 세트',
 'SRTL 재설치를 했다는 사실만으로 최초3회 성능측정 완료 처리하지 않음. 필요한 설치환경에서 각3회, core/첫사용프레임을 분리. 오늘 기기시작 성공증거 재사용.', '시작은 되지만 첫사용까지 지연 원인이 남는 위험.')
add('START-002 START-003 START-004 START-005','Codex·격리 지연/오류/성능 환경',
 '실제 외부 네트워크/DB실패/광고 지연/배포환경 제보 재현',
 '기존 로컬모의/SQLite/USB측정 PASS를 반복하지 않음. 실제 실패주입이 필요한 잔여와 운영성능 제보를 구분해 한 원인당 필요한 측정만 수행.',
 '지연한 옛 초기화 결과 적용, 핵심화면 차단, 큰자료/외부SDK 지연의 원인 미분리.')
add('START-006','Codex·별도 시작 전환 검사','초기 로딩 중 접힘↔펼침/앱전환',
 '앱이 뜬 다음 자세전환은 이미 많음. 시작 진행중에 전환시켜 중복 초기화·광고폭·첫화면 재구성을 확인. 정상사용 레이아웃 확인만으로 승격 금지.',
 '초기화 도중 폐기된 위젯 응답/광고폭 재구성 오류.')
add('ENGLISH-006','Codex·언어/위젯 잔여','영어 저장/읽기 전체 경로 중 Native·위젯 등 미대조 구간',
 '메인/팝업/Native 일부/조표 16자 라벨 증거는 오늘 추가됨. 위젯 및 전체라벨 확인 동선 등 미확인 경로만 원장과 대조. 영어 미제공 테마 강제 활성화 금지.',
 '한 화면 정상이어도 위젯/다른 경로에서 라벨 잘림·읽기 불일치.')
add('BASIC-003','Codex·격리 수면자료','자동 후보 거절 학습의 실제 사용자 경로',
 '수동추가/겹침/수정/삭제와 후보확정은 이미 확인. 개인폰 학습을 바꾸지 않기 위해 남긴 후보거절·후보제외합계 경로를 합성환경에서 확인.',
 '거절해도 후보가 다시 나타나거나 미확인 후보가 합계에 포함될 위험.')
add('BASIC-004','Codex·근무시간 UI 잔여','집계기간 변경의 실제 UI와 현 제품 범위 정리',
 '자정넘김720분/OT동시증감·연말·캐시 검사는 완료. 기간변경 UI 연결만 대조. 현재 없는 휴게입력은 N/A로 세부조건 정정하며 새기능을 만들지 않음.',
 '집계기간/캐시 갱신 누락. 조변경 과거OT 정책은 사용자 합의대로 후순위로 유지.')
add('DEV2-003','원장 범위 정리·추가 기기시험 불필요','현재 없는 앱내 진단 공유시트 취소 조건',
 '실제 진단파일 생성/민감본문제외/이후 알람은 기존 증거가 있다. 현 앱에 공유시트가 없으므로 그 하위조건을 N/A로 정정 승인 기록 후 행을 닫을 것. OS파일관리자를 새 테스트로 확대하지 않음.',
 '없는 기능 때문에 원장이 영구미완료로 남는 관리 오류; 현재 미재현 앱결함이라는 뜻 아님.')
add('DEV2-005','Codex·Play 내부트랙','실제 Play 설치경로의 버전 안내/업데이트',
 '모의 채널 예외/중복/버전 비교 PASS 재사용. 내부트랙 구버전→새버전 설치/안내/데이터유지 확인. adb설치 dev는 대체 증거 아님.', '트랙/계정별 배포 지연과 앱 버전 로직을 혼동할 위험.')
for i in range(1,6):
    add(f'HUMAN-{i:03}', '사용자 직접', ['소리·진동 체감','잠금·유휴·재부팅 실제 깨우기','SRTL 캡처·자유탐색 독립 가독성','S26 영어 실제 입력 확인','배율·시스템내비게이션 터치여유'][i-1],
        ['본문 H1','본문 H3','본문 H4','본문 H5','본문 H6'][i-1]+'의 방법·의도·위험을 따른다. 사용자 확인 결과가 오기 전 PASS로 올리지 않는다.',
        '기계 로그와 사용자의 물리/가독성 체감은 별도다.')

remaining = [r for r in rows if 'PASS' not in r['상태'] and r['상태'] not in ('해당 없음','취소(기능삭제)')]
lookup={ident:g for g in groups for ident in g['ids']}
assert len(lookup)==sum(len(g['ids']) for g in groups), 'Duplicate residual ID'
assert set(lookup)=={r['ID'] for r in remaining}, (set(lookup)-{r['ID'] for r in remaining}, {r['ID'] for r in remaining}-set(lookup))
for r in rows:
    r['최종대조일']='2026-10-04'
    r.setdefault('SRTL보완_2026-10-04','')
    if r['ID'] in lookup:
        g=lookup[r['ID']]
        r['실제잔여']=g['missing'];r['후속담당']=g['owner']
    else:
        r['실제잔여']='없음(기존 증거 범위)';r['후속담당']='재실행하지 않음'
for name in ['최종대조일','SRTL보완_2026-10-04','실제잔여','후속담당']:
    if name not in fields:fields.append(name)
with SOURCE.open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
counts=collections.Counter(r['상태'] for r in rows)
done=sum('PASS' in r['상태'] for r in rows)
excluded=sum(r['상태'] in ('해당 없음','취소(기능삭제)') for r in rows)
audit={'rows':len(rows),'complete':done,'excluded':excluded,'unclosed':len(remaining),
       'states':dict(counts),'reviewed_evidence_rows':len(evidence),'changes':changes,
       'residual_groups':groups,'before_sha256':hashlib.sha256(backup.read_bytes()).hexdigest(),
       'after_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest()}
(AUDIT/'reconciliation.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
with (AUDIT/'remaining_functional.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(remaining)

text=(DOCS/'최종인계_본문_2026-10-04.txt').read_text(encoding='utf-8')
text+='\n[원장 재집계]\n'
text+=f'202행 = 완료 {done} + 제외 {excluded} + 미종결 {len(remaining)}.\n'
text+='상태별: '+', '.join(f'{key} {value}' for key,value in counts.items())+'\n'
text+='오늘 보완 증거를 18행에 연결했다. RING-019는 부분→PASS, RING-004는 기기대기→부분 확인.\n'
text+='DELETE-001은 울림중 전체삭제 수정 후 실제 재검증 근거를 더해 수정 후 PASS로 변경.\n'
text+='나머지 오늘 기능 검사의 상당수는 이미 PASS인 행의 추가 증거 또는 새 조별규칙 기능이다.\n'
text+='미종결78행은 새로78개 전체 시나리오를 처음부터 실행한다는 뜻이 아니다. 부분행의 빠진 조건만 아래에 남겼다.\n'
text+='미종결 구분: 부분59 / 기기대기13 / 사용자직접5 / 정책1. 이 중 DEV2-003은 없는 공유시트 조건의 범위 정리이며 기기시험 추가가 아니다.\n'
text+='후속 SRTL 레이아웃 세션의 필수 기능 재실행 수는 0이다. 남은 기능 검사는 아래 별도 세션에 배정한다.\n'
text+='오늘 신규 완료가 적게 늘어 보이는 이유: 기존112 PASS에 겹친 재검증을 중복 가산하지 않고, 3종/경계/UI 전체조건 중 일부만 한 행은 정직하게 부분으로 유지했기 때문이다.\n'
text+='원장 원본 보존: build/handoff_reconcile_2026-10-04/functional_inventory_before.csv\n'
text+='행별 대조/해시: build/handoff_reconcile_2026-10-04/reconciliation.json\n'
text+='기계가 읽을 잔여 CSV: build/handoff_reconcile_2026-10-04/remaining_functional.csv\n'
text+='\n[이번 SRTL 증거를 붙인 원장 항목]\n'
for c in changes:text+=f"{c['id']} | {c['before']} → {c['after']}\n  완료 부분: {c['note']}\n  증거: {c['evidence']}\n"
text+='\n[202행 밖의 새 조별규칙/이력삭제 기능 — 별도 완료, 202에 중복가산 금지]\n'
extra=[
 ('개별5조 최초설정·서로다른3/8/12일순환·요일규칙·중복허용',ULTRA+'team_create.log','created_mixed_roster PASS'),
 ('공통4조 생성/취소/내조변경/인덱스고정/다시만들기',ULTRA+'team_common_flow_verified.log','PASS common UI'),
 ('조 저장 SQL실패 후 근무/조/예외 롤백',ULTRA+'team_atomic_rollback.log','calendar rolled back'),
 ('커밋전 프로세스종료/재시작: 내근무·조 일관성 및 DBOS9',ULTRA+'team_atomic_verify.log','PASS: process death'),
 ('이력만삭제: 미래알람50·템플릿·근무·조 보존, 재갱신 후 과거이력 부활0',FINAL+'active_delete_reset_final.log','current_history_clear_contract PASS'),
]
for label,path,marker in extra:
    assert marker in read_log(path),(path,marker)
    text+=f'완료 | {label}\n  {path}\n'
for team in ['B','E','D','A']:
    path=ULTRA+f'team_switch_{team}.log'
    assert 'other rules unchanged' in read_log(path)
    text+=f'완료 | 개별 조 →{team}, 과거/미래50일·이력보존·다른조규칙불변·예약 대조\n  {path}\n'
text+='설정에서 내 스케줄 변경 시 전체조 삭제/취소는 SRTL_재연결_대기_2026-10-03.txt의 당시 완료 기록을 보존한다.\n'
text+='옛 prefs/DB 조 저장 불일치 결함은 DB v26 단일 트랜잭션과 위 rollback/kill/restart 증거로 후속 보완됐다.\n'
text+='단 커밋 직후 OS 일부 예약 실패는 REFRESH-015에 별도 남아 있으며 이를 해결 완료로 합치지 않는다.\n'

text+='\n[실제 잔여 기능 목록 — ID별 현재 상태·방법·의도·위험]\n'
for n,g in enumerate(groups,1):
    text+=f"\nF{n:02} | {' '.join(g['ids'])}\n담당/환경: {g['owner']}\n남은 조건: {g['missing']}\n방법: {g['method']}\n의도/실패 위험: {g['risk']}\n"
    for ident in g['ids']:
        r=byid[ident]
        text+=f"  {ident} [{r['상태']}] {r['진입경로']} / {r['준비와조작']}\n"
        text+=f"    완료 기준: {r['기대결과']}\n    기존 완료/제약: {r['Codex판정']}\n"

text+='\n[전체 202행 상태 색인 — 번호 누락 확인용]\n'
for r in rows:
    text+=f"{r['ID']} | {r['상태']} | {r['준비와조작']} | 후속: {r['후속담당']}\n"
text+='\n[비교 캡처 번호표 — 공통 fixture, 기본1.0]\n'
with (ROOT/'artifacts/srtl_2026-10-03/capture_catalog.csv').open(encoding='utf-8-sig',newline='') as f:
    for r in csv.DictReader(f):
        na=r['language']=='en-US' and r['variant'] in ['initialBadge','underline','eventChip','editorial']
        text+=f"{r['number']} | {r['screen']} / {r['variant']} | {r['language']} | {r['posture']} | {'N/A: 영어 미제공' if na else '기기에서 지원되는 자세만 촬영'}\n"
text+='\n[다음 세션 첫 보고 형식]\n새 기기/실제 화면 크기/최신 APK hash 확인 → 이번 연결 목표(번호/수정묶음) → 진행.\n'
text+='종료 보고: 실제 검토한 조건, 교체한 번호, 발견/수정/재확인, 미지원과 미실행, 다음 재개점.\n'
text+='전체 기능 완료나 출시 가능을 레이아웃 검사만으로 선언하지 않는다. 모든 증거를 새 APK 전체 PASS로 승격하지 않는다.\n'
target=DOCS/'최종인계_기능원장_SRTL_레이아웃_2026-10-04.txt'
target.write_text(text,encoding='utf-8-sig')
if '--desktop' in sys.argv:
    desktop=ROOT.parent/'교대시계_최종인계_기능원장_SRTL_레이아웃_2026-10-04.txt'
    desktop.write_bytes(target.read_bytes())
print(json.dumps({'complete':done,'excluded':excluded,'unclosed':len(remaining),'groups':len(groups),'document':str(target)},ensure_ascii=True))
