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
  });

  group('ML 모델(TF-IDF + LogisticRegression)', () {
    test('병원 진료 예약 -> 병원·건강관리', () {
      final r = classifier.classify('병원 진료 예약');
      expect(r.categoryKey, 'health');
      expect(r.method, 'ml');
    });

    test('마트에서 장보기 -> 쇼핑', () {
      final r = classifier.classify('마트에서 장보기');
      expect(r.categoryKey, 'shopping');
      expect(r.method, 'ml');
    });

    test('넷플릭스 보기 -> 여가/휴식', () {
      final r = classifier.classify('넷플릭스 보기');
      expect(r.categoryKey, 'leisure');
      expect(r.method, 'ml');
    });

    test('회의 준비 -> 업무', () {
      final r = classifier.classify('회의 준비');
      expect(r.categoryKey, 'work');
      expect(r.method, 'ml');
    });

    test('자격증 시험 공부 -> 공부 (margin이 커서 확신도 높음)', () {
      final r = classifier.classify('자격증 시험 공부');
      expect(r.categoryKey, 'study');
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
