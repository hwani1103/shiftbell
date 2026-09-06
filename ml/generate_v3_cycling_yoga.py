# -*- coding: utf-8 -*-
"""
카테고리 확장(17 -> 19개) - 신설 카테고리 2종(자전거/요가·필라테스) 학습
데이터 대량 생성. ml/generate_v2_data.py와 동일한 원칙/구조를 따름:

  - 직접 키워드형(하드매핑이 잡을 수 있는 형태) + 간접 표현형(키워드 없이
    문맥으로 ML이 배워야 하는 형태) 혼합
  - 캐주얼 어미("타야됨"/"타고 옴"/"할까"), 붙여쓰기("자전거타기"), 사투리·
    축약형 없이도 실사용 문체에 가깝게 다양화
  - "자전거 헬멧 사기"류 순수 구매(쇼핑), "자전거 브레이크 수리"류 순수 정비
    (기타), "자격증"류(공부) 경계 예문도 소량 같이 넣어 ML이 하드매핑 defer
    이후에도 올바르게 판단하도록 함

사용법: python ml/generate_v3_cycling_yoga.py  (data/pilot_dataset.jsonl에 append)
"""
import json
import pathlib
import random

DATA_DIR = pathlib.Path(__file__).parent / "data"
PILOT_PATH = DATA_DIR / "pilot_dataset.jsonl"

random.seed(20260903)

TARGET_PER_CATEGORY = 300


def existing_texts():
    texts = set()
    for fn in ["pilot_dataset.jsonl", "boundary_cases.jsonl", "eval_holdout.jsonl"]:
        with open(DATA_DIR / fn, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                texts.add(json.loads(line)["text"])
    return texts


def gen_sentences(templates, slots, n, seen):
    out = []
    tried = 0
    max_tries = n * 60
    while len(out) < n and tried < max_tries:
        tried += 1
        t = random.choice(templates)
        try:
            filled = {}
            for key in slots:
                if "{" + key + "}" in t:
                    filled[key] = random.choice(slots[key])
            text = t.format(**filled)
        except (KeyError, IndexError):
            continue
        text = " ".join(text.split())
        if text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


TIME_CASUAL = [
    "아침에", "새벽에", "출근 전에", "퇴근하고", "점심시간에", "오후에", "저녁에",
    "자기 전에", "주말에", "이번 주말", "다음 주말", "오늘", "내일", "모레",
    "이따가", "쉬는 날", "휴무일에", "비번날", "다음 휴무에", "D-3",
]

# ============================================================
# 1. 자전거 (cycling)
# ============================================================
CYCLING_DIRECT = [
    "{time} 자전거 타기",
    "{time} 자전거타기",
    "{time} 자전거 타야됨",
    "{time} 자전거타야됨",
    "{time} 자전거 타고 한강 가기",
    "{time} 따릉이 타고 출근",
    "{time} 따릉이 대여해서 한바퀴",
    "{time} 자전거 라이딩 {dist}",
    "{time} 로드바이크 끌고 나가기",
    "{time} 산악자전거 코스 도전",
    "{time} 자전거로 {dist} 라이딩",
    "{time} 자전거 타고 출퇴근",
    "{time} MTB 타고 임도 라이딩",
    "{time} 자전거 힐클라임 훈련",
    "{time} 자전거 타고 강변 왕복",
    "{time} 실내 자전거 인터벌 {dist}",
    "{time} 자전거 페달링 연습",
    "{time} 따릉이 타고 동네 한바퀴",
    "{time} 자전거 타고 편의점 다녀오기",
    "{time} 자전거로 등하교",
    "{time} 자전거 타고 바람 쐬기",
    "{time} 로드바이크 라이딩 {dist}",
    "주말 자전거 대회 참가 신청",
    "{time} 자전거 타고 강변 한바퀴",
    "{time} 자전거 타고 근교 나들이",
    "{time} 따릉이 타러 나가기",
]
# ⚠️ "달리기"/"뛰기"/"조깅"/"러닝" 등 RUNNING_KEYWORDS와 겹치는 단어는 절대
# 안 씀 - 간접 표현이 우연히 다른 카테고리 하드매핑에 걸려버리는 걸 방지
# (ml/check_keyword_regressions.py로 실측 검증 후 확정).
CYCLING_INDIRECT = [
    "{time} 두 바퀴로 한강 왕복하기",
    "{time} 페달 밟으면서 한강 돌기",
    "{time} 두발자전거 끌고 동네 한바퀴",
    "{time} 헬멧 쓰고 강변 라이딩 코스 돌기",
    "{time} 안장에 앉아서 강변길 질주하기",
    "{time} 두 바퀴 굴리며 동네 한바퀴",
]
CYCLING_SLOTS = {"time": TIME_CASUAL, "dist": ["10km", "20km", "30km", "40km", "한바퀴", "30분", "1시간"]}

CYCLING_BOUNDARY = [
    ("자전거 헬멧 새로 장만하기", "쇼핑"),
    ("자전거 안장 새로 주문하기", "쇼핑"),
    ("자전거 타이어 펑크 나서 수리 맡기기", "기타"),
    ("자전거 체인 정비 맡기러 가기", "기타"),
    ("자전거 자격증(생활체육지도자) 시험 준비", "공부"),
    ("자전거 동호회 정기 라이딩 참여", "약속/사교"),
]

# ============================================================
# 2. 요가/필라테스 (스트레칭 포함)
# ============================================================
YOGA_DIRECT = [
    "{time} 요가 수업 듣기",
    "{time} 요가하러가기",
    "{time} 요가 하러 가기",
    "{time} 필라테스 학원 고고",
    "{time} 필라테스 수업 가기",
    "{time} 필라테스 예약하기",
    "{time} 요가 클래스 예약",
    "{time} 요가원 등록하기",
    "{time} 필라테스 리포머 수업",
    "{time} 스트레칭하기",
    "{time} 전신 스트레칭 루틴",
    "{time} 폼롤러로 스트레칭",
    "{time} 요가 매트 깔고 홈요가",
    "{time} 필라테스 기구 수업",
    "{time} 요가 명상 클래스",
    "{time} 요가 자세 교정 수업",
    "{time} 필라테스 소도구 수업",
    "{time} 아침 요가 루틴",
    "{time} 취침 전 스트레칭",
    "{time} 필라테스 그룹 수업 참여",
    "{time} 요가 호흡법 연습",
    "{time} 필라테스 코어 운동",
    "{time} 요가 동작 따라하기",
    "{time} 필라테스 자세 연습",
    "{time} 요가 유튜브 보면서 따라하기",
    "{time} 필라테스 유튜브 보면서 따라하기",
    "{time} 스트레칭 유튜브 따라하기",
    "{time} 요가 클래스 참석",
    "{time} 필라테스 재등록하기",
    "{time} 목/어깨 스트레칭",
]
YOGA_INDIRECT = [
    "{time} 매트 깔고 몸 풀기",
    "{time} 유연성 운동 루틴 하기",
    "{time} 굳은 몸 풀어주기 동작",
    "{time} 호흡 맞춰가며 몸 늘리기 동작",
    "{time} 코어 잡아주는 기구 수업 듣기",
    "{time} 뭉친 어깨 풀어주는 동작 루틴",
]
YOGA_SLOTS = {"time": TIME_CASUAL}

YOGA_BOUNDARY = [
    ("요가 매트 새로 주문하기", "쇼핑"),
    ("필라테스 링 소도구 새로 구매하기", "쇼핑"),
    ("요가복 세일해서 몇 벌 사기", "쇼핑"),
    ("요가 지도자 자격증 시험 접수", "공부"),
    ("필라테스 강사 자격증반 등록", "공부"),
    ("동네 요가 동호회 정기 모임", "약속/사교"),
]


def main():
    seen = existing_texts()
    rows = []

    cyc = gen_sentences(CYCLING_DIRECT, CYCLING_SLOTS, int(TARGET_PER_CATEGORY * 0.75), seen)
    cyc += gen_sentences(CYCLING_INDIRECT, CYCLING_SLOTS, int(TARGET_PER_CATEGORY * 0.25), seen)
    for t in cyc:
        rows.append({"text": t, "label": "자전거"})
    for t, label in CYCLING_BOUNDARY:
        if t not in seen:
            seen.add(t)
            rows.append({"text": t, "label": label})

    yoga = gen_sentences(YOGA_DIRECT, YOGA_SLOTS, int(TARGET_PER_CATEGORY * 0.8), seen)
    yoga += gen_sentences(YOGA_INDIRECT, YOGA_SLOTS, int(TARGET_PER_CATEGORY * 0.2), seen)
    for t in yoga:
        rows.append({"text": t, "label": "요가/필라테스"})
    for t, label in YOGA_BOUNDARY:
        if t not in seen:
            seen.add(t)
            rows.append({"text": t, "label": label})

    with open(PILOT_PATH, "a", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"자전거: {len(cyc)}개 + 경계 {len(CYCLING_BOUNDARY)}개")
    print(f"요가/필라테스: {len(yoga)}개 + 경계 {len(YOGA_BOUNDARY)}개")
    print(f"총 {len(rows)}개 추가")


if __name__ == "__main__":
    main()
