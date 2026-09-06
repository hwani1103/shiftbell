// 메모_자동분류_ML_계획.md Phase 4 - MemoCategoryClassifier(키워드 하드매핑 +
// TF-IDF/LogisticRegression 이식)가 Python 원본(ml/predict.py)과 같은 결과를
// 내는지 확인. 기대값은 실제로 `python ml/predict.py "..."`를 돌려서 받아온
// 것 그대로임(2026-08-27) - 모델을 재학습/재export하면 이 기대값도 다시 뽑아서
// 갱신할 것(ml/verify_export.py로 JSON이 원본 모델과 일치하는지 먼저 확인한 뒤,
// 이 테스트로 Dart 이식 자체가 맞는지 확인하는 2단계 검증 구조).
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/memo_category_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final classifier = MemoCategoryClassifier.instance;

  setUpAll(() async {
    await classifier.ensureLoaded();
  });

  test('모델 자산이 정상적으로 로드된다', () {
    expect(classifier.isLoaded, true);
  });

  group('키워드 하드매핑(ML까지 안 감)', () {
    test('직계가족 키워드가 다른 활동 키워드보다 우선한다', () {
      final r = classifier.classify('운동 하러가기 전에 엄마한테 전화하기');
      expect(r.categoryKey, 'family');
      expect(r.method, 'tier1_immediate_family');
    });

    test('인척 키워드도 가족으로 분류된다', () {
      final r = classifier.classify('매형이랑 술 한잔');
      expect(r.categoryKey, 'family');
      expect(r.method, 'tier1b_extended_family');
    });

    test('사람을 만나는 표현은 사교로 분류된다', () {
      final r = classifier.classify('친구랑 저녁 약속');
      expect(r.categoryKey, 'social');
      expect(r.method, 'tier2_social');
    });

    test('명확한 스포츠 키워드는 운동으로 분류된다', () {
      final r = classifier.classify('테니스 치기');
      expect(r.categoryKey, 'exercise');
      expect(r.method, 'tier3_sports');
    });

    test('"동창회"는 "동창" 부분일치로 오탐되지 않는다(어절 전체 일치만 허용)', () {
      // _word_matches_token은 "동창회".startsWith("동창")이어도 나머지("회")가
      // 조사 목록에 없으면 매칭 안 함 - 이게 깨지면 다른 무관한 단어들도
      // 줄줄이 오탐(아이디어→아이, 정형외과→형 등)나기 쉬움.
      final r = classifier.classify('동창회 모임 나가기');
      expect(r.method, isNot(contains('tier')));
    });

    test('인척 존칭("장모님")도 가족으로 잡힌다', () {
      // "장모"+"님" - _kCommonParticles에 '님' 추가한 것 확인.
      final r = classifier.classify('장모님 병원 진료 동행하기');
      expect(r.categoryKey, 'family');
    });
  });

  group('활동 키워드 하드매핑(tier4, 2026-08-27 추가)', () {
    test('짧은 동사 결합형도 접두어 매칭으로 잡힌다', () {
      expect(classifier.classify('공부하러가기').categoryKey, 'study');
      expect(classifier.classify('병원가야됨').categoryKey, 'health');
      expect(classifier.classify('출장가기').categoryKey, 'work');
    });

    test('카테고리 이름 그 자체(복합어 포함)도 정확히 잡힌다', () {
      expect(classifier.classify('독서').categoryKey, 'study');
      expect(classifier.classify('쇼핑').categoryKey, 'shopping');
      expect(classifier.classify('온라인쇼핑').categoryKey, 'shopping');
      expect(classifier.classify('식사').categoryKey, 'meal');
    });

    test('"모임"이 같이 있으면 활동 하드매핑을 보류하고 ML에 맡긴다', () {
      // "독서모임"은 실측 데이터에서 사교로 분류된 경우가 더 많았음
      // (ml/check_keyword_regressions.py) - 공부로 강제하면 안 됨.
      final r = classifier.classify('동네 독서모임 정기 뒷풀이');
      expect(r.method, isNot('tier4_activity'));
    });

    test('이미 있던 스포츠 하드매핑은 그대로 유지된다', () {
      final r = classifier.classify('골프치러가기');
      expect(r.categoryKey, 'exercise');
      expect(r.method, 'tier3_sports');
    });
  });

  group('자전거/요가·필라테스 하드매핑(tier3b, 2026-09-03 신설)', () {
    test('자전거/따릉이는 공백 있는 형태도, "타다" 활용형 붙여쓴 형태도 잡힌다', () {
      expect(classifier.classify('자전거 타러 가기').categoryKey, 'cycling');
      expect(classifier.classify('따릉이 타고 한강').categoryKey, 'cycling');
      final r = classifier.classify('자전거타야됨');
      expect(r.categoryKey, 'cycling');
      expect(r.method, 'tier3b_cycling');
    });

    test('요가하러가기/필라테스 학원 고고/스트레칭 - 사용자 예시 문구가 그대로 잡힌다', () {
      expect(classifier.classify('요가하러가기').categoryKey, 'yoga');
      expect(classifier.classify('필라테스 학원 고고').categoryKey, 'yoga');
      final r = classifier.classify('스트레칭');
      expect(r.categoryKey, 'yoga');
      expect(r.method, 'tier3b_yoga');
    });

    test('"필요가 있다"는 "요가"로 끝나도 요가로 오탐되지 않는다', () {
      final r = classifier.classify('연차 미리 써야 할 필요가 있다');
      expect(r.categoryKey, isNot('yoga'));
    });

    // ⭐ 2026-09-03 - 하드매핑은 "자전거 헬멧 사기"류를 tier3b_cycling으로
    // 강제하지 않고 ML로 defer한다(이게 이 테스트의 핵심 확인 대상). 다만
    // ML 자체가 최종적으로 '쇼핑'을 고르는지는 학습 데이터의 char n-gram
    // 분포에 달려있어 완벽히 보장되진 않음(가족↔쇼핑의 PURCHASE_MARKERS
    // 미해결 사례와 같은 성격의 한계 - ml/카테고리_가이드.md 참고) - 여기선
    // "하드매핑이 무조건 자전거로 강제하지는 않는다"만 확인한다.
    test('자전거 헬멧을 사기만 하는 문장은 하드매핑을 defer한다(tier3b_cycling 아님)', () {
      final r = classifier.classify('자전거 헬멧 사기');
      expect(r.method, isNot('tier3b_cycling'));
    });

    test('자전거 정비만 맡기는 문장(타는 동작 없음)은 기타로 분류된다', () {
      final r = classifier.classify('자전거 브레이크 수리 맡기러 가기');
      expect(r.method, isNot('tier3b_cycling'));
      expect(r.categoryKey, 'etc');
    });

    test('구매 후 실제로 타면(콤보 문장) 자전거로 잡힌다', () {
      final r = classifier.classify('자전거 안전장비 새로 사서 라이딩');
      expect(r.categoryKey, 'cycling');
      expect(r.method, 'tier3b_cycling');
    });
  });

  group('ML 모델(TF-IDF + LogisticRegression)', () {
    test('진료 예약하기 -> 병원·건강관리 (하드매핑 안 걸림)', () {
      final r = classifier.classify('진료 예약하기');
      expect(r.categoryKey, 'health');
      expect(r.method, 'ml');
    });

    test('마트에서 장보기 -> 쇼핑', () {
      final r = classifier.classify('마트에서 장보기');
      expect(r.categoryKey, 'shopping');
      expect(r.method, 'ml');
    });

    // ⭐ 2026-09-03 - 원래 기대값은 'leisure'였으나, ml/eval_e2e.py로 실측해보니
    // 학습 데이터 자체가 "넷플릭스" 관련 문장을 문화생활 18건 vs 여가/휴식 8건으로
    // 갈라서 라벨링하고 있었음(예: "넷플릭스 정주행"이 양쪽 라벨에 다 존재) - 즉
    // 하나로 정할 만큼 명확한 경계가 아니라는 뜻이라 하드매핑은 하지 않기로 함
    // (ml/keyword_router.py의 "여가/휴식" ACTIVITY_PREFIX_KEYWORDS 주석 참고).
    // 이 테스트는 "특정 카테고리가 맞다"가 아니라 데이터가 실제로 가리키는
    // 다수결(문화생활)과 모델 예측이 일치하는지만 확인 - 데이터 정리로 다수결이
    // 바뀌면 이 기대값도 같이 바뀌어야 함.
    test('넷플릭스 보기 -> 문화생활(학습 데이터 다수결)', () {
      final r = classifier.classify('넷플릭스 보기');
      expect(r.categoryKey, 'culture');
      expect(r.method, 'ml');
    });

    test('회의 준비 -> 업무', () {
      final r = classifier.classify('회의 준비');
      expect(r.categoryKey, 'work');
      expect(r.method, 'ml');
    });

    test('자격증 시험 접수 -> 공부 (margin이 커서 확신도 높음, 하드매핑 안 걸림)', () {
      final r = classifier.classify('자격증 시험 접수');
      expect(r.categoryKey, 'study');
      expect(r.method, 'ml');
      expect(r.confidence, greaterThan(0.9));
    });

    test('소파에서 뒹굴거리기 -> 여가/휴식', () {
      final r = classifier.classify('소파에서 뒹굴거리기');
      expect(r.categoryKey, 'leisure');
    });
  });

  group('경계 케이스', () {
    test('빈 문자열은 기타로 분류된다', () {
      final r = classifier.classify('');
      expect(r.categoryKey, 'etc');
    });

    test('공백만 있는 문자열도 기타로 분류된다', () {
      final r = classifier.classify('   ');
      expect(r.categoryKey, 'etc');
    });
  });
}
