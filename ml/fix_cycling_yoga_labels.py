# -*- coding: utf-8 -*-
"""
relabel_v3_cycling_yoga.py(하드매핑 자동 적용)로 못 잡는 나머지 케이스를
수동으로 확정하는 1회성 스크립트(사람이 직접 문맥 판단해서 만든 매핑).

- "자전거로"/"요가로"처럼 "로" 연결형(하드매핑이 일부러 안 잡음 - 카테고리_
  가이드.md의 "로/으로" 제외 원칙)
- "에어리얼요가"/"핫요가"/"임산부요가"처럼 다른 말과 붙어서 "요가"로 시작하지
  않는 복합어(하드매핑 anywhere=False라 안 잡음)
- "자격증" 문맥(공부로), 순수 구매(쇼핑으로), 순수 수리(기타 유지)
- boundary_cases.jsonl의 "요가원 가서 OO" 6건 + "자전거로/타고 OO" 2건은
  달리기/수영/등산이 전용 카테고리로 승격됐을 때와 동일한 원리로 재해석
  (강도/목적 무관하게 실제로 그 활동을 했으면 전용 카테고리) - label과
  rationale을 갱신.
"""
import json
import pathlib

DATA_DIR = pathlib.Path(__file__).parent / "data"

PILOT_RELABEL = {
    "자전거로 한강까지 왕복": "자전거",
    "자전거로 출퇴근하기 시작": "자전거",
    "자전거로 왕복 40km 라이딩": "자전거",
    "자전거로 강변 왕복 전력질주": "자전거",
    "자전거로 업힐 훈련": "자전거",
    "자전거 동호회 정기 라이딩": "약속/사교",  # "동호회" 신호 - 사교 우선(동네 자전거모임과 동일 원칙)
    "아침 요가로 하루 시작": "요가/필라테스",
    "요가원 첫 체험수업": "요가/필라테스",
    "요가매트 새로 사서 홈트 시작": "요가/필라테스",
    "요가원 온라인 클래스 등록": "요가/필라테스",
    "에어리얼요가 수업 참여하기": "요가/필라테스",
    "명상요가 클래스 신청하기": "요가/필라테스",
    "핫요가 스튜디오 등록하기": "요가/필라테스",
    "빈야사요가 클래스 참여하기": "요가/필라테스",
    "필라테스 자격증반 알아보기": "공부",
    "요가복 새로 사서 클래스 가기": "요가/필라테스",
    "요가매트 새로 사서 홈요가 시작": "요가/필라테스",
    "요가 블록 소도구 구매하기": "쇼핑",
    "요가 스트랩 소도구 구매하기": "쇼핑",
    "실버요가 클래스 부모님과 함께 참여": "요가/필라테스",
    "임산부요가 클래스 등록하기": "요가/필라테스",
    "요가 티칭 자격증 과정 등록하기": "공부",
    "필라테스 강사 자격증 준비하기": "공부",
    "필라테스 도구 세트 새로 구매하기": "쇼핑",
    "필라테스 국제자격증 과정 알아보기": "공부",
    "빈야사요가 클래스 참여해야지": "요가/필라테스",
    "빈야사요가 클래스 참여한 듯": "요가/필라테스",
    "핫요가 스튜디오 등록해야지": "요가/필라테스",
    "핫요가 스튜디오 등록했음": "요가/필라테스",
    "임산부요가 클래스 등록하자": "요가/필라테스",
    "임산부요가 클래스 등록한 듯": "요가/필라테스",
    "요가 자격증반 등록": "공부",
    "요가 자격증반 수업 참여하기": "공부",
}

# (text) -> (new_label, new_rationale)
BOUNDARY_RELABEL = {
    "자전거타고 동네 슬슬 한바퀴 돌기": (
        "자전거", "2026-09-03 - 자전거가 전용 카테고리로 승격되며 재해석: 등산/수영과 "
        "동일 원칙으로 강도·목적과 무관하게 실제로 타면 무조건 자전거(예전엔 운동↔여가 "
        "판단 대상이었음)"),
    "자전거로 강변 왕복 전력질주": (
        "자전거", "2026-09-03 - 위와 동일한 이유로 재해석(전력질주든 슬슬이든 자전거 "
        "카테고리로 수렴)"),
    "요가원 가서 명상 위주 수업": (
        "요가/필라테스", "2026-09-03 - 요가·필라테스가 전용 카테고리로 승격되며 재해석: "
        "명상 위주든 근력 위주든 요가원에서 실제로 수업을 들었으면 무조건 요가/필라테스"),
    "요가원 가서 근력 위주 수업": (
        "요가/필라테스", "2026-09-03 - 위와 동일 - 강도 무관하게 요가/필라테스로 수렴"),
    "요가원 가서 편안하게 스트레칭만": (
        "요가/필라테스", "2026-09-03 - 스트레칭도 신설 카테고리에 포함 - 강도/목적 무관"),
    "요가원 가서 고강도 클래스 수강": (
        "요가/필라테스", "2026-09-03 - 위와 동일 - 강도 무관하게 요가/필라테스로 수렴"),
    "요가원 가서 쉬는 느낌으로 스트레칭": (
        "요가/필라테스", "2026-09-03 - 스트레칭도 신설 카테고리에 포함 - 강도/목적 무관"),
    "요가원 가서 근력 위주 파워요가": (
        "요가/필라테스", "2026-09-03 - 위와 동일 - 강도 무관하게 요가/필라테스로 수렴"),
}


def process_pilot():
    path = DATA_DIR / "pilot_dataset.jsonl"
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    n = 0
    for row in rows:
        if row["text"] in PILOT_RELABEL:
            new_label = PILOT_RELABEL[row["text"]]
            if row["label"] != new_label:
                row["label"] = new_label
                n += 1
    with open(path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"pilot_dataset.jsonl: {n}건 수정")


def process_boundary():
    path = DATA_DIR / "boundary_cases.jsonl"
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    n = 0
    for row in rows:
        if row["text"] in BOUNDARY_RELABEL:
            new_label, new_rationale = BOUNDARY_RELABEL[row["text"]]
            row["label"] = new_label
            row["confused_with"] = "운동/여가·휴식(구 분류)"
            row["rationale"] = new_rationale
            n += 1
    with open(path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"boundary_cases.jsonl: {n}건 수정")


if __name__ == "__main__":
    process_pilot()
    process_boundary()
