"""
predict.py의 실제 파이프라인(keyword_router 하드매핑 -> ML fallback)을 그대로
eval_holdout.jsonl/boundary_cases.jsonl에 돌려서, evaluate.py(순수 ML만 테스트해서
비관적인 수치가 나옴)와 달리 실제 Dart 앱에서 체감하는 정확도에 가까운 숫자를 낸다.

사용법: python eval_e2e.py [파일명 ...]  (기본: eval_holdout.jsonl boundary_cases.jsonl)
"""
import json
import pathlib
import sys

import predict

DATA_DIR = pathlib.Path(__file__).parent / "data"


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def run(fname):
    rows = load_jsonl(DATA_DIR / fname)
    wrong = []
    hard_mapped = 0
    for r in rows:
        text = r["text"]
        gold = r["label"]
        result = predict.predict(text)
        if result["method"] != "ml" and result["method"] != "ml_low_confidence_fallback":
            hard_mapped += 1
        if result["label"] != gold:
            wrong.append((text, gold, result["label"], result["method"]))
    total = len(rows)
    acc = (total - len(wrong)) / total if total else 0
    print(f"=== {fname}: {total}개 중 {len(wrong)}개 오분류 (정확도 {acc:.1%}, 하드매핑 {hard_mapped}개) ===")
    for text, gold, pred, method in wrong:
        print(f'  "{text}" | 실제={gold} 예측={pred} (method={method})')
    print()
    return wrong


if __name__ == "__main__":
    files = sys.argv[1:] or ["eval_holdout.jsonl", "boundary_cases.jsonl"]
    for fn in files:
        run(fn)
