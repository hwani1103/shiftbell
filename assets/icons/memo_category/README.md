# 메모 자동분류 카테고리 아이콘

`메모_자동분류_ML_계획.md`의 9개 범주 + 기타에 대응하는 아이콘.
[Lucide](https://lucide.dev) (ISC License, MIT 호환 오픈소스) 라인 스타일 아이콘 세트에서
1:1로 매핑해 가져왔다 — 24x24, `stroke="currentColor"` 기반이라 Flutter에서
`ColorFilter`/`SvgTheme` 등으로 색을 그대로 얹어 쓸 수 있음 (fill 없음, 배경 투명).

## 매핑

| 파일 | 카테고리 | Lucide 아이콘 |
|---|---|---|
| `work.svg` | 업무 | `briefcase` |
| `study.svg` | 공부 | `book-open` |
| `exercise.svg` | 운동 | `dumbbell` |
| `health.svg` | 병원·건강관리 | `stethoscope` |
| `meal.svg` | 식사 | `utensils` |
| `social.svg` | 약속/사교 | `handshake` |
| `family.svg` | 가족 | `house-heart` |
| `shopping.svg` | 쇼핑 | `shopping-cart` |
| `leisure.svg` | 여가/휴식 | `tree-palm` |
| `etc.svg` | 기타 | `circle-ellipsis` |

카테고리 정의/우선순위는 `ml/카테고리_가이드.md` 참고. 아이콘을 다른 것으로 바꾸고
싶으면 [lucide.dev](https://lucide.dev/icons) 에서 이름을 찾아 같은 방식으로
`https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/<name>.svg` 에서
받아 교체하면 됨(파일명은 유지, 내용만 교체).

## 출처 / 라이선스

- Lucide (`lucide-icons/lucide`, ISC License) — https://github.com/lucide-icons/lucide
- 2026-08-27, 위 저장소 `main` 브랜치에서 그대로 다운로드. 수정 없음.

## 적용 방법 (다른 세션용 메모)

이 프로젝트는 아직 SVG 렌더링 패키지(`flutter_svg` 등)를 쓰고 있지 않음.
적용할 때 선택지:
1. `flutter_svg` 추가 후 `SvgPicture.asset('assets/icons/memo_category/work.svg', colorFilter: ...)`
2. 아이콘 폰트로 변환(예: `fantasticon`) 후 `IconData`로 사용 — 기존 Material 아이콘 쓰는
   방식과 동일하게 맞추고 싶으면 이쪽
3. PNG로 사전 래스터화 — 색 커스터마이징이 필요 없다면 가장 단순

`pubspec.yaml`의 `flutter: assets:`에 `assets/icons/memo_category/` 등록은 아직
안 해뒀음(이 커밋 시점에 다른 세션이 `pubspec.yaml`을 동시에 수정 중이라 충돌 방지
차 건드리지 않음) — 적용하는 쪽에서 등록 + 위 1번 또는 2번 처리를 같이 해줄 것.
