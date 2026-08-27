"""
최종 예측 파이프라인: 키워드 하드매핑(Tier 1~3) -> ML 모델(+margin 필터, Tier 4)

Dart로 옮길 때도 이 순서 그대로 옮기면 된다:
  1. keyword_router.route(text) 먼저 확인
  2. 안 걸리면 TF-IDF+LogisticRegression으로 top1/top2 확률 계산
  3. margin(top1-top2)이 threshold보다 작으면 -> 기타
  4. 아니면 top1 카테고리
"""
import pathlib

import joblib

import keyword_router

MODEL_PATH = pathlib.Path(__file__).parent / "models" / "pilot_v1.joblib"
DEFAULT_MARGIN_THRESHOLD = 0.08

_pipeline = None
_classes = None


def _load():
    global _pipeline, _classes
    if _pipeline is None:
        _pipeline = joblib.load(MODEL_PATH)
        _classes = list(_pipeline.named_steps["clf"].classes_)


def predict(text, margin_threshold=DEFAULT_MARGIN_THRESHOLD):
    """
    반환: dict(label, method, confidence, margin)
    method: 'tier1_immediate_family' 등 규칙 이름, 또는 'ml' / 'ml_low_confidence_fallback'
    """
    label, tier = keyword_router.route(text)
    if label is not None:
        return {"label": label, "method": tier, "confidence": None, "margin": None}

    _load()
    prob = _pipeline.predict_proba([text])[0]
    ranked = sorted(zip(_classes, prob), key=lambda x: -x[1])
    top1, top2 = ranked[0], ranked[1]
    margin = top1[1] - top2[1]

    if margin < margin_threshold:
        return {"label": "기타", "method": "ml_low_confidence_fallback",
                "confidence": top1[1], "margin": margin}
    return {"label": top1[0], "method": "ml",
            "confidence": top1[1], "margin": margin}


if __name__ == "__main__":
    import sys
    for line in sys.argv[1:] or ["운동 하러가기 전에 엄마한테 전화하기"]:
        result = predict(line)
        print(f'"{line}" -> {result}')
