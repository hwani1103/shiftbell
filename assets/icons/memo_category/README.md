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

## 적용 방법 (2026-08-27 업데이트 - 렌더링 확인 완료)

`flutter_svg`(`^2.0.10+1`)를 `pubspec.yaml`에 추가하고 `assets/icons/memo_category/`도
자산으로 등록해뒀음. 실제 사용 예:

```dart
SvgPicture.asset(
  'assets/icons/memo_category/work.svg',
  colorFilter: const ColorFilter.mode(kAppMainAccent, BlendMode.srcIn), // currentColor stroke라 색이 그대로 먹음
)
```

카테고리 키/라벨/자산 경로 매핑은 `lib/screens/memo_category_icon_lab_screen.dart`의
`kMemoCategoryIcons` 상수를 그대로 가져다 쓰면 됨(이 파일은 10종을 그리드로 렌더링해
보여주는 임시 확인용 화면 — 실제 device의 dev flavor 빌드로 렌더링 확인 완료,
`work.svg`부터 `etc.svg`까지 전부 정상 표시됨). 어디에도 라우팅은 안 돼 있어서
확인하려면 `main.dart`의 `home:`을 잠깐 `MemoCategoryIconLabScreen()`으로 바꿔서
실행하면 됨(확인 후 반드시 되돌릴 것) — 카테고리 아이콘이 실제 화면(일정관리 등)에
적용되고 나면 이 화면 파일은 지워도 됨.
