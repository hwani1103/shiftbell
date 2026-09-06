# 메모 자동분류 카테고리 아이콘

`ml/카테고리_가이드.md`의 19개 범주(기존 9개+기타, 2026-09-01에 7개 신설,
2026-09-03에 2개 신설)에 대응하는 아이콘.
[Lucide](https://lucide.dev) (ISC License, MIT 호환 오픈소스) 라인 스타일 아이콘 세트에서
1:1로 매핑해 가져왔다 — 24x24, `stroke="currentColor"` 기반이라 Flutter에서
`ColorFilter`/`SvgTheme` 등으로 색을 그대로 얹어 쓸 수 있음 (fill 없음, 배경 투명).

## 매핑

| 파일 | 카테고리 | Lucide 아이콘 |
|---|---|---|
| `work.svg` | 업무 | `briefcase` |
| `study.svg` | 공부 | `book-open` |
| `exercise.svg` | 운동(기타 종목) | `dumbbell` |
| `health.svg` | 병원·건강관리 | `stethoscope` |
| `meal.svg` | 식사 | `utensils` |
| `social.svg` | 약속/사교 | `handshake` |
| `family.svg` | 가족 | `house-heart` |
| `shopping.svg` | 쇼핑 | `shopping-cart` |
| `leisure.svg` | 여가/휴식 | `tree-palm` |
| `running.svg` | 달리기 | Tabler `run` ⚠️(좌표 1.2배 확대, 아래 참고) |
| `swimming.svg` | 수영 | Tabler `swimming` ⚠️(좌표 1.2배 확대, 아래 참고) |
| `hiking.svg` | 등산 | Lucide `mountain` (2026-09-01 후속2 - Tabler `mountain`에서 되돌림, 아래 참고) |
| `culture.svg` | 문화생활 | `clapperboard` |
| `finance.svg` | 금융 | `landmark` |
| `housework.svg` | 집안일 | `washing-machine` |
| `beauty.svg` | 미용 | `scissors` |
| `cycling.svg` | 자전거 | `bike` |
| `yoga.svg` | 요가/필라테스(스트레칭 포함) | Tabler `yoga` ⚠️(좌표 1.2배 확대, 아래 참고) |
| `etc1.svg`~`etc10.svg` | 기타(10종 순환) | `circle`/`square`/`triangle`/`diamond`/`hexagon`/`pentagon`/`octagon`/`star`/`shapes`/`asterisk` |

⭐ 2026-09-01 후속2 - "기타"는 원래 `etc.svg`(circle-ellipsis) 하나였는데,
"말풍선처럼 보여서 실제 카테고리로 오인될 수 있다"는 피드백으로 **누가 봐도
자동분류 실패 표시임을 알 수 있는 순수 도형 10종**으로 교체 확정함. 한 개만
고정해서 쓰지 않고, `lib/screens/schedule_management_tab.dart`의
`_nextEtcIconIndex()`가 "기타"로 분류될 때마다 1→2→…→10→1…순으로 순환
배정한다(SharedPreferences에 누적 카운터 저장 - 다른 설정과 함께 백업/복구도
자동으로 됨). 실제 카테고리로 맵핑된 나머지 16종은 이 순환과 무관하게 항상
고정 아이콘 하나만 씀.

⭐ 2026-09-01 - "운동" 아이콘(아령)이 달리기/수영/등산까지 뭉뚱그리는 게
아쉽다는 피드백으로 이 3종을 전용 카테고리로 분리(테니스/골프/웨이트 등
"기타 종목"만 계속 `exercise`에 남음). 같은 이유로 "여가/휴식"에서 영화/공연/
전시 등도 `culture`로 분리했고, "기타"로 자주 빠지던 은행 용무/집안일 잡무도
전용 카테고리로 뺐다. 자세한 근거(실측 데이터 기반 판단)는
`ml/keyword_router.py`의 각 키워드 리스트 위 주석 참고.

⚠️ **`running.svg`/`swimming.svg`/`yoga.svg`만 출처가 Lucide가 아니라
[Tabler Icons](https://tabler.io/icons)(MIT License)임.** 2026-09-01 후속 -
"사람이 달리는/수영하는 모양"을 원한다는 피드백을 받았는데, Lucide는
미니멀 아이콘 세트 특성상 사람 자세를 구체적으로 그린 스포츠 픽토그램이
아예 없음(`person-running`/`swimming`/`yoga` 등 이름으로 찾아봤지만 전부
없음, 확인됨). Tabler Icons가 Lucide와 기술적으로 거의 동일한 스펙(`viewBox
24x24`, `fill="none"`, `stroke="currentColor"`, `stroke-width="2"`,
`stroke-linecap/linejoin="round"`)이라 섞어 써도 시각적으로 이질감이 없어서
이 3개만 예외적으로 가져옴. `cycling.svg`(자전거)는 Lucide `bike`가 그대로
있어서 Lucide에서 받음 - 이 3개(사람 자세 픽토그램)와 달리 예외 아님.

⭐ 2026-09-01 후속2 - **등산(`hiking.svg`)은 Tabler `mountain`이 "산 같지
않다"는 피드백으로 Lucide `mountain`(원래 있던 것)으로 되돌림** - 결과적으로
Tabler 출처는 running/swimming 2종만 남음. **`running.svg`/`swimming.svg`는
"다른 아이콘보다 사람 모양이 작아 보인다"는 피드백으로, 원본 Tabler 좌표를
각자의 원래 bbox 중심 기준 1.2배 확대해서 좌표를 직접 재계산함**(stroke-width는
그대로 "2" - 좌표만 키웠으므로 다른 아이콘과 획 두께 차이 없음). 계산 방법:
절대좌표 시작점만 `center + (원본 - center) * 1.2`로 옮기고, 그 뒤 상대좌표
델타(l/v/a 등)와 호(arc)의 반지름은 전부 그대로 1.2를 곱함 - 균등 확대이므로
이렇게만 해도 도형 전체가 정확히 1.2배 커진 동일한 모양이 됨(회전·왜곡 없음).

카테고리 정의/우선순위는 `ml/카테고리_가이드.md` 참고. 아이콘을 다른 것으로 바꾸고
싶으면 [lucide.dev](https://lucide.dev/icons) 에서 이름을 찾아 같은 방식으로
`https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/<name>.svg` 에서
받아 교체하면 됨(파일명은 유지, 내용만 교체).

## 출처 / 라이선스

- Lucide (`lucide-icons/lucide`, ISC License) — https://github.com/lucide-icons/lucide
  - 2026-08-27, 위 저장소 `main` 브랜치에서 그대로 다운로드(10종). 2026-09-01에
    4종(문화생활/금융/집안일/미용) 추가 다운로드. 후속2에서 `mountain.svg`
    (등산)도 이 저장소에서 다시 받아와 `hiking.svg`로 교체(한때 Tabler로
    바꿨다가 되돌림). 2026-09-03에 `bike.svg`를 `cycling.svg`로 추가 다운로드.
    전부 수정 없이 그대로.
- Tabler Icons (`tabler/tabler-icons`, MIT License) — https://github.com/tabler/tabler-icons
  - 2026-09-01, `running.svg`/`swimming.svg` 2종만(위 ⚠️ 참고, `hiking.svg`는
    후속2에서 Lucide로 되돌림). `outline/run.svg`, `outline/swimming.svg`를
    그대로 다운로드하되 파일 상단 태그 주석(`<!-- tags: ... -->`)만 제거하고,
    후속2에서 좌표를 1.2배로 재계산함(도형 내용 자체가 바뀐 건 이때뿐 -
    다운로드 직후엔 수정 없었음).
  - 2026-09-03, `yoga.svg` 추가(카테고리 확장, 자전거/요가·필라테스 신설).
    `outline/yoga.svg`를 태그 주석만 제거하고 running/swimming과 동일한 방식
    (원래 bbox 중심 기준 1.2배 확대)으로 좌표 재계산.

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
`kMemoCategoryIcons` 상수를 그대로 가져다 쓰면 됨(이 파일은 전체 아이콘을 그리드로
렌더링해 보여주는 임시 확인용 화면). 어디에도 라우팅은 안 돼 있어서 확인하려면
`main.dart`의 `home:`을 잠깐 `MemoCategoryIconLabScreen()`으로 바꿔서 실행하면 됨
(확인 후 반드시 되돌릴 것).
