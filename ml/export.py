"""
Phase 4 — 학습된 파이프라인(ml/models/pilot_v1.joblib)을 Dart가 그대로 읽을 수 있는
JSON으로 내보낸다. keyword_router.py는 이미 순수 로직이라 별도 export 없이 Dart로
그대로 재작성하면 되고, 여기서는 TF-IDF(char_wb 2~3gram) + LogisticRegression만
export한다.

출력: assets/ml/memo_category_model.json (Flutter 자산으로 바로 번들됨)

Dart 쪽 재현 방법(lib/services/memo_category_classifier.dart 참고):
  1. 텍스트 lowercase
  2. char_wb n-gram 추출(단어 단위로 " "+word+" " 패딩 후 2~3글자 슬라이딩 윈도우,
     단어 경계를 넘어가는 n-gram은 없음) - ngram_range=(2,3)이 고정값이라 이 스크립트가
     내보내는 vocab/idf도 그 가정 위에서만 유효함. 학습 파이프라인을 바꾸면 이 스크립트와
     Dart 쪽 n-gram 함수를 같이 고칠 것.
  3. vocab에 있는 n-gram만 카운트 (없는 건 무시 - OOV)
  4. sublinear tf: count>0이면 1+ln(count), 아니면 0
  5. tfidf = tf' * idf[index]
  6. L2 정규화 (전체 벡터의 유클리드 노름으로 나눔)
  7. logits[c] = intercept[c] + sum(coef[c][i] * tfidf[i])  (0이 아닌 i만 순회하면 됨)
  8. softmax(logits) -> 확률, top1-top2 margin으로 기타 폴백 판단 (predict.py와 동일)
"""
import json
import pathlib

import joblib
import numpy as np

ML_DIR = pathlib.Path(__file__).parent
MODEL_PATH = ML_DIR / "models" / "pilot_v1.joblib"
OUT_PATH = ML_DIR.parent / "assets" / "ml" / "memo_category_model.json"

# ml/카테고리_가이드.md의 한글 라벨 -> 앱/아이콘에서 쓰는 영문 키
# (assets/icons/memo_category/README.md, lib/screens/schedule_management_tab.dart의
# _kScheduleCategoryIcons와 반드시 같은 매핑을 유지할 것)
LABEL_TO_KEY = {
    "업무": "work",
    "공부": "study",
    "운동": "exercise",
    "병원·건강관리": "health",
    "식사": "meal",
    "약속/사교": "social",
    "가족": "family",
    "쇼핑": "shopping",
    "여가/휴식": "leisure",
    "기타": "etc",
}


def main():
    pipeline = joblib.load(MODEL_PATH)
    tfidf = pipeline.named_steps["tfidf"]
    clf = pipeline.named_steps["clf"]

    assert tfidf.analyzer == "char_wb", tfidf.analyzer
    assert tuple(tfidf.ngram_range) == (2, 3), tfidf.ngram_range
    assert tfidf.sublinear_tf is True
    assert tfidf.lowercase is True
    assert tfidf.norm == "l2"

    # vocabulary_: term -> index (임의 순서의 dict) -> index 순서로 정렬된 배열로 변환.
    vocab_items = sorted(tfidf.vocabulary_.items(), key=lambda kv: kv[1])
    vocab_terms = [term for term, _ in vocab_items]
    idf = tfidf.idf_

    classes_ko = list(clf.classes_)
    missing = [c for c in classes_ko if c not in LABEL_TO_KEY]
    if missing:
        raise SystemExit(f"LABEL_TO_KEY에 없는 클래스 발견: {missing} - 매핑을 먼저 추가할 것")
    classes_key = [LABEL_TO_KEY[c] for c in classes_ko]

    def r(x, nd=6):
        return round(float(x), nd)

    payload = {
        "meta": {
            "ngram_min": 2,
            "ngram_max": 3,
            "analyzer": "char_wb",
            "sublinear_tf": True,
            "lowercase": True,
            "norm": "l2",
            "vocab_size": len(vocab_terms),
            "n_classes": len(classes_ko),
        },
        "classes_ko": classes_ko,
        "classes_key": classes_key,
        "vocab": vocab_terms,
        "idf": [r(v) for v in idf],
        "coef": [[r(v) for v in row] for row in clf.coef_],
        "intercept": [r(v) for v in clf.intercept_],
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    size_kb = OUT_PATH.stat().st_size / 1024
    print(f"✅ export 완료: {OUT_PATH} ({size_kb:.1f} KB)")
    print(f"   vocab {len(vocab_terms)}개, 클래스 {len(classes_ko)}개: {classes_key}")


if __name__ == "__main__":
    main()
