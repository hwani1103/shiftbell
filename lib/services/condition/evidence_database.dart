// lib/services/condition/evidence_database.dart
//
// ⭐ 컨디션 매니저 Phase 2 - Evidence Database. 여기 없는 근거는 어떤 Rule에도
// 쓰지 않는다(컨디션매니저_근거자료.md와 반드시 1:1로 맞출 것 - 근거 내용을
// 바꿀 땐 그 문서와 이 파일을 항상 같이 고칠 것).
//
// condition_rule_engine.dart의 모든 Finding/Tip은 evidenceIds로 여기 있는
// id를 최소 1개 이상 가리켜야 한다 - "이 판정을 왜 하는가?"를 항상 추적할 수
// 있게 하기 위함(스펙 24장).

class Evidence {
  final String id;
  final String source; // 발행 기관/저자
  final String topic;
  final String finding; // 핵심 결과(원문 취지 요약, 과장 없이)
  final String evidenceLevel; // 이 자료 자체가 밝히는/일반적으로 통용되는 근거 수준
  final String appUsage; // 앱이 실제로 쓰는 표현 범위
  final String? url;

  const Evidence({
    required this.id,
    required this.source,
    required this.topic,
    required this.finding,
    required this.evidenceLevel,
    required this.appUsage,
    this.url,
  });
}

const List<Evidence> kEvidenceDatabase = [
  Evidence(
    id: 'EVIDENCE-001',
    source: 'NIOSH, Training for Nurses on Shift Work and Long Work Hours (Module 5)',
    topic: '교대 방향(정방향/역방향)',
    finding: '정방향 교대(주간→오후→야간)가 역방향보다 적응하기 쉽다고 보고됨. '
        '회전 속도가 빠를수록, 주 단위 회전일수록 더 힘든 경향.',
    evidenceLevel: '정부기관 종합 훈련자료(다수 생체리듬 연구를 정리한 전문가 합의 수준)',
    appUsage: '"일부 연구에서는 정방향이 역방향보다 적응에 유리한 것으로 보고됩니다" '
        '수준의 정보 제공. "정방향=건강에 좋음" 같은 단정 금지.',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod5/04.html',
  ),
  Evidence(
    id: 'EVIDENCE-002',
    source: 'Knauth & Hornberger (NIOSH Module 5 인용)',
    topic: '근무 사이 최소 회복시간',
    finding: '두 근무 사이 최소 11시간의 회복시간을 둘 것을 권장.',
    evidenceLevel: '학술 권고(정부기관 훈련자료에 인용)',
    appUsage: '회복시간이 11시간보다 짧을 때 "짧습니다"라는 사실만 서술.',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod5/06.html',
  ),
  Evidence(
    id: 'EVIDENCE-003',
    source: 'EU Directive 2003/88/EC (Working Time Directive) 제3조',
    topic: '근무 사이 최소 회복시간(법제 기준)',
    finding: '모든 근로자는 24시간마다 최소 11시간의 연속 휴식을 보장받아야 함.',
    evidenceLevel: '법제/정부 가이드라인(널리 채택된 최소 기준)',
    appUsage: 'EVIDENCE-002와 함께 11시간 임계값의 근거로 사용.',
    url: 'https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32003L0088',
  ),
  Evidence(
    id: 'EVIDENCE-004',
    source: 'Folkard S, Lombardi DA. Am J Ind Med. 2006.',
    topic: '장시간 근무와 사고/부상 상대위험',
    finding: '8시간 근무 대비 10시간 근무는 상대위험 약 +13%, 12시간 근무는 약 '
        '+27% 증가하는 것으로 모델링됨.',
    evidenceLevel: '여러 연구를 종합한 메타분석적 모델링(Risk Index)',
    appUsage: '오늘 근무가 12시간 이상일 때 "근무시간이 길수록 피로·사고 위험이 '
        '상대적으로 높아지는 경향이 보고됩니다" 수준으로만 서술. 개인 위험도를 '
        '%로 제시하지 않음.',
    url: 'https://onlinelibrary.wiley.com/doi/abs/10.1002/ajim.20307',
  ),
  Evidence(
    id: 'EVIDENCE-005',
    source: 'NIOSH, Training for Nurses on Shift Work and Long Work Hours (Module 5, Extended Shifts)',
    topic: '연속 근무 후 휴식일(근무시간대별 일반화)',
    finding: '"연속 8시간 근무 5일 또는 10시간 근무 4일 후에는 1~2일의 완전한 휴식을, '
        '연속 12시간 근무 3일 후에는 2일의 휴식을 계획할 것"을 권고. 또한 "며칠 몰아서 '
        '일하고 4~7일을 몰아 쉬는" 압축 패턴은 전문가들이 피할 것을 권고한다고 명시(2026-09-17 '
        '재조사로 근무시간대별 일반화된 수치 확인 - 기존엔 12시간 근무 축만 반영했음).',
    evidenceLevel: '정부기관 종합 훈련자료의 정성적 권고(정량적 "위험 시작 일수"는 아님)',
    appUsage: '근무시간이 8시간대/10시간대/12시간대인지에 따라 각각 5일/4일/3일 연속 뒤 '
        '회복시간이 부족(24~48시간 미만)하면 "높은 부담" 판정에 사용 - 원문 숫자를 그대로 '
        '씀, 임의로 만든 임계값이 아님. 8시간 미만 근무의 연속일수는 이 근거가 다루지 않아 '
        '레벨 판정에 안 씀(RULE_CONSECUTIVE_WORKDAYS 참고 - "며칠 몰아서 일하는 압축 패턴을 '
        '피하라"는 이 자료의 일반 원칙만 빌리고, 정확한 일수 기준 자체는 이 앱의 판단).',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod5/05.html',
  ),
  Evidence(
    id: 'EVIDENCE-006',
    source: 'NIOSH, Training for Nurses on Shift Work and Long Work Hours (Module 9, Sleep)',
    topic: '야간근무 후 수면',
    finding: '야간근무 후에는 수면을 확보하는 것을 우선할 것을 권고.',
    evidenceLevel: '정부기관 종합 훈련자료',
    appUsage: '야간근무 다음 날이 휴무인 경우 "회복을 위한 수면·휴식 구간"으로 '
        '맥락을 재구성(상태 판정에는 영향 없음, 순수 정보 제공).',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod9/06.html',
  ),
  Evidence(
    id: 'EVIDENCE-007',
    source: 'AASM, Management of Shift Work Disorder — Clinical Practice Guideline (2025)',
    topic: '야간근무 전 낮잠',
    finding: '졸림을 겪는 교대근무 수면장애 성인에서 야간근무 전 낮잠을 조건부로 '
        '권장(단, 가이드라인 스스로 "근거 수준 매우 낮음"이라고 명시). 낮잠 직후 '
        '수면관성으로 일시적 졸림/인지저하가 있을 수 있어 운전 등 위험한 활동 전 '
        '시간을 둘 것을 권고.',
    evidenceLevel: '조건부 권고, 근거 수준 매우 낮음(가이드라인 원문 명시)',
    appUsage: '팁으로만 노출("도움이 될 수 있다고 보고됩니다, 근거 수준은 높지 '
        '않습니다" + 낮잠 직후 운전 주의). 상태 판정에는 절대 사용하지 않음.',
    url: 'https://aasm.org/wp-content/uploads/2025/08/Extrinsic-CRSWD-CPG_SWD_May2025.pdf',
  ),
  Evidence(
    id: 'EVIDENCE-008',
    source: 'Drake C, Roehrs T, Shambroom J, Roth T. J Clin Sleep Med. 2013.',
    topic: '카페인과 수면',
    finding: '취침 6시간 전 카페인(400mg) 섭취도 총 수면시간을 1시간 이상 유의하게 '
        '감소시킴.',
    evidenceLevel: '무작위 대조 실험(반복 인용되는 기준 연구)',
    appUsage: '추천 수면 시간대 시작 시각 기준 6시간 전부터 카페인 섭취를 줄이도록 '
        '안내.',
    url: 'https://jcsm.aasm.org/doi/abs/10.5664/jcsm.3170',
  ),
  Evidence(
    id: 'EVIDENCE-009',
    source: 'NIOSH, Training for Nurses on Shift Work and Long Work Hours (Module 9, Light)',
    topic: '야간근무 후 귀가길 빛 노출',
    finding: '야간근무 후 귀가길에 선글라스 등으로 강한 빛 노출을 줄이면 이후 수면에 '
        '도움이 될 수 있음. 단, 매우 졸린 상태에서는 선글라스가 각성 효과를 줄여 '
        '졸음운전 위험을 높일 수 있다는 안전 경고가 함께 명시됨.',
    evidenceLevel: '정부기관 종합 훈련자료 + 생체리듬 연구 기반',
    appUsage: '야간근무가 끝나는 날 팁으로 노출하되, 졸음운전 안전 경고 문구를 '
        '반드시 함께 표시.',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod9/04.html',
  ),
  Evidence(
    id: 'EVIDENCE-010',
    source: 'NIOSH, Training for Nurses on Shift Work and Long Work Hours (Module 9, Diet)',
    topic: '야간근무 중 식사',
    finding: '자정~새벽 6시 사이 식사량을 줄이고, 주 수면 전 1~2시간 내 과식을 '
        '피하며, 가벼운 음식 위주로 할 것을 권고. 기름지고 자극적인 음식·알코올· '
        '설탕 많은 음식은 자제.',
    evidenceLevel: '정부기관 종합 훈련자료',
    appUsage: '오늘이 야간근무일 때 "과식·기름진 음식을 피하고 가벼운 식사 위주로" '
        '팁 노출.',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod9/08.html',
  ),
  Evidence(
    id: 'EVIDENCE-011',
    source: 'National Sleep Foundation, Sleep Health 저널(2015) — 다학제 전문가 패널 합의',
    topic: '성인 권장 수면시간',
    finding: '성인(만 18~64세) 권장 수면시간은 7~9시간(고령자 7~8시간).',
    evidenceLevel: '다학제 전문가 패널 합의(RAND/UCLA Appropriateness Method)',
    appUsage: '"오늘 목표 수면: 7~9시간"처럼 항상 범위로 표시. 특정 분·시간 단위로 '
        '정확히 표현하지 않음.',
    url: 'https://www.sleephealthjournal.org/article/s2352-7218(15)00015-7/fulltext',
  ),
  Evidence(
    id: 'EVIDENCE-012',
    source: 'EU Directive 2003/88/EC (Working Time Directive) 제6조',
    topic: '주간 최대 근무시간(법제 기준)',
    finding: '평균 주간 근무시간(연장근무 포함)이 기준기간 동안 48시간을 넘지 '
        '않아야 함.',
    evidenceLevel: '법제/정부 가이드라인(널리 채택된 최소 기준)',
    appUsage: '2026-09-18 재설계 - ConditionRuleEngine.scheduleLoadProfileFor()에서 이 사람의 근무 패턴 '
        '자체(개인 기준선)가 구조적으로 주 48시간을 넘는지 판단할 때만 절대값으로 씀(레벨과 무관한 '
        '배경 정보 한 줄, "이 근무 패턴은 평균 주 N시간이에요"). RULE_WEEKLY_LOAD_INCREASE(최근 7일 '
        '실근무시간이 평소보다 늘었는지)는 이 48시간을 더 이상 절대 기준으로 쓰지 않고 개인 기준선 '
        '대비 증가 폭만 보되, 같은 축의 배경 근거로 evidenceIds에 계속 인용함(절대 기준 위반을 '
        '단정하는 문구는 안 씀 - 12시간 표준 근무자는 원래도 48시간을 구조적으로 넘기 때문). '
        '60시간 이상은 EVIDENCE-014와 함께 씀. 개인 위험도·질병 연관은 절대 언급하지 않음.',
    url: 'https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32003L0088',
  ),
  // ⭐ 2026-09-04 - 사용자 요청("연속 야간근무 자체에 대한 근거를 찾아서 rule에
  // 반영")으로 추가 조사해서 찾음. EVIDENCE-004(같은 Folkard 계열 - 근무
  // "길이"에 따른 상대위험)와는 축이 다른, 근무 "연속 횟수"(그것도 야간근무가
  // 낮/오후근무보다 더 가파르게 나쁨)에 대한 별개 수치라 새 Evidence로 분리함.
  // 출처 확인 경로: Frontiers(2024) rapid evidence review가 이 수치를 Folkard &
  // Tucker(2003)로 명확히 귀속시켜 재인용하고 있음(1차 논문 원문 직접 접근은
  // 이번 조사에서 확인 못 함 - 2차 인용 확인 수준).
  Evidence(
    id: 'EVIDENCE-013',
    source: 'Folkard S, Tucker P. Occup Med (Lond). 2003 (Frontiers 2024 rapid '
        'evidence review에 재인용된 수치 기준)',
    topic: '연속 야간근무 횟수와 사고 위험',
    finding: '야간근무가 연속될수록 사고·부상 상대위험이 누적됨(1일째 대비 2일째 '
        '약 +6%, 3일째 약 +17%, 4일째 약 +36% - 낮/오후근무의 연속보다 야간근무의 '
        '연속에서 위험 증가가 더 가파름). 이 수치를 근거로 원자력 등 안전 최우선 '
        '산업의 근무 규정은 연속 야간근무를 보통 4일로 상한선을 둠.',
    evidenceLevel: '동료심사 학술지 원 연구(다수 연구를 종합한 산업안전 지표) - '
        '2차 인용(Frontiers 2024 rapid evidence review)으로 수치 재확인',
    appUsage: '연속 야간근무 3일째부터 "주의" 신호로, 4일째부터는 그 자체로 '
        '"회복 부담이 큰 날"로 판정(가속화 구간이라는 원 연구 취지 반영). 개인별 '
        '%나 사고 확률은 표시하지 않고 "위험이 누적/가속화되는 경향" 수준으로만 '
        '서술.',
  ),
  // ⭐ 2026-09-17 - 사용자 요청("12시간 근무 자체를 매번 위험하다고 하지 말고, 근무
  // 시간대와 무관하게 최근 며칠간 총 근무량이 실제로 많은지로 판단해야 한다")에 따라
  // 조사해서 추가. EVIDENCE-012(EU 48시간)와 같은 "주간 총 근무시간" 축이지만, EU
  // 지침보다 더 구체적인 절대 상한(주 60시간)을 제시하는 별개 출처라 분리함 - 두 근거를
  // 합쳐 48시간(주의)/60시간(그 자체로 높은 부담) 2단계로 씀.
  Evidence(
    id: 'EVIDENCE-014',
    source: 'Institute of Medicine, Keeping Patients Safe (2004); 2014년 체계적 검토 '
        '(둘 다 NIOSH Training for Nurses Module 5에 인용된 수치로 확인)',
    topic: '주간 누적 근무시간 상한',
    finding: '간호사 근무시간을 24시간 내 12시간, 7일 내 60시간을 넘지 않도록 제한할 '
        '것을 권고(IOM 2004). 2014년 체계적 검토는 주 40시간을 넘는 근무가 환자안전 '
        '저하와 연관된다고 보고.',
    evidenceLevel: '정부기관 종합 훈련자료에 인용된 위원회 보고서 + 체계적 검토(원문 '
        '직접 확인은 이번 조사에서 못 함 - 2차 인용 확인 수준)',
    appUsage: '2026-09-18 재설계 - scheduleLoadProfileFor()에서 개인 기준선이 주 60시간 이상이면 '
        'EVIDENCE-012와 함께 배경 정보에 "간호사 근무시간 권고 상한(주 60시간)" 문구 추가. '
        'RULE_WEEKLY_LOAD_INCREASE에서는 최근 7일 실근무시간이 평소보다 크게(기준선의 25% 이상 '
        '또는 최소 12시간 이상) 늘었을 때 배경 근거로 evidenceIds에 인용(60시간 절대 위반을 '
        '단정하지 않음 - 평소가 이미 60시간대인 사람도 있기 때문). 40시간 수치는 서술에서 참고만 '
        '하고 별도 레벨 신호로는 쓰지 않음(EU 48시간 기준과 같은 축의 더 약한 근거를 이중으로 '
        '반영하지 않기 위함). 개인 위험도·질병 연관은 언급하지 않음.',
    url: 'https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod5/07.html',
  ),
];

Evidence? evidenceById(String id) {
  for (final e in kEvidenceDatabase) {
    if (e.id == id) return e;
  }
  return null;
}
