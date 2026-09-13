// lib/services/condition/today_forecast_engine.dart
//
// ⭐ 2026-09-01 - "오늘의 컨디션 예측" 킬러 기능(컨디션매니저_설계.md 12~13장).
//
// ⚠️ 설계 원칙(반드시 지킬 것):
// 1. ConditionRuleEngine(B번, 4개 rule로만 NORMAL/ATTENTION/HIGH_LOAD 판정)은
//    이 파일이 전혀 건드리지 않는다 - fallback 문구 재사용 목적으로만 결과를
//    읽고, 그 판정 로직 자체는 그대로 둔다.
// 2. 숫자 점수/%/확률/질병 진단 절대 금지 - 근무시간/수면시간 등 "사실"과
//    evidence_database.dart에 실제로 있는 근거로만 문장을 만든다.
//    ⭐ 2026-09-01 후속8(사용자 명시 완화) - "운동은 조사해둔 근거가 없으니
//    절대 추천하지 않는다"는 원래 원칙은, 특정 연구 수치를 근거로 내세우는
//    구체적 의학적 조언에만 적용된다. "무리한 운동은 삼가고 가벼운 스트레칭
//    정도로", "심신 안정" 처럼 특정 논문 인용 없이도 일반적으로 통용되는
//    상식 수준의 생활 조언은 evidenceIds 없이(빈 리스트) 허용한다 - 사용자가
//    "이정도는 범용적으로 쓰이는 건강 상식이니 근거자료 없이도 된다"고 명시적
//    으로 완화함(축4/추천 팁 레이어 한정, ConditionRuleEngine의 4-rule 판정
//    로직에는 여전히 미적용). 단, "강도 높은 운동을 하세요"처럼 적극적 처방은
//    여전히 안 함 - 항상 "쉬어라/무리하지 마라/가볍게" 방향의 보수적 조언만.
// 3. **조합형(compositional) 문장 생성 + 축마다 변주(variant) 풀** - "경우의
//    수가 곱하기로 늘어나는" 문제를, 모든 조합(축1×축2×축3×급성 ≈ 수백 가지)을
//    손으로 다 쓰는 대신 축마다 독립적으로 상태를 분류하고 그 축들을 이어
//    붙이는 방식으로 푼다. 거기에 "같은 축-상태라도 매번 똑같은 문장이면
//    지겨워진다"는 피드백을 반영해, 축-상태마다 문구를 여러 개(보통 3개)
//    준비해두고 **날짜 기반으로 결정론적으로(그날그날 안정적으로, 그러나
//    날짜가 바뀌면 다르게) 로테이션**시킨다(_Composer.pick 참고). 조합을 전부
//    손으로 쓰는 것보다 이게 나은 이유: 조합형은 이미 모든 조합을 자동으로
//    커버하고, 매번 실제 숫자가 박히므로, 변주까지 더하면 "문구 수백 개를
//    직접 쓴 것"과 체감상 비슷한 다양성을 코드량은 훨씬 적게(축마다 3개씩,
//    총 80여 개) 유지하면서 낸다 - 반대로 조합을 전부 손으로 쓰면 같은
//    조합에 대해 숫자만 다른 문장을 수백 번 복붙하는 꼴이라 유지보수만
//    폭증하고 다양성은 오히려 안 늘어난다(조합형이 이미 다 커버하므로).
// 4. 최대 8주(56일)까지 추세를 봄(4주보다 넓게 - 짧은 창은 최근 이상치 한두
//    개로 "추세"가 오염되기 쉬움).

import 'condition_rule_engine.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_history.dart';

// ═══════════════════════════════════════════════════════════════════════
// 변주 선택 - 날짜 + 항목별 키로 결정론적 인덱스를 뽑는다. 같은 날 안에서는
// 항상 같은 결과(화면이 여러 번 다시 그려져도 문장이 안 바뀜), 날짜가
// 바뀌거나 항목이 다르면 다른 인덱스가 나온다(여러 절이 항상 같은 인덱스로
// "동반 회전"하지 않도록 seedKey를 각 절마다 다르게 줌).
// ═══════════════════════════════════════════════════════════════════════

int _variantIndex(DateTime date, String seedKey, int count) {
  if (count <= 1) return 0;
  final dayNumber = date.difference(DateTime(2020, 1, 1)).inDays;
  final hash = (dayNumber * 31 + seedKey.hashCode).abs();
  return hash % count;
}

// ⭐ 2026-09-07 - "오늘의 컨디션" 최종 문구 다듬기(사용자 요청). 각 절
// (헤드라인/수면/원인/팁 등)이 서로 독립적으로 문구를 고르다 보니, 우연히
// 같은 날 "~한 편이에요." 류 어미가 세네 번 겹쳐 기계적으로 들리는 문제가
// 있었다. 절이 말하는 "내용"(어떤 사실을 전할지)은 그대로 두고, "그 문장을
// 어떤 어미로 끝낼지"만 조립 단계에서 조율한다.
//
// 핵심: 각 절의 실제 텍스트 확정(과거의 _pickFrom 호출)을 그 절이
// 계산되는 시점(예: OT 추세는 함수 초반에 미리 계산됨)이 아니라, 그 절이
// 실제로 최종 문장 목록에 들어가는 시점(= 화면에 노출되는 진짜 순서)까지
// 미룬다. 그래야 "직전 문장 어미가 뭐였는지"를 정확히 알고 피할 수 있다 -
// 계산 순서와 노출 순서가 다른 축(OT 추세/급성/최근 피로도 등, 함수 초반에
// 한꺼번에 계산되지만 어느 게 실제로 어떤 순서로 붙을지는 분기에 따라
// 다름)이 있어서, 계산 시점에 조율하면 실제로 안 붙는 문장끼리 서로를
// 피하거나 반대로 진짜 이웃한 문장끼리는 못 피하는 오류가 생긴다. 그래서
// 이 축들은 "결정"(direction/tier 등, 함수 초반 계산 그대로 유지)과
// "렌더링"(실제 문구 선택, 최종 노출 시점까지 지연)을 분리했다 - 아래
// _OtTrendResult.renderMain/_AcuteEvent.render 등 참고.
//
// 다양화 규칙: 직전 문장과 어미가 겹치면 다른 후보로, 같은 어미가 이
// 메시지 안에서 이미 2번 나왔으면 그것도 피한다. 후보가 그것뿐이면 문법을
// 해치지 않는 선에서 그냥 허용한다(완벽한 배제보다 자연스러움이 목적) -
// 항상 실제로 준비된 후보 문장 중에서만 고르므로 비문이 생길 위험이 없다.
enum _EndingStyle { pyeonieyo, isseoyo, boseyo, juseyo, joayo, ieyo, general, other }

_EndingStyle _endingStyleOf(String text) {
  // 문미 판정에서 괄호 속 부가정보(예: "(약 8.0시간)")는 제외한다.
  final noParens = text.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  final tail = noParens.endsWith('.') ? noParens.substring(0, noParens.length - 1) : noParens;
  if (tail.endsWith('편이에요')) return _EndingStyle.pyeonieyo;
  if (tail.endsWith('좋아요') || tail.endsWith('좋을 것 같아요') || tail.endsWith('좋겠어요')) {
    return _EndingStyle.joayo;
  }
  if (tail.endsWith('보세요')) return _EndingStyle.boseyo;
  if (tail.endsWith('주세요')) return _EndingStyle.juseyo;
  if (tail.endsWith('있어요')) return _EndingStyle.isseoyo;
  if (tail.endsWith('예요') || tail.endsWith('이에요')) return _EndingStyle.ieyo;
  if (tail.endsWith('아요') || tail.endsWith('어요') || tail.endsWith('해요') || tail.endsWith('돼요')) {
    return _EndingStyle.general;
  }
  return _EndingStyle.other;
}

/// buildTodayForecast() 한 번의 호출 동안만 살아있는 조립기 - 문장이 실제로
/// 최종 목록에 들어가는 순서 그대로 pick()을 호출해야 어미 다양화가
/// 정확하다(호출 순서 = 화면 노출 순서라는 전제가 이 클래스의 정확성 조건).
class _Composer {
  final DateTime date;
  final List<_EndingStyle> _used = [];
  _Composer(this.date);

  String pick(List<String Function()> variants, String seedKey) {
    if (variants.length == 1) {
      final text = variants[0]();
      _used.add(_endingStyleOf(text));
      return text;
    }
    final preferred = _variantIndex(date, seedKey, variants.length);
    final order = List.generate(variants.length, (i) => (preferred + i) % variants.length);
    final prevStyle = _used.isEmpty ? null : _used.last;

    // 1차: 직전 문장과도 다르고, 이 메시지 안에서 아직 2번 미만 쓰인 후보.
    for (final idx in order) {
      final text = variants[idx]();
      final style = _endingStyleOf(text);
      final repeatCount = _used.where((s) => s == style).length;
      if (style != prevStyle && repeatCount < 2) {
        _used.add(style);
        return text;
      }
    }
    // 2차: 그런 후보가 없으면 최소한 직전 문장과는 다른 후보로 완화.
    for (final idx in order) {
      final text = variants[idx]();
      final style = _endingStyleOf(text);
      if (style != prevStyle) {
        _used.add(style);
        return text;
      }
    }
    // 3차: 그마저도 없으면(후보가 다 같은 어미) 원래 선호 인덱스 그대로.
    final text = variants[preferred]();
    _used.add(_endingStyleOf(text));
    return text;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 공개 API
// ═══════════════════════════════════════════════════════════════════════

enum SleepDataCoverage { none, low, mid, high }

class TodayForecast {
  final String message; // 최종 완성된 표시용 텍스트(2~3문장)
  final List<String> evidenceIds;
  final SleepDataCoverage sleepCoverage;
  final int trackedNightCount;
  final int nightsWithSleepData;

  const TodayForecast({
    required this.message,
    required this.evidenceIds,
    required this.sleepCoverage,
    required this.trackedNightCount,
    required this.nightsWithSleepData,
  });
}

TodayForecast buildTodayForecast({
  required ConditionResult baseResult,
  required ShiftPatternAnalyzer analyzer,
  required List<SleepHistoryNight> nights, // collectRecentWorkNights() 결과, 오래된 순, 최대 8주
  required Map<String, PersonalSleepPattern> personalPatterns,
  required Map<String, int> otMinutesByDate, // 'YYYY-MM-DD' -> 분, 최소 최근 5일 커버해야 함
  required DateTime today,
}) {
  // ⭐ 2026-09-01 버그 수정 - collectRecentWorkNights가 이제 휴무/미배정일도
  // 함께 반환하므로(파일 상단 import한 sleep_history.dart 참고), "최근 근무일
  // N일 중 수면 기록 M일" 같은 "근무일 커버리지" 계산은 반드시 실제 근무일만
  // (workNights) 걸러서 써야 한다 - 안 그러면 휴무일까지 분모에 섞여서
  // "근무일마다 성실히 기록했다"도 낮은 커버리지로 잘못 나온다(반대로 최근
  // 5일 실측 피로도(_classifyRecentFatigue)는 휴무일 수면도 알아야 정확하므로
  // 거긴 원본 nights를 그대로 넘김 - 아래 recentFatigue 참고).
  final workNights = nights.where((n) => n.isWorkDay).toList();

  final trackedCount = workNights.length;
  final withData = workNights.where((n) => n.hasSleepData).length;
  final coverage = _coverageFor(trackedCount, withData);

  // ⭐ 2026-09-01 후속3 - "기본 근무시간이 사람마다 다르다"(8시간 vs 12시간 등)는
  // 피드백 반영. 개인 평소 근무시간(baselineShiftMinutes)을 구해서, 절대 시간
  // 기준(RULE_LONG_SHIFT의 12시간 - ConditionRuleEngine 전용 Evidence 근거값이라
  // 절대 안 건드림)과 별개로 "이 사람 기준으로 오늘/어제가 평소보다 긴가"를
  // 이 예측 문구 레이어에서만 추가로 본다(sleep_history.dart 참고).
  final baselineShiftMinutes = personalBaselineShiftMinutes(workNights);
  final otTrend = _classifyOtTrend(_recentWeeklySummaries(analyzer, today));
  final coverageTrend = _classifyCoverageTrend(workNights);
  final sufficiencyTrend = _classifySufficiencyTrend(workNights);
  final acute = _findAcuteEvent(workNights, today, personalPatterns, baselineShiftMinutes);
  final todayLongerThanUsual = _findTodayLongerThanUsual(baseResult, baselineShiftMinutes);
  // ⭐ 신규 - "이번 주 후반(미래) 변경은 절대 안 보고, 오늘까지의 최근 5일 실측
  // 근무·OT·수면·회복시간만" 종합하는 축. 축1(OT 트렌드)은 "완결된 주" 단위라
  // 최소 한 주가 지나야 반영되는 지연이 있었는데, 이 축은 매일 굴러가는 5일
  // 창이라 어제 반영된 변경이 오늘 바로 드러난다.
  final recentFatigue = _classifyRecentFatigue(
    analyzer: analyzer,
    today: today,
    otMinutesByDate: otMinutesByDate,
    nights: nights,
    baseResult: baseResult,
    baselineShiftMinutes: baselineShiftMinutes,
  );

  final evidenceIds = <String>{};
  final sentences = <String>[];
  final recentFatigueFired = recentFatigue.tier != _FatigueTier.stable;
  // ⭐ 2026-09-07 - 어미 다양화 조립기. 아래 각 sentences.add(...)가 실제
  // 화면 노출 순서이고, 그 순서 그대로 텍스트를 확정해야 정확하다(파일 상단
  // _Composer 주석 참고) - 그래서 각 절의 렌더링을 여기(진짜 노출 시점)까지
  // 미뤄뒀다.
  final composer = _Composer(today);

  // ── 문장 1: 헤드라인 - 우선순위 acute(어제 급성) > 최근 5일 피로도(여러
  // 측면을 다 짚어주는 다문장) > OT 주간 트렌드(가장 긴 호흡의 배경 설명,
  // fallback) ────────────────────────────────────────────────────
  if (acute != null) {
    sentences.add(acute.render(composer));
    evidenceIds.addAll(acute.evidenceIds);
    if (recentFatigue.tier == _FatigueTier.high && recentFatigueFired) {
      // 급성 + 최근 5일 피로도까지 겹치는 드문 경우만 둘 다 노출
      sentences.addAll(_renderRecentFatigueSentences(recentFatigue, composer));
      evidenceIds.addAll(recentFatigue.evidenceIds);
    }
    // ⭐ 2026-09-06 - 문장 개수 제약을 없앴으니(사용자 요청) 급성/최근 며칠
    // 신호가 이미 있어도, 8주 흐름(축1)에 따로 할 말이 있으면(renderShort는
    // stable/데이터부족이면 null이라 그 경우엔 자동으로 안 붙음) 항상 같이
    // 붙인다 - "이번엔 급성이라 축1은 생략" 하지 않음. 원래는 evidenceIds를
    // 안 더해서 문장은 보이는데 근거 표시는 빠지는 불일치가 있었음(수정).
    final otClause = otTrend.renderShort(composer);
    if (otClause != null) {
      sentences.add(otClause);
      evidenceIds.addAll(otTrend.evidenceIds);
    }
  } else if (recentFatigueFired) {
    sentences.addAll(_renderRecentFatigueSentences(recentFatigue, composer));
    evidenceIds.addAll(recentFatigue.evidenceIds);
    // ⭐ 후속20 - 수면/초과근무 등만 잡히고 근무 패턴(연속근무/야간빈도/회복
    // 시간) 자체는 안 잡혔을 때, "근무는 괜찮았다"는 사실도 짧게 곁들여서
    // 전체 그림이 한쪽으로 치우치지 않게 함(_renderStableWorkNote 참고).
    final stableNote = _renderStableWorkNote(recentFatigue, composer);
    if (stableNote != null) sentences.add(stableNote);
    if (todayLongerThanUsual != null) {
      sentences.add(todayLongerThanUsual.render(composer));
      evidenceIds.addAll(todayLongerThanUsual.evidenceIds);
    }
    // ⭐ 2026-09-06 재설계(사용자 지적) - 원래(후속7) 여기서 축1(몇 주 흐름)을
    // 아예 뺐었다. "문장을 3개로 정제해달라"는 요청 때문이었는데, 그 결과
    // "최근 며칠(축4)이 유독 안 좋아서 그 신호가 뜨는 바로 그 날"에 오히려
    // "이게 몇 주째 이어지는 흐름인지"가 화면에서 통째로 사라지는 역설이
    // 있었다(정작 그게 가장 궁금할 시점에 안 보임). 문장 개수 제약은 이제
    // 없앴으니(사용자 요청 - "3줄로 제한할 필요 없다, 중복만 피하면 된다")
    // 축1이 노말/정체(stable) 상태가 아니라 실제로 할 말이 있을 때는
    // (renderShort는 stable/데이터부족이면 이미 null이라 그 경우엔 자동으로
    // 안 붙음) 짧은 형태로 같이 붙인다 - 축4와 문장이 겹치지 않도록 이미
    // 만들어져 있던 short 버전(급성 분기가 쓰던 것과 동일)을 재사용.
    final otClause = otTrend.renderShort(composer);
    if (otClause != null) {
      sentences.add(otClause);
      evidenceIds.addAll(otTrend.evidenceIds);
    }
  } else {
    sentences.add(otTrend.renderMain(composer));
    evidenceIds.addAll(otTrend.evidenceIds);
    // 급성 이벤트도, 최근 5일 신호도 없을 때만 - "오늘 근무가 이 사람 기준으로
    // 평소보다 긴가"를 짧게 덧붙임.
    if (todayLongerThanUsual != null) {
      sentences.add(todayLongerThanUsual.render(composer));
      evidenceIds.addAll(todayLongerThanUsual.evidenceIds);
    }
  }

  // ── 문장 2: 수면 데이터 상황(커버리지 + 충분도 추세) ─────────────
  final sleepClause = _composeSleepClause(coverage, coverageTrend, sufficiencyTrend, composer);
  if (sleepClause != null) sentences.add(sleepClause);

  // ── 원인/컨디션 추론 + 권고를 한 문장으로 - 헤드라인이 이미 원인을 설명한
  // 경우(acute/recentFatigue)는 생략(중복 방지) ─────────────────────
  if (acute == null && !recentFatigueFired) {
    final concern = _combineConcern(otTrend.direction, sufficiencyTrend, composer);
    sentences.add(concern.causeClause);
    evidenceIds.addAll(concern.evidenceIds);
  }

  // ⭐ 2026-09-01 후속8 - "행동 추천이 그날그날 특화되지 않고 뻔하다"는 피드백으로
  // _pickRecommendation(4갈래 고정 팁)을 폐기하고, 축4가 이미 우선순위까지
  // 매겨둔 reasons를 그대로 재사용해 요인별 구체적 행동 팁으로 교체.
  final tip = _pickActionTip(
    acute: acute != null,
    reasons: recentFatigue.reasons,
    otDirection: otTrend.direction,
    sufficiency: sufficiencyTrend,
    composer: composer,
  );
  if (tip != null) {
    sentences.addAll(tip.sentences);
    evidenceIds.addAll(tip.evidenceIds);
  }

  if (sentences.isEmpty) {
    sentences.add(baseResult.levelFindings.isNotEmpty
        ? baseResult.levelFindings.first.message
        : '최근 근무 패턴이 안정적이에요. 특별히 신경 쓸 부분은 보이지 않아요.');
  }

  return TodayForecast(
    message: sentences.join(' '),
    evidenceIds: evidenceIds.toList(),
    sleepCoverage: coverage,
    trackedNightCount: trackedCount,
    nightsWithSleepData: withData,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 축 1: 근무시간(OT) 추세 모양
// ═══════════════════════════════════════════════════════════════════════

enum _OtDirection { increasing, decreasing, recentSpike, recentDrop, volatile, stable, insufficientData }

class _OtTrendResult {
  final _OtDirection direction;
  // ⭐ 2026-09-07 - 문장 1(헤드라인)과 급성 있을 때 짧게 덧붙일 버전을 이제
  // 텍스트로 바로 안 들고, 후보 목록+seedKey만 들고 있다가 renderMain/
  // renderShort가 실제 노출 시점에 composer로 확정한다(파일 상단 _Composer
  // 주석 참고).
  final List<String Function()> mainVariants;
  final String mainSeedKey;
  final List<String Function()>? shortVariants; // null이면 짧은 버전 없음(stable)
  final String? shortSeedKey;
  final List<String> evidenceIds;
  const _OtTrendResult({
    required this.direction,
    required this.mainVariants,
    required this.mainSeedKey,
    required this.shortVariants,
    required this.shortSeedKey,
    required this.evidenceIds,
  });

  String renderMain(_Composer c) => c.pick(mainVariants, mainSeedKey);
  String? renderShort(_Composer c) => shortVariants == null ? null : c.pick(shortVariants!, shortSeedKey!);
}

// ⚠️ 아래 임계값은 전부 "설계상 정한 값"(연구값 아님) - ConditionRuleEngine의
// 3시간 낮잠 기준·60분 버퍼와 같은 성격. 실제 ConditionLevel 판정에는
// 관여하지 않는, 문구 선택 전용 임계값이다.
const double _kTrendChangeRatio = 0.20; // 20%+ 변화해야 추세로 인정
const double _kSpikeRatio = 1.35; // 최근 1주가 전체 평균의 1.35배 이상 -> 급증
const double _kDropRatio = 0.65; // 최근 1주가 전체 평균의 0.65배 이하 -> 급감
const double _kVolatileCoeffVariation = 0.30; // 변동계수(표준편차/평균) 기준

_OtTrendResult _classifyOtTrend(List<WeeklyPatternSummary> weeks) {
  // weeks: 오래된 순, 마지막 = 이번 주(진행 중, 아직 안 끝나서 총량이 적게
  // 잡히므로 추세 비교에서는 제외 - 표시용 숫자로만 참고 가능).
  final completed = weeks.length > 1 ? weeks.sublist(0, weeks.length - 1) : const <WeeklyPatternSummary>[];
  final withData = completed.where((w) => w.knownDurationSampleCount > 0).toList();

  if (withData.length < 2) {
    return _OtTrendResult(
      direction: _OtDirection.insufficientData,
      mainVariants: [() => '최근 근무시간 데이터가 아직 충분하지 않아요.'],
      mainSeedKey: 'ot_insufficient_main',
      shortVariants: null,
      shortSeedKey: null,
      evidenceIds: const [],
    );
  }

  final hours = withData.map((w) => w.knownDurationTotalMinutes / 60).toList();
  final overallAvg = hours.reduce((a, b) => a + b) / hours.length;
  final lastWeekHours = hours.last;

  final mid = (hours.length / 2).ceil();
  final earlierHalf = hours.sublist(0, mid);
  final recentHalf = hours.sublist(mid);
  final earlierAvg = earlierHalf.reduce((a, b) => a + b) / earlierHalf.length;
  final recentAvg = recentHalf.isEmpty ? earlierAvg : recentHalf.reduce((a, b) => a + b) / recentHalf.length;

  final recentH = recentAvg.toStringAsFixed(1);
  final earlierH = earlierAvg.toStringAsFixed(1);
  final lastWeekH = lastWeekHours.toStringAsFixed(1);
  final overallH = overallAvg.toStringAsFixed(1);

  final broadRatio = earlierAvg > 0 ? recentAvg / earlierAvg : 1.0;
  final spikeRatio = overallAvg > 0 ? lastWeekHours / overallAvg : 1.0;

  if (broadRatio < 1 + _kTrendChangeRatio && broadRatio > 1 - _kTrendChangeRatio && spikeRatio >= _kSpikeRatio) {
    return _OtTrendResult(
      direction: _OtDirection.recentSpike,
      mainVariants: [
        () => '평소보다 최근 1주 근무시간이 갑자기 늘었어요(약 $lastWeekH시간, 평소 약 $overallH시간).',
        () => '최근 1주만 유독 근무시간이 확 늘었어요(약 $lastWeekH시간, 평소는 약 $overallH시간 정도였어요).',
        () => '평균 주별 근무시간에 비해 최근 1주 근무시간이 크게 늘었어요(약 $lastWeekH시간).',
      ],
      mainSeedKey: 'ot_spike_main',
      shortVariants: [
        () => '최근 1주 근무시간도 평소보다 갑자기 늘었어요(약 $lastWeekH시간).',
        () => '최근 1주만 유독 근무시간이 늘었어요(약 $lastWeekH시간).',
      ],
      shortSeedKey: 'ot_spike_short',
      evidenceIds: const ['EVIDENCE-004'],
    );
  }
  if (broadRatio < 1 + _kTrendChangeRatio && broadRatio > 1 - _kTrendChangeRatio && spikeRatio <= _kDropRatio) {
    return _OtTrendResult(
      direction: _OtDirection.recentDrop,
      mainVariants: [
        () => '최근 1주 근무시간이 평소보다 갑자기 줄었어요(약 $lastWeekH시간, 평소 약 $overallH시간).',
        () => '최근 1주만 유독 근무시간이 확 줄었어요(약 $lastWeekH시간, 평소는 약 $overallH시간 정도였어요).',
        () => '평균 주별 근무시간에 비해 최근 1주 근무시간이 크게 줄었어요(약 $lastWeekH시간).',
      ],
      mainSeedKey: 'ot_drop_main',
      shortVariants: [
        () => '최근 1주 근무시간은 평소보다 줄었어요(약 $lastWeekH시간).',
        () => '최근 1주만 유독 근무시간이 줄었어요(약 $lastWeekH시간).',
      ],
      shortSeedKey: 'ot_drop_short',
      evidenceIds: const [],
    );
  }
  if (broadRatio >= 1 + _kTrendChangeRatio) {
    return _OtTrendResult(
      direction: _OtDirection.increasing,
      mainVariants: [
        () => '최근 근무시간이 계속 늘고 있어요(최근 주 평균 약 $recentH시간, 이전 약 $earlierH시간).',
        () => '최근 들어 근무시간이 꾸준히 늘어나는 추세예요(최근 주 평균 약 $recentH시간, 이전 약 $earlierH시간).',
        () => '근무시간이 이전 약 $earlierH시간에서 최근 약 $recentH시간으로 계속 늘고 있어요.',
      ],
      mainSeedKey: 'ot_increasing_main',
      shortVariants: [
        () => '최근 근무시간도 계속 늘어나는 추세예요(주 평균 약 $recentH시간).',
        () => '근무시간도 최근 들어 꾸준히 늘고 있어요(주 평균 약 $recentH시간).',
      ],
      shortSeedKey: 'ot_increasing_short',
      evidenceIds: const ['EVIDENCE-004', 'EVIDENCE-005'],
    );
  }
  if (broadRatio <= 1 - _kTrendChangeRatio) {
    return _OtTrendResult(
      direction: _OtDirection.decreasing,
      mainVariants: [
        () => '최근 근무시간이 계속 줄고 있어요(최근 주 평균 약 $recentH시간, 이전 약 $earlierH시간).',
        () => '최근 들어 근무시간이 꾸준히 줄어드는 추세예요(최근 주 평균 약 $recentH시간, 이전 약 $earlierH시간).',
        () => '근무시간이 이전 약 $earlierH시간에서 최근 약 $recentH시간으로 계속 줄고 있어요.',
      ],
      mainSeedKey: 'ot_decreasing_main',
      shortVariants: [
        () => '최근 근무시간은 계속 줄어드는 추세예요(주 평균 약 $recentH시간).',
        () => '근무시간도 최근 들어 꾸준히 줄고 있어요(주 평균 약 $recentH시간).',
      ],
      shortSeedKey: 'ot_decreasing_short',
      evidenceIds: const [],
    );
  }

  final mean = overallAvg;
  final variance = hours.map((h) => (h - mean) * (h - mean)).reduce((a, b) => a + b) / hours.length;
  final coeffVariation = mean > 0 ? (variance > 0 ? _sqrt(variance) / mean : 0) : 0;
  if (coeffVariation >= _kVolatileCoeffVariation) {
    return _OtTrendResult(
      direction: _OtDirection.volatile,
      mainVariants: [
        () => '최근 근무시간이 주마다 들쑥날쑥해요(주 평균 약 $overallH시간).',
        () => '최근 근무시간이 주별로 편차가 큰 편이에요(주 평균 약 $overallH시간).',
        () => '근무시간이 주마다 꽤 다른 편이에요(평균 약 $overallH시간).',
      ],
      mainSeedKey: 'ot_volatile_main',
      shortVariants: [
        () => '최근 근무시간도 주마다 편차가 큰 편이었어요.',
        () => '근무시간도 최근 들쑥날쑥한 편이었어요.',
      ],
      shortSeedKey: 'ot_volatile_short',
      evidenceIds: const [],
    );
  }

  return _OtTrendResult(
    direction: _OtDirection.stable,
    mainVariants: [
      () => '최근 근무시간은 큰 변화 없이 비슷하게 유지되고 있어요(주 평균 약 $overallH시간).',
      () => '최근 근무 패턴은 평소와 비슷하게 안정적이에요(주 평균 약 $overallH시간).',
      () => '근무시간이 꾸준히 일정한 편이에요(주 평균 약 $overallH시간).',
    ],
    mainSeedKey: 'ot_stable_main',
    shortVariants: null,
    shortSeedKey: null,
    evidenceIds: const [],
  );
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  var guess = x / 2;
  for (var i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

/// 이번 주(진행 중 포함) ~ (weeksBack-1)주 전까지, 오래된 순.
List<WeeklyPatternSummary> _recentWeeklySummaries(ShiftPatternAnalyzer analyzer, DateTime today, {int weeksBack = 8}) {
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final result = <WeeklyPatternSummary>[];
  for (var i = weeksBack - 1; i >= 0; i--) {
    result.add(analyzer.weeklySummary(thisMonday.subtract(Duration(days: 7 * i))));
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════
// 축 2: 수면 기록 커버리지 추세(기록을 하고 있는지 자체의 변화)
// ═══════════════════════════════════════════════════════════════════════

enum _CoverageTrend { none, steadyLow, steadyHigh, recentlyStarted, recentlyStopped }

_CoverageTrend _classifyCoverageTrend(List<SleepHistoryNight> nights) {
  if (nights.isEmpty) return _CoverageTrend.none;
  final overallRatio = nights.where((n) => n.hasSleepData).length / nights.length;
  if (overallRatio <= 0) return _CoverageTrend.none;

  final mid = (nights.length / 2).ceil();
  final earlier = nights.sublist(0, mid);
  final recent = nights.sublist(mid);
  final earlierRatio = earlier.isEmpty ? 0.0 : earlier.where((n) => n.hasSleepData).length / earlier.length;
  final recentRatio = recent.isEmpty ? 0.0 : recent.where((n) => n.hasSleepData).length / recent.length;

  if (earlierRatio <= 0.15 && recentRatio >= 0.5) return _CoverageTrend.recentlyStarted;
  if (earlierRatio >= 0.5 && recentRatio <= 0.15) return _CoverageTrend.recentlyStopped;
  return overallRatio < 0.5 ? _CoverageTrend.steadyLow : _CoverageTrend.steadyHigh;
}

// ═══════════════════════════════════════════════════════════════════════
// 축 3: 수면 충분도 추세(권장 최소 7시간 기준 - EVIDENCE-011)
// ═══════════════════════════════════════════════════════════════════════

enum _SufficiencyTrend { consistentlyGood, consistentlyPoor, recentlyDeclined, recentlyImproved, volatile, insufficientData }

const int _kSufficientMinutes = 7 * 60; // EVIDENCE-011 권장 최소

_SufficiencyTrend _classifySufficiencyTrend(List<SleepHistoryNight> nights) {
  final withData = nights.where((n) => n.hasSleepData).toList();
  if (withData.length < 4) return _SufficiencyTrend.insufficientData;

  final mid = (withData.length / 2).ceil();
  final earlier = withData.sublist(0, mid);
  final recent = withData.sublist(mid);
  double goodRatio(List<SleepHistoryNight> list) =>
      list.where((n) => n.sleepMinutes! >= _kSufficientMinutes).length / list.length;
  final earlierGood = goodRatio(earlier);
  final recentGood = recent.isEmpty ? earlierGood : goodRatio(recent);

  if (earlierGood >= 0.6 && recentGood <= 0.35) return _SufficiencyTrend.recentlyDeclined;
  if (earlierGood <= 0.35 && recentGood >= 0.6) return _SufficiencyTrend.recentlyImproved;
  if (earlierGood >= 0.7 && recentGood >= 0.7) return _SufficiencyTrend.consistentlyGood;
  if (earlierGood <= 0.3 && recentGood <= 0.3) return _SufficiencyTrend.consistentlyPoor;
  return _SufficiencyTrend.volatile;
}

String? _composeSleepClause(
  SleepDataCoverage coverage,
  _CoverageTrend coverageTrend,
  _SufficiencyTrend sufficiency,
  _Composer composer,
) {
  switch (coverageTrend) {
    case _CoverageTrend.none:
      // ⭐ 2026-09-01 후속6 - "수면 기록이 없어서 비교가 어렵다"는 결핍 표현
      // 대신, 기록하면 얻는 이득을 알려주는 방향으로(사용자 요청).
      return composer.pick([
        () => '수면을 기록해두시면 더 정확한 컨디션 예측을 받아보실 수 있어요.',
        () => '수면 기록을 남겨보시면 컨디션 예측이 더 정교해져요.',
        () => '수면까지 기록하시면 오늘처럼 근무 패턴만 볼 때보다 더 자세한 분석이 가능해져요.',
      ], 'coverage_none');
    case _CoverageTrend.recentlyStopped:
      return composer.pick([
        () => '최근 들어 수면 기록이 뜸해졌어요.',
        () => '요 며칠은 수면 기록이 잘 안 남아있어요.',
        () => '최근에는 수면 기록이 줄었어요.',
      ], 'coverage_stopped');
    case _CoverageTrend.recentlyStarted:
      return composer.pick([
        () => '최근부터 수면 기록을 시작하셨네요.',
        () => '요즘 들어 수면을 기록하기 시작하셨어요.',
        () => '최근부터 수면 데이터가 쌓이기 시작했어요.',
      ], 'coverage_started');
    case _CoverageTrend.steadyLow:
    case _CoverageTrend.steadyHigh:
      break; // 아래 충분도 절로 넘어감
  }

  final sufficiencyMsg = _composeSufficiencyClause(sufficiency, coverage, composer);
  if (sufficiencyMsg == null) return null;

  // ⭐ 2026-09-01 후속9 - "기록이 아예 없다"/"전부 다 있다"는 이미 각각 처리됨
  // (none 케이스는 위에서 기회 프레이밍으로, coverage==high면 아래 조건에
  // 안 걸려서 덧붙는 문구 없음 - "전부 있으면 생략"). 그 사이 - 기록은 하고
  // 있지만 듬성듬성한 경우(대략 절반 안팎, coverage low/mid)만 실질적인
  // 수면 분석 문장 뒤에 "꾸준히 기록하면 더 정확해진다"는 격려를 짧게
  // 덧붙인다. insufficientData(표본 자체가 너무 적어 이미 그 자체가 격려
  // 문구인 경우)는 중복이라 제외.
  final isSubstantive = sufficiency != _SufficiencyTrend.insufficientData;
  if (isSubstantive && (coverage == SleepDataCoverage.low || coverage == SleepDataCoverage.mid)) {
    final tail = composer.pick([
      () => '꾸준히 기록해주시면 다음 예측이 더 정확해질 수 있어요.',
      () => '기록을 조금 더 꾸준히 남겨보시면 비교가 더 정밀해져요.',
      () => '수면 기록이 꾸준히 쌓이면 예측이 한층 더 정확해져요.',
    ], 'coverage_partial_tail');
    return '$sufficiencyMsg $tail';
  }
  return sufficiencyMsg;
}

String? _composeSufficiencyClause(_SufficiencyTrend sufficiency, SleepDataCoverage coverage, _Composer composer) {
  switch (sufficiency) {
    case _SufficiencyTrend.consistentlyGood:
      return composer.pick([
        () => '수면은 대체로 충분히 유지되고 있어요.',
        () => '요즘 수면 시간은 꾸준히 잘 채워지는 편이에요.',
        () => '수면은 대체로 권장 시간만큼 확보돼요.',
      ], 'sufficiency_good');
    case _SufficiencyTrend.consistentlyPoor:
      return composer.pick([
        () => '수면 시간도 계속 부족한 편이에요.',
        () => '수면 시간이 꾸준히 권장 범위보다 적어요.',
        () => '요즘 수면도 계속 넉넉하지 않았어요.',
      ], 'sufficiency_poor');
    case _SufficiencyTrend.recentlyDeclined:
      return composer.pick([
        () => '최근 들어 수면 시간도 줄었어요.',
        () => '요즘 들어 수면 시간이 이전보다 짧아졌어요.',
        () => '최근 수면 시간이 눈에 띄게 줄어든 편이에요.',
      ], 'sufficiency_declined');
    case _SufficiencyTrend.recentlyImproved:
      return composer.pick([
        () => '최근 들어 수면 시간은 좋아지고 있어요.',
        () => '요즘 들어 수면 시간이 이전보다 늘었어요.',
        () => '최근 수면 시간이 점점 나아지는 편이에요.',
      ], 'sufficiency_improved');
    case _SufficiencyTrend.volatile:
      return composer.pick([
        () => '수면 시간은 날마다 편차가 있는 편이에요.',
        () => '수면 시간이 날마다 들쑥날쑥해요.',
        () => '수면 시간 편차가 좀 있어요.',
      ], 'sufficiency_volatile');
    case _SufficiencyTrend.insufficientData:
      if (coverage != SleepDataCoverage.low) return null;
      return composer.pick([
        () => '수면 기록을 조금 더 남겨보시면 예측이 더 정교해져요.',
        () => '수면 기록이 조금씩 쌓이고 있어요 - 더 채워지면 비교가 정밀해질 거예요.',
        () => '수면 데이터가 조금 더 쌓이면 비교가 정확해져요.',
      ], 'sufficiency_insufficient');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 원인/컨디션 추론(축1 방향 × 축3 상태를 합쳐서 톤을 고름 - 근거는 이미
// 위 각 축에서 붙였으므로 여기 문장 자체엔 새 evidence 없음)
// ═══════════════════════════════════════════════════════════════════════

class _ConcernResult {
  final String causeClause;
  final List<String> evidenceIds;
  const _ConcernResult(this.causeClause, this.evidenceIds);
}

bool _otConcerning(_OtDirection d) =>
    d == _OtDirection.increasing || d == _OtDirection.recentSpike || d == _OtDirection.volatile;
bool _otImproving(_OtDirection d) => d == _OtDirection.decreasing || d == _OtDirection.recentDrop;
bool _sleepConcerning(_SufficiencyTrend s) =>
    s == _SufficiencyTrend.consistentlyPoor || s == _SufficiencyTrend.recentlyDeclined;
bool _sleepImproving(_SufficiencyTrend s) =>
    s == _SufficiencyTrend.consistentlyGood || s == _SufficiencyTrend.recentlyImproved;

_ConcernResult _combineConcern(_OtDirection ot, _SufficiencyTrend sleep, _Composer composer) {
  final otBad = _otConcerning(ot);
  final sleepBad = _sleepConcerning(sleep);
  // ⭐ 2026-09-01 후속9(실측 테스트로 발견) - "꾸준히 좋음"(consistentlyGood)과
  // "실제로 좋아지는 중"(recentlyImproved/decreasing/recentDrop)을 같은
  // _sleepImproving/_otImproving으로 묶어서 판단했더니, 변화가 전혀 없이
  // 그냥 꾸준한 상태를 매번 "컨디션이 회복되고 있어요"라고 서술하는 부정확한
  // 문구가 나왔음(테스트 A2~A5에서 실측). 여기서만 "진짜 개선 추세"와
  // "원래도 꾸준히 좋음"을 나눠서 다르게 서술한다.
  final otReallyImproving = ot == _OtDirection.decreasing || ot == _OtDirection.recentDrop;
  final sleepReallyImproving = sleep == _SufficiencyTrend.recentlyImproved;

  if (otBad && sleepBad) {
    return _ConcernResult(
      composer.pick([
        () => '근무 부담과 수면 부족이 겹치면서 피로가 쌓이고 있을 수 있어요.',
        () => '근무도 많고 수면도 부족해서 피로가 누적되고 있을 수 있어요.',
        () => '근무 부담도 크고 수면도 부족해 컨디션에 영향이 있을 수 있어요.',
      ], 'concern_both_bad'),
      const ['EVIDENCE-004'],
    );
  }
  if (otBad) {
    return _ConcernResult(
      composer.pick([
        () => '근무 부담이 늘면서 피로가 쌓이고 있을 수 있어요.',
        () => '근무시간이 늘어난 만큼 피로도 함께 늘고 있을 수 있어요.',
        () => '근무 부담 증가가 컨디션에 영향을 주고 있을 수 있어요.',
      ], 'concern_ot_bad'),
      const ['EVIDENCE-004'],
    );
  }
  if (sleepBad) {
    return _ConcernResult(
      composer.pick([
        () => '수면이 부족해지면서 컨디션에 영향이 있을 수 있어요.',
        () => '수면 부족이 컨디션 저하로 이어지고 있을 수 있어요.',
        () => '수면이 충분하지 않아 컨디션에 영향이 있을 수 있어요.',
      ], 'concern_sleep_bad'),
      const ['EVIDENCE-011'],
    );
  }
  if (otReallyImproving && sleepReallyImproving) {
    return _ConcernResult(
      composer.pick([
        () => '부담도 줄고 수면도 안정적이라 컨디션이 회복되고 있을 수 있어요.',
        () => '근무 부담이 줄고 수면도 잘 챙겨지고 있어 회복세로 보여요.',
        () => '근무도 수월해지고 수면도 안정적이라 컨디션이 좋아지고 있을 수 있어요.',
      ], 'concern_both_good'),
      const [],
    );
  }
  if (otReallyImproving || sleepReallyImproving) {
    return _ConcernResult(
      composer.pick([
        () => '전반적으로 컨디션이 회복되고 있을 수 있어요.',
        () => '전반적인 부담이 줄면서 컨디션이 나아지고 있을 수 있어요.',
        () => '회복 방향으로 흘러가고 있을 수 있어요.',
      ], 'concern_either_good'),
      const [],
    );
  }
  // ⭐ "꾸준히 좋음"(sleepGood이지만 진짜 개선은 아닌 경우)은 이미 sleepClause
  // (_composeSufficiencyClause)가 "수면이 꾸준히 좋다"고 말해준 뒤라 여기서
  // 또 같은 얘기를 반복하면 중복임 - 그냥 중립 문구로 마무리(아래 fallthrough).
  return _ConcernResult(
    composer.pick([
      () => '특별히 우려되는 변화는 보이지 않아요.',
      () => '지금까지는 특별한 변화 없이 무난한 편이에요.',
      () => '눈에 띄는 특이사항은 없어 보여요.',
    ], 'concern_neutral'),
    const [],
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 급성 이벤트(어제 하루) - 트렌드보다 우선하는 헤드라인
// ═══════════════════════════════════════════════════════════════════════

class _AcuteEvent {
  // ⭐ 2026-09-07 - message를 바로 안 들고 후보+seedKey만 들고 있다가 render()가
  // 실제 노출 시점에 composer로 확정한다(파일 상단 _Composer 주석 참고).
  final List<String Function()> variants;
  final String seedKey;
  final List<String> evidenceIds;
  const _AcuteEvent(this.variants, this.seedKey, this.evidenceIds);
  String render(_Composer c) => c.pick(variants, seedKey);
}

const int _kAcuteShortSleepMinutes = 6 * 60;
const int _kBelowBaselineGapMinutes = 90;

// ⭐ 2026-09-01 후속3 - "평소보다 긴 근무"로 볼 차이(분). 수면 쪽 baseline 기준
// (_kBelowBaselineGapMinutes)과 대칭을 맞춘 값 - 둘 다 근거자료 값이 아니라
// 순수 문구 판단용 임계값.
const int _kLongerThanBaselineGapMinutes = 90;

_AcuteEvent? _findAcuteEvent(
  List<SleepHistoryNight> nights,
  DateTime today,
  Map<String, PersonalSleepPattern> personalPatterns,
  double? baselineShiftMinutes,
) {
  final yesterday = today.subtract(const Duration(days: 1));
  SleepHistoryNight? lastNight;
  for (final n in nights) {
    if (n.date.year == yesterday.year && n.date.month == yesterday.month && n.date.day == yesterday.day) {
      lastNight = n;
      break;
    }
  }
  // ⭐ 2026-09-01 버그 수정 - sleep_history.dart의 collectRecentWorkNights가
  // 이제 휴무/미배정일도 반환하므로(shiftDurationMinutes: 0), 어제가 그런
  // 날이면 이 함수는 조용히 건너뜀 - 안 그러면 "어제 0시간 근무 후..." 같은
  // 말이 안 되는 문구가 나감. 실제 근무 후 급성 수면 부족만 이 헤드라인의
  // 대상이라는 원래 취지 그대로 유지.
  if (lastNight == null || !lastNight.hasSleepData || lastNight.shiftDurationMinutes <= 0) return null;

  final sleepMin = lastNight.sleepMinutes!;
  final shiftH = _fmtHours(lastNight.shiftDurationMinutes);
  final sleepH = _fmtHours(sleepMin);

  // ⭐ 2026-09-01 후속4 - "실제로 얼마나 잤는지"가 가장 중요한 값이라는 피드백
  // 반영. 예전엔 "어제 근무가 길었을 때만"(shiftWasLong 게이트) 이 신호가
  // 떴는데, 그러면 근무 자체는 평소와 비슷한데 이런저런 이유로 수면만 유독
  // 짧았던 날(예: 8시간 근무 후 3시간만 잠)을 완전히 놓치게 됨 - 이제 수면이
  // 짧으면(6시간 미만, EVIDENCE-011 권장 최소 밑) 근무 길이와 무관하게 항상
  // 헤드라인으로 뜬다. 어제 근무가 "이 사람 평소보다도" 길었으면(개인 평소
  // 근무시간 대비 90분 이상, 표본 부족 시 절대 11시간으로 폴백) 그 사실도 같이
  // 언급해서 원인을 더 구체적으로 짚어줄 뿐 - 게이트 조건이 아님.
  //
  // ⚠️ ConditionRuleEngine의 RULE_LONG_SHIFT(12시간 이상, EVIDENCE-004)는 이것과
  // 완전히 별개이고 절대 건드리지 않는다 - 그건 "장시간 근무 자체의 위험"에 대한
  // 실제 연구 근거값(습관화 여부와 무관하게 위험이 보고됨)이고, 여기 이 값은
  // 순수 문구 선택용 개인 비교 기준일 뿐이다.
  final baselineGap = baselineShiftMinutes != null ? lastNight.shiftDurationMinutes - baselineShiftMinutes : null;
  final longerThanPersonalUsual = baselineGap != null && baselineGap >= _kLongerThanBaselineGapMinutes;

  if (sleepMin < _kAcuteShortSleepMinutes) {
    final variants = longerThanPersonalUsual
        ? [
            () => '어제는 평소보다 긴 $shiftH시간 근무(평소 약 ${_fmtHours(baselineShiftMinutes!.round())}시간) 후 '
                '수면이 $sleepH시간으로 짧았어요. 오늘은 무리한 일정을 피하고 컨디션을 살펴주세요.',
            () => '평소(약 ${_fmtHours(baselineShiftMinutes!.round())}시간)보다 긴 $shiftH시간 근무 후 '
                '$sleepH시간밖에 못 주무셨어요. 오늘은 컨디션에 유의해주세요.',
            () => '어제 근무가 평소보다 길었는데(약 $shiftH시간) 수면도 $sleepH시간으로 부족했어요. '
                '오늘은 평소보다 컨디션 관리가 필요해요.',
          ]
        : [
            () => '어제 $shiftH시간 근무 후 실제 수면이 $sleepH시간으로 짧았어요. 오늘은 무리한 일정을 피하고 컨디션을 살펴주세요.',
            () => '어제 $shiftH시간 근무하고 $sleepH시간밖에 못 주무셨어요. 오늘은 컨디션에 유의해주세요.',
            () => '어제 $shiftH시간 근무 후 수면이 $sleepH시간으로 부족했어요. 오늘은 평소보다 컨디션 관리가 필요해요.',
          ];
    final seedKey = longerThanPersonalUsual ? 'acute_short_sleep_baseline' : 'acute_short_sleep';
    return _AcuteEvent(variants, seedKey, const ['EVIDENCE-004', 'EVIDENCE-011']);
  }

  final pattern = personalPatterns[lastNight.shiftName];
  if (pattern != null && pattern.avgSleepMinutes - sleepMin >= _kBelowBaselineGapMinutes) {
    final avgH = _fmtHours(pattern.avgSleepMinutes.round());
    final shiftName = lastNight.shiftName;
    return _AcuteEvent(
      [
        () => '평소 "$shiftName" 근무 후엔 보통 $avgH시간 정도 주무셨는데, 어제는 $sleepH시간으로 평소보다 부족했어요.',
        () => '어제는 평소 "$shiftName" 근무 후 보통 자던 $avgH시간보다 $sleepH시간으로 짧게 주무셨어요.',
        () => '"$shiftName" 근무 후 평소 수면은 약 $avgH시간이었는데, 어제는 $sleepH시간으로 그보다 적었어요.',
      ],
      'acute_below_baseline',
      const [],
    );
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// 축 4(신규) - 최근 5일 실측 피로도. "이번 주 후반(아직 안 지난 미래) 근무
// 변경은 절대 반영하지 않는다 - 실제로 일하게 될지 모르고, 수면도 아직 알 수
// 없으므로" 원칙에 따라 철저히 today까지(포함)의 확정된 값만 본다.
//
// 축1(OT 트렌드)은 "완결된 주" 단위라 최소 한 주가 지나야 반영되는 지연이
// 있었다(달력에서 이번 주 근무를 바꿔도 문구가 전혀 안 바뀌는 문제의 원인) -
// 이 축은 매일 굴러가는 5일 창이라 어제 바뀐 내용도 오늘 바로 반영된다.
// date_overtime(실제 초과근무 기록)도 여기서 처음으로 컨디션 예측에 반영됨 -
// 그 전엔 존재 자체를 안 봤음.
//
// ⭐ 2026-09-01 후속6 - 1차 구현이 "야간근무 빈도"만 보고 "5일 연속근무
// 자체"(야간이 하나도 없어도 쉬는 날 없이 계속 근무하면 그것만으로도 부담)를
// 놓친다는 피드백으로 신호를 5개로 확장. 연속근무일수는
// `ConditionRuleEngine`이 5일 창과 무관하게(끝없이 역탐색해서) 이미 계산해둔
// `consecutiveWorkDays`를 그대로 읽으므로, "5일 창만 보고 5일 연속이라고
// 잘못 판단"하는 일은 없음(6일/7일 연속도 정확히 잡힘).
//
// ⭐ 후속7 - 여러 신호가 겹쳐도 최대 3문장(헤드라인+후속언급 1개+종합문장)으로
// 정제함(4~5개가 겹쳐도 전부 나열하지 말 것 - 사용자 요청). 연속근무일수도
// 처음엔 "연속 근무 5일째"처럼 실제 숫자를 넣었었는데, 이마저도 "raw 데이터
// 쓸 필요 없다"는 피드백으로 빼고 "연속 근무가 잦다/길어졌다" 식 정성적
// 표현만 남김 - 원자료 나열 금지 원칙을 이 축에도 동일하게 적용.
//
// ⭐ 후속9(실제 시나리오 테스트로 발견) - "야야야야휴"(5일 주기, 4연속 야간
// 12시간+1일 휴무)처럼 연속근무가 항상 4일에서 끊기는 패턴은 workStreak(5일
// 이상 기준)이 영원히 안 뜨는데, 실제로는 ConditionRuleEngine이
// RULE_EXTENDED_STREAK_SHORT_BREAK(12시간+ 근무 3일 연속 + 다음 휴식
// 48시간 미만, EVIDENCE-004+005)로 이미 HIGH_LOAD까지 판정하고 있었음 - 그런데
// 축4는 RULE_SHORT_RECOVERY만 읽고 이 rule은 아예 안 읽어서, 가장 근거가
// 확실한 고강도 신호가 "오늘의 컨디션" 카드에 전혀 안 뜨는 구멍이 있었다.
// extendedStreak를 최우선 순위로 추가해서 고침 - RULE_LONG_SHIFT(단순 12시간
// 이상 하루)는 여전히 안 씀(습관화된 12시간 근무자를 매일 플래그하면 안
// 된다는 14장 원칙 그대로 - 그건 "매일 이 위험에 노출된다"는 사실이지 이상
// 신호가 아님). RULE_EXTENDED_STREAK_SHORT_BREAK는 다르다 - "연속 + 짧은
// 회복"이라는 진짜 이상 패턴이라 여기 포함하는 게 맞음.
// 아래 임계값은 전부 축1과 마찬가지로 "설계상 정한 값"이다.
// ═══════════════════════════════════════════════════════════════════════

enum _FatigueTier { stable, building, high }
// ⭐ 2026-09-13 - noRestPattern 추가("이 스케줄 자체가 애초에 쉬는 날이 없는가" -
// shift_pattern_analyzer.dart의 patternHasNoRestDay, condition_score.dart의
// _wNoRestPattern과 같은 신호). workStreak(오늘까지 실제로 며칠째 못 쉬었는지,
// 시간이 지나야 쌓임)과 달리 스케줄을 등록한 첫날부터도 참/거짓이 정해지는
// 더 근본적인 신호라 별도 reason으로 둠 - 우선순위는 workStreak보다 위(더
// 확정적인 사실이므로).
enum _FatigueReason { extendedStreak, recovery, noRestPattern, workStreak, nightFrequency, sleepShortage, overtimeLoad, generalLoad }

// ⭐ 2026-09-01 후속21(사용자 요청) - "최근 상황"을 보는 창을 5일 → 7일로
// 넓힘(더 안정적인 판단 근거 확보). 절대적인 부담 기준(야간이 며칠이면
// "잦다"인지, 연속근무 "길다"가 며칠부터인지, 초과근무 "많다"가 몇 시간부터인지)은
// 창이 넓어졌다고 같이 늘리지 않음 - "얼마나 멀리까지 보는가"와 "그 자체로 얼마나
// 부담스러운가"는 서로 다른 성격의 숫자라, 창을 넓힌다고 비율로 환산해 같이
// 올리면 오히려 "3일 연속 야간" 같은 명백한 신호가 묻힘(실제로 7일 중 4일로
// 올렸을 때 3연속 야간 시나리오가 신호를 놓치는 회귀가 발견됨 - 그래서 절대값
// 3을 유지). condition_score.dart의 _kScoreWindowDays도 동일하게 7로 맞춤(두
// 레이어가 "최근"의 정의를 다르게 쓰면 워딩과 점수가 서로 다른 이야기를 하는
// 것처럼 보일 수 있어서).
const int _kFatigueWindowDays = 7; // 오늘 포함 최근 7일
const int _kManyNightsThreshold = 3; // 7일 중 3일 이상 야간이면 "잦다" - 절대 기준, 창 길이와 무관하게 고정
const int _kWorkStreakThresholdDays = 5; // 연속 근무가 "길다"고 볼 절대 기준 - 창 길이와 무관하게 고정
const int _kHeavyOtMinutes = 8 * 60; // 누적 OT가 이만큼은 넘어야 유의미한 부담(EVIDENCE-012) - 3시간 정도는 무시
const int _kMinWorkDaysForFatigueSignal = 2; // 최근 창 중 실근무일이 이 미만이면 판단 보류(데이터 부족)
// ⭐ 2026-09-01 후속7 - "4~5개 요인이 겹쳐도 전부 나열하지 말고 정제해서
// 보여달라"는 요청으로 2 → 1로 줄임: 헤드라인(1위) + 후속 언급(2위) 딱 하나만
// 구체적으로 짚고, 그 이상 겹치는 건 별도 문장 없이 마지막 종합 문장의 톤만
// 올려서 표현한다(요인이 몇 개든 문장 개수는 최대 3개: 헤드라인+후속+종합).
const int _kMaxAdditionalFatigueMentions = 1;

class _RecentFatigueResult {
  final _FatigueTier tier;
  final List<String> evidenceIds;
  final List<_FatigueReason> reasons; // 우선순위 순 - 추천 팁 선택이 그대로 재사용
  /// ⭐ 2026-09-01 후속20(사용자 요청) - "점수가 왜 이런지 감이 안 온다,
  /// 근무 패턴 얘기가 아예 없어서 그런 것 같다"는 지적 반영. 수면/OT 등
  /// 다른 요인만 잡히고 근무 패턴 자체(연속근무일수/야간빈도/회복시간)는
  /// 전혀 문제없을 때, "근무 자체는 괜찮았다"는 사실도 짧게 곁들이기 위한
  /// 플래그 - true면 근무 패턴 쪽에 이미 할 말이 있다는 뜻이라
  /// _renderStableWorkNote가 중복/모순 방지로 아무것도 안 붙인다.
  final bool hasWorkPatternConcern;
  final int workDayCount;
  final int nightCount;
  final int? consecutiveWorkDays;
  // ⭐ 2026-09-07 - sentences/stableWorkNote를 여기서 바로 문자열로 안 들고
  // (reasons만 결정으로 남겨두고) _renderRecentFatigueSentences/
  // _renderStableWorkNote가 실제 노출 시점에 composer로 렌더링한다(파일
  // 상단 _Composer 주석 참고 - "결정"과 "렌더링"을 분리).
  const _RecentFatigueResult(
    this.tier,
    this.evidenceIds,
    this.reasons, {
    required this.hasWorkPatternConcern,
    required this.workDayCount,
    required this.nightCount,
    required this.consecutiveWorkDays,
  });
}

/// ⭐ 후속20 - "근무 패턴 자체"에 이미 할 말이 있으면(_kWorkPatternReasons 중
/// 하나라도 활성) 중복/모순 방지로 별도 안내 문장을 안 붙인다.
String? _renderStableWorkNote(_RecentFatigueResult r, _Composer composer) {
  if (r.reasons.isEmpty || r.hasWorkPatternConcern) return null;
  return _stableWorkPatternNote(
    workDayCount: r.workDayCount,
    nightCount: r.nightCount,
    consecutiveWorkDays: r.consecutiveWorkDays,
    composer: composer,
  );
}

/// 축4(최근 피로도) 전체 문장을 실제 노출 순서(=composer.pick 호출 순서)로
/// 렌더링한다 - 헤드라인(1위 요인) → 후속 언급(2위 요인, 있으면) → 종합 문장.
List<String> _renderRecentFatigueSentences(_RecentFatigueResult r, _Composer composer) {
  if (r.reasons.isEmpty) return const [];
  if (r.reasons.length == 1) {
    return [_fatigueFactorClause(r.reasons.first, composer, consecutiveWorkDays: r.consecutiveWorkDays)];
  }
  final sentences = <String>[
    _fatigueFactorClause(r.reasons.first, composer, consecutiveWorkDays: r.consecutiveWorkDays),
  ];
  final remaining = r.reasons.skip(1).toList();
  final mentioned = remaining.take(_kMaxAdditionalFatigueMentions);
  for (final reason in mentioned) {
    sentences.add(_fatigueAdditionalMention(reason, composer, consecutiveWorkDays: r.consecutiveWorkDays));
  }
  sentences.add(_fatigueClosing(r.reasons.length, composer));
  return sentences;
}

/// ⭐ 후속20 - "근무 패턴 자체"를 다루는 이유들(회복시간/장시간연속/연속근무일/
/// 야간빈도) - 이 중 하나라도 활성이면 근무 패턴에 이미 할 말이 있는 것이므로
/// stableWorkNote를 따로 안 붙인다(중복/모순 방지 - "근무는 괜찮다"고 하면서
/// 동시에 "연속 근무가 길다"고 하면 안 되니까).
const _kWorkPatternReasons = {
  _FatigueReason.extendedStreak,
  _FatigueReason.recovery,
  _FatigueReason.noRestPattern,
  _FatigueReason.workStreak,
  _FatigueReason.nightFrequency,
};

// ⭐ 2026-09-13 - "연속 근무일이 길다"는 5일부터 flat하게 같은 문장이었는데,
// 5일과 30일이 말로는 구분이 안 된다는 지적(condition_score.dart의 비례
// 감점과 같은 이유) - 이 만큼 넘어가면 "장기화" 전용 문구 세트로 갈아탄다.
// 근거자료 수치가 아니라 순수 문구 판단용 임계값(다른 _k* 워딩 임계값과 동일 성격).
const int _kWorkStreakSevereThresholdDays = 14;

_RecentFatigueResult _classifyRecentFatigue({
  required ShiftPatternAnalyzer analyzer,
  required DateTime today,
  required Map<String, int> otMinutesByDate,
  required List<SleepHistoryNight> nights,
  required ConditionResult baseResult,
  required double? baselineShiftMinutes,
}) {
  var nightCount = 0;
  var workDayCount = 0;
  var shiftMinutesTotal = 0;
  var otMinutesTotal = 0;

  final windowStart = today.subtract(const Duration(days: _kFatigueWindowDays - 1));
  for (var i = 0; i < _kFatigueWindowDays; i++) {
    final day = today.subtract(Duration(days: i));
    final inst = analyzer.instanceForDate(day);
    if (inst.category == ShiftTimeCategory.night) nightCount++;
    if (inst.isWorkDay) {
      workDayCount++;
      final dur = inst.durationMinutes;
      if (dur != null) shiftMinutesTotal += dur;
    }
    otMinutesTotal += otMinutesByDate[_dateKey(day)] ?? 0;
  }

  // ⭐ 2026-09-13 - 패턴 자체에 휴무가 없는지는 날짜 윈도우와 무관한 정적 사실이라
  // 창이 짧아 이르게 return하는 위 분기보다 먼저 확인 - 방금 등록한 스케줄이라
  // 아직 근무일 표본이 2일도 안 쌓였어도 이 신호만은 즉시 반영되게 함.
  final patternNeverRests = analyzer.patternHasNoRestDay == true;

  if (workDayCount < _kMinWorkDaysForFatigueSignal) {
    if (patternNeverRests) {
      return _RecentFatigueResult(
        _FatigueTier.building,
        const [],
        const [_FatigueReason.noRestPattern],
        hasWorkPatternConcern: true,
        workDayCount: workDayCount, nightCount: nightCount, consecutiveWorkDays: baseResult.consecutiveWorkDays,
      );
    }
    return _RecentFatigueResult(
      _FatigueTier.stable, const [], const [],
      hasWorkPatternConcern: true, // reasons가 비어 있어 실제로는 안 쓰이지만, 명시적으로 억제
      workDayCount: workDayCount, nightCount: nightCount, consecutiveWorkDays: null,
    );
  }

  final totalLoadMinutes = shiftMinutesTotal + otMinutesTotal;
  final avgLoadPerWorkday = totalLoadMinutes / workDayCount;

  final sleepInWindow = nights.where(
    (n) => n.hasSleepData && !n.date.isBefore(windowStart) && !n.date.isAfter(today),
  );
  final sleepSamples = sleepInWindow.length;
  final avgSleepMinutes =
      sleepSamples == 0 ? null : sleepInWindow.fold<int>(0, (sum, n) => sum + n.sleepMinutes!) / sleepSamples;

  final manyNights = nightCount >= _kManyNightsThreshold;
  final heavyOt = otMinutesTotal >= _kHeavyOtMinutes;
  // ⭐ 축1의 "평소 대비 90분" 기준(_kLongerThanBaselineGapMinutes)을 그대로
  // 재사용 - 개인 평소 근무시간 비교는 이 파일 전체에서 하나의 기준으로 통일.
  final aboveBaselineLoad = baselineShiftMinutes != null &&
      (avgLoadPerWorkday - baselineShiftMinutes) >= _kLongerThanBaselineGapMinutes;
  final poorRecentSleep = sleepSamples >= 2 && avgSleepMinutes! < _kSufficientMinutes;
  final shortRecoveryNow = baseResult.levelFindings.any((f) => f.ruleId == 'RULE_SHORT_RECOVERY');
  // ⭐ 후속9 - RULE_LONG_SHIFT는 여전히 안 씀(습관화된 12시간 근무자를 매일
  // 플래그하면 안 됨, 14장 원칙). RULE_EXTENDED_STREAK_SHORT_BREAK는 다름 -
  // "장시간 근무 연속 + 짧은 회복"이라는 실제 이상 패턴이라 최우선 신호로 씀.
  final extendedStreakNow = baseResult.levelFindings.any((f) => f.ruleId == 'RULE_EXTENDED_STREAK_SHORT_BREAK');
  // ⭐ 신규 - 야간 여부와 무관하게 "쉬는 날 없이 며칠째 근무 중인가" 자체를
  // 별도 신호로 봄(ConditionRuleEngine이 이미 계산해둔 값을 그대로 읽음 -
  // 임계값 중복 정의 안 함). 5일 연속 근무 자체는 특정 연구 수치에 매인 값이
  // 아니라(EVIDENCE-005는 "12시간 이상 근무가 3일 연속"이라는 다른 조건이라
  // 여기 그대로 못 씀) 순수 "설계상 정한 값"이라 evidenceIds 없이 서술만 함.
  // ⭐ 후속21 - 이 기준은 이제 _kWorkStreakThresholdDays(=5, 창 길이와 분리된
  // 절대값)를 씀 - _kFatigueWindowDays가 7로 늘어났다고 "연속근무가 길다"는
  // 기준까지 같이 늘어나면 오히려 둔감해짐(예전엔 5일 연속이면 걸렸는데
  // 이제 7일을 채워야 걸리는 건 원치 않는 부작용).
  final consecutiveWorkDays = baseResult.consecutiveWorkDays;
  final longWorkStreak = consecutiveWorkDays != null && consecutiveWorkDays >= _kWorkStreakThresholdDays;
  final loadFlag = heavyOt || aboveBaselineLoad;

  final activeReasons = <_FatigueReason>[
    if (extendedStreakNow) _FatigueReason.extendedStreak,
    if (shortRecoveryNow) _FatigueReason.recovery,
    if (patternNeverRests) _FatigueReason.noRestPattern,
    if (longWorkStreak) _FatigueReason.workStreak,
    if (manyNights) _FatigueReason.nightFrequency,
    if (poorRecentSleep) _FatigueReason.sleepShortage,
    if (loadFlag) (heavyOt ? _FatigueReason.overtimeLoad : _FatigueReason.generalLoad),
  ];

  if (activeReasons.isEmpty) {
    return _RecentFatigueResult(
      _FatigueTier.stable, const [], const [],
      hasWorkPatternConcern: true,
      workDayCount: workDayCount, nightCount: nightCount, consecutiveWorkDays: consecutiveWorkDays,
    );
  }

  // ⭐ 후속20 - 활성 요인 중 "근무 패턴" 계열이 하나도 없으면(=수면/초과근무만
  // 문제) 근무 패턴 자체는 괜찮았다는 뜻 - 그 판단(hasWorkPatternConcern)만
  // 여기서 내리고, 실제 안내 문장은 _renderStableWorkNote가 노출 시점에
  // 렌더링한다.
  final hasWorkPatternConcern = activeReasons.any(_kWorkPatternReasons.contains);

  final evidenceIds = <String>{};
  for (final r in activeReasons) {
    evidenceIds.addAll(_fatigueReasonEvidence(r));
  }

  // ⭐ 2개 이상 겹칠 때 - 우선순위 1위를 헤드라인 문장으로, 나머지(최대
  // _kMaxAdditionalFatigueMentions개)를 "거기에 ~도" 식 짧은 후속 문장으로
  // 덧붙이고, 그래도 남는 게 있으면 뭉뚱그린 문구 하나, 마지막에 강도별 종합
  // 문장으로 마무리. 사용자 요청대로 "야간 3일" 같은 원자료 나열 대신 요인들을
  // 순서대로 짚어준 뒤 강도로 마무리하는 구조(실제 렌더링은
  // _renderRecentFatigueSentences 참고 - 3개 이상 겹쳐도 별도 "그 외에도~"
  // 문장을 추가하지 않고, 종합 문장이 요인 개수로 톤만 올린다).
  final tier = activeReasons.length == 1 ? _FatigueTier.building : _FatigueTier.high;
  return _RecentFatigueResult(
    tier,
    evidenceIds.toList(),
    activeReasons,
    hasWorkPatternConcern: hasWorkPatternConcern,
    workDayCount: workDayCount,
    nightCount: nightCount,
    consecutiveWorkDays: consecutiveWorkDays,
  );
}

/// ⭐ 후속20 - "근무 패턴 자체는 문제없다"고 짧게 짚어줄 문장 하나를 고른다.
/// 여러 근거 중 가장 눈에 띄는 것 하나만(전부 나열 안 함) - 우선순위: 이번
/// 창의 근무일 자체가 적었나(쉬는 날이 많았나) > 연속 근무일수가 짧았나 >
/// 야간 근무가 아예 없었나 > (그 외엔) 그냥 무난했다는 일반 문장.
/// ⭐ 2026-09-01 후속22(사용자 요청) - 문구를 다시 다듬음. 부담이 "있다"고
/// 말할 땐 "연속근무일이 길다/잦다"는 표현이 자연스럽지만(위 _fatigueFactorClause의
/// workStreak/nightFrequency 케이스가 이미 그렇게 씀), 거꾸로 "괜찮다"고
/// 안심시킬 땐 "연속 근무일수가 짧다"처럼 같은 단어를 뒤집어 쓰면 오히려
/// 어색하고 기계적으로 들림 - 사람이 실제로 하는 말처럼 "출근이 잦지 않았다",
/// "쉬는 날이 껴 있었다", "휴무가 넉넉했다" 쪽으로 풀어 씀.
String _stableWorkPatternNote({
  required int workDayCount,
  required int nightCount,
  required int? consecutiveWorkDays,
  required _Composer composer,
}) {
  if (workDayCount <= 2) {
    return composer.pick([
      () => '이번 주는 출근이 잦지 않아서 몸에 큰 무리는 없었을 거예요.',
      () => '휴무일이 넉넉했던 편이라 컨디션 관리엔 유리했어요.',
      () => '근무보다 쉬는 날이 많았던 한 주라 부담은 적었을 거예요.',
    ], 'stable_work_light_density');
  }
  if (consecutiveWorkDays != null && consecutiveWorkDays <= 2) {
    return composer.pick([
      () => '근무 사이사이 쉬는 날이 있어서 회복할 시간은 챙긴 편이에요.',
      () => '며칠 일하고 바로 쉬어가는 흐름이라 몸엔 여유가 있었을 거예요.',
      () => '근무일 대비 휴무일 배치가 괜찮아서 부담이 크게 쌓이진 않았어요.',
    ], 'stable_work_short_streak');
  }
  if (nightCount == 0) {
    return composer.pick([
      () => '야간 근무 없이 지나간 며칠이라 그 부담은 없었어요.',
      () => '이번엔 야간 없이 근무가 이어져서 그쪽으로는 걱정할 게 없었던 편이에요.',
    ], 'stable_work_no_night');
  }
  return composer.pick([
    () => '요즘 근무 흐름 자체는 크게 무리가 없어 보여요.',
    () => '전반적인 근무 리듬은 최근 안정적인 편이었어요.',
  ], 'stable_work_general');
}

/// 헤드라인/단독(building) 문장 - 요인 하나를 온전한 한 문장으로 서술.
/// ⭐ 2026-09-13 - [consecutiveWorkDays]는 workStreak 케이스의 장기화(severe)
/// 여부 판단에만 씀(다른 reason은 무시) - "5일 연속"과 "몇 주째 연속"을 같은
/// 문장으로 뭉개지 않기 위함(condition_score.dart의 비례 감점과 같은 이유,
/// 다만 여기선 정성적 표현으로만 - 원자료 숫자 나열 금지 원칙은 그대로 유지).
String _fatigueFactorClause(_FatigueReason reason, _Composer composer, {int? consecutiveWorkDays}) {
  switch (reason) {
    case _FatigueReason.extendedStreak:
      return composer.pick([
        () => '장시간 근무가 여러 날 연속으로 이어지고 있어요.',
        () => '긴 근무가 계속 이어지는 중이라 회복이 특히 필요한 시기예요.',
        () => '장시간 근무 연속에 비해 다음 회복시간이 충분치 않아요.',
      ], 'fatigue_building_extended_streak');
    case _FatigueReason.recovery:
      return composer.pick([
        () => '오늘은 근무 사이 회복시간이 평소보다 짧아요.',
        () => '오늘은 다음 근무까지의 회복시간이 조금 빠듯한 편이에요.',
      ], 'fatigue_building_recovery');
    case _FatigueReason.noRestPattern:
      return composer.pick([
        () => '지금 근무표 자체가 쉬는 날 없이 짜여 있어요.',
        () => '이 근무 패턴은 애초에 휴무가 포함돼 있지 않아요.',
        () => '근무표를 보면 쉬는 날 없이 계속 도는 구조예요.',
      ], 'fatigue_building_norest_pattern');
    case _FatigueReason.workStreak:
      final severe = (consecutiveWorkDays ?? 0) >= _kWorkStreakSevereThresholdDays;
      return severe
          ? composer.pick([
              () => '쉬는 날 없이 근무가 이어진 지 꽤 오래됐어요.',
              () => '연속 근무가 상당히 길게 이어지고 있어요.',
              () => '쉬는 날 없이 근무가 이어지는 기간이 길어지고 있어요.',
            ], 'fatigue_building_workstreak_severe')
          : composer.pick([
              () => '요즘 쉬는 날 없이 근무가 이어지고 있어요.',
              () => '최근 연속 근무일이 길어진 편이에요.',
              () => '쉬는 날 없이 근무가 계속 이어지는 중이에요.',
            ], 'fatigue_building_workstreak');
    case _FatigueReason.nightFrequency:
      return composer.pick([
        () => '요즘 야간근무가 조금씩 잦아지고 있어요.',
        () => '최근 며칠 야간근무 비중이 늘어난 편이에요.',
      ], 'fatigue_building_nights');
    case _FatigueReason.sleepShortage:
      return composer.pick([
        () => '요 며칠 수면이 평소보다 부족했어요.',
        () => '최근 며칠 수면 시간이 조금 아쉬운 편이었어요.',
      ], 'fatigue_building_sleep');
    case _FatigueReason.overtimeLoad:
      return composer.pick([
        () => '요 며칠 초과근무가 꽤 있었어요.',
        () => '평소 근무시간에 비해 초과근무가 많아 보여요.',
      ], 'fatigue_building_ot');
    case _FatigueReason.generalLoad:
      return composer.pick([
        () => '요 며칠 근무시간이 평소보다 긴 편이었어요.',
        () => '최근 며칠 근무 부담이 평소보다 조금 큰 편이에요.',
      ], 'fatigue_building_load');
  }
}

/// 헤드라인 뒤에 덧붙는 짧은 후속 문장(2번째 이후 요인용) - "거기에 ~도"
/// 식으로 앞 문장에 이어붙는 톤이라 독립 문장으로도 어색하지 않게 씀.
String _fatigueAdditionalMention(_FatigueReason reason, _Composer composer, {int? consecutiveWorkDays}) {
  switch (reason) {
    case _FatigueReason.extendedStreak:
      return composer.pick([
        () => '장시간 근무도 계속 이어지고 있어요.',
        () => '긴 근무가 연속되는 것도 겹친 상태예요.',
      ], 'fatigue_mention_extended_streak');
    case _FatigueReason.recovery:
      return composer.pick([
        () => '거기에 오늘은 회복시간까지 짧아요.',
        () => '오늘은 회복시간도 넉넉하지 않은 편이에요.',
      ], 'fatigue_mention_recovery');
    case _FatigueReason.noRestPattern:
      return composer.pick([
        () => '게다가 이 근무표엔 원래 쉬는 날이 없어요.',
        () => '이 패턴 자체에 휴무가 아예 없다는 것도 걸려요.',
      ], 'fatigue_mention_norest_pattern');
    case _FatigueReason.workStreak:
      final severe = (consecutiveWorkDays ?? 0) >= _kWorkStreakSevereThresholdDays;
      return severe
          ? composer.pick([
              () => '연속 근무가 이어진 지도 상당히 오래됐어요.',
              () => '쉬는 날 없이 근무가 이어진 기간도 길어요.',
            ], 'fatigue_mention_workstreak_severe')
          : composer.pick([
              () => '연속 근무일수도 길어진 상태예요.',
              () => '쉬는 날 없이 근무가 이어진 지도 며칠 됐어요.',
            ], 'fatigue_mention_workstreak');
    case _FatigueReason.nightFrequency:
      return composer.pick([
        () => '야간근무 비중도 최근 늘어난 편이에요.',
        () => '야간근무도 최근 며칠 잦았어요.',
      ], 'fatigue_mention_nights');
    case _FatigueReason.sleepShortage:
      return composer.pick([
        () => '수면도 충분하지 않았어요.',
        () => '수면 시간도 넉넉하지 않았던 편이에요.',
      ], 'fatigue_mention_sleep');
    case _FatigueReason.overtimeLoad:
      return composer.pick([
        () => '초과근무도 꽤 있었고요.',
        () => '평소보다 초과근무도 많았어요.',
      ], 'fatigue_mention_ot');
    case _FatigueReason.generalLoad:
      return composer.pick([
        () => '근무시간도 평소보다 길었어요.',
        () => '근무 부담도 평소보다 큰 편이었어요.',
      ], 'fatigue_mention_load');
  }
}

/// 마지막 종합 문장 - 겹친 요인 개수(2개 vs 3개 이상)로만 강도를 나눔(원자료
/// 나열 대신 "정도"로 표현하라는 요청 반영).
String _fatigueClosing(int reasonCount, _Composer composer) {
  if (reasonCount >= 3) {
    return composer.pick([
      () => '여러 부담이 겹치면서 피로 누적이 상당한 수준으로 예상돼요.',
      () => '근무·수면 여러 방면에서 부담이 겹쳐서 컨디션 관리가 특히 필요한 시기예요.',
    ], 'fatigue_closing_high');
  }
  return composer.pick([
    () => '피로가 쌓이고 있을 수 있어요.',
    () => '컨디션에 영향이 있을 수 있으니 오늘은 조금 더 유의해주세요.',
  ], 'fatigue_closing_moderate');
}

List<String> _fatigueReasonEvidence(_FatigueReason reason) {
  switch (reason) {
    case _FatigueReason.extendedStreak:
      return const ['EVIDENCE-004', 'EVIDENCE-005']; // RULE_EXTENDED_STREAK_SHORT_BREAK와 동일 근거
    case _FatigueReason.recovery:
      return const ['EVIDENCE-002', 'EVIDENCE-003'];
    case _FatigueReason.noRestPattern:
      return const []; // workStreak와 동일 - 순수 설계값, 인용 안 함
    case _FatigueReason.workStreak:
      return const []; // 연구 근거값이 아니라 순수 설계값(위 주석 참고) - 인용 안 함
    case _FatigueReason.nightFrequency:
      return const ['EVIDENCE-006'];
    case _FatigueReason.sleepShortage:
      return const ['EVIDENCE-011'];
    case _FatigueReason.overtimeLoad:
      return const ['EVIDENCE-012'];
    case _FatigueReason.generalLoad:
      return const ['EVIDENCE-004'];
  }
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// ⭐ 2026-09-07 - `_ConcernResult`(이미 resolved된 문자열)와 달리 이 결과는
/// composer로 실제 노출 시점에 렌더링해야 하는 값이라 별도 타입으로 둔다.
class _DeferredConcern {
  final List<String Function()> variants;
  final String seedKey;
  final List<String> evidenceIds;
  const _DeferredConcern(this.variants, this.seedKey, this.evidenceIds);
  String render(_Composer c) => c.pick(variants, seedKey);
}

/// ⭐ 2026-09-01 후속3 - 어제(acute)와 별개로 "오늘 근무 자체"가 이 사람 기준으로
/// 평소보다 긴지를 짧게 짚어준다. acute 이벤트가 없을 때만 헤드라인 뒤에 붙는다
/// (급성 이벤트가 있으면 문장이 너무 길어지고, 대부분 같은 이야기가 겹침).
_DeferredConcern? _findTodayLongerThanUsual(ConditionResult baseResult, double? baselineShiftMinutes) {
  final todayMinutes = baseResult.today.durationMinutes;
  if (todayMinutes == null || baselineShiftMinutes == null) return null;
  final gap = todayMinutes - baselineShiftMinutes;
  if (gap < _kLongerThanBaselineGapMinutes) return null;

  final todayH = _fmtHours(todayMinutes);
  final baselineH = _fmtHours(baselineShiftMinutes.round());
  return _DeferredConcern(
    [
      () => '오늘 근무는 평소(약 $baselineH시간)보다 긴 약 $todayH시간이에요.',
      () => '오늘은 평소보다 긴 근무(약 $todayH시간, 평소 약 $baselineH시간)가 예정돼 있어요.',
      () => '평소 약 $baselineH시간 근무하시는데, 오늘은 약 $todayH시간으로 더 길어요.',
    ],
    'today_longer_than_usual',
    const [],
  );
}

String _fmtHours(int minutes) {
  final h = minutes / 60;
  return h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
}

// ═══════════════════════════════════════════════════════════════════════
// 권고(행동 팁) - 2026-09-01 후속8. 예전엔 "수면부족→휴식→카페인→유지" 4갈래
// 고정 팁이었는데(어떤 원인이든 같은 문구), "그날의 특화된 추천이 아니다"는
// 피드백으로 축4가 이미 우선순위까지 매겨둔 reasons를 그대로 재사용해 요인별
// 구체적 행동으로 교체함. 근거가 있는 항목은 evidence_database.dart를 인용,
// workStreak처럼 특정 연구 수치가 없는 항목은(파일 상단 원칙 2번 참고 -
// 사용자 명시 완화) "무리하지 마라/가볍게" 방향의 보수적 상식 조언만 씀.
// 급성 카페인 팁(RULE_CAFFEINE_CUTOFF)은 이미 별도 "오늘의 추천" 카드
// (ConditionRuleEngine.tips)에 있어서 여기서 중복 안 함.
// ═══════════════════════════════════════════════════════════════════════

class _TipResult {
  final List<String> sentences; // 1~2문장(단독 또는 상위 2개 요인 조합)
  final List<String> evidenceIds;
  const _TipResult(this.sentences, this.evidenceIds);
}

_TipResult? _pickActionTip({
  required bool acute,
  required List<_FatigueReason> reasons, // 축4 우선순위 그대로(recovery>workStreak>nightFrequency>sleepShortage>load)
  required _OtDirection otDirection,
  required _SufficiencyTrend sufficiency,
  required _Composer composer,
}) {
  // 급성(어제 실제 수면 부족)은 항상 수면 확보가 최우선 행동 - 축4가 이미
  // sleepShortage를 잡았으면 중복 없이 합치고, 아니면 맨 앞에 끼워 넣는다.
  final effective = <_FatigueReason>[
    if (acute && !reasons.contains(_FatigueReason.sleepShortage)) _FatigueReason.sleepShortage,
    ...reasons,
  ];

  if (effective.isEmpty) {
    if (_otImproving(otDirection) || _sleepImproving(sufficiency)) {
      final message = composer.pick([
        () => '지금처럼 유지하시면 좋아요.',
        () => '지금 페이스를 잘 유지하고 계세요.',
        () => '이 흐름 그대로 이어가시면 좋을 것 같아요.',
      ], 'tip_keepup');
      return _TipResult([message], const []);
    }
    return null;
  }

  final primary = effective.first;
  final evidenceIds = <String>{..._fatigueReasonEvidence(primary)};
  final sentences = <String>[_actionTipPrimary(primary, composer)];

  // 2번째 요인까지만 더 짚어준다(문장 수 정제 - 축4 헤드라인과 동일한 원칙).
  if (effective.length >= 2 && effective[1] != primary) {
    final secondary = effective[1];
    sentences.add(_actionTipSecondary(secondary, composer));
    evidenceIds.addAll(_fatigueReasonEvidence(secondary));
  }

  return _TipResult(sentences, evidenceIds.toList());
}

/// 요인 하나를 구체적 행동으로 옮긴 문장(단독이거나 헤드라인 역할).
String _actionTipPrimary(_FatigueReason reason, _Composer composer) {
  switch (reason) {
    case _FatigueReason.extendedStreak:
      return composer.pick([
        () => '장시간 근무가 계속 이어진 만큼, 이번 휴무는 최대한 회복에 집중해보세요.',
        () => '긴 근무가 연속된 만큼, 가능하면 다음 휴식일을 충분히 확보해보세요.',
        () => '장시간 근무가 이어지는 시기엔 무리한 활동은 피하고 몸을 회복시키는 데 집중해보세요.',
      ], 'action_extended_streak');
    case _FatigueReason.recovery:
      return composer.pick([
        () => '회복시간이 짧은 만큼, 오늘은 불필요한 일정을 줄이고 최대한 쉬는 데 집중해보세요.',
        () => '쉬는 시간이 넉넉지 않으니, 이동이나 준비 시간을 줄여서라도 잠을 조금 더 확보해보세요.',
        () => '짧은 회복시간 동안은 무리한 약속보다 휴식을 우선해보세요.',
      ], 'action_recovery');
    case _FatigueReason.noRestPattern:
      return composer.pick([
        () => '쉬는 날이 아예 없는 패턴인 만큼, 근무 사이 짧은 시간이라도 회복에 최대한 써보세요.',
        () => '가능하다면 근무표에 쉬는 날을 넣는 방법도 함께 고려해보세요.',
        () => '휴무가 없는 구조라면 근무 강도를 조절하거나 쉬는 날을 만드는 쪽을 검토해보는 게 좋아요.',
      ], 'action_norest_pattern');
    case _FatigueReason.workStreak:
      return composer.pick([
        () => '연속 근무가 이어지는 만큼, 격한 운동보다는 가벼운 스트레칭 정도로 몸을 풀어주세요.',
        () => '쉬는 날 없이 근무가 계속될 땐 무리한 활동보다 몸과 마음을 쉬게 하는 데 집중해보세요.',
        () => '연속 근무 중엔 강도 높은 운동은 잠시 미루고, 가벼운 스트레칭이나 산책 정도가 좋아요.',
      ], 'action_workstreak');
    case _FatigueReason.nightFrequency:
      return composer.pick([
        () => '야간근무가 잦은 시기엔 낮에도 최대한 어둡고 조용한 환경에서 수면을 확보해보세요.',
        () => '야간근무 비중이 높을 땐 평소보다 수면 환경에 조금 더 신경 써보는 게 좋아요.',
      ], 'action_nightfreq');
    case _FatigueReason.sleepShortage:
      return composer.pick([
        () => '오늘은 다른 일정보다 수면부터 채우는 걸 우선해보세요.',
        () => '가능하다면 오늘은 조금 일찍 잠자리에 들어 부족한 잠을 보충해보세요.',
        () => '오늘만큼은 수면 시간을 평소보다 넉넉히 챙겨보세요.',
      ], 'action_sleep');
    case _FatigueReason.overtimeLoad:
      return composer.pick([
        () => '초과근무가 많았던 만큼, 남은 시간엔 회복을 최우선으로 챙겨보세요.',
        () => '초과근무로 근무시간이 늘었던 만큼 따로 쉴 시간을 확보해보세요.',
      ], 'action_ot');
    case _FatigueReason.generalLoad:
      return composer.pick([
        () => '근무시간이 길었던 만큼, 오늘은 무리한 활동은 피하고 컨디션 관리에 신경 써보세요.',
        () => '평소보다 근무가 길었으니 회복에 조금 더 시간을 써보세요.',
      ], 'action_load');
  }
}

/// 2번째 요인에 짧게 덧붙는 후속 행동 문장.
String _actionTipSecondary(_FatigueReason reason, _Composer composer) {
  switch (reason) {
    case _FatigueReason.extendedStreak:
      return composer.pick([
        () => '긴 근무가 이어진 만큼 회복에 더 신경 써주세요.',
        () => '장시간 근무 연속도 겹쳐 있으니 무리하지 마세요.',
      ], 'action_mention_extended_streak');
    case _FatigueReason.recovery:
      return composer.pick([
        () => '짧은 틈에도 눈을 붙일 수 있으면 좋아요.',
        () => '오늘은 회복시간도 넉넉하지 않으니 더 신경 써주세요.',
      ], 'action_mention_recovery');
    case _FatigueReason.noRestPattern:
      return composer.pick([
        () => '장기적으로는 쉬는 날을 넣는 방향도 고민해보세요.',
        () => '근무 강도 조절이나 휴무 추가를 검토해보는 것도 방법이에요.',
      ], 'action_mention_norest_pattern');
    case _FatigueReason.workStreak:
      return composer.pick([
        () => '가벼운 스트레칭 정도만 곁들여도 도움이 돼요.',
        () => '무리한 운동은 이번엔 피해주세요.',
      ], 'action_mention_workstreak');
    case _FatigueReason.nightFrequency:
      return composer.pick([
        () => '빛 노출도 조절해보면 회복에 도움이 될 수 있어요.',
        () => '수면 환경에도 조금 더 신경 써보세요.',
      ], 'action_mention_nightfreq');
    case _FatigueReason.sleepShortage:
      return composer.pick([
        () => '수면을 조금이라도 더 확보하는 게 우선이에요.',
        () => '가능하면 짧게라도 잠을 보충해보세요.',
      ], 'action_mention_sleep');
    case _FatigueReason.overtimeLoad:
      return composer.pick([
        () => '무리한 개인 일정은 잠시 미뤄두는 것도 방법이에요.',
        () => '이번엔 일정을 조금 가볍게 잡아보세요.',
      ], 'action_mention_ot');
    case _FatigueReason.generalLoad:
      return composer.pick([
        () => '컨디션 관리에 조금 더 신경 써주세요.',
        () => '무리하지 않는 선에서 하루를 보내보세요.',
      ], 'action_mention_load');
  }
}

SleepDataCoverage _coverageFor(int tracked, int withData) {
  if (tracked == 0) return SleepDataCoverage.none;
  final ratio = withData / tracked;
  if (ratio <= 0) return SleepDataCoverage.none;
  if (ratio < 0.5) return SleepDataCoverage.low;
  if (ratio < 0.9) return SleepDataCoverage.mid;
  return SleepDataCoverage.high;
}
