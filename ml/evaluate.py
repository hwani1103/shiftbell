"""
Phase 1 평가: train.py가 저장한 모델을 학습에 전혀 쓰이지 않은
eval_holdout.jsonl(짧고 축약된 문체)로 평가.

같은 생성 방식(=내가 손으로 쓴 pilot_dataset)으로 나온 train/test 분할은
문체가 같아서 정확도가 과대평가되기 쉽다. eval_holdout은 일부러 다른
문체로 써서, "학습 데이터 문체에 과적합됐는지"를 보는 용도.

추가로 boundary_cases.jsonl 전체에 대한 예측도 참고용으로 출력한다.
(주의: 이 케이스들 대부분은 이미 학습에 쓰였을 수 있어 정확도가 아니라
"어떤 경계 사례가 아직도 틀리는지" 정성적으로 보는 용도)
"""
import json
import pathlib

import joblib
from sklearn.metrics import classification_report, confusion_matrix

DATA_DIR = pathlib.Path(__file__).parent / "data"
MODEL_DIR = pathlib.Path(__file__).parent / "models"


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
    pipeline = joblib.load(MODEL_DIR / "pilot_v1.joblib")

    # --- 1. eval_holdout: 진짜 일반화 테스트 ---
    holdout = load_jsonl(DATA_DIR / "eval_holdout.jsonl")
    texts = [r["text"] for r in holdout]
    labels = [r["label"] for r in holdout]

    preds = pipeline.predict(texts)
    probs = pipeline.predict_proba(texts)
    classes = pipeline.named_steps["clf"].classes_

    print("=== eval_holdout.jsonl (60개, 학습에 안 쓰인 독립 문체) 성능 ===")
    print(classification_report(labels, preds, zero_division=0))

    labels_sorted = sorted(set(labels))
    cm = confusion_matrix(labels, preds, labels=labels_sorted)
    print("=== Confusion Matrix (행=실제, 열=예측) ===")
    header = "".join(f"{l[:4]:>6}" for l in labels_sorted)
    print(f"{'':10}{header}")
    for true_label, row in zip(labels_sorted, cm):
        row_str = "".join(f"{v:>6}" for v in row)
        print(f"{true_label:10}{row_str}")

    print("\n=== eval_holdout 오분류 상세 ===")
    n_wrong = 0
    for text, true, pred, prob in zip(texts, labels, preds, probs):
        if true != pred:
            n_wrong += 1
            confidence = prob[list(classes).index(pred)]
            print(f'  "{text}" | 실제={true} 예측={pred} (확신도 {confidence:.0%})')
    if n_wrong == 0:
        print("  (없음)")
    print(f"\n총 {len(texts)}개 중 {n_wrong}개 오분류 (정확도 {(len(texts)-n_wrong)/len(texts):.1%})")

    # --- 2. boundary_cases 전체 예측 (참고용, 학습에 포함됐을 수 있음) ---
    boundary = load_jsonl(DATA_DIR / "boundary_cases.jsonl")
    b_texts = [r["text"] for r in boundary]
    b_labels = [r["label"] for r in boundary]
    b_preds = pipeline.predict(b_texts)

    print("\n=== boundary_cases.jsonl 전체 예측 (참고용, 학습 포함 가능성 있음) ===")
    n_wrong_b = 0
    for row, pred in zip(boundary, b_preds):
        mark = "OK" if pred == row["label"] else "??"
        if pred != row["label"]:
            n_wrong_b += 1
        print(f'  [{mark}] "{row["text"]}" | 정답={row["label"]} 예측={pred} '
              f'(vs {row["confused_with"]})')
    print(f"\n{len(boundary)}개 중 {n_wrong_b}개 오분류")


if __name__ == "__main__":
    main()
