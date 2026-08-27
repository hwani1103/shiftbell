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
/// 'family'/'shopping'/'leisure'/'etc' 중 하나 - assets/icons/memo_category/의
/// 파일명, lib/screens/schedule_management_tab.dart의 _kScheduleCategoryIcons와
/// 동일한 키 체계.
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
];

const List<String> _kImmediateFamily = [
  '엄마', '어머니', '아빠', '아버지', '아들', '딸', '남편', '아내', '배우자',
  '할머니', '할아버지', '부모님', '친정엄마', '친정아빠', '아이',
];

// "가족"은 "온가족/전가족"처럼 복합어로도 자주 쓰여서 contains(부분일치)로 따로 잡음.
const List<String> _kImmediateFamilyContains = ['가족'];

// "형/누나/언니/오빠/동생"은 일부러 뺐다 - 혈연이 아니라 친한 사람을 부르는
// 호칭으로도 매우 흔히 쓰여서(ml/keyword_router.py 참고), ML+margin 판단에 맡김.
const List<String> _kExtendedFamily = [
  '며느리', '사위', '시댁', '처가',
  '장인', '장모', '처남', '처형', '처제', '매형', '매부', '동서', '시누이',
  '형수', '제수', '올케', '고모', '이모', '삼촌', '외삼촌', '조카', '사돈',
  '시아버지', '시어머니', '시부모님', '손자', '손녀', '사촌',
];

const List<String> _kAcquaintanceMarkers = [
  '친구', '동료', '지인', '소개', '동창', '직장동료', '회사동료',
];

const List<String> _kSocialKeywords = [
  '친구', '동창', '동기', '선배', '후배', '동료', '지인', '정모', '동호회',
];

// 잠정 비활성화(원본과 동일 - ml/keyword_router.py의 PURCHASE_MARKERS 주석 참고).
const List<String> _kPurchaseMarkers = <String>[];

const List<String> _kSportsKeywords = [
  '테니스', '골프', '라운딩', '탁구', '축구', '배드민턴', '스쿼시',
  '클라이밍', '필라테스', '복싱', '웨이트', '마라톤', '농구', '배구',
  '야구', '줄넘기', '크로스핏',
];

const List<String> _kSportsFalsePositives = [
  '골프공', '테니스공', '야구공', '축구공', '탁구공',
];

// ⭐ 2026-08-27 - 짧은 단어/구가 '기타'로 자주 빠지는 문제 실측 후 추가.
// ml/keyword_router.py의 ACTIVITY_PREFIX_KEYWORDS와 동일 - "업무"/"휴식"은
// 전체 라벨 데이터(5,464개) 검증에서 충돌이 나서 뺐음(ml/check_keyword_
// regressions.py, 주석 참고). 바뀌면 두 파일 다 같이 고칠 것.
const Map<String, List<String>> _kActivityPrefixKeywords = {
  'study': ['공부', '독서'],
  'health': ['병원'],
  'work': ['출장'],
  'meal': ['식사', '외식'],
  'leisure': ['여가'],
};

// "쇼핑"은 "온라인쇼핑"처럼 복합어로도 흔히 쓰여서 contains로 잡음.
const Map<String, List<String>> _kActivityContainsKeywords = {
  'shopping': ['쇼핑'],
};

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
    return _kCommonParticles.contains(rest);
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
