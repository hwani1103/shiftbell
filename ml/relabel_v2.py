"""
카테고리 확장(10 -> 17개) 1회성 마이그레이션 스크립트.

신설 하드매핑 tier(달리기/수영/등산/문화생활/금융/집안일/미용)가 실제로
"항상 옳다"는 전제로, 기존 라벨 데이터에 그 tier를 그대로 적용해서 라벨을
새 카테고리로 갱신한다. 기존 tier(가족/사교/기존 운동/기존 활동 4종)가 먼저
걸리는 행은 캐스케이드 순서상 신설 tier에 아예 안 넘어가므로 건드리지 않음
(가족/사교 우선순위가 자동으로 보존됨).

대상: pilot_dataset.jsonl, boundary_cases.jsonl, eval_holdout.jsonl
(user_batch1.jsonl은 원래 train.py가 안 읽는 별도 데이터라 이번엔 제외 - 필요하면
나중에 별도로 마이그레이션할 것)

사용법: python ml/relabel_v2.py  (dry-run 기본, --apply로 실제 반영)
"""
import argparse
import json
import pathlib
import collections

import keyword_router as kr

DATA_DIR = pathlib.Path(__file__).parent / "data"
TARGET_FILES = ["pilot_dataset.jsonl", "boundary_cases.jsonl", "eval_holdout.jsonl"]

NEW_LABELS = {"달리기", "수영", "등산", "문화생활", "금융", "집안일", "미용"}


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
    parser.add_argument("--apply", action="store_true", help="실제로 파일을 덮어씀 (기본은 dry-run)")
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
