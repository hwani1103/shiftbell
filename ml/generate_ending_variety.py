"""
카테고리-내용 맵핑 점검(2026-09-01) - 어미(문장이 어떻게 끝나는지) 다양성 보강.

실측 결과 pilot_dataset.jsonl 7,254개 중 "하자"/"할거임"/"해야됨"/"할까"류
캐주얼한 의지/예정 표현은 사실상 전무했음(전부 합쳐 5건 미만, 반면 "-하기"로
끝나는 문장은 1,917개) - 즉 모델이 "OO하기" 스타일에는 익숙하지만 실사용자가
메모할 때 흔히 쓰는 "OO 할거임", "OO 하자" 같은 표현은 거의 못 보고 학습됨.

"하다" 동사는 활용이 규칙적이라(하/해/할/했/한 5개 어간만 있음, 불규칙 활용 없음)
어미 교체가 안전함 - "-하기"로 끝나는 기존 문장을 그대로 가져다 어미만 바꿔서
같은 라벨로 추가한다. "-하기"가 아닌 다른 동사(가기/사기/먹기 등, 불규칙
활용까지 고려해야 해서 이번엔 범위 밖 - 필요하면 후속으로 진행)는 이번 스코프
밖.

사용법: python ml/generate_ending_variety.py (data/pilot_dataset.jsonl에 append)
"""
import json
import pathlib
import random

import keyword_router as kr

DATA_DIR = pathlib.Path(__file__).parent / "data"
PILOT_PATH = DATA_DIR / "pilot_dataset.jsonl"

random.seed(20260901)

MAX_PER_CATEGORY = 30
VARIANTS_PER_SENTENCE = 2

# "-하기" -> 각 어미. "하러 가기"류는 이미 데이터에 61건 있어서 제외.
ENDING_VARIANTS = ["하자", "해야지", "해야됨", "할까", "할거임", "했음", "한 듯"]


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def main():
    rows = load_jsonl(PILOT_PATH)
    existing_texts = {r["text"] for r in rows}

    # ⭐ 원문 자체가 이미 하드매핑과 충돌하는 문장(예: "아이 카시트 새로
    # 구매하기" - 쇼핑이 맞는데 "아이"가 가족 하드매핑을 먼저 채감)은 증강
    # 대상에서 뺀다 - 그대로 어미만 바꿔봤자 같은 충돌을 여러 벌 복제할 뿐이라
    # (실측으로 발견, 최초 버전은 이 필터가 없어서 147건이던 충돌이 163건으로
    # 늘어났었음).
    by_label = {}
    skipped_conflicts = 0
    for r in rows:
        if not r["text"].endswith("하기"):
            continue
        hard_label, _ = kr.route(r["text"])
        if hard_label is not None and hard_label != r["label"]:
            skipped_conflicts += 1
            continue
        by_label.setdefault(r["label"], []).append(r["text"])
    print(f"이미 하드매핑과 충돌하는 원문 {skipped_conflicts}건은 증강 대상에서 제외")

    new_rows = []
    for label, texts in by_label.items():
        sample = random.sample(texts, min(MAX_PER_CATEGORY, len(texts)))
        for text in sample:
            stem = text[:-2]  # "하기" 제거
            variants = random.sample(ENDING_VARIANTS, VARIANTS_PER_SENTENCE)
            for v in variants:
                new_text = stem + v
                if new_text in existing_texts:
                    continue
                existing_texts.add(new_text)
                new_rows.append({"text": new_text, "label": label})

    with open(PILOT_PATH, "a", encoding="utf-8") as f:
        for row in new_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"카테고리 {len(by_label)}개, 총 {len(new_rows)}개 어미-변형 문장을 {PILOT_PATH}에 추가함")
    import collections
    c = collections.Counter(r["label"] for r in new_rows)
    for k, v in c.most_common():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
