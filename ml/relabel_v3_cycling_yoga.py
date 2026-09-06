"""
카테고리 확장(17 -> 19개, 자전거/요가·필라테스 신설) 1회성 마이그레이션 스크립트.
ml/relabel_v2.py와 동일한 패턴 - 신설 하드매핑 tier(tier3b_cycling/tier3b_yoga)를
기존 라벨 데이터에 그대로 적용해서 라벨을 갱신한다.

대상: pilot_dataset.jsonl, boundary_cases.jsonl, eval_holdout.jsonl

사용법: python ml/relabel_v3_cycling_yoga.py  (dry-run 기본, --apply로 실제 반영)
"""
import argparse
import json
import pathlib
import collections

import keyword_router as kr

DATA_DIR = pathlib.Path(__file__).parent / "data"
TARGET_FILES = ["pilot_dataset.jsonl", "boundary_cases.jsonl", "eval_holdout.jsonl"]

NEW_LABELS = {"자전거", "요가/필라테스"}


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
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    total_changed = 0
    for fname in TARGET_FILES:
        path = DATA_DIR / fname
        rows = load_jsonl(path)
        changes = collections.Counter()
        for row in rows:
            label, tier = kr.route(row["text"])
            if label in NEW_LABELS and label != row["label"]:
                changes[(row["label"], label)] += 1
                row["label"] = label
        n_changed = sum(changes.values())
        total_changed += n_changed
        print(f"{fname}: {n_changed}건 변경")
        for (old, new), cnt in sorted(changes.items(), key=lambda x: -x[1]):
            print(f"  {old} -> {new}: {cnt}건")

        if args.apply:
            with open(path, "w", encoding="utf-8") as f:
                for row in rows:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"\n총 {total_changed}건 {'반영됨' if args.apply else '(dry-run, --apply로 실제 반영)'}")


if __name__ == "__main__":
    main()
