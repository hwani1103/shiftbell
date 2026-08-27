"""
keyword_router.py의 하드매핑 규칙을 추가/수정할 때마다 돌릴 회귀 검사.

전체 라벨 데이터(pilot_dataset + boundary_cases + eval_holdout, 5,464개)에
새 규칙을 적용해서, **하드매핑이 정답과 다른 라벨로 확정해버리는 케이스가
있는지**만 확인한다(하드매핑이 아예 안 걸려서 ML로 넘어가는 건 이 스크립트의
관심사가 아님 - 그건 기존과 동일하게 ML+margin이 처리함).

사용법: python ml/check_keyword_regressions.py
"""
import json
import pathlib

import keyword_router

DATA_DIR = pathlib.Path(__file__).parent / "data"


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            rows.append((row["text"], row["label"]))
    return rows


def main():
    all_rows = (
        load_jsonl(DATA_DIR / "pilot_dataset.jsonl")
        + load_jsonl(DATA_DIR / "boundary_cases.jsonl")
        + load_jsonl(DATA_DIR / "eval_holdout.jsonl")
    )
    print(f"전체 라벨 데이터 {len(all_rows)}개로 검사")

    conflicts = []
    hits_agree = 0
    hits_total = 0
    for text, true_label in all_rows:
        label, tier = keyword_router.route(text)
        if label is None:
            continue
        hits_total += 1
        if label == true_label:
            hits_agree += 1
        else:
            conflicts.append((text, true_label, label, tier))

    print(f"하드매핑이 걸린 건수: {hits_total} (정답과 일치: {hits_agree}, 불일치: {len(conflicts)})")

    if conflicts:
        print("\n❌ 하드매핑이 정답과 다른 라벨을 강제한 케이스:")
        for text, true_label, hard_label, tier in conflicts:
            print(f'  "{text}" 정답={true_label} 하드매핑={hard_label}({tier})')
        raise SystemExit(f"\n{len(conflicts)}건 충돌 - 규칙을 다시 확인할 것")

    print("\n✅ 충돌 없음 - 하드매핑이 확정하는 라벨은 전부 기존 정답과 일치함")


if __name__ == "__main__":
    main()
