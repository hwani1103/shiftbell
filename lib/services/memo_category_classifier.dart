// lib/services/memo_category_classifier.dart
//
// ⭐ 2026-08-27 - 메모_자동분류_ML_계획.md Phase 4. ml/ 아래 Python 프로토타입을
// 그대로 이식한 것 - 알고리즘을 바꿀 땐 항상 두 곳(Python/Dart)을 같이 고칠 것.
//
// 순서 (ml/predict.py와 동일):
//   1. 키워드 하드매핑(ml/keyword_router.py 이식, _MemoKeywordRouter) 먼저 확인
//   2. 안 걸리면 TF-IDF(char_wb 2~3gram) + LogisticRegression(ml/export.py가
//      assets/ml/memo_category_model.json으로 내보낸 vocab/idf/coef/intercept)
//   3. top1-top2 확률차(margin)가 threshold보다 작으면 'etc'(기타)로 폴백
//
// 온디바이스 전용 - 서버/LLM API 호출 없음. 서비스 하나가 앱 전역에서 재사용되도록
// 싱글턴으로 둠(모델 로드가 ~2MB JSON 파싱 + vocab 2만개 Map 구성이라 매번 새로
// 만들 이유가 없음). 사용 전 반드시 [MemoCategoryClassifier.instance.ensureLoaded]를
// await할 것 - main.dart에서 앱 시작 시 미리 한 번 불러 두면(warm) 실제 분류 시점엔
// 즉시 반환됨.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// 분류 결과. [categoryKey]는 'work'/'study'/'exercise'/'health'/'meal'/'social'/
/// 'family'/'shopping'/'leisure'/'running'/'swimming'/'hiking'/'culture'/
/// 'finance'/'housework'/'beauty'/'cycling'/'yoga'/'etc' 중 하나
/// (2026-09-01 - 10종 -> 17종, 2026-09-03 - 17종 -> 19종) -
/// assets/icons/memo_category/의 파일명, lib/screens/schedule_management_tab.dart의
/// _kScheduleCategoryIcons와 동일한 키 체계.
class MemoCategoryPrediction {
  final String categoryKey;
  final String method; // 디버깅/로그용 - 'tier1_immediate_family', 'ml', 'ml_low_confidence_fallback' 등
  final double? confidence;
  final double? margin;

  const MemoCategoryPrediction({
    required this.categoryKey,
    required this.method,
    this.confidence,
    this.margin,
  });

  @override
  String toString() =>
      'MemoCategoryPrediction($categoryKey, method=$method, confidence=$confidence, margin=$margin)';
}

class MemoCategoryClassifier {
  MemoCategoryClassifier._();
  static final MemoCategoryClassifier instance = MemoCategoryClassifier._();

  // ml/predict.py DEFAULT_MARGIN_THRESHOLD와 동일 값 - 바뀌면 같이 바꿀 것.
  // (계획서상 "잠정값" - Phase 4~5 진행하며 재튜닝 여지 있음)
  static const double defaultMarginThreshold = 0.08;

  bool _loaded = false;
  Future<void>? _loading;

  late final Map<String, int> _vocab;
  late final List<double> _idf;
  late final List<List<double>> _coef; // [classIndex][featureIndex]
  late final List<double> _intercept;
  late final List<String> _classesKey;

  bool get isLoaded => _loaded;

  /// 모델 JSON을 비동기로 로드(최초 1회만 실제 로드, 이후 즉시 반환).
  /// main.dart 시작 시 한 번 호출해서 미리 데워두는 걸 권장.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final raw =
        await rootBundle.loadString('assets/ml/memo_category_model.json');
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;

    final vocabList = (json['vocab'] as List).cast<String>();
    final vocab = <String, int>{};
    for (var i = 0; i < vocabList.length; i++) {
      vocab[vocabList[i]] = i;
    }
    _vocab = vocab;
    _idf =
        (json['idf'] as List).map((e) => (e as num).toDouble()).toList();
    _coef = (json['coef'] as List)
        .map((row) =>
            (row as List).map((e) => (e as num).toDouble()).toList())
        .toList();
    _intercept = (json['intercept'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    _classesKey = (json['classes_key'] as List).cast<String>();
    _loaded = true;
  }

  /// 동기 분류 - 반드시 [ensureLoaded]가 끝난 뒤 호출할 것.
  MemoCategoryPrediction classify(
    String text, {
    double marginThreshold = defaultMarginThreshold,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const MemoCategoryPrediction(
          categoryKey: 'etc', method: 'empty_text');
    }

    final routed = _MemoKeywordRouter.route(trimmed);
    if (routed != null) {
      return MemoCategoryPrediction(
          categoryKey: routed.$1, method: routed.$2);
    }

    if (!_loaded) {
      throw StateError(
          'MemoCategoryClassifier.ensureLoaded()를 먼저 await할 것 (키워드 하드매핑에 안 걸려서 ML 모델이 필요함)');
    }
    return _mlPredict(trimmed, marginThreshold);
  }

  MemoCategoryPrediction _mlPredict(String text, double marginThreshold) {
    final lower = text.toLowerCase();
    final ngrams = _charWbNgrams(lower);

    final counts = <int, int>{};
    for (final ng in ngrams) {
      final idx = _vocab[ng];
      if (idx != null) {
        counts[idx] = (counts[idx] ?? 0) + 1;
      }
    }

    // sublinear tf(1+ln(count)) * idf, 그 다음 L2 정규화.
    final tfidf = <int, double>{};
    for (final entry in counts.entries) {
      final tf = 1 + math.log(entry.value);
      tfidf[entry.key] = tf * _idf[entry.key];
    }
    var normSq = 0.0;
    for (final v in tfidf.values) {
      normSq += v * v;
    }
    final norm = math.sqrt(normSq);
    if (norm > 0) {
      tfidf.updateAll((_, v) => v / norm);
    }

    // logits = intercept + coef · tfidf (0이 아닌 항만 순회 - 짧은 메모라 수십 개뿐)
    final nClasses = _classesKey.length;
    final logits = List<double>.from(_intercept);
    tfidf.forEach((idx, v) {
      for (var c = 0; c < nClasses; c++) {
        logits[c] += _coef[c][idx] * v;
      }
    });

    // softmax
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final probs = exps.map((e) => e / sumExp).toList();

    final order = List<int>.generate(nClasses, (i) => i)
      ..sort((a, b) => probs[b].compareTo(probs[a]));
    final top1 = order[0];
    final top2 = order[1];
    final margin = probs[top1] - probs[top2];

    if (margin < marginThreshold) {
      return MemoCategoryPrediction(
        categoryKey: 'etc',
        method: 'ml_low_confidence_fallback',
        confidence: probs[top1],
        margin: margin,
      );
    }
    return MemoCategoryPrediction(
      categoryKey: _classesKey[top1],
      method: 'ml',
      confidence: probs[top1],
      margin: margin,
    );
  }
}

// ⭐ char_wb n-gram - sklearn TfidfVectorizer(analyzer='char_wb', ngram_range=(2,3))와
// 동일한 결과를 내도록 포팅함(단어를 " "+word+" "로 패딩한 뒤 2~3글자 슬라이딩
// 윈도우, 단어 경계를 넘는 n-gram은 안 만듦). ml/export.py의 ngram_min/max=2,3
// 가정과 묶여 있는 값이라, 학습 파이프라인의 ngram_range를 바꾸면 여기 2, 3도
// 같이 바꿔야 함.
List<String> _charWbNgrams(String text, {int minN = 2, int maxN = 3}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  final ngrams = <String>[];
  for (final word in normalized.split(' ')) {
    if (word.isEmpty) continue;
    final w = ' $word ';
    final wLen = w.length;
    for (var n = minN; n <= maxN; n++) {
      if (n > wLen) continue;
      for (var i = 0; i <= wLen - n; i++) {
        ngrams.add(w.substring(i, i + n));
      }
    }
  }
  return ngrams;
}

// ============================================================
// ⭐ 키워드 하드매핑 - ml/keyword_router.py를 그대로 이식.
// 규칙/주석은 원본과 동일하게 유지 - 바뀌면 두 파일을 같이 고칠 것.
// ============================================================

const List<String> _kCommonParticles = [
  '가', '이', '은', '는', '을', '를', '의', '에게', '한테', '께',
  '랑', '이랑', '와', '과', '도', '만', '까지', '부터', '께서',
  '인데', '이고', '이지만', '라도', '이라도', '야', '아',
  // ⭐ 2026-08-27 - 존칭 접미사("장모"+"님"="장모님" 등). ml/keyword_router.py 참고.
  '님', '어른', '댁',
  // ⭐ 2026-09-01(실사용 문장 테스트) - "청소나 가볍게 하기"류의 캐주얼한
  // "~나"(or) 연결 조사가 없어서 CHORE_KEYWORDS 등이 못 잡던 걸 발견해서 추가.
  '나', '이나',
];

// ⭐ 2026-09-03 - ml/keyword_router.py의 _particle_suffix_ok 이식. 기존엔
// rest 전체가 _kCommonParticles의 항목 '한 개'와 정확히 일치해야만 통과됐는데,
// 한국어는 조사가 여러 개 겹쳐 붙는 게 흔함("친구들과의" = "들"(복수) +
// "과"(조사) + "의"(조사)) - rest가 "과의"가 되는데 목록엔 "과"/"의"만 개별로
// 있어서 매칭에 실패, "친구"/"동료" 같은 명백한 지인 신호를 놓치는 실측
// 버그를 발견해서 재귀적으로 여러 조사를 계속 벗겨내도록 고침. 긴 조사부터
// 시도(짧은 조사가 긴 조사의 접두사인 케이스에서 잘못 잘리는 것 방지).
// ⚠️ "로"/"으로"는 일부러 안 넣는다 - "등산로"/"조깅으로"에서 실측 회귀 발견
// (ml/keyword_router.py의 RUNNING_KEYWORDS 주석 근처 설명 참고).
bool _particleSuffixOk(String rest) {
  if (rest.isEmpty) return true;
  final sorted = [..._kCommonParticles]..sort((a, b) => b.length.compareTo(a.length));
  for (final p in sorted) {
    if (rest.startsWith(p) && _particleSuffixOk(rest.substring(p.length))) {
      return true;
    }
  }
  return false;
}

const List<String> _kImmediateFamily = [
  '엄마', '어머니', '아빠', '아버지', '아들', '딸', '남편', '아내', '배우자',
  '할머니', '할아버지', '부모님', '친정엄마', '친정아빠', '아이',
];

// "가족"은 "온가족/전가족"처럼 복합어로도 자주 쓰여서 contains(부분일치)로 따로 잡음.
// ⭐ 2026-09-01 - "본가"도 같은 이유로 추가(ml/keyword_router.py 참고 - 신설
// "집안일" 하드매핑이 "본가 OO 청소해드리기"류를 가족보다 먼저 채가는 걸 막기 위함).
const List<String> _kImmediateFamilyContains = ['가족', '본가'];

// "형/누나/언니/오빠/동생"은 일부러 뺐다 - 혈연이 아니라 친한 사람을 부르는
// 호칭으로도 매우 흔히 쓰여서(ml/keyword_router.py 참고), ML+margin 판단에 맡김.
const List<String> _kExtendedFamily = [
  '며느리', '사위', '시댁', '처가',
  '장인', '장모', '처남', '처형', '처제', '매형', '매부', '동서', '시누이',
  '형수', '제수', '올케', '고모', '이모', '삼촌', '외삼촌', '조카', '사돈',
  '시아버지', '시어머니', '시부모님', '손자', '손녀', '사촌',
];

// ⭐ 2026-09-01(실사용 문장 테스트) - "팀원"도 "동료"와 동일 개념인데 빠져있어서
// 추가("점심시간에 팀원들이랑 순대국밥집 가기"가 사교로 안 잡히던 걸 발견).
const List<String> _kAcquaintanceMarkers = [
  '친구', '동료', '지인', '소개', '동창', '직장동료', '회사동료', '팀원',
];

const List<String> _kSocialKeywords = [
  '친구', '동창', '동기', '선배', '후배', '동료', '지인', '정모', '동호회', '팀원',
];

// 잠정 비활성화(원본과 동일 - ml/keyword_router.py의 PURCHASE_MARKERS 주석 참고).
const List<String> _kPurchaseMarkers = <String>[];

// ⭐ 2026-09-01(카테고리 확장) - "마라톤"은 _kRunningKeywords로 옮김(ml/
// keyword_router.py 참고).
const List<String> _kSportsKeywords = [
  '테니스', '골프', '라운딩', '탁구', '축구', '배드민턴', '스쿼시',
  '클라이밍', '복싱', '웨이트', '농구', '배구',
  '야구', '줄넘기', '크로스핏',
];
// ⭐ 2026-09-03 - "필라테스"는 카테고리 확장(요가/필라테스 신설)으로 이
// 목록에서 빠짐(전용 카테고리로 승격, ml/keyword_router.py 참고).

const List<String> _kSportsFalsePositives = [
  '골프공', '테니스공', '야구공', '축구공', '탁구공',
];

// ⭐ 2026-09-01 - 카테고리 확장(10 -> 17개). ml/keyword_router.py의 동일
// 섹션(주석 포함)을 그대로 이식 - 근거/트레이드오프는 그쪽 주석 참고.
const List<String> _kRunningKeywords = ['러닝', '달리기', '조깅', '런닝', '마라톤'];
// "마리오카트 레이스 한판 달리기"처럼 게임 속 "달리기"(레이싱 게임)와 충돌 -
// 실측으로 발견한 유일한 사례라 해당 게임 이름만 좁게 예외 처리.
const List<String> _kRunningFalsePositives = ['닌텐도'];
const List<String> _kSwimmingKeywords = ['수영'];
const List<String> _kHikingKeywords = ['등산', '트레킹', '산행', '둘레길', '등반'];
// "지리산 등반"처럼 산 이름 + "등반"이 등산과 동의어로 흔히 쓰여서 추가했는데,
// "등반"은 "암벽등반"(실내 클라이밍, 이미 _kSportsKeywords의 "클라이밍"이
// 커버하는 완전히 다른 종목)과도 겹쳐서 그 복합어만 예외 처리.
const List<String> _kHikingFalsePositives = ['암벽등반'];
// ⭐ 2026-09-03 - 카테고리 확장(17 -> 19개). "자전거"/"요가·필라테스"(스트레칭
// 포함) 신설 - ml/keyword_router.py의 동일 섹션(주석 포함)을 그대로 이식.
const List<String> _kCyclingKeywords = ['자전거', '따릉이'];
const List<String> _kCyclingFalsePositives = ['하늘자전거'];
const List<String> _kYogaKeywordsAnywhere = ['필라테스', '스트레칭'];
// ⚠️ "요가"만 anywhere=false(어절 맨 앞에서만 인정) - "필요가 있다"의
// "필요가"가 "요가"로 끝나는 오탐 방지(ml/keyword_router.py 참고).
const List<String> _kYogaKeywordsPrefixOnly = ['요가'];
const List<String> _kCyclingYogaPurchaseOrRepairMarkers = [
  '사기', '사주기', '구매하기', '구입하기', '주문하기', '장만하기', '수리', '맡기러',
];
const List<String> _kCultureKeywords = ['영화', '콘서트', '공연', '전시', '뮤지컬', '연극', '페스티벌'];
const List<String> _kFinanceKeywords = ['은행', '환전', '적금', '예금', '연말정산', '공과금'];
const List<String> _kFinanceFalsePositives = ['은행나무'];
const List<String> _kChoreKeywords = ['청소', '빨래', '설거지', '분리수거'];
const List<String> _kBeautyContainsKeywords = ['미용실', '네일아트', '네일샵', '왁싱', '염색', '속눈썹'];
const List<String> _kBeautyPrefixKeywords = ['펌', '커트'];

// ⭐ 2026-08-27 - 짧은 단어/구가 '기타'로 자주 빠지는 문제 실측 후 추가.
// ml/keyword_router.py의 ACTIVITY_PREFIX_KEYWORDS와 동일 - "업무"/"휴식"은
// 전체 라벨 데이터(5,464개) 검증에서 충돌이 나서 뺐음(ml/check_keyword_
// regressions.py, 주석 참고). 바뀌면 두 파일 다 같이 고칠 것.
// ⭐ 2026-09-01(실사용 문장 테스트) - "인강"(7/7 전부 공부)과 "강의"(41/43
// 공부, 나머지 2건 "정신건강의학과"는 prefix 매칭이라 애초에 안 걸림) 추가.
// ⭐ 2026-09-03 - "코테"(코딩테스트 줄임말, "인강"과 같은 원리)/"집콕"/"방탈출"
// 추가(ml/keyword_router.py와 동일 - eval_e2e.py로 실측 검증, check_keyword_
// regressions.py 전체 충돌 0건). OTT 브랜드명(넷플릭스 등)과 "캠핑"도 시도했으나
// 실제 라벨 데이터와 충돌해서 뺐음(그쪽 파일 주석 참고).
const Map<String, List<String>> _kActivityPrefixKeywords = {
  'study': ['공부', '독서', '인강', '강의', '코테'],
  'health': ['병원'],
  'work': ['출장'],
  'meal': ['식사', '외식'],
  'leisure': ['여가', '집콕', '방탈출'],
};

// "쇼핑"은 "온라인쇼핑"처럼 복합어로도 흔히 쓰여서 contains로 잡음.
const Map<String, List<String>> _kActivityContainsKeywords = {
  'shopping': ['쇼핑'],
};

// ⭐ 2026-09-06(실사용 신고) - "치킨 먹자"/"~~먹자"류의 구어체 제안형 식사
// 표현이 하드매핑에 전혀 안 걸려서(_kActivityPrefixKeywords의 '식사'/'외식'만
// 잡음) ML로 넘어갔는데, 학습데이터의 'meal' 라벨이 전부 "OO 시켜 먹기"류의
// 격식체+구체 메뉴 설명이라(예: "야식으로 치킨 시켜먹기") 이렇게 짧고 캐주얼한
// 문장은 학습 분포 밖이라 오분류가 잦았다(실측: "치킨 먹자"가 병원·건강관리로
// 감 - 짧은 문장이라 n-gram이 몇 개 안 남아서 우연한 상관에 취약함). "약
// 먹자"류(복용)와의 오탐을 막기 위해 복용 관련 단어가 같이 있으면 이 tier는
// 건너뛰고 ML(건강 쪽으로 이미 잘 학습됨)에 맡긴다. ml/keyword_router.py의
// EATING_PROPOSAL_KEYWORDS/EATING_PROPOSAL_MEDICATION_DEFER와 동일.
const List<String> _kEatingProposalKeywords = ['먹자', '먹을래', '먹으러'];
const List<String> _kEatingProposalMedicationDefer = [
  '약', '영양제', '유산균', '비타민', '오메가', '프로폴리스', '한약',
];

// "독서 모임"류처럼 실제로는 사람을 만나는 게 핵심인 경우가 더 많아서(실측),
// "모임" 신호가 있으면 활동 하드매핑 전체를 보류하고 ML 판단에 맡김.
const List<String> _kActivityDeferMarkers = ['모임'];

abstract final class _MemoKeywordRouter {
  static List<String> _tokens(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  static bool _wordMatchesToken(String token, String word) {
    if (!token.startsWith(word)) return false;
    var rest = token.substring(word.length);
    if (rest.isEmpty) return true;
    if (rest.startsWith('들')) {
      rest = rest.substring(1);
      if (rest.isEmpty) return true;
    }
    return _particleSuffixOk(rest);
  }

  static bool _anyWordMatched(List<String> tokens, List<String> keywords) {
    for (final tok in tokens) {
      for (final kw in keywords) {
        if (_wordMatchesToken(tok, kw)) return true;
      }
    }
    return false;
  }

  static bool _anyPrefixMatched(List<String> tokens, List<String> keywords) {
    for (final tok in tokens) {
      for (final kw in keywords) {
        if (tok.startsWith(kw)) return true;
      }
    }
    return false;
  }

  static bool _anyContainsMatched(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  // ⭐ 2026-09-01(2차 - 어미/앞말 대응 점검) 처음엔 "하"/"해" 두 어간만
  // 인정했는데 "할거임"(할)/"했음"(했)/"한 적"(한) 같은 "하다" 활용형의 다른
  // 어간을 놓치는 걸 발견해서 5개로 늘림.
  static const List<String> _kVerbStems = ['하', '해', '할', '했', '한'];

  // ⭐ 2026-09-03 - _kCyclingKeywords 전용 확장 어간("타다": 타기/타며/타고/
  // 탄다/탈/탔). "청소타령"류 무관한 단어와의 충돌 위험 때문에 전역 _kVerbStems
  // 에는 안 넣고 이 tier에만 좁게 적용(ml/keyword_router.py 참고).
  static const List<String> _kCyclingVerbStems = [
    '하', '해', '할', '했', '한', '타', '탄', '탈', '탔',
  ];

  // ⭐ 2026-09-01 - CHORE_KEYWORDS(집안일)/RUNNING·SWIMMING·HIKING_KEYWORDS/
  // BEAUTY_PREFIX_KEYWORDS(미용) 전용 매처. ml/keyword_router.py의
  // _verb_word_matches_token과 동일 - "청소기"/"청소용"/"빨래바구니"/"펌프형"
  // 처럼 명사가 이어지는 경우(뒤가 조사도 "하다" 활용형도 아님)는 절대 안 잡음
  // - 단순 prefix 매칭보다 엄격함.
  //
  // anywhere=false(기본)면 word가 어절 맨 앞에 와야 함. anywhere=true면
  // "새벽러닝"/"주말등산"처럼 word 앞에 다른 말이 붙어 있어도 인정 -
  // RUNNING/SWIMMING/HIKING/CHORE처럼 그 자체로 뜻이 뚜렷해 오탐 위험이 낮은
  // 키워드에만 씀. BEAUTY_PREFIX_KEYWORDS의 "펌"은 "컨펌하기"(confirm, 전혀
  // 무관)처럼 짧은 한 글자라 anywhere=true로 켜면 오탐이 생기므로 반드시
  // anywhere=false(기본값)로 유지할 것.
  static bool _verbWordMatchesToken(String token, String word,
      {bool anywhere = false, List<String> stems = _kVerbStems}) {
    final idx = anywhere ? token.indexOf(word) : (token.startsWith(word) ? 0 : -1);
    if (idx == -1) return false;
    final rest = token.substring(idx + word.length);
    if (rest.isEmpty) return true;
    if (rest.isNotEmpty && stems.contains(rest[0])) return true;
    return _particleSuffixOk(rest);
  }

  static bool _anyVerbWordMatched(List<String> tokens, List<String> keywords,
      {bool anywhere = false, List<String> stems = _kVerbStems}) {
    for (final tok in tokens) {
      for (final kw in keywords) {
        if (_verbWordMatchesToken(tok, kw, anywhere: anywhere, stems: stems)) return true;
      }
    }
    return false;
  }

  /// 반환값: (categoryKey, method) 또는 null(안 걸리면 ML로 넘어가라는 뜻).
  static (String, String)? route(String text) {
    final tokens = _tokens(text);
    final hasAcquaintance = _anyWordMatched(tokens, _kAcquaintanceMarkers);
    final hasPurchase = _anyContainsMatched(text, _kPurchaseMarkers);

    final immediateHit = _anyWordMatched(tokens, _kImmediateFamily) ||
        _anyContainsMatched(text, _kImmediateFamilyContains);
    final extendedHit = _anyWordMatched(tokens, _kExtendedFamily);

    if (immediateHit || extendedHit) {
      if (hasPurchase) {
        return ('shopping', 'tier0_purchase_over_family');
      }
      if (!hasAcquaintance) {
        return (
          'family',
          immediateHit ? 'tier1_immediate_family' : 'tier1b_extended_family'
        );
      }
      // 가족어 + 지인/친구/동료 신호가 같이 있으면 "남의 가족" 가능성 -> 계속 진행
    }

    if (_anyWordMatched(tokens, _kSocialKeywords)) {
      return ('social', 'tier2_social');
    }

    final sportsHit = _anyPrefixMatched(tokens, _kSportsKeywords) ||
        _anyContainsMatched(text, _kSportsKeywords);
    if (sportsHit && !_anyContainsMatched(text, _kSportsFalsePositives)) {
      return ('exercise', 'tier3_sports');
    }

    // ⭐ 2026-09-01(실측 후 수정) - 신설 카테고리 3종(달리기/수영/등산)은 처음엔
    // 일반 스포츠처럼 prefix+contains로 잡았다가, "러닝메이트랑 저녁"(사교인데
    // "러닝메이트"가 "러닝"으로 시작해서 오분류), "러닝머신 매트 주문"/"등산화
    // 밑창 갈기"(장비를 사는 쇼핑인데 오분류) 실측 충돌을 발견해서
    // _anyVerbWordMatched(어절이 그 단어 자체이거나 조사/동사 활용형으로 이어질
    // 때만 인정, "메이트"/"머신"/"화"처럼 명사가 이어지면 안 잡음)로 바꿈.
    // "산행"/"둘레길"이 동호회 회식 맥락에서도 쓰여서, 클럽/모임 신호가 있으면
    // 이 3개 tier를 통째로 defer(ml/keyword_router.py와 동일).
    final tier3bSocialDefer = _anyContainsMatched(
        text, ['클럽', '모임', '뒷풀이', '신년회', '송년회', '환영회', '정모', '산악회']);
    // ⭐ 2026-09-03 - "자격증"(시험 준비가 핵심이라 공부가 더 맞음 - "네일아트
    // 자격증 실기 연습" 실측 충돌로 발견)이 있으면 문화생활/금융/집안일/미용
    // (tier3c)뿐 아니라 자전거/요가·필라테스(tier3b)에도 적용하기 위해 위로 옮김.
    final certDefer = _anyContainsMatched(text, ['자격증']);
    if (!tier3bSocialDefer) {
      // ⭐ 2026-09-01(2차) - anywhere:true로 "새벽러닝"/"주말등산"처럼 앞에
      // 다른 말이 붙는 경우도 잡음(_verbWordMatchesToken 주석 참고).
      if (_anyVerbWordMatched(tokens, _kRunningKeywords, anywhere: true) &&
          !_anyContainsMatched(text, _kRunningFalsePositives)) {
        return ('running', 'tier3b_running');
      }
      if (_anyVerbWordMatched(tokens, _kSwimmingKeywords, anywhere: true)) {
        return ('swimming', 'tier3b_swimming');
      }
      if (_anyVerbWordMatched(tokens, _kHikingKeywords, anywhere: true) &&
          !_anyContainsMatched(text, _kHikingFalsePositives)) {
        return ('hiking', 'tier3b_hiking');
      }

      // ⭐ 2026-09-03 - 자전거/요가·필라테스(신설). cert_defer 또는 구매/수리
      // 신호가 있으면 이 둘도 defer(ml/keyword_router.py와 동일 원칙).
      final cyclingYogaDefer = certDefer ||
          _anyContainsMatched(text, _kCyclingYogaPurchaseOrRepairMarkers);
      if (!cyclingYogaDefer) {
        if (_anyVerbWordMatched(tokens, _kCyclingKeywords,
                anywhere: true, stems: _kCyclingVerbStems) &&
            !_anyContainsMatched(text, _kCyclingFalsePositives)) {
          return ('cycling', 'tier3b_cycling');
        }
        if (_anyVerbWordMatched(tokens, _kYogaKeywordsAnywhere, anywhere: true) ||
            _anyVerbWordMatched(tokens, _kYogaKeywordsPrefixOnly)) {
          return ('yoga', 'tier3b_yoga');
        }
      }
    }

    // ⭐ 2026-09-01 - 신설 카테고리 4종(문화생활/금융/집안일/미용).
    if (!certDefer && _anyContainsMatched(text, _kCultureKeywords)) {
      return ('culture', 'tier3c_culture');
    }
    // ⭐ "은행"은 contains가 아니라 prefix로 잡는다 - "문제은행"(시험, 금융과
    // 무관)이 contains로는 걸려서 실측 충돌 발견.
    if (!certDefer &&
        _anyPrefixMatched(tokens, _kFinanceKeywords) &&
        !_anyContainsMatched(text, _kFinanceFalsePositives)) {
      return ('finance', 'tier3c_finance');
    }
    // ⭐ 2026-09-01(2차) - "주말청소"/"저녁설거지"처럼 앞에 다른 말이 붙는
    // 경우도 잡게 anywhere:true (RUNNING/SWIMMING/HIKING과 같은 이유).
    if (!certDefer && _anyVerbWordMatched(tokens, _kChoreKeywords, anywhere: true)) {
      return ('housework', 'tier3c_housework');
    }
    // ⭐ "펌"/"커트"는 "컨펌"/"펌프형"과 충돌 위험이 있어 단순 prefix가 아니라
    // _anyVerbWordMatched(조사/동사활용형 뒤따를 때만 인정)로 잡는다. anywhere는
    // 반드시 기본값(false)으로 둘 것 - "컨펌하기"(confirm, "펌"이 뒤에 붙어
    // anywhere였으면 오탐)가 실측으로 확인된 충돌이라 "펌"은 어절 맨 앞에서만
    // 인정해야 함.
    if (!certDefer &&
        (_anyContainsMatched(text, _kBeautyContainsKeywords) ||
            _anyVerbWordMatched(tokens, _kBeautyPrefixKeywords))) {
      return ('beauty', 'tier3c_beauty');
    }

    // ⭐ "모임"이 같이 있으면(예: "동네 주민 모임에서 붕어빵 먹으러 가자고
    // 연락 옴") 핵심이 식사가 아니라 그 모임(사교)이라 _kActivityDeferMarkers와
    // 같은 원리로 defer(ml/keyword_router.py의 check_keyword_regressions.py
    // 실측 검증으로 발견).
    if (!_anyContainsMatched(text, _kEatingProposalMedicationDefer) &&
        !_anyContainsMatched(text, _kActivityDeferMarkers) &&
        _anyContainsMatched(text, _kEatingProposalKeywords)) {
      return ('meal', 'tier3d_eating_proposal');
    }

    if (!_anyContainsMatched(text, _kActivityDeferMarkers)) {
      for (final entry in _kActivityPrefixKeywords.entries) {
        if (_anyPrefixMatched(tokens, entry.value)) {
          return (entry.key, 'tier4_activity');
        }
      }
      for (final entry in _kActivityContainsKeywords.entries) {
        if (_anyContainsMatched(text, entry.value)) {
          return (entry.key, 'tier4_activity');
        }
      }
    }

    return null;
  }
}
