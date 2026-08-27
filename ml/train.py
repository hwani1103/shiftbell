"""
Phase 1 baseline: char n-gram TF-IDF + Logistic Regression.

목적은 "이 모델이 최종 성능을 낸다"가 아니라 "지금 카테고리 설계가
근본적으로 분리 불가능한 수준은 아닌지"를 싼 값에 확인하는 것.
(메모_자동분류_ML_계획.md Phase 1 참고)

학습 데이터 = pilot_dataset.jsonl + boundary_cases.jsonl (440개)
eval_holdout.jsonl(60개)은 절대 여기 섞지 않는다 — evaluate.py 전용.
"""
import json
import pathlib

import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

DATA_DIR = pathlib.Path(__file__).parent / "data"
MODEL_DIR = pathlib.Path(__file__).parent / "models"
MODEL_DIR.mkdir(exist_ok=True)

RANDOM_STATE = 42


def load_jsonl(path):
    texts, labels = [], []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            texts.append(row["text"])
            labels.append(row["label"])
    return texts, labels


def main():
    pilot_texts, pilot_labels = load_jsonl(DATA_DIR / "pilot_dataset.jsonl")
    boundary_texts, boundary_labels = load_jsonl(DATA_DIR / "boundary_cases.jsonl")

    texts = pilot_texts + boundary_texts
    labels = pilot_labels + boundary_labels
    print(f"학습 풀: pilot {len(pilot_texts)}개 + boundary {len(boundary_texts)}개 = {len(texts)}개")

    X_train, X_test, y_train, y_test = train_test_split(
        texts, labels, test_size=0.2, random_state=RANDOM_STATE, stratify=labels
    )
    print(f"내부 train/test split: {len(X_train)} / {len(X_test)}")

    pipeline = Pipeline([
        ("tfidf", TfidfVectorizer(
            analyzer="char_wb",
            ngram_range=(2, 3),
            min_df=1,
            sublinear_tf=True,
        )),
        ("clf", LogisticRegression(
            max_iter=2000,
            class_weight="balanced",
        )),
    ])

    pipeline.fit(X_train, y_train)

    vocab_size = len(pipeline.named_steps["tfidf"].vocabulary_)
    n_classes = len(pipeline.named_steps["clf"].classes_)
    print(f"\nvocab size (char 2~3-gram): {vocab_size}")
    print(f"클래스 수: {n_classes}")
    print(f"가중치 행렬 크기: {n_classes} x {vocab_size} = {n_classes * vocab_size:,}개 float")

    y_pred = pipeline.predict(X_test)

    print("\n=== 내부 테스트셋(20%, 학습 풀에서 분리) 성능 ===")
    print(classification_report(y_test, y_pred, zero_division=0))

    labels_sorted = sorted(set(labels))
    cm = confusion_matrix(y_test, y_pred, labels=labels_sorted)
    print("=== Confusion Matrix (행=실제, 열=예측) ===")
    header = "".join(f"{l[:4]:>6}" for l in labels_sorted)
    print(f"{'':10}{header}")
    for true_label, row in zip(labels_sorted, cm):
        row_str = "".join(f"{v:>6}" for v in row)
        print(f"{true_label:10}{row_str}")

    model_path = MODEL_DIR / "pilot_v1.joblib"
    joblib.dump(pipeline, model_path)
    print(f"\n모델 저장: {model_path}")


if __name__ == "__main__":
    main()
