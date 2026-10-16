# Sync Path Core

Flutter와 플랫폼에 의존하지 않는 순수 Dart 규칙 엔진이다.
2026-10-15 피날레 계약: 보드5~8, 유닛2~5, 종점 명령1~16. `maxRouteCommands`를 파서와 검증기가 함께 사용하며 장치는 문2개/다회용 포탈2쌍까지다. 기존1~70레벨의 규칙·데이터는 유지한다.
현재 게임은 `constant-cell-speed-v2`를 사용한다. `shared-goal-v1`은 과거 인증서 회귀 검증용으로만 보존한다.
파서가 실제 ruleSet을 LevelIdentity에 묶으므로 서로 다른 규칙의 저장/trace를 섞지 않는다.

- 최대 N은 명령/종점 선택 횟수다. v2에서는 길이 d인 명령의 논리 시간은 d다.
- 모든 Unit은 t=0 출발, 칸당 속도 1, 다음 명령은 자기 앞 명령 직후 출발한다.
- 대기 금지, 분할/왕복/재방문 허용. 직선 분할은 타이밍을 바꾸지 않는다.
- Goal 통과/이후 명령 금지. 도착 즉시 흡수, 동시 Goal 도착 허용.
- 연속 절대 시간에 중심 좌표가 일치하면 충돌한다. 크기/픽셀/FPS와 무관하다.

`LevelParser`는 256KiB JSON과 치수/숫자/리스트/ID/schema/mechanics 상한을 검사한다.
`LevelValidator`는 배치/연결성과 개별 도달 가능성을 확인한다. 공동 해결 가능성은 Solver가 확인한다.
`RouteValidator`는 draft/complete, 정확한 Unit 집합, 중간 벽/대각선/제자리/Goal 통과/N 초과를 검사한다.

`MotionCompiler`의 LinearPiece는 명령 ordinal(step)과 별개로 startTimeUnits/endTimeUnits를 제공한다.
`TemporalCollisionResolver`는 겹치는 절대 시간 구간의 상대 위치/속도를 유리수로 계산한다.
최초 충돌의 모든 쌍을 안정 정렬하며 명령 경계의 중복을 제거한다.
같은 시각의 다른 Goal 도착은 기록하지만 전체 충돌 실패를 상쇄하지 않는다.

`SimulationEngine.simulate`는 InvalidPlan 또는 불변 SimulationTrace를 반환한다.
`ArrivalEvent.globalTime`이 실제 도착 시각이다. `step`은 해당 Unit의 명령 번호다.
`durationInTimeUnits`를 사용한다. 호환 별칭 `durationInSteps`도 같은 논리 시간을 가리키며 v2에서 명령 횟수를 뜻하지 않는다.
CollisionEvent의 step/localTime은 전역 시간의 정수 구간/분수 표현이고 globalTime이 기준이다.
실패 trace의 motions에는 충돌 시점에 걸친 원래 명령이 포함되므로 렌더링은 종료 시각에서 반드시 clamp한다.
렌더링 경계에서만 double로 변환한다. 시각적 가속/감속이 중심 위치에 ease를 적용하면 안 된다.

```dart
final pack = const LevelParser().parsePack(json).value!;
final level = pack.levels.first;
final result = const SimulationEngine().simulate(level, RoutePlan(level.identity, routes));
```

패키지 디렉터리에서 `dart analyze`, `dart test`.
새 규칙 실기기 경로 회귀와 절대 시간/칸 사이 충돌/Goal/직선 분할/경계 다중 충돌 검사가 포함된다.
UI/저장/에셋/Solver는 다른 패키지에 있으며 기존 앱 연결은 없다.
