"""Apply the latest 2026-10-01 user scope to the existing audit catalogs.

All previously excluded entries are included again. Preserves original PASS results.
"""

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs/next_version/전수검증_자료_2026-09-30"


def update_csv(path, classify, evidence=None):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fields = list(reader.fieldnames)
        rows = list(reader)
    for field in ("이번범위", "범위사유"):
        if field not in fields:
            fields.append(field)
    for row in rows:
        row["이번범위"], row["범위사유"] = classify(row)
        if evidence:
            evidence(row)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    return rows


def functional_scope(row):
    key = row["ID"]
    group = row["영역"]
    if key in {"DEV2-001", "DEV2-002"}:
        return "취소·기능삭제", "사용자 지시로 근무 패턴 코드 기능 전체 삭제"
    if key in {"START-006", "DEV2-008"} or group == "HUMAN" or key in {"RING-013", "RING-014", "RING-015", "RING-016"}:
        return "SRTL·사용자", "다른 기기 또는 사용자 체감이 필요한 항목"
    if group == "DST":
        return "필수·로컬", "알람 시각 정확성; 시간대 모의·단위 증거로 판정"
    if group == "ENGLISH":
        return "필수·영어", "영어 관련 항목은 전부 범위에 유지"
    if group == "DEV2":
        return "필수·dev", "dev 추가 기능은 전부 범위에 유지"
    if key in {"BASIC-001", "BASIC-002", "BASIC-003", "ONETAP-002", "ONETAP-003", "ONETAP-004", "START-002", "START-004", "START-005"}:
        return "필수·기존", "사용자가 제외 항목도 다시 포함하도록 요청"
    if group in {"ALARM", "RING", "ONETAP", "DELETE", "REFRESH", "BACKUP", "FRIEND"}:
        return "필수·중요", "기존 기능이라도 알람·갱신·복원·Firebase 위험이 큼"
    return "필수·영어UI", "영어 출시 화면 또는 시작 흐름과 연결"


def functional_evidence(row):
    if row["ID"] in {"DEV2-001", "DEV2-002"}:
        row["상태"] = "취소(기능삭제)"
        row["Codex판정"] = "사용자 지시로 기능 전체 삭제. 이전 실기기 증거는 역사 기록이며 출시 검사 대상에서 제외"
    if row["ID"] == "DEV2-006":
        row["준비와조작"] = "원터치+개별 고정 예외+복원+갱신"
    if row["ID"] == "ONETAP-001":
        row["상태"] = "PASS"
        row["Codex판정"] = "PASS: KO 달력 원터치 빈 칸 UI에서 07:00/소리+진동 저장, dev 프로세스 종료·재시작 뒤 패널에 07:00과 기존 23:11 모두 표시. 시험 칸 UI 삭제 뒤 기존 칸 유지"
        row["증거"] = "build/usb_audit_2026-09-30/r6_onetap_empty_editor.png, r6_onetap_slot_saved.png, r6_onetap_restart_panel.png, r6_onetap_slot_delete.png"
    if row["ID"] == "ENGLISH-001":
        row["상태"] = "PASS"
        row["Codex판정"] = "PASS: 실제 KO 5탭→en-US 3탭·일요일 시작·상세 Oct 1 (Thu)→en-GB 3탭·월요일 시작·상세 1 Oct (Thu)→KO 5탭·근무/메모 유지. 영어 위젯 US/GB 주 시작도 별도 확인"
        row["증거"] = "build/usb_audit_2026-09-30/r7_locale_us_app.png, r7_locale_us_detail3.png, r7_locale_gb_app.png, r7_locale_gb_detail.png, r7_locale_ko_return_app.png; r4_widget_gb.png"
    if row["ID"] == "ENGLISH-005":
        row["상태"] = "PASS"
        row["Codex판정"] = "PASS: KO 원터치 DB/OS1→EN 유지·다음알람 UI 표시·삭제취소1/1→KO 복귀1/1→EN 삭제0/0. KO 수면 기록 EN/KO 보존, 수면 위젯 공급자는 EN 없음→KO 재등록→EN 없음. KO 일정 알림 예약1→EN0→KO1, 일정 행 유지; 시험 일정 삭제 후0. 실제 홈 배치 위젯의 재배치는 UI-045 별도"
        row["증거"] = "build/usb_audit_2026-09-30/r5_sleep_*.vm.json, r5_onetap_*.json/png, r5_schedule_*.vm.json/txt; USB_20261001_locale_fix_build.json"
    if row["ID"] == "DEV2-004":
        row["상태"] = "PASS"
        row["Codex판정"] = "PASS: KO 실기기 첫조회 시각 0~7일, 서버 강제조회 성공·빈 version0 캐시·다음조회14일, SDK 오프라인 시 캐시 유지·1~2일 재시도. 시험 뒤 원래 due/cache 복원. Dart/Native 기본 날짜 일치는 로컬 parity 검사. 실제 변경 문서의 운영 반영은 별도"
        row["증거"] = "build/usb_audit_2026-09-30/r5_holiday_*.vm.json; holiday_source_parity_test.dart"
    if row["ID"] == "DEV2-003":
        row["상태"] = "부분 확인"
        row["Codex판정"] = "부분 확인: 실제 dev 진단 파일 자동 생성(193438 bytes). 영어 메모3개/시험 일정 본문·이메일·UID/share code 패턴 노출 없음. 알람 예약 시각은 이벤트에 포함. OS 파일 공유시트 취소 왕복은 별도"
        row["증거"] = "build/usb_audit_2026-09-30/private/r5_diag_latest.txt (비공개 원문); DiagReport.kt"
    if row["ID"] == "BACKUP-024":
        row["상태"] = "PASS"
        row["Codex판정"] = "PASS: KO 전체 백업→EN 복원→KO 복귀를 기본·활성 원터치·수면 기록 세 상태로 검사. 기존 일정 행1·프리셋 유지, 활성 custom 매번 DB/OS1/1, 수면 기록 동일 ID/내용 보존. EN 복원 뒤 dev 일정 알림 예약 없음, 작업/Native 잠금 없음. 시험 알람·수면 정리 후0/0"
        row["증거"] = "build/usb_audit_2026-09-30/export_r7_*.vm.json, export_r7_*_os.json; private/export_r7_*snapshot.json (비공개)"
    if row["ID"] == "ONETAP-014":
        row["상태"] = "부분 확인"
        row["Codex판정"] = "부분 확인: 로컬 MethodChannel에서 scheduleNativeAlarm 예외를 주입하자 scheduleFailed, DB 알람·생성 원장·이력0, 같은 슬롯 재시도 성공. 실기기 SCHEDULE_EXACT_ALARM appop ignore는 USE_EXACT_ALARM 때문에 실제 거부되지 않아 Native 실패 경로는 미확인; 설정/시험 알람 원복"
        if "custom_alarm_service_test.dart" not in row["로컬참고"]:
            row["로컬참고"] = row["로컬참고"] + "; custom_alarm_service_test.dart"
        row["증거"] = "test/custom_alarm_service_test.dart; build/usb_audit_2026-09-30/r6_onetap_permission_denied.vm.json, r6_onetap_permission_probe_cleanup_os.json"


def ui_scope(row):
    key = row["ID"]
    if key == "UI-033":
        return "취소·기능삭제", "사용자 지시로 패턴 코드 화면 전체 삭제"
    if key in {"UI-033", "UI-034", "UI-035", "UI-036", "UI-045", "UI-051", "UI-052", "UI-053", "UI-054"}:
        return "필수·영어숨김/복귀", "영어 숨김과 한국어 복귀 뒤 재노출·데이터 유지를 연속 검증"
    if key == "UI-042":
        return "SRTL·사용자", "Flip 커버 실물 필요"
    if key in {"UI-016", "UI-017", "UI-039"}:
        return "필수·dev/영어", "dev 추가 화면 또는 영어 공유 화면"
    return "필수·영어UI", "실제 영어 화면과 레이아웃 검사"


def ui_evidence(row):
    key = row["ID"]
    if key == "UI-033":
        row["S26_EN"] = "취소 — 근무 패턴 코드 기능 전체 삭제"
    evidence = {
        "UI-016": "실제 A/B/C 설정·저장, 내 조 전환, 이름 편집 화면 확인; 배율/회전 미완",
        "UI-017": "실제 전체 근무표 Day Shift/Day Off가 둘 다 'Da'로 잘리는 결함 확인; 수정 보류",
        "UI-018": "실제 영어 메모 목록과 날짜 이동 확인; 긴 목록 전체 조합 미완",
        "UI-029": "친구 0/1/100개·캐시·삭제 UI 실제 확인; 전체 배율 조합 미완",
        "UI-031": "서버 제거 반영·친구 달력 UI 실제 확인; 전체 배율 조합 미완",
        "UI-039": "실제 영어 PWA 첫 방문/재방문/변경/삭제/잘못된 코드 확인; 전체 배율 조합 미완",
        "UI-044": "실제 US 일요일·GB 월요일, 영어 근무명·메모3개 표시 확인; 월 전체 높이는 홈 공간 부족으로 미확인",
    }
    if key in evidence:
        row["S26_EN"] = "부분 확인 — " + evidence[key]
        marker = "build/usb_audit_2026-09-30/r3_*, r4_*"
        if marker not in row["증거"]:
            row["증거"] = (row["증거"] + "; " if row["증거"] else "") + marker
    if key in {"UI-046", "UI-047", "UI-048", "UI-049", "UI-050", "UI-055"}:
        row["S26_EN"] = "부분 확인 — 실제 영어 테마 6종 정상/150% 배율, 긴 메모3개, US/GB 주 시작 확인; 전체 조합 미완"
        marker = "build/usb_audit_2026-09-30/r3_large_notes_*, r4_*"
        if marker not in row["증거"]:
            row["증거"] = (row["증거"] + "; " if row["증거"] else "") + marker
    if key == "UI-045":
        row["S26_EN"] = "부분 확인 — EN 공급자 없음→KO 재등록→EN 다시 없음; KO 수면 기록의 EN/KO 왕복 보존 확인. 실제 기존 홈 배치와 후보/시작·종료는 미완"
        marker = "build/usb_audit_2026-09-30/r5_sleep_*.vm.json"
        if marker not in row["증거"]:
            row["증거"] = (row["증거"] + "; " if row["증거"] else "") + marker
    if key == "UI-014":
        row["S26_EN"] = "부분 확인 — KO 실기기에서 빈 원터치 칸 저장→재시작 뒤 2칸 표시→시험 칸 삭제·기존 칸 보존. 영어 UI에서는 진입 숨김; 5칸 전체·배율 조합 미완"
        marker = "build/usb_audit_2026-09-30/r6_onetap_*.png"
        if marker not in row["증거"]:
            row["증거"] = (row["증거"] + "; " if row["증거"] else "") + marker


if __name__ == "__main__":
    functional = update_csv(DATA / "기능_상태전이.csv", functional_scope, functional_evidence)
    ui = update_csv(DATA / "화면_체크리스트.csv", ui_scope, ui_evidence)
    from collections import Counter
    print("functional", len(functional), dict(Counter(row["이번범위"] for row in functional)))
    print("ui", len(ui), dict(Counter(row["이번범위"] for row in ui)))
