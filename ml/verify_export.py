"""
assets/ml/memo_category_model.json(export.py의 결과물)만으로 sklearn 없이 직접
재현한 예측이 실제 pipeline.predict_proba와 일치하는지 확인하는 회귀 검증.

**모델을 재학습/재export할 때마다 이 스크립트를 돌려서 확인할 것.** Dart 포팅
(lib/services/memo_category_classifier.dart)이 구현한 것과 같은 수식(char_wb
n-gram -> sublinear tf-idf -> L2 정규화 -> LogReg dot product -> softmax)을 여기서도
독립적으로 재현하므로, 이 스크립트가 통과하면 "export한 JSON 자체가 원본 모델을
정확히 담고 있다"는 것과 "Dart가 구현해야 할 수식이 이거다"라는 것 둘 다 확인됨
(Dart 코드 자체의 정확성은 이 스크립트로는 못 잡음 - 별도로 Dart 유닛테스트 필요).

사용법: python ml/verify_export.py  (export.py를 먼저 실행해서 JSON을 만들어둔 상태여야 함)
"""
import json
import math
import pathlib
import re

import joblib

ML_DIR = pathlib.Path(__file__).parent
MODEL_PATH = ML_DIR / "models" / "pilot_v1.joblib"
JSON_PATH = ML_DIR.parent / "assets" / "ml" / "memo_category_model.json"

TEST_SENTENCES = [
    "운동 하러가기 전에 엄마한테 전화하기",
    "친구랑 저녁 약속",
    "병원 진료 예약",
    "마트에서 장보기",
    "넷플릭스 보기",
    "회의 준비",
    "자격증 시험 공부",
    "부서 회식",
    "매형이랑 술 한잔",
    "테니스 치기",
]

MAX_ALLOWED_PROB_DIFF = 1e-4  # export.py가 float을 6자리로 반올림해서 나는 오차 정도만 허용


def char_wb_ngrams(text, min_n=2, max_n=3):
    normalized = re.sub(r"\s+", " ", text).strip()
    ngrams = []
    for word in normalized.split(" "):
        if not word:
            continue
        w = " " + word + " "
        w_len = len(w)
        for n in range(min_n, max_n + 1):
            if n > w_len:
                continue
            for i in range(0, w_len - n + 1):
                ngrams.append(w[i:i + n])
    return ngrams


def predict_proba_manual(text, vocab, idf, coef, intercept, n_classes):
    text = text.lower()
    counts = {}
    for ng in char_wb_ngrams(text):
        idx = vocab.get(ng)
        if idx is not None:
            counts[idx] = counts.get(idx, 0) + 1

    tfidf = {idx: (1 + math.log(c)) * idf[idx] for idx, c in counts.items()}
    norm = math.sqrt(sum(v * v for v in tfidf.values()))
    if norm > 0:
        tfidf = {idx: v / norm for idx, v in tfidf.items()}

    logits = list(intercept)
    for idx, v in tfidf.items():
        for c in range(n_classes):
            logits[c] += coef[c][idx] * v

    m = max(logits)
    exps = [math.exp(l - m) for l in logits]
    s = sum(exps)
    return [e / s for e in exps]


def main():
    if not JSON_PATH.exists():
        raise SystemExit(f"{JSON_PATH} 없음 - 먼저 `python ml/export.py`를 실행할 것")

    with open(JSON_PATH, encoding="utf-8") as f:
        model = json.load(f)

    vocab = {term: i for i, term in enumerate(model["vocab"])}
    idf = model["idf"]
    coef = model["coef"]
    intercept = model["intercept"]
    classes_key = model["classes_key"]
    classes_ko = model["classes_ko"]
    n_classes = len(classes_key)

    pipeline = joblib.load(MODEL_PATH)
    sk_classes = list(pipeline.named_steps["clf"].classes_)

    ko_to_key = dict(zip(classes_ko, classes_key))

    all_ok = True
    max_diff_overall = 0.0
    for text in TEST_SENTENCES:
        sk_prob = pipeline.predict_proba([text])[0]
        sk_by_key = {ko_to_key[label]: p for label, p in zip(sk_classes, sk_prob)}

        my_prob = predict_proba_manual(text, vocab, idf, coef, intercept, n_classes)
        my_by_key = dict(zip(classes_key, my_prob))

        max_diff = max(abs(sk_by_key[k] - my_by_key[k]) for k in classes_key)
        max_diff_overall = max(max_diff_overall, max_diff)

        sk_top = max(sk_by_key, key=sk_by_key.get)
        my_top = max(my_by_key, key=my_by_key.get)
        ok = sk_top == my_top and max_diff < MAX_ALLOWED_PROB_DIFF
        all_ok = all_ok and ok
        status = "OK" if ok else "MISMATCH"
        print(f"[{status}] '{text}' sklearn={sk_top}({sk_by_key[sk_top]:.4f}) "
              f"json={my_top}({my_by_key[my_top]:.4f}) max_diff={max_diff:.2e}")

    print(f"\n최대 확률 오차: {max_diff_overall:.2e} (허용치 {MAX_ALLOWED_PROB_DIFF:.0e})")
    if not all_ok:
        raise SystemExit("❌ export된 JSON이 원본 모델과 어긋남 - export.py를 다시 확인할 것")
    print("✅ export된 JSON이 원본 모델과 일치함")


if __name__ == "__main__":
    main()
