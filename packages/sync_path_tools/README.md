# Sync Path Tools

제작/검증 전용 순수 Dart 패키지다. `core`에만 의존하며 정상 플레이/lab에는 의존성으로 넣지 않는다.

`PuzzleSolver`는 Goal에서 끝나는 가시성 그래프, reverse BFS, 거리 가지치기 DFS, MRV/forward checking CSP와 제한된 호환성 캐시를 사용한다. 분할/왕복/재방문을 제거하지 않는다. 발견한 모든 정답은 core 전체 simulate로 다시 확인한다. 캐시는 실행 한 번에만 존재하므로 옛 level revision과 섞이지 않는다.

`SolverBudget`는 노드, Unit별 도메인, 저장할 정답, 호환성 캐시를 제한한다. 완전 탐색이면 `exactCount`(BigInt), 중단되면 `lowerBound`/`truncated`를 제공한다. 예산 초과 전에 정답을 찾았으면 SAT이지만 정확 개수를 주장하지 않는다. 정답을 찾지 못한 예산 초과는 UNKNOWN이며 UNSAT으로 바꾸지 않는다. 시간 제한은 현재 API에 없고 재현 가능한 노드/도메인 상한으로 제한한다.

개발 인증서 검증:

```powershell
& 'C:\tools\flutter\bin\cache\dart-sdk\bin\dart.exe' run bin/verify_pilot.dart '../../docs/next_version_27이후/game_design_v1/08_pilot_levels.json' '../../docs/next_version_27이후/game_design_v1/09_pilot_certificates.json' '../../docs/next_version_27이후/game_implementation_v1/pilot_verification.json'
```

독립 검증기는 graph/BFS/CollisionResolver/SimulationEngine을 쓰지 않고 지도에서 직접 ray DFS와 유리수 후보 전수 검사를 수행한다. 두 방식의 모든 개별 경로·전체 정답 조합·359개 결과의 최초 충돌 쌍/시각/좌표·통계가 인증서와 일치해야 PASS다. expected 값은 구현으로 다시 만들지 않고 기존 문서 인증서를 사용한다.

검증 범위는 고정 12레벨과 bounded v1 규칙이다. 재미/사람 난이도/실기기/UI 검증을 뜻하지 않는다. W04의 Solver와 인증서 검증 부분만 구현했고, Generator는 이번 규칙 엔진 우선 범위 이후로 남겼다.

## 현행 v2 / Generator

Generator도 구현되어 seed 기반으로 witness 경로를 보존한 벽 변형을 만들며 Solver+전체 engine을 통과한 경우만 VERIFIED로 표시한다.
`constant-cell-speed-v2` 호환성은 명령 번호가 아니라 absolute-time interval을 비교한다.
옛 359조합/47해답 인증서 검사는 역사적 shared-goal-v1 회귀로 유지한다.
현행 12레벨은 14,700조합/184해답을 전수 확인했다. 독립 oracle는 명령을 한 칸 edge로 확장하고
각 정수 구간에서 t=0,1/2,1을 검사한다. 상대 속도 성분이 -2..2이므로 모든 첫 접촉 후보를 포함한다.
4,000개 seeded 3-Unit 임의 경로에서도 첫 충돌 시각/위치/모든 쌍이 일치한다.

```powershell
dart run bin/verify_constant_speed.dart ../../examples/sync_path_lab/assets/pilot_levels.json ../../docs/next_version_27이후/game_implementation_v3/level_verification.json
```

## 캠페인30 제작/검증 (현행)

search_campaign.dart는 seed와 상한을 사용해 연결된 후보를 만들고, 완전 SAT만 후보에 보존한다.
직선 명령 분할 중복을 제외한 해답 수, 독립 경로 선택 수, 필수 우회 거리/유닛 수 등은 설계 보조 지표다.
curate_campaign.py가 tutorial5+새25를 선택하고 빈 외곽을 다듬고 제목/힌트를 연결한다.
verify_campaign.dart는 raw 경로 도메인 전체를 독립 DFS와 비교하고, 동일 시간의 cell trajectory로 분할 중복을 제거한다.
모든 유닛 쌍/경로 쌍9969건을 독립 cell-edge oracle와 대조하고, oracle 호환성 행렬로 독립 공동 해답 집합을 완전 탐색한다.
그 집합321개와 기존 Solver의 정규화된 집합이 일치한다. 모든 공동 정답/추가40개 계획/힌트 원본 witness도 전체 engine/oracle로 확인한다.
이 방식은 거대한 Cartesian product 전부를 engine으로 실행했다는 주장이 아니다. 모든 금지 조건이 pairwise이므로 호환성 가지치기로 정확한 공동 해답 집합을 얻는다.

```powershell
dart run bin/verify_campaign.dart ../../examples/sync_path_lab/assets/pilot_levels.json ../../docs/next_version_27이후/game_implementation_v4/level_verification.json ../../docs/next_version_27이후/game_implementation_v4/campaign_design.json
```

난이도2–8은 사람 평가가 아닌 목표 구간이다. check_campaign_shape.py는 회전/반사/평행이동 복제 없음과 후반5개 묶음의 설계 지표 평균 증가를 검사한다.

## 2026-10-14 캠페인50 저작

`bin/author_campaign50.py`는 연결된 통로/방의 후보를 만들고, 명령 직선분할을 제거한 시간별 셀/간선 점유 bitset으로 경로 조합을 전수 평가한다. N<=5/5~7 정사각/최대4공 계약을 따른다. `--mode initial --seed 501014 --attempts 20000`의 첫 풀과 `--mode multi --seed 501015 --attempts 50000`의 확장 풀은 v6에 보존했다. 오래된풀의N=6 후보는 최종선정에서 제외되었다. 개발용Python만 쓰고 런타임 의존성은 추가하지 않는다.

`curate_campaign50.py`는 시작→Goal거리/명령수,모든공의 충돌 관여,필수추가거리/우회공,지형중복,연속 분석점수 상승 및 급격한 점수단차 제한을 확인하며 선택한다. 30번의새4공 도입은2공 우회부터 시작한다. 분석점수는 인간 난이도의 실측값이 아니다.

`verify_campaign.dart`는 별도Dart Solver의 모든 원시명령경로와 독립 셀/반칸 간선 Oracle,모든 고유안전해답을 비교한다. 최종50레벨의40,608쌍/874고유해답이 일치한다. `check_campaign50.py`는 저작해답 수와 Dart 인증서가 일치하고,50개 맵 구조가 다르며 계약을 지키는지 확인한다. 현행 인증서는 `docs/next_version_27이후/game_implementation_v6/level_verification.json`이다.
# 100레벨 피날레 저작·검증 (2026-10-15)

`bin/author_finale100.py`는71~100의 후보와 정답/지표를 새 v11 원장에 저장한다. `bin/publish_finale100.py --publish`는 기존70을 그대로 잇고 제목 없는100레벨 팩을 만든다. `bin/verify_finale100.dart`는 별도 ray 열거·반시각 좌표 점유·문 시각 창으로 해답 수와 이동 하한을 대조하고, 모든 안전한 정규화 계획을 실제 엔진에 넣어 재인증한다.

보스 후보는 `author_boss100_balanced.py`가 로컬 Python 계산 작업자6개로 범위가 제한된 독립 seed를 탐색하며 checkpoint를 남긴다. 완료된 `finale_candidates.json`이 저작 입력이며, 점수는 사람의 난이도 측정값이 아니다. 재인증에는 검색 재실행이 필요하지 않다.

같은 방향의 직선 분할은 v2에서 타이밍을 바꾸지 않으므로 포탈 입구에서 끝나는 명령을 제외하고 합칠 수 있다. 이 정규화는 이동 한도 아래 해답의 존재 여부를 보존한다. 원시 명령열 전체 개수와 정규화 해답 수는 구분한다. 도메인·탐색 예산 초과는 UNKNOWN/오류이며 통과로 처리하지 않는다. 이전 `verify_portals70.dart`는51~70의 역사적 회귀 범위만 검사한다.
