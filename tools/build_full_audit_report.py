"""Build reviewable audit inventories from sources and this run's evidence.

Run from the repository root. Does not execute tests or contact any service.
Never converts a related unit-test success into a device/UI success.
"""
from pathlib import Path
import csv
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/전수검증_자료_2026-09-30'
RUN = ROOT / 'build/full_audit_2026-09-30'
OUT.mkdir(exist_ok=True)

def write_csv(name, rows):
    if not rows:
        return
    destination = OUT / name
    if destination.exists() and 'ID' in rows[0]:
        with destination.open(encoding='utf-8-sig', newline='') as f:
            previous = {row['ID']: row for row in csv.DictReader(f)}
        for row in rows:
            old = previous.get(row['ID'], {})
            for key in row:
                if key in ('Codex판정', '사용자교차판정', '증거') or key.startswith(('Fold8_', 'Fold8Ultra_', 'Flip8_', 'S26_')):
                    if old.get(key) and old[key] != '대기':
                        row[key] = old[key]
            if old.get('Codex판정') or old.get('사용자교차판정') not in ('', '대기', None):
                if '상태' in row:
                    row['상태'] = old['상태']
    with destination.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

cases = []
def case(area, route, steps, expected, owner='USB', evidence=''):
    cases.append(dict(ID=f'{area}-{sum(c["영역"] == area for c in cases)+1:03}', 영역=area,
        진입경로=route, 준비와조작=steps, 기대결과=expected, 실행담당=owner,
        상태='기기연결대기' if owner in ('USB','SRTL') else '직접확인대기',
        로컬참고=evidence, Codex판정='', 사용자교차판정='', 증거=''))

# Each sequence changes the same alarm or a dependency of its generation.
for route in ['다음알람 > 현재 알람 카드 (등록 목록은 읽기 전용)', '달력 > 날짜 상세']:
    for kind in ['고정', '원터치', '스누즈']:
        for action, expected in [
            ('종류 소리+진동→진동→무음 변경 후 재진입', 'DB 종류와 표시 일치; 고정만 set_type 예외; 원터치 칸 원본은 별개'),
            ('울리기 전 개별 삭제 후 자정 갱신', 'DB/OS 예약 제거·취소 이력 보존; 고정 skip 유지; 원터치라면 대체 고정 재계산'),
            ('삭제 확인창 취소 후 재진입', '원본·OS 예약·이력이 변경되지 않음'),
            ('같은 삭제 버튼 빠르게 두 번 누르기', '다른 ID는 유지; 중복 종료 이력·중복 대체 예약 없음'),
        ]:
            case('ALARM', route, f'미래 {kind} 1개 준비 → {action}', expected,
                evidence='custom_alarm_service_test; g1_override_state_test; full_audit_critical_test')

for route in ['온보딩 근무별 알람', '설정 > 고정알람 수정']:
    for offset in ['전날', '당일', '다음날']:
        case('ALARM', route, f'{offset} 00:00/23:59 템플릿을 월말·연말 배정일에 저장',
             '배정일과 실제 울림 날짜 구분; 10일 롤링 범위·인접일 재계산 일치', evidence='g1_generation_fixture_test; AlarmDayOffsetPriorityTest')
    for action, expected in [
        ('근무당 0→1→5개 추가 후 6번째 추가 시도', '상한 5개; 삭제 후 한 칸 추가 가능'),
        ('동일 시각 템플릿 중복 저장', '중복 예약 없음; 사용자 안내와 DB 일치'),
        ('수정 후 저장하지 않고 뒤로가기', '확인/취소 정책대로 원본 유지 또는 저장; 부분 반영 없음'),
        ('저장 버튼 연타·저장 직후 백그라운드', '중복 템플릿·중복 OS 예약 없이 완료 상태 회복'),
    ]:
        case('ALARM', route, action, expected, evidence='g1_generation_fixture_test; g1_schedule_failure_test')

one_tap = [
 ('빈 칸에 시각·종류 저장→재실행', '5칸 설정 유지; 다음 알람에는 할당 전 행 없음'),
 ('오늘 지난 시각·현재 시각·1분 뒤 각각 할당', '지난/현재 거절, 미래만 생성'),
 ('모레·어제·다른 달 날짜 탭', '오늘/내일 이외 생성 및 일반 날짜 팝업 차단'),
 ('월말 밤에 내일 할당', '다음 달 1일로 assigned_day/예약 일치'),
 ('같은 칸 오늘·내일 할당→오늘 재할당', '오늘/내일 각 1개, 중복 거절'),
 ('내일 5칸 할당→고정 별도 추가', '원터치 5개 유지, 고정 포함 총합을 5개로 잘못 제한하지 않음'),
 ('할당된 칸 편집 시도', '연결된 날짜 안내와 수정 잠금; 원본 유지'),
 ('오늘·내일 연결 칸 삭제 취소→확인', '취소는 무변경; 확인은 연결 미래만 취소/이력; 다른 칸 유지'),
 ('삭제한 칸 번호 재사용', '이전 연결·이력이 새 알람에 잘못 연결되지 않음'),
 ('고정 먼저 생성→동일 분 원터치', '고정 1개 유지, 원터치 생성 거절'),
 ('원터치 먼저 생성→고정 템플릿 추가', '원터치 1개; 건너뛴 고정의 허위 생성/삭제 이력 없음'),
 ('가려진 고정 존재→원터치 개별 삭제', '확인창 대체 알람 안내; 유효한 고정 1개 재예약'),
 ('가려진 고정 변경/삭제→원터치 삭제', '현재 설정으로만 대체; 예전 고정이 살아나지 않음'),
 ('원터치 생성 중 Native 예약 예외', '실패 안내; 알람 행·생성 로그 롤백'),
 ('원터치 삭제 뒤 대체 고정 예약 실패', '실패/일부실패 안내, 재시도 경로; 성공으로 오표시 안 함'),
 ('원터치 울림 중 설정 칸 삭제', '현재 회차를 잘못 종료하지 않음; 미래 연결만 제거'),
 ('구 dev preset_slot 없는 custom 행과 새 칸 혼재→칸 삭제', '레거시 행을 엉뚱한 칸 연결로 삭제하지 않음'),
 ('패널 선택 상태에서 뒤로가기 두 번', '선택 해제→패널 닫기; 달력 제스처 복귀'),
]
for steps, expected in one_tap:
    case('ONETAP', '달력 원터치 패널 / 설정 칸', steps, expected, evidence='custom_alarm_service_test; custom_alarm_panel_test; full_audit_critical_test')

for steps, expected in [
 ('고정·원터치·스누즈와 생성/종료 이력 준비→모든 알람 완전 삭제', '세 종류와 템플릿·OS 예약 삭제, 이력·생성 로그 유지'),
 ('모든 알람 삭제 취소', '행·템플릿·예약 모두 유지'),
 ('모든 알람 삭제 후 앱 재실행·자정·부팅', '삭제한 템플릿에서 알람이 부활하지 않음'),
 ('A 울림 중 미래 B만 삭제', 'A 재생·회차·제어 유지, B만 취소 이력'),
 ('A 울림 중 A를 목록에서 삭제', '회차 한 번 종료; 이력 중복 없음'),
 ('전체 근무표 초기화 취소→확인', '취소 무변경; 확인은 코드상 이력/생성로그까지 삭제하는 예외임을 표시와 대조'),
 ('종료한 알람의 오래된 알림 액션 다시 전달', '새 알람 회차를 종료하거나 스누즈하지 않음'),
]:
    case('DELETE', '다음알람 / 설정 / 알림', steps, expected, evidence='G1RingRoundTest; full_audit_critical_test; schedule_provider.resetSchedule')

for source in ['잠금 전체화면', '해제 오버레이', '알림 제어 버튼', 'Flip 커버']:
    for steps, expected in [
        ('소리+진동·진동·무음 각 1회 발생→끄기', '해당 회차 종료·OS/알림 정리·이력 1개; 실제 체감은 HUMAN'),
        ('5분 후→재울림→끄기', '누른 실제 시점+300초; 같은 회차 중복 예약 없음'),
        ('5분 후 시각에 B가 있을 때 스누즈', '추가 스누즈 없음; A 종료, B 유지, 충돌 안내·이력 일치'),
        ('끄기와 5분 후 거의 동시에 전달', '최초 유효 액션만 반영; 중복 이력·잔여 소리 없음'),
    ]:
        case('RING', source, steps, expected, evidence='G1RingRoundTest; AlarmSnoozeDstTest; CoverAlarmNotificationTest')

for steps, expected in [
 ('재생 중 아무 조작 없이 기본 타임아웃까지 대기', '자동 종료·관련 알림 정리·timeout 이력 1개'),
 ('사전 알림 20분 경계 진입→알람 수정/삭제', '사전 알림이 최신 예약과 일치, 삭제 후 유령 알림 없음'),
 ('연속 알람 A→B 인계 중 A 액션', 'B 회차를 오래된 A 액션이 제어하지 않음'),
 ('이어폰·Bluetooth·통화·DND·볼륨0 조건', 'OS 정책 및 앱 설정에 따른 전달을 로그와 물리 소리 별도 판정'),
 ('최근 앱 목록 제거 후 대기', '일반 프로세스 종료와 강제중지 구분; 예약 전달·이력 확인'),
 ('Android 설정에서 강제중지 후 재실행', 'OS 강제중지 제한을 기록; 재실행 뒤 예약 회복'),
]:
    case('RING', '기기 알람', steps, expected, evidence='G1RingRoundTest; G1WakeSyncTest')

for trigger in ['앱 재실행', '자정 Guard', '재부팅 잠금 해제 전', '재부팅 잠금 해제 후', '앱 덮어쓰기 업데이트', '정확한 알람 권한 재허용', '시간대 변경', '수동 시각 변경']:
    case('REFRESH', trigger, '고정·원터치·스누즈·개별 삭제/종류 예외가 섞인 데이터 준비→트리거',
         '고정만 필요한 diff; 원터치/스누즈 보존; DB 예정 epoch와 OS 예약 대응; 중복/부활 없음', evidence='G1GenerationEngineTest; G1WakeSyncTest; AlarmSnoozeDstTest')
for steps, expected in [
 ('날짜 근무 A→B→A', '인접 실제 날짜 재생성; 바뀐 배정의 오래된 예외 정리'),
 ('템플릿 시각 A→B→A', '같은 ID/예외를 무조건 재사용하지 않음; 현 원본 일치'),
 ('근무명 A/B 맞교환', '템플릿·근무표·시간 설정의 참조 일괄 변경'),
 ('여러 날짜 일괄배정과 Native 갱신 경합', '커밋된 일정에 수렴; 서로 다른 스냅샷 혼합 없음'),
 ('동일 설정으로 연속 갱신', '유효 ID 유지·불필요 이력 증가/중복 OS 예약 없음'),
 ('고정 생성 중 DB 실패', '트랜잭션 롤백; 커밋 전 OS 예약하지 않음'),
 ('DB 커밋 직후 OS 예약 일부 실패', '실패 ID 추적·재시도; 이미 성공한 ID 중복 없음'),
 ('10일 롤링 마지막 날·11일째 및 전후날 기여', '지정 범위와 인접 근무 기여 누락 없음'),
 ('개별 override 29/30/31일 경과', '보존/정리 경계가 코드 정책대로 동작'),
 ('같은 실제 시각 전날/당일/다음날 템플릿 경쟁', '당일 우선, 지정 우선순위 일치; 1개 예약'),
]:
    case('REFRESH', '달력 근무 수정 / 설정 / 갱신 엔진', steps, expected, evidence='g1_override_state_test; g1_generation_fixture_test; G1GenerationEngineTest')

for zone, day, start, end in [('New York','2026-11-01','00:59','첫 01:04'),('New York','2026-11-01','첫 01:58','둘째 01:03'),('London','2026-10-25','00:59','첫 01:04'),('London','2026-10-25','첫 01:58','둘째 01:03'),('New York','2026-03-08','01:58','03:03')]:
    case('DST', '잠금/오버레이/알림 중 각각 별도 회차', f'{zone} {day} {start}에서 스누즈 → {end}',
         '실제 300초; offset DB·OS epoch·첫/둘째 표시·이력 일치. 기기 시간 변경 전 원래 값 기록', evidence='AlarmSnoozeDstTest; alarm_snooze_instant_test; 스누즈_DST_보완_2026-09-30.md')
for steps, expected in [
 ('첫 01:04 스누즈와 둘째 01:04 고정 동시 존재', '표시는 같아도 실제 epoch가 다르므로 둘 다 유지'),
 ('스누즈 중 뉴욕→런던→서울 이동', '실제 목표시점 유지; 현재 시간대로 표시'),
 ('스누즈 중 재부팅/프로세스 종료/백업 복원', '이월·재예약 시 offset 보존; 첫 시각이 둘째로 밀리지 않음'),
 ('봄 존재하지 않는 고정 현지 시각', 'gap 간격 앞으로 보정; 실제 중복은 한 번'),
 ('가을 중복되는 고정 현지 시각', '둘째 시각 한 번; Dart/Native 계산 일치'),
 ('구버전 offset 없는 반복 시간 데이터', '어느 회차였는지 복구했다고 주장하지 않음; 호환 읽기'),
]:
    case('DST', '다음알람 / 이력 / OS 예약', steps, expected, evidence='alarm_dst_test; AlarmDstTest; alarm_snooze_backup_test')

backup = [
 ('직접→자동→직접→자동 저장', '각 슬롯 최신 1개; 서로의 정상 파일을 삭제하지 않음'),
 ('직접/자동 동시 요청 및 저장 중 추가 변경', '종류별 대기 병합 후 직렬 실행; 마지막 변경 반영'),
 ('백업 내용 동일→설정만 변경→메모만 변경', '동일 자동 백업 생략; 설정/데이터 변경은 지문 변화'),
 ('스케줄 초기화 직후 자동 백업', '빈 근무표로 정상 자동 슬롯 덮어쓰지 않음'),
 ('이전 단일슬롯 형식→첫 두슬롯 저장', '성공 후에만 구파일 정리; 실패 시 정상 사본 유지'),
 ('MediaStore 쓰기 실패·공간 부족·검증 읽기 실패', '이전 정상 파일 유지; 마지막 성공시각/지문 거짓 갱신 없음'),
 ('파일 선택 취소·권한 취소', '현 DB/설정/예약 불변'),
 ('잘린 JSON·빈 파일·초과 크기·지원하지 않는 버전', '변경 전 거절; 원본 파일 보존'),
 ('필수 테이블/열 누락·자료형 오류·허용 안 된 시스템 테이블', '검증에서 거절; DB/OS 변경 없음'),
 ('2월30일·13월·24시·60분·60초·잘못된 assigned_day', '다른 시각으로 정규화하지 않고 거절'),
 ('고정/스누즈가 포함된 편집 백업', '복원 입력 거절; 정상 export는 미래 custom만 포함'),
 ('공유 소유권·권한·설치별 키가 든 구백업', '로컬 공유 의도/UID/권한을 이전 기기 값으로 덮지 않음'),
 ('custom preset_slot/assigned_day 연결 누락·범위초과', '연결 완전성 검증; 잘못된 칸 재사용 안 함'),
 ('현재 스누즈 ID와 백업 custom ID 충돌', '스누즈 원래 ID 유지; custom 새 ID 매핑; 재개 때 동일 매핑'),
 ('같은 백업 두 번 복원', '이력 자연키 병합; 중복 이력/중복 미래 알람 없음'),
 ('첫/둘째 반복 시간의 두 이력 복원', '실제 시점 다르면 둘 다 보존·정렬'),
 ('알람 울림 직전/도중 복원', '진행 중 회차 보호; epoch 변경 시 롤백/재시도'),
 ('복원 도중 회차 계속 변경', '무한 반복 안 함; 5회 한계 후 작업 보존'),
 ('백업에 없는 설정키가 현재 존재', '복원 대상 키만 기본값으로; 설치별 키 유지'),
 ('DB 적용 중 제약 오류', '원본 테이블 부분 적용 없음; 작업 보존·재개 가능'),
 ('OS 정리 실패 / 최종 재조정 실패', '실패 안내·작업 파일 보존·잠금 해제·재시도 가능'),
 ('작업 사본 분실·내용 변조·job.json 손상', '현재 DB로 안전 종료; 거짓 복원 완료 없음'),
 ('복원 중 직접/자동 백업 요청', '중간 데이터로 정상 백업 슬롯 덮어쓰지 않음'),
 ('KO 백업→EN 복원→KO 복귀', '숨긴 기능 데이터/원터치 보존; EN 신규 진입/알림 정책 유지'),
 ('재설치 뒤 Download 파일 직접 선택', '자동 소유권 접근 가정 없이 수동 선택 복원'),
]
for steps, expected in backup:
    case('BACKUP', '설정 백업/복원 및 중단 복구', steps, expected,
         evidence='full_audit_critical_test; cross_review_backup_friend_test; BackupFileReaderTest; BackupFileNamingTest')
for phase in ['validated', 'locked', 'osCleared', 'dbApplied', 'prefsApplied', 'osReconciled']:
    case('BACKUP', '복원 중단 화면', f'{phase} 단계 이후 dev 프로세스 종료→재시작→이어서 복원 / 현재 데이터로 계속',
         'job 단계와 ID 매핑 유지; 성공한 단계 불필요 중복 적용 없음; 최종 DB/설정/OS 일치; 완료 전 기록 삭제 안 함', evidence='restore_coordinator.dart; RestoreOs.kt')

friends = [
 ('공유 off→이름 입력→공유 시작→코드 복사', '서버 확인 여부 구분; 인증 UID 소유 문서·세대값 확인'),
 ('공유 활성→근무 A→B→A', '최종 스냅샷과 수신자 달력 일치; 불필요 같은 payload 업로드 생략'),
 ('공유 활성→날짜별 예외/색상/근무명 변경', '수신자 앱·웹에서 최신 패턴/배정/색상 확인'),
 ('공유 활성→전체 스케줄 초기화→새 패턴 생성', '빈 중간 상태와 새 패턴의 서버 갱신 시점을 기록; 과거 표를 최신이라고 표시하지 않음'),
 ('공유 활성→백업 복원', '현재 공유 의도 유지; 복원한 패턴 dirty 재업로드'),
 ('공유 중지 온라인→수신자 새로고침', '서버 삭제/취소 확인 후 등록·캐시 제거'),
 ('공유 중지 오프라인→앱 종료→온라인 재시작', 'stop_pending 보존·삭제 재시도; ACK 전 링크가 남을 수 있음 안내'),
 ('업로드 ACK 대기 중 공유 중지', '뒤늦은 ACK가 active를 부활시키지 않음'),
 ('중지→즉시 다시 시작→오래된 응답', 'generation 순서 유지; 최신 의도만 유효'),
 ('업로드 실패/권한거부/타임아웃', 'dirty 유지·확정 상태 거짓 갱신 없음; 재시도 수렴'),
 ('친구 코드 잘못된 prefix·슬래시·빈값·중복', '거절; 중복 행 없음'),
 ('친구 추가 연타/동시 같은 코드', 'owner_id UNIQUE·UI 결과 일치'),
 ('네트워크 없이 새 친구 추가', '확인불가 등록 정책; 미조회 빈 상태, 삭제된 친구라고 단정 안 함'),
 ('캐시 있는 친구→오프라인 진입', '마지막 캐시 유지·미확인 안내; 최신으로 오표시 안 함'),
 ('서버 실제 notFound/revoked→조회', '오프라인과 구분해 등록/캐시 제거'),
 ('서버 payload 중첩 자료형 오류', '앱 크래시 없이 invalid; 이전 캐시를 최신으로 오표시 안 함'),
 ('친구 0/1/10/100명→목록 왕복·마지막 삭제', '명시적 상한 없음; 스크롤/하단 safe area/빈 상태 정상'),
 ('목록 처음 열기와 초기 DB load 경합', '초기 빈 state 때문에 자동 조회 누락 안 함'),
 ('2분 이내 왕복→pull to refresh', '자동 스로틀, 명시적 갱신은 수행; 읽기 건수 기록'),
 ('친구 전체 조회 중 항목 삭제', '삭제 항목 부활/오래된 UI 재삽입 없음'),
 ('한국어 공유 중→영어 오프라인→온라인', '신규 업로드 차단·stop_pending 처리; 숨김만 하고 계속 공유하지 않음'),
 ('익명 인증 준비 실패 후 회복', '알람/달력 사용 가능; 공유 재시도 시 준비 상태 반영'),
 ('웹 링크 첫 열기/재방문/새 탭', '현재 서버 데이터 표시; 로딩 무한대기 없음'),
 ('웹 링크 삭제된 코드/손상 코드/네트워크 오류', '명확한 오류·재시도; 캐시를 최신이라고 오해시키지 않음'),
 ('웹 배포 후 기존 열린 탭·PWA', '정적 캐시와 근무표 최신성 분리; 새 자산·아이콘 실제 갱신 확인'),
 ('규칙 다른 UID 쓰기·삭제·전체 목록 query', '거절; 본인 문서 쓰기만 허용, 제품 정책에 따른 단건 공개 읽기'),
 ('공유 payload에 메모/일정/알람시각·진단 민감정보', '공유 계약 밖 데이터 유출 없음'),
]
for steps, expected in friends:
    case('FRIEND', '내 공유코드 / 친구목록 / 수신자 앱·웹', steps, expected,
         evidence='friend_sync_state_test; friend_provider_cache_test; friend_schedule_data_test; t13_rules.test.mjs')

for steps, expected in [
 ('첫 설치 / 업데이트 후 첫 실행 / 두 번째 콜드 / warm resume를 분리 측정', '각 3회 정도, Android TotalTime·core ready·첫 사용 프레임 기록; 반복 원인 없이 추가 실행 안 함'),
 ('온라인 / 비행기모드 / 느린 네트워크에서 시작', 'Firebase 최대10초 경로와 DB/광고 layout 시간을 구분; 제보 원인 확정은 실제 증거 필요'),
 ('DB 오류 / DB open 미완료→재시도→늦게 온 이전 결과', '15초 진행·45초 재시도 정책, 오래된 초기화 결과 무시'),
 ('UMP 동의 / SDK 초기화 장기 지연', '핵심 화면 사용 가능; 늦은 광고는 현재 창 폭 사용'),
 ('큰 DB 이력 / 폰트 첫 다운로드 / 분류기 첫 로딩', '동기 CPU 작업·IO·네트워크 대기를 각각 측정'),
 ('시작 중 접힘→펼침 / 다른 앱 전환', '첫 화면 재구성·테마·광고 폭 정상; 중복 시작 없음'),
]:
    case('START', '앱 시작', steps, expected, evidence='startup_gate_test; ad_startup_layout_test; firebase_bootstrap_test')

for steps, expected in [
 ('KO→en_US→en_GB→KO', '탭 5/3 및 지역 주시작·날짜 형식; 저장 기능 데이터 유지'),
 ('12/24시간 설정을 편집기 열기 전/도중 변경', '00:00/12:00/13:00/23:59 표시·저장 왕복; AM/PM 변환 1회'),
 ('영어 도움말·개인정보·권한·오류·백업', '제외 기능을 현재 제공한다고 안내하지 않음; 한국어 잔류/치환 인자 오류 없음'),
 ('숨긴 테마를 KO에서 선택→EN→KO', 'EN 기본 fallback; KO 원래 테마 복귀'),
 ('기존 원터치·일정·수면 위젯 준비→EN', '원터치 기존 예약은 유지/관리 가능; 일정 새 알림 차단; 수면 위젯 비활성'),
 ('Day Off / Day Shift / Night duty / Long Day / Twilight 입력', '10자 이내 지원 라벨 저장·읽기; Chip/알람/이력 말줄임·전체 확인 동선'),
 ('Night Shift / Early Shift / Afternoon Shift 입력', '현재 10자 상한의 실제 입력 차단/절단 결과 기록; 지원된다고 표시하지 않음'),
]:
    case('ENGLISH', '온보딩부터 설정·Native·위젯', steps, expected, evidence='english_release_copy_test; english_release_layout_test; EnglishReleaseTest; alarm_time_format_test')

for area, route, steps, expected in [
 ('BASIC','달력 메모','추가→수정→삭제 / 저장 완료 직후 종료→재시작','저장 완료된 메모 유지; 삭제만 반영; 0/1/3개 표시'),
 ('BASIC','일정관리','추가→시각/날짜 수정→알림 ON/OFF→삭제','이전 예약 취소, 현재 예약 1개, 삭제 후 알림 없음'),
 ('BASIC','수면','수동 추가→겹침 거절→수정→삭제 / 후보 확인·거절','합계·기록 일치; 미확인 후보 합계 제외'),
 ('BASIC','근무시간/OT','출퇴근·자정넘김·휴게·OT 수정→집계 기간 변경','중복/누락 없는 집계; 날짜경계 정상'),
 ('DEV2','패턴 전달','온보딩/기존설정 수신→옛 고정과 원터치 비교','고정·원본 패턴 교체, 원터치/메모 유지; 옛 OS 예약 제거'),
 ('DEV2','패턴 전달','잘린 코드·잘못된 버전·DB 실패','기존 패턴/알람/메모/설정 롤백'),
 ('DEV2','진단 파일','생성→공유시트 취소→알람 발생','민감 본문/공유 코드 없음; 실패/취소가 알람 막지 않음'),
 ('DEV2','공휴일','캐시·0~7일 첫조회·14일 갱신·오프라인','조회주기/정상 캐시 보존; Dart/Native 기본 날짜 일치'),
 ('DEV2','업데이트 안내','재시작·같은 버전·새 버전·통신 실패','중복 안내 억제; Play 트랙 확인은 실제 설치 경로 별도'),
 ('DEV2','새 기능 조합','원터치+개별 고정 예외+패턴 수신+복원+갱신','서로의 원본/예외/이력/공유 의도 손상 없음'),
 ('DEV2','영어 게이트와 기존 기능','언어전환+공유 stop_pending+스누즈+복원','숨김과 데이터 유지 분리; 로컬 의도·epoch 보존'),
 ('DEV2','커버와 기존 알람','커버↔내부 전환 도중 알림/끄기/스누즈','동일 회차 유지; 커버 조용한 채널↔기본채널 복원'),
]:
    case(area, route, steps, expected, evidence='자동검증 결과 CSV의 관련 소스/테스트명 참조')

for steps, expected in [
 ('소리 7종/제조사 알람음·볼륨·진동 체감', '선택한 소리/진동, 끄기 뒤 잔여 재생 없음'),
 ('잠금/Doze/재부팅 뒤 실제 깨우기 체감', '예약 로그와 별개로 화면·소리·진동 실제 전달 확인'),
 ('Codex가 남긴 SRTL KO/EN 화면 자유 탐색', '폰트·칩 가독성, 터치 여유, 불합리한 UI를 독립 기록'),
 ('S26 영어 Codex 인계 상태에서 자유 확인', '입력한 실제 영문 라벨/메모 그대로 확인; KO 반복 제외'),
 ('기본/큰 글자·제스처/3버튼 내비게이션 체감', '하단 버튼·목록 마지막 행 접근, 시스템 영역 오터치 없음'),
]:
    case('HUMAN', '최소 직접확인', steps, expected, owner='HUMAN')

# Screens are individual routes, not artificial device-count multiplication.
screens = [
 ('시작 로딩/지연/실패/재시도','startup_gate.dart','공통'),
 ('스플래시','splash_screen.dart','공통'),
 ('권한 소개/권한 경고/시스템 설정 복귀','permission_intro_screen.dart','공통'),
 ('온보딩 환영/정기·불규칙 선택','onboarding_screen.dart','공통'),
 ('온보딩 근무 추가/삭제/이름 입력','onboarding_screen.dart','공통'),
 ('온보딩 패턴 배열/오늘 인덱스','onboarding_screen.dart','공통'),
 ('온보딩 근무별 고정 알람/시각/전후날','onboarding_screen.dart','공통'),
 ('다음알람 빈 상태/원형/스누즈 첫둘째 회차','next_alarm_tab.dart','공통'),
 ('등록 알람 읽기 전용 시트 / 현재 알람 카드 종류변경·삭제확인','next_alarm_tab.dart','공통'),
 ('전체 알람 이력/생성로그/회차 설명','all_alarms_history_view.dart','공통'),
 ('달력 날짜 상세/알람/메모/근무 변경','calendar_tab.dart','공통'),
 ('달력 월 이동/오늘/6주/미배정/일괄배정','calendar_tab.dart','공통'),
 ('달력 메모 입력/편집/삭제/키보드','calendar_tab.dart','공통'),
 ('달력 원터치 5칸/선택/칸편집/삭제확인','calendar_tab.dart','KO만; EN 진입숨김'),
 ('달력 테마 선택/미리보기','calendar_theme_picker_screen.dart','공통'),
 ('전체 조 설정/조 이름/오프셋/내 조','all_teams_setup_screen.dart','공통'),
 ('전체 근무표/월 이동/조별 긴 이름','all_shifts_view.dart','공통'),
 ('메모 전체목록/날짜 이동/긴 목록','memo_list_view.dart','공통'),
 ('설정 메인/긴 스크롤/백업시각/탭설정','settings_tab.dart','공통'),
 ('설정 근무표 메뉴/패턴 변경/초기화 확인','settings_tab.dart','공통'),
 ('설정 근무명 수정/중복오류/색상 선택','settings_tab.dart','공통'),
 ('설정 고정알람 목록/편집/추가/저장확인','settings_tab.dart','공통'),
 ('설정 알람종류/소리목록/볼륨/진동','settings_tab.dart','공통'),
 ('시스템 알람음 선택/문서 선택/공유시트','settings_tab.dart','공통; OS'),
 ('근무시간/휴게/OT/집계기간/급여일','work_hours_settings_screen.dart','공통'),
 ('백업 복원 선택/정보/덮어쓰기 확인','restore_backup_screen.dart','공통'),
 ('복원 진행/오류','restore_progress_screen.dart','공통'),
 ('중단 복원/이어서/현재데이터 사용','restore_interrupted_screen.dart','공통'),
 ('친구목록 0/1/100/미확인/손상/삭제확인','friend_list_screen.dart','KO만; EN 숨김'),
 ('친구 추가 이름/코드/키보드/오류','friend_list_screen.dart','KO만; EN 숨김'),
 ('친구 달력/월 이동/캐시 안내','friend_calendar_view.dart','KO만; EN 숨김'),
 ('내 공유코드/이름변경/중지/대기 배너','my_share_code_screen.dart','KO만; EN 숨김'),
 ('일정관리 타임라인/날짜줄/추가·수정/알림','schedule_management_tab.dart','KO만; EN 숨김'),
 ('수면 메인/후보/편집/근무시간/규칙 안내','condition_tab.dart','KO만; EN 숨김'),
 ('수면 전체달력/기록상세','sleep_calendar_full_screen.dart','KO만; EN 숨김'),
 ('도움말 모든 펼침 섹션/긴 설명','help_screen.dart','공통; EN 항목축소'),
 ('개인정보 전체 스크롤/외부링크','privacy_policy_screen.dart','공통; EN 문구차이'),
 ('친구 웹/PWA안내/없음/오류/재시도','../web_main.dart','KO 공유 뷰어'),
 ('잠금 알람 전체화면/긴근무명/큰글자','native:AlarmActivity.kt','공통'),
 ('해제 알람 오버레이/가로/인셋','native:AlarmOverlayService.kt','공통'),
 ('Flip 커버 알람/접힘펼침/2버튼','native:CoverAlarmLayout.kt','공통; Flip8'),
 ('사전알림/제어알림/완료알림/언어','native:NotificationHelper.kt','공통'),
 ('홈 달력 위젯 최소폭/월전체/메모3개/긴근무명','native:CalendarWidgetProvider.kt','공통'),
 ('수면 위젯/후보/시작종료','native:SleepWidgetProvider.kt','KO만; EN 비활성'),
]
theme_source = (ROOT / 'lib/models/calendar_theme.dart').read_text(encoding='utf-8')
# Explicit current IDs; verify against source inventory rather than stale docs.
match = re.search(r'enum CalendarThemeId\s*\{([^}]+)', theme_source)
if match:
    for theme in re.findall(r'^\s*(\w+)\s*[,;]', match.group(1), re.M):
        screens.append((f'달력 테마 {theme} 0/1/3메모·6주·공휴일', 'calendar_tab.dart', 'KO 전체; EN 허용6개/나머지 fallback'))
ui = []
for i, (name, source, scope) in enumerate(screens, 1):
    ui.append(dict(ID=f'UI-{i:03}', 화면과상태=name, 소스=source, 언어적용=scope,
        로컬='320/500/501/600dp 및 기존 바형/폴드; 자동검증표에 실제 실행 범위만 기록',
        검사='기본/큰글자; 키보드; 긴목록 끝; SafeArea; 접힘↔펼침/가로; 저장·뒤로가기 상태; 잘림·겹침·터치',
        Fold8_KO='대기', Fold8_EN='대기', Fold8Ultra_KO='대기', Fold8Ultra_EN='대기',
        Flip8_KO='대기', Flip8_EN='대기', S26_EN='대기', 사용자교차판정='대기', 증거=''))

write_csv('기능_상태전이.csv', cases)
write_csv('화면_체크리스트.csv', ui)

# Preserve each numbered original device step, including exact original wording.
legacy = (ROOT / 'docs/next_version/교대시계_dev_실기기_테스트.txt').read_text(encoding='utf-8-sig')
legacy_rows = []
for m in re.finditer(r'^(\d+-\d+)\. (.+)$', legacy, re.M):
    identifier, text = m.groups()
    legacy_rows.append(dict(ID=identifier, 원문=text.strip(), 상태='사용자완료보고' if identifier.startswith('1-') else '이번빌드미실시',
        담당='사용자 완료 보고' if identifier.startswith('1-') else 'USB Codex; 소리/진동만 HUMAN',
        비고='DB v24→v25 재시험 제외' if identifier.startswith('1-') else '영어 수면/패턴/원터치 신규진입 항목은 현재 EN 숨김 정책 적용', 증거=''))
write_csv('기존_실기기_이관.csv', legacy_rows)

# Inventory actual source surfaces to make unreviewed areas visible.
inventory = []
for folder in ['lib/screens', 'lib/providers', 'lib/services', 'lib/widgets', 'android/app/src/main/kotlin/com/hwani1103/shiftbell']:
    for path in sorted((ROOT / folder).rglob('*')):
        if path.suffix not in ('.dart', '.kt'):
            continue
        text = path.read_text(encoding='utf-8-sig')
        entries = []
        for no, line in enumerate(text.splitlines(), 1):
            if re.search(r'(showDialog|showModalBottomSheet|onPressed:|onTap:|onLongPress:|^\s*(?:static )?Future<.*\w+\(|^\s*(?:override )?fun \w+\()', line):
                entries.append(f'{no}: {line.strip()}')
        inventory.append(dict(파일=path.relative_to(ROOT).as_posix(), 진입점수=len(entries), 진입점='\n'.join(entries),
            주의='정적 목록화는 동작 통과 판정이 아님'))
write_csv('소스_진입점.csv', inventory)

def read_text(path):
    data = path.read_bytes()
    return data.decode('utf-16') if data.startswith((b'\xff\xfe',b'\xfe\xff')) else data.decode('utf-8-sig', errors='replace')

automated = []
usb_run = ROOT / 'build/usb_audit_2026-09-30'
usb_final_logs = ['restore_resume_regression', 'alarm_list_layout_final',
                  'english_label_alignment', 'english_calendar_alignment_layout',
                  'time_format_resume', 'delete_all_regression',
                  'overtime_settings_layout', 'friend_density_safe_area',
                  'r2_date_alarm_popup_layout']
logfiles = sorted(RUN.glob('*.jsonl')) + [
    usb_run / (name + '.jsonl') for name in usb_final_logs
    if (usb_run / (name + '.jsonl')).exists()]
for logfile in logfiles:
    if 'before' in logfile.stem:
        continue
    suites, tests, done, errors = {}, {}, {}, {}
    for line in read_text(logfile).splitlines():
        try: event = json.loads(line)
        except ValueError: continue
        if event.get('type') == 'suite': suites[event['suite']['id']] = event['suite']['path']
        if event.get('type') == 'testStart': tests[event['test']['id']] = event['test']
        if event.get('type') == 'testDone': done[event['testID']] = event
        if event.get('type') == 'error': errors[event['testID']] = event.get('error','')
    for id_, test in tests.items():
        name = test['name']
        if name.startswith('loading ') or name in ('(setUpAll)', '(tearDownAll)') or name.endswith(' (setUpAll)') or name.endswith(' (tearDownAll)'):
            continue
        result = done.get(id_, {})
        status = 'SKIP' if result.get('skipped') else {'success':'PASS','failure':'FAIL','error':'FAIL'}.get(result.get('result'), 'NOT_FINISHED')
        source = suites.get(test['suiteID'], '').replace(str(ROOT).replace('\\','/')+'/', '')
        automated.append(dict(실행=logfile.stem, 소스=source, 테스트=name, 상태=status,
            상세=errors.get(id_,''), 근거=logfile.relative_to(ROOT).as_posix(), 범위='로컬 자동검사; 실제 OS/기기 검증 아님'))

xml_root = RUN / 'native_final'
if not xml_root.exists():
    xml_root = ROOT / 'build/app/test-results/testDevDebugUnitTest'
for run_name, results in [('native_final', xml_root), ('r3_native_results', usb_run / 'r3_native_results')]:
 for file in sorted(results.glob('TEST-*.xml')):
     tree = ET.parse(file).getroot()
     for item in tree.findall('testcase'):
         failure = item.find('failure')
         if failure is None: failure = item.find('error')
         automated.append(dict(실행=run_name, 소스=tree.attrib['name'], 테스트=item.attrib['name'],
             상태='FAIL' if failure is not None else 'SKIP' if item.find('skipped') is not None else 'PASS',
             상세=failure.attrib.get('message','') if failure is not None else '',
             근거=file.relative_to(ROOT).as_posix(), 범위='Robolectric/JVM; 실제 울림 전달 아님'))
for name in ['firestore', 'dashboard']:
    log = RUN / f'{name}.log'
    if not log.exists(): continue
    text = read_text(log)
    # Node spec reporter uses checkmarks; TAP uses ok/not ok.
    for m in re.finditer(r'^(?:[✔✖]\s+|(?:not )?ok \d+ - )(.+?)(?: \([\d.]+m?s\))?$', text, re.M):
        automated.append(dict(실행=name, 소스='t13_rules.test.mjs' if name == 'firestore' else 'transform.test.mjs', 테스트=m.group(1),
            상태='FAIL' if m.group(0).startswith(('✖','not ok')) else 'PASS', 상세='',
            근거=log.relative_to(ROOT).as_posix(), 범위='demo Firestore 로컬 규칙' if name == 'firestore' else '로컬 집계 로직'))
write_csv('자동검증_실행결과.csv', automated)
summary = dict(기능=len(cases), 화면=len(ui), 기존실기기=len(legacy_rows), 소스=len(inventory),
    주의='누적 실행은 재검증을 포함하며 고유 테스트 수가 아님. 최초 FAIL의 해결은 본문 실행 결과 참조.',
    누적실행=Counter(row['상태'] for row in automated), 실행별={name:dict(Counter(r['상태'] for r in automated if r['실행']==name)) for name in sorted({r['실행'] for r in automated})})
(OUT / '집계.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
