"""
키워드 하드매핑 레이어 (Tier 1~3) — ML 모델 앞단에서 먼저 확인.

설계 원칙(카테고리_가이드.md의 우선순위 규칙을 코드로 그대로 옮긴 것):
  1단계: 직계가족 키워드 -> 무조건 가족 (문장 어디에 있든, 다른 활동 키워드가 있어도 우선)
  1-b단계: 인척(매형/처남 등) 키워드 -> 가족. 단, "친구/동료/지인/소개" 같은
           "이 사람의 지인을 만난다"는 신호가 같이 있으면 사교로 넘김
           (예: "매형이랑 술 한잔"=가족 vs "매형 지인 소개로 만난 사람"=사교)
  2단계: 사람을 만난다는 명시적 표현(친구/동창/동료 등) -> 사교
  3단계: 명확하고 애매하지 않은 활동 키워드 -> 해당 카테고리
         (당구/볼링처럼 실제로 애매한 건 여기 넣지 않고 ML에 맡김)
  3-b/3-c단계 (2026-09-01, 카테고리 10->17개 확장): 위와 같은 원칙으로 새
         카테고리 7종(달리기/수영/등산/문화생활/금융/집안일/미용) 추가.
         자세한 근거는 각 키워드 리스트 위 주석 참고.
  4단계: 위에 안 걸리면 None 반환 -> predict.py에서 ML 모델로 넘어감

매칭 방식 (2026-08-26, 실사용 데이터 500개로 교차검증하며 수정):
  - 가족/사교 키워드는 "어절이 그 단어 자체이거나(+흔한 조사/복수형만 붙은 경우)"만
    매칭한다. 접두어(prefix)나 부분일치(contains)로 느슨하게 잡으면
    "아이디어/아이언"(아이), "닦아내기"(아내), "정형외과"(형), "비동기"(동기),
    "이모티콘"(이모) 같은 완전히 무관한 단어와 충돌한다 — 전부 실사용 데이터에서
    실제로 걸렸던 오탐임. "가족"만 예외로 부분일치 허용(온가족/전가족 등 복합어
    커버 목적, 오탐 위험이 낮아서).
  - 스포츠 키워드는 계속 접두어 매칭 유지("테니스치기/골프치기"처럼 조사 없이
    바로 동사가 붙는 패턴이 흔해서). 스포츠 이름은 무관한 단어와 겹칠 위험이
    낮다고 판단.
"""

_COMMON_PARTICLES = [
    "가", "이", "은", "는", "을", "를", "의", "에게", "한테", "께",
    "랑", "이랑", "와", "과", "도", "만", "까지", "부터", "께서",
    "인데", "이고", "이지만", "라도", "이라도", "야", "아",
    # ⭐ 2026-08-27 - 존칭 접미사. "장모"+"님"="장모님", "장인"+"어른"="장인어른",
    # "처남"+"댁"="처남댁"처럼 인척 호칭 뒤에 자연스럽게 붙는데, 이게 없어서
    # "장인어른 병원 모시고 가기"류가 가족 하드매핑에 안 걸리고 활동
    # 하드매핑(병원)으로 새 사람이 가버리는 걸 실측(check_keyword_regressions.py)
    # 으로 발견해서 추가함.
    "님", "어른", "댁",
    # ⭐ 2026-09-01(실사용 문장 테스트) - "청소나 가볍게 하기"류의 캐주얼한
    # "~나"(or) 연결 조사가 없어서 CHORE_KEYWORDS 등이 못 잡던 걸 발견해서 추가.
    "나", "이나",
]
# ⭐ 2026-09-03 - "로"/"으로"는 일부러 안 넣는다. "소개로"(소개+로) 같은 흔한
# 격조사를 잡으려고 시도했는데, "등산로"(하이킹 코스를 뜻하는 명사 자체, "등산"+
# 조사"로"가 아님)/"조깅으로"(뒤에 오는 뉘앙스가 ML이 이미 "운동" vs "달리기"로
# 잘 가르던 문맥)에서 실측 회귀가 발견됨(check_keyword_regressions.py) - "로"는
# 흔한 명사 끝음절과도 겹쳐서 "펌"/"런"과 같은 이유로 위험 판정, 하드매핑에서
# 뺌. "이모 소개로 나온 사람" 같은 케이스는 여전히 ML 판단에 맡긴다.


def _particle_suffix_ok(rest):
    """⭐ 2026-09-03 - rest가 알려진 조사들의 연쇄(0개 이상)로만 이루어져 있으면
    True. 기존엔 rest 전체가 _COMMON_PARTICLES의 항목 '한 개'와 정확히 일치해야만
    통과됐는데, 한국어는 조사가 여러 개 겹쳐 붙는 게 흔함("친구들과의" =
    "들"(복수) + "과"(조사) + "의"(조사), "동료들과의"도 동일) - 이 경우 rest가
    "과의"가 되는데 목록엔 "과"/"의"만 개별로 있어서 매칭에 실패, "친구"/"동료"
    같은 명백한 지인 신호를 놓치는 실측 버그(boundary_cases.jsonl의 "며느리
    친구들과의 모임"류)를 발견해서 재귀적으로 여러 조사를 계속 벗겨내도록 고침.
    긴 조사부터 시도(짧은 조사가 긴 조사의 접두사인 케이스에서 잘못 잘리는 것
    방지 - 예: "이랑"을 "이"+"랑"으로 잘못 나누면 다음 재귀에서 "랑"이 남는
    문제가 생길 수 있음)."""
    if rest == "":
        return True
    for p in sorted(_COMMON_PARTICLES, key=len, reverse=True):
        if rest.startswith(p) and _particle_suffix_ok(rest[len(p):]):
            return True
    return False

IMMEDIATE_FAMILY = [
    "엄마", "어머니", "아빠", "아버지", "아들", "딸", "남편", "아내", "배우자",
    "할머니", "할아버지", "부모님", "친정엄마", "친정아빠", "아이",
]
# "가족"은 "온가족/전가족"처럼 다른 어절 뒤에 붙는 복합어로도 자주 쓰여서
# contains(부분일치)로 따로 잡는다. "가족"은 그 자체로 오탐 위험 낮음.
# ⭐ 2026-09-01 - "본가"("부모님 댁"을 가리키는 말)도 같은 이유로 추가. 신설한
# "집안일" 하드매핑이 "본가 OO 청소해드리기"류를 가족보다 먼저 채가는 걸
# 실측으로 발견해서(가족 우선순위 규칙 위반) 여기 추가함 - "본가" 자체가
# 무관한 단어와 충돌할 위험은 낮음.
IMMEDIATE_FAMILY_CONTAINS = ["가족", "본가"]

# "형/누나/언니/오빠/동생"은 일부러 뺐다 — 실사용 데이터에서 "친한 형",
# "친한 동생"처럼 혈연이 아니라 친한 손위/손아래 사람을 부르는 호칭으로도
# 매우 흔히 쓰이는 걸 확인함(예: "친한 형 가게 오픈해서 축하금 송금"은
# 사용자가 사교로 분류함, 친형이 아님). 하드매핑은 확실할 때만 써야 하므로
# 이 4개는 ML+margin 판단에 맡긴다.
EXTENDED_FAMILY = [
    "며느리", "사위", "시댁", "처가",
    "장인", "장모", "처남", "처형", "처제", "매형", "매부", "동서", "시누이",
    "형수", "제수", "올케", "고모", "이모", "삼촌", "외삼촌", "조카", "사돈",
    "시아버지", "시어머니", "시부모님", "손자", "손녀", "사촌",
]

# "이 가족어가 사실은 '남의 가족'이다"라는 신호. 두 가지 방향 다 잡는다:
#   - "매형 지인 소개로 만난 사람" (가족어 뒤에 지인 표시)
#   - "친구 부모님", "직장동료 배우자" (가족어 앞에 남의 관계어)
# ⭐ 2026-09-01(실사용 문장 테스트) - "팀원"도 "동료"와 동일 개념인데 빠져있어서
# 추가("점심시간에 팀원들이랑 순대국밥집 가기"가 사교로 안 잡히던 걸 발견).
# "동료"도 이미 소수(4/41) 식사 라벨과 충돌하는 걸 감안하면 같은 수준의
# 트레이드오프 - 새로운 종류의 문제는 아님.
ACQUAINTANCE_MARKERS = [
    "친구", "동료", "지인", "소개", "동창", "직장동료", "회사동료", "팀원",
]

# "모임"은 뺐다 — "스터디 모임", "독서 모임"처럼 실제로는 공부/개인활동 쪽
# 문맥에서도 흔히 쓰여서(실사용 데이터에서 확인), 사교로 강제로 보내면 오히려
# 틀림. "정모/동호회"는 그 자체로 "사람 만나는 모임"이라는 뜻이 뚜렷해서 유지.
SOCIAL_KEYWORDS = [
    "친구", "동창", "동기", "선배", "후배", "동료", "지인", "정모", "동호회", "팀원",
]

# "구매가 핵심이면 쇼핑" 규칙 (카테고리_가이드.md 쇼핑↔가족 항목).
# 단, 실사용 데이터에서 "생신 선물", "휴가 나온 동생 먹고싶다던 고기 사주기"처럼
# 기념일/돌봄 맥락의 구매는 사용자들이 전부 가족으로 분류했다 — 순수 쇼핑 목적
# 구매("아이 옷 사러가기")와는 다른 뉘앙스. 이 구분은 키워드만으로는 안전하게
# 못 갈라서, 이 규칙은 잠정 보류하고 ML+margin 판단에 맡긴다.
# (2026-08-26: PURCHASE_MARKERS 하드 오버라이드 비활성화 — 계획서 "결정해야 할 것" 참고)
PURCHASE_MARKERS = []

# 실제로 애매한 적 없는(=학습 데이터에서 여가/휴식 쪽으로 쓰인 적 없는) 종목만.
# 수영/요가/헬스/등산/자전거처럼 강도·목적에 따라 여가/휴식과 갈리는 종목은
# 일부러 뺐다 — ML이 그 뉘앙스를 이미 잘 배웠는데 하드매핑이 덮어쓰면 안 됨.
# 당구/볼링도 같은 이유로 계속 제외.
# ⭐ 2026-09-01(카테고리 확장) - "마라톤"은 RUNNING_KEYWORDS(달리기 전용 카테고리
# 신설)로 옮김. 실측(5,464개)에서 "마라톤"이 낀 문장은 전부 운동보다 "달리기"
# 자체를 가리켜서(마라톤 대회/장거리 러닝 등) 새 카테고리가 더 정확함.
# ⭐ 2026-09-12 - 라켓 스포츠(테니스/배드민턴/탁구/스쿼시), 구기종목(축구/농구/
# 야구/배구), 입식 격투기(복싱)를 각각 전용 카테고리로 분리(사용자 요청 -
# "운동" 하나로 뭉뚱그려지던 종목별 아이콘을 원함). 남은 건 골프/라운딩/
# 클라이밍/웨이트/줄넘기/크로스핏 - "헬스장 트레이닝" 성격의 종목만.
SPORTS_KEYWORDS = ["골프", "라운딩", "클라이밍", "웨이트", "줄넘기", "크로스핏"]
# ⭐ 2026-09-03 - "필라테스"는 카테고리 확장(아래 "요가/필라테스" 신설)으로
# 이 목록에서 빠짐(전용 카테고리로 승격).
# "골프공"처럼 운동 이름 + 공(볼)이 마사지 도구 등 완전히 다른 용도로 쓰이는
# 경우를 걸러낸다("족저근막위염 마사지용 골프공" 같은 실사용 사례로 발견).
SPORTS_FALSE_POSITIVES = ["골프공"]

# ⭐ 2026-09-12 - "PT받기"가 병원·건강관리로 오분류되던 문제 수정(사용자
# 신고). bare "PT"만 보고 무조건 운동으로 보내면 "PT 자료 준비"/"PT 발표"
# (PowerPoint 발표자료의 흔한 준말) 같은 업무 맥락과 충돌하므로, 개인
# 트레이닝 맥락의 동반 신호가 있을 때만 인정하고 업무발표 신호가 있으면
# 제외한다. 대소문자 구분 없이 매칭(route()에서 처리).
PERSONAL_TRAINING_KEYWORDS = ["PT"]
PERSONAL_TRAINING_CONTEXT_KEYWORDS = [
    "받기", "받자", "받을", "받았", "등록", "수업", "예약", "트레이너", "헬스",
]
PERSONAL_TRAINING_FALSE_POSITIVES = [
    "PT자료", "PT준비", "PT발표", "PT연습", "사업PT", "기업PT", "경쟁PT",
]

# ⭐ 2026-09-12 - 라켓 스포츠(테니스/배드민턴/탁구/스쿼시) 전용 카테고리
# 신설. 전부 SPORTS_KEYWORDS에서 그대로 옮겨온 단어라 매칭 방식/오탐
# 목록도 그대로 승계함.
RACKET_SPORTS_KEYWORDS = ["테니스", "배드민턴", "탁구", "스쿼시"]
RACKET_SPORTS_FALSE_POSITIVES = ["테니스공", "탁구공"]

# ⭐ 2026-09-12 - 구기종목 3종(축구/농구/야구)을 각각 전용 아이콘으로 분리.
# 배구는 전용 아이콘 없이 BALL_SPORTS_KEYWORDS(구기종목, 뭉뚱그린 아이콘
# 하나)로 남김.
SOCCER_KEYWORDS = ["축구"]
SOCCER_FALSE_POSITIVES = ["축구공"]
BASKETBALL_KEYWORDS = ["농구"]
BASKETBALL_FALSE_POSITIVES = ["농구공"]
BASEBALL_KEYWORDS = ["야구"]
BASEBALL_FALSE_POSITIVES = ["야구공"]
BALL_SPORTS_KEYWORDS = ["배구"]

# ⭐ 2026-09-12 - 입식 격투기(복싱/킥복싱/무에타이) 전용 카테고리 신설.
# "복싱"은 기존 SPORTS_KEYWORDS에 있던 걸 그대로 옮겨옴, 킥복싱/무에타이는 신규.
COMBAT_SPORTS_KEYWORDS = ["복싱", "킥복싱", "무에타이"]

# ⭐ 2026-09-01 - 카테고리 확장(10개 -> 17개). "운동" 아이콘(아령)이 달리기/수영/
# 등산까지 뭉뚱그리는 게 별로라는 피드백으로 이 3개를 전용 카테고리로 분리함.
# 실측(5,464개)에서 "등산"/"수영"/"조깅"/"러닝"이 낀 문장은 절대다수가 이미
# "운동"으로 라벨돼 있었다(등산 33/45, 수영 37/42, 조깅 9/9, 러닝 26/31) -
# 즉 기존에도 사실상 "운동"의 하위집합으로 취급되던 것을 이번에 독립시킨 것.
# 나머지(사교/쇼핑/여가로 남은 것)는 "동호회 모임"/"등산용품 구매"처럼 다른
# 신호가 더 강한 경우라 그대로 둔다(캐스케이드 순서상 사교 tier가 이미 먼저
# 걸러줌).
#
# ⭐ 기존에 SPORTS_KEYWORDS가 수영/등산을 일부러 뺐던 이유("강도·목적에 따라
# 여가/휴식과 갈림")는 이제 해소됐다 - 예전엔 "운동이냐 여가냐"라는 두 카테고리
# 중 하나를 억지로 골라야 해서 위험했지만, 이제 전용 카테고리가 생겨서
# "수영/등산이면 무조건 이 카테고리"로 확정해도 더 이상 오답이 아니다(강도/
# 목적과 무관하게 물놀이든 진지한 훈련이든 전부 "수영" 카테고리 하나로 수렴).
RUNNING_KEYWORDS = ["러닝", "달리기", "조깅", "런닝", "마라톤"]
# ⭐ 2026-09-03 - "런"(한강런/새벽런 등)도 추가하려 했으나, check_keyword_regressions.py
# 전체 검증에서 "오픈런"(매장 오픈 시간에 맞춰 줄서기, 달리기와 무관)과 충돌
# 발견("오픈런하기"/"오픈런 조율"이 하드매핑 안 걸린 상태로 이미 학습 데이터에
# 있었음) - anywhere=True라 "오픈런"의 "런"도 그대로 잡혀버림. "한강런"류는
# 여전히 ML+margin 판단에 맡김(하드매핑 안 함).
# "마리오카트 레이스 한판 달리기"처럼 게임 속 "달리기"(레이싱 게임)와 충돌 -
# 실측으로 발견한 유일한 사례라 해당 게임 이름만 좁게 예외 처리.
RUNNING_FALSE_POSITIVES = ["닌텐도"]
SWIMMING_KEYWORDS = ["수영"]
HIKING_KEYWORDS = ["등산", "트레킹", "산행", "둘레길", "등반"]
# ⭐ 2026-09-01(실사용 문장 테스트) - "지리산 등반"처럼 산 이름 + "등반"이
# 등산과 동의어로 흔히 쓰여서 추가했는데, "등반"은 "암벽등반"(실내 클라이밍,
# 이미 SPORTS_KEYWORDS의 "클라이밍"이 커버하는 완전히 다른 종목)과도 겹쳐서
# 그 복합어만 예외 처리.
HIKING_FALSE_POSITIVES = ["암벽등반"]

# ⭐ 2026-09-03 - 카테고리 확장(17 -> 19개). "자전거"와 "요가/필라테스"(스트레칭
# 포함) 2종을 달리기/수영/등산과 같은 원리로 신설 - 강도·목적과 무관하게 이
# 활동이면 무조건 이 카테고리(운동/여가 사이에서 억지로 고를 필요가 없어짐).
# "필라테스"는 기존에 SPORTS_KEYWORDS(운동)에 있었으나 이번에 전용 카테고리로
# 승격하며 거기서 제거함.
CYCLING_KEYWORDS = ["자전거", "따릉이"]
# "하늘자전거"(누워서 다리를 페달 돌리듯 움직이는 실내 운동 동작 - 실제
# 자전거를 타는 게 아님)만 예외 처리. "자전거길"(산책로를 가리키는 명사)은
# 뒤에 "길"이 붙어 있어 _verb_word_matched 자체가 이미 안 잡음(뒤가 조사도
# "하다" 활용형도 아니라서) - 별도 예외 불필요.
CYCLING_FALSE_POSITIVES = ["하늘자전거"]
YOGA_KEYWORDS_ANYWHERE = ["필라테스", "스트레칭"]
# ⚠️ "요가"만 anywhere=False(어절 맨 앞에서만 인정)로 별도 취급 -
# anywhere=True로 켜면 "필요가 있다"(필요+가, 매우 흔한 조사 결합)의
# "필요가"가 "요가"로 끝나는 바람에 오탐됨(BEAUTY_PREFIX_KEYWORDS의 "펌"과
# 같은 이유 - 반드시 anywhere=False로 유지할 것).
YOGA_KEYWORDS_PREFIX_ONLY = ["요가"]
# ⭐ "자전거 헬멧 사기"/"요가 블록 구매하기"처럼 장비를 사는 문장, "자전거
# 브레이크 수리 맡기러 가기"처럼 정비만 맡기는 문장에서 실측 충돌 발견 -
# 러닝화/등산화와 달리 "자전거 헬멧"은 붙여쓰지 않고 띄어 써서 기존
# _verb_word_matched의 복합어 방어(뒤에 명사가 이어지면 안 잡음)가 안 먹힘
# ("자전거"가 그 자체로 독립된 어절이라 조건 없이 매칭됨). 이 문장들은 전부
# "사거나 수리를 맡기고 끝날 뿐 실제로 타는 동작이 전혀 없다"는 공통점이 있어,
# 이 신호가 있으면 이 tier 전체를 defer(ML에 맡김 - 실측상 대부분 쇼핑/기타로
# 감). "~새로 사서 라이딩"/"~구매해서 연습"처럼 뒤에 다른 동작이 이어지는
# 연결형("사서"/"구매해서")은 이 목록에 없어서 안 걸림 - 실제 콤보 문장은 전부
# 그 형태로만 나타남(관찰 기반, ml/check_keyword_regressions.py로 검증).
CYCLING_YOGA_PURCHASE_OR_REPAIR_MARKERS = [
    "사기", "사주기", "구매하기", "구입하기", "주문하기", "장만하기", "수리", "맡기러",
]

# ⭐ 2026-09-01 - "문화생활"(영화/공연/전시 등) 신설. 실측에서 이 단어들이 낀
# 문장은 절대다수가 "여가/휴식"이었다(영화 21건 중 17건, 뮤지컬 10/10, 공연
# 3/3, 전시 13건 중 8건, 콘서트 4건 중 3건) - "여가/휴식" 아이콘(야자수)이 너무
# 뭉뚱그린다는 같은 문제라 별도 카테고리로 분리. 나머지(사교로 남은 일부)는
# "동료랑 영화보기"처럼 사람 만남이 더 강한 신호라 그대로 둠(사교 tier가 먼저
# 걸러줌).
CULTURE_KEYWORDS = ["영화", "콘서트", "공연", "전시", "뮤지컬", "연극", "페스티벌"]

# ⭐ 2026-09-01 - "금융"(은행/보험/세금 등 행정성 용무) 신설. 이런 용무는
# 마땅한 카테고리가 없어 "기타"로 자주 빠졌다(실측 "은행" 11건 중 7건이
# 기타) - ACTIVITY_PREFIX_KEYWORDS의 "출장"(업무)/"병원"(건강) 같은 걸
# 하나 더 늘리는 셈. "대출"은 "도서관에서 책 대출"과 겹쳐서 뺐다(당구/볼링과
# 같은 이유로 ML에 맡김). "은행나무"(가로수)/"문제은행"(시험)은 prefix
# 매칭(아래 route()에서 _prefix_matched 사용) 자체가 "은행"으로 시작하는
# 어절만 잡으므로 저절로 안전함("문제은행"은 "문제"로 시작, "은행나무"만
# 별도 예외 필요).
FINANCE_KEYWORDS = ["은행", "환전", "적금", "예금", "연말정산", "공과금"]
FINANCE_FALSE_POSITIVES = ["은행나무"]

# ⭐ 2026-09-01 - "집안일"(청소/빨래/설거지/분리수거) 신설. 이것도 마땅한
# 카테고리가 없어 "기타"/"쇼핑"으로 흩어져 있었다. 단, "청소기"/"청소용품"/
# "빨래바구니"처럼 그 도구를 "사는" 문장(쇼핑이 맞음)과는 반드시 갈라야 해서
# 일반 접두어 매칭 대신 전용 매처(_chore_word_matched, 아래)를 씀 - 어절이
# 정확히 그 단어 자체이거나 "하다/해야/하고" 등 동사 활용형으로 이어질 때만
# 잡고, "기"/"용"/"바구니"처럼 명사가 이어지는 경우(=도구/제품을 가리킴)는
# 절대 안 잡음.
CHORE_KEYWORDS = ["청소", "빨래", "설거지", "분리수거"]

# ⭐ 2026-09-01 - "미용"(미용실/네일/염색 등 사람 대상 뷰티 케어) 신설.
# ⚠️ 반려동물 관련 데이터에 "반려동물 미용"류가 많아서(실측 40건+) 절대
# bare "미용"으로 하드매핑하면 안 됨 - 전부 구체적인 복합어(미용실/네일아트/
# 네일샵/왁싱/염색/속눈썹)만 쓴다. "펌"은 "컨펌"/"펌프"와 충돌 위험이 있어
# prefix 매칭(어절이 "펌"으로 시작)으로만 잡음(뒤에 조사/활용형이 붙는 경우만
# 인정 - _word_matched와 동일 원리라 "컨펌"/"펌프형"은 애초에 "펌"으로
# 시작하지 않아서 안전).
# 학습 데이터 전수 확인(2026-09-21): "네일" 포함 102건 중 99건이 미용.
# "네일아트/네일샵"만 잡던 기존 목록은 "네일 예약/네일 받기"를 놓쳤다.
BEAUTY_CONTAINS_KEYWORDS = ["미용실", "네일", "왁싱", "염색", "속눈썹"]
BEAUTY_PREFIX_KEYWORDS = ["펌", "커트"]

# ⭐ 2026-08-27 - "짧은 단어/구가 기타로 자주 빠진다" 실측(사용자 제보 +
# predict.py로 직접 확인) 후 추가한 범용 활동 키워드 하드매핑. SPORTS_KEYWORDS와
# 같은 원칙: 카테고리 이름 자체이거나 그와 거의 동의어라 "강도/맥락에 따라
# 다른 카테고리로 갈릴 여지가 사실상 없는" 것만 넣는다(수영/요가/헬스/등산을
# SPORTS_KEYWORDS에서 뺀 이유와 같은 기준 - ML이 이미 배운 뉘앙스를 덮어쓰면
# 안 됨). 매칭은 SPORTS_KEYWORDS와 동일하게 접두어(prefix) - "공부하러가기",
# "병원가야됨"처럼 조사 없이 동사가 바로 붙는 패턴을 잡기 위함.
#
# ⚠️ 후보를 넓게 잡아서 ml/check_keyword_regressions.py로 전체 라벨 데이터
# (5,464개)에 실측 검증한 뒤, 실제로 충돌이 난 것들은 뺐다(당구/볼링을 뺀
# 것과 같은 원칙 - "명확해 보이는 키워드도 실측 없이 하드매핑하면 안 됨"):
#   - "업무" 자체는 제외함 - "은행 업무"(개인 용무, 기타), "업무 관련 자격증"
#     (공부), "업무와 무관한"(부정 문맥을 못 읽고 그대로 강제) 등에서 6번
#     틀림. "출장"은 이런 다의성이 없어서 유지.
#   - "휴식"도 제외함 - "헌혈 후 휴식", "안대로 눈 휴식"처럼 치료/관리
#     목적의 휴식이 병원·건강관리로 가야 하는데 여가로 강제됨(2번 다 틀림) -
#     수영/헬스처럼 목적에 따라 갈리는 유형으로 판단, ML에 맡김. "여가"는
#     이런 충돌이 없어서 유지.
#   - "병원"은 그대로 유지 - "부모님 병원 모시고 가기"류는 가족 하드매핑이
#     먼저 걸려서(route()의 우선순위 캐스케이드) 이 키워드까지 안 옴, 실측
#     충돌 0건.
ACTIVITY_PREFIX_KEYWORDS = {
    # ⭐ 2026-09-01(실사용 문장 테스트) - "인강"(인터넷 강의 줄임말, 7/7 전부
    # 공부로 일치)과 "강의"(41/43 공부 - 나머지 2건 "정신건강의학과"는 prefix
    # 매칭이라 "정신건강의학과"가 "강의"로 시작하지 않아서 애초에 안 걸림,
    # 충돌 아님) 추가.
    # ⭐ 2026-09-03 - "코테"(코딩테스트 줄임말, "인강"과 같은 원리 - 다른 뜻으로
    # 쓰일 여지가 사실상 없는 축약어)를 e2e 평가(eval_e2e.py)에서 발견해 추가.
    "공부": ["공부", "독서", "인강", "강의", "코테"],
    # 학습 데이터 전수 확인: 치과 42건 중 37건, 약국 13건 중 12건이 건강.
    # 가족 신호는 이 tier보다 먼저 처리되므로 "엄마 치과 동행"은 계속 가족이다.
    "병원·건강관리": ["병원", "치과", "약국"],
    "업무": ["출장"],
    "식사": ["식사", "외식"],
    # ⭐ 2026-09-03 - "집콕"/"방탈출" 추가(check_keyword_regressions.py 전체
    # 검증 통과, 충돌 0건). OTT 브랜드명(넷플릭스 등)과 "캠핑"도 처음엔 같이
    # 추가해보려 했으나 전체 검증에서 실제 라벨 데이터와 충돌해서 뺐다:
    #   - "넷플릭스"는 실측 데이터 자체가 갈려 있음(문화생활 18건 vs 여가/휴식
    #     8건 - "넷플릭스 정주행"처럼 똑같은 표현도 양쪽에 다 있어서 하드매핑할
    #     만큼 명확하지 않음, ML 판단에 맡김이 맞음).
    #   - "캠핑"은 "캠핑용품/캠핑의자 주문·구매"처럼 장비 구매 문장과 충돌
    #     (러닝화/등산화와 같은 "장비 구매는 쇼핑" 원칙 위반 - CHORE_KEYWORDS나
    #     RUNNING_KEYWORDS처럼 별도 매처 없이 단순 prefix라 못 갈랐음).
    "여가/휴식": ["여가", "집콕", "방탈출"],
}
HEALTH_ACTIVITY_FALSE_POSITIVES = ["치과위생사"]
# "독서"는 "독서 모임/독서모임"처럼 실제로는 사람을 만나는 모임(사교)을
# 가리키는 경우가 실측 데이터에서 더 많이 나와서("모임"이 같이 있으면 방향이
# 뒤집힘, ml/check_keyword_regressions.py로 확인) - "모임" 신호가 있으면
# 활동 하드매핑 전체를 보류하고 ML 판단에 맡긴다.
ACTIVITY_DEFER_MARKERS = ["모임"]
# "쇼핑"은 "온라인쇼핑"처럼 다른 단어 뒤에 붙는 복합어로도 흔히 쓰여서
# contains(부분일치)로 잡는다 - "가족"을 IMMEDIATE_FAMILY_CONTAINS로 따로
# 처리한 것과 같은 이유(외래어 단독 형태라 다른 무관한 단어와 충돌할
# 위험이 낮음).
ACTIVITY_CONTAINS_KEYWORDS = {
    "쇼핑": ["쇼핑"],
}

# ⭐ 2026-09-12(사용자 신고) - "사파리투어"가 쇼핑으로 오분류되던 문제 수정.
# "투어"/"관광"은 지명 뒤에 그대로 붙는 복합어로 흔히 쓰여서 anywhere=True
# (_verb_word_matched)로 잡음. ⚠️ 처음엔 단순 contains로 잡았다가
# check_keyword_regressions.py 실측 검증에서 "관광통역안내사 자격시험
# 신청"(공부)이 "관광"을 포함한다는 이유만으로 여가로 오분류되는 걸 발견해서,
# RUNNING/HIKING과 동일한 엄격한 매처로 바꿈. "여행" 자체는 관계·목적에 따라
# 갈리는 폭이 넓어서(위 파일 상단 주석 "반려동물/육아/여행은... 제외함" 참고)
# 안 넣음.
LEISURE_TRAVEL_KEYWORDS = ["투어", "관광"]

# ⭐ 2026-09-06 - route()의 tier3d_eating_proposal 참고. "먹자"/"먹을래"/"먹으러"는
# 뒤에 무슨 말이 오든(음식 이름, 아무것도 없음) 거의 항상 "같이 밥 먹자"는 뜻이라
# contains(부분일치)로 넉넉하게 잡는다.
EATING_PROPOSAL_KEYWORDS = ["먹자", "먹을래", "먹으러"]
# "약 먹자"/"영양제 먹자"처럼 복용을 뜻하면 식사가 아니라 건강이 맞으므로 제외.
EATING_PROPOSAL_MEDICATION_DEFER = ["약", "영양제", "유산균", "비타민", "오메가", "프로폴리스", "한약"]


def _tokens(text):
    return text.split()


def _word_matches_token(token, word):
    """어절이 word 자체이거나, word+(들)+흔한 조사로 이루어졌을 때만 True."""
    if not token.startswith(word):
        return False
    rest = token[len(word):]
    if rest == "":
        return True
    if rest.startswith("들"):
        rest = rest[1:]
        if rest == "":
            return True
    return _particle_suffix_ok(rest)


def _word_matched(tokens, keywords):
    return [kw for tok in tokens for kw in keywords if _word_matches_token(tok, kw)]


def _prefix_matched(tokens, keywords):
    return [kw for tok in tokens for kw in keywords if tok.startswith(kw)]


def _contains_matched(text, keywords):
    return [kw for kw in keywords if kw in text]


# ⭐ 2026-09-12 - "PT"(개인 트레이닝) 전용 대소문자 무시 매처. 이 키워드
# 체계의 다른 항목은 전부 한글이라 케이스 이슈가 없었는데, "PT"는 영문
# 약어라 사용자가 "pt받기"처럼 소문자로도 흔히 씀.
def _prefix_matched_ignore_case(tokens, keywords):
    upper_keywords = [kw.upper() for kw in keywords]
    return [kw for tok in tokens for kw in upper_keywords if tok.upper().startswith(kw)]


def _contains_matched_ignore_case(text, keywords):
    upper_text = text.upper()
    return [kw for kw in keywords if kw.upper() in upper_text]


# ⭐ 2026-09-01(2차 - 어미/앞말 대응 점검) - 처음엔 "하"/"해" 두 어간만 인정했는데
# "할거임"(할)/"했음"(했)/"한 적"(한) 같은 "하다" 활용형의 다른 어간을 놓치는 걸
# 발견해서 5개로 늘림. "하기/하러가자/하자"는 "하" 어간, "해야됨"은 "해" 어간이라
# 이미 커버됐었지만, "할거임"류(의지/예정형)는 어간 자체가 "할"로 바뀌어서
# 별도로 추가해야 했음.
_VERB_STEMS = ("하", "해", "할", "했", "한")

# ⭐ 2026-09-03 - CYCLING_KEYWORDS 전용 확장 어간. "자전거"/"따릉이"는 "하다"가
# 아니라 "타다"(타기/타며/타고/탄다/탈/탔)로 활용되는데, 기존 _VERB_STEMS엔
# "하다" 계열만 있어서 "자전거타고"/"자전거타야됨"처럼 붙여 쓴 형태를 놓치는
# 걸 발견함("자전거 타고"처럼 띄어 쓴 경우는 "자전거"가 그 자체로 독립 어절이라
# 이미 잡혔음 - 붙여 쓴 경우만 문제). 이 확장을 전역 _VERB_STEMS에 바로
# 추가하지 않은 이유: "청소타령"/"빨래타령"(잔소리를 뜻하는 관용구, 실제로
# 청소/빨래를 하는 게 아님)처럼 "타"로 시작하는 무관한 실제 단어와 CHORE_
# KEYWORDS 등 다른 anywhere=True 키워드가 충돌할 위험이 있어서 - CYCLING_
# KEYWORDS("자전거"/"따릉이")는 그 자체로 뜻이 뚜렷해 이런 충돌 위험이 낮다고
# 판단해 이 tier에만 좁게 적용함.
_CYCLING_VERB_STEMS = _VERB_STEMS + ("타", "탄", "탈", "탔")


def _verb_word_matches_token(token, word, anywhere=False, stems=_VERB_STEMS):
    """word가 어절 안에 있고, 그 뒤가 (없음 | 조사 | "하다" 활용형 - 하/해/할/했/한
    으로 시작)일 때만 True. "청소기"/"청소용"/"빨래바구니"(CHORE_KEYWORDS),
    "펌프형"(BEAUTY_PREFIX_KEYWORDS)처럼 명사가 이어지는 경우(뒤가 활용형도
    조사도 아님)는 절대 안 잡는다 - 단순 prefix 매칭(_prefix_matched)보다 엄격함.

    anywhere=False(기본)면 word가 어절 맨 앞에 와야 함(_word_matches_token과
    동일한 전제). anywhere=True면 "새벽러닝"/"주말등산"처럼 word 앞에 다른
    말이 붙어 있어도(=word가 어절 어디에 있든) 인정 - RUNNING/SWIMMING/HIKING/
    CHORE_KEYWORDS처럼 그 자체로 뜻이 뚜렷해 다른 단어 뒤에 붙어도 오탐 위험이
    낮은 키워드에만 씀. BEAUTY_PREFIX_KEYWORDS의 "펌"은 "컨펌하기"(confirm,
    전혀 무관)처럼 짧은 한 글자라 anywhere=True로 켜면 오탐이 생겨서 반드시
    anywhere=False(기본값)로 유지할 것.

    stems는 기본 _VERB_STEMS("하다" 계열) - CYCLING_KEYWORDS만 _CYCLING_VERB_
    STEMS(위 주석 참고)를 넘겨서 "타다" 활용형도 인정하게 함."""
    if anywhere:
        idx = token.find(word)
    else:
        idx = 0 if token.startswith(word) else -1
    if idx == -1:
        return False
    rest = token[idx + len(word):]
    if rest == "":
        return True
    if rest[0] in stems:
        return True
    return _particle_suffix_ok(rest)


def _verb_word_matched(tokens, keywords, anywhere=False, stems=_VERB_STEMS):
    return [kw for tok in tokens for kw in keywords if _verb_word_matches_token(tok, kw, anywhere, stems)]


def route(text):
    """
    반환값: (label, tier) 또는 (None, None) — 규칙에 안 걸리면 ML로 넘어가라는 뜻.
    """
    tokens = _tokens(text)
    has_acquaintance = bool(_word_matched(tokens, ACQUAINTANCE_MARKERS))
    has_purchase = bool(_contains_matched(text, PURCHASE_MARKERS))

    immediate_hit = _word_matched(tokens, IMMEDIATE_FAMILY) or _contains_matched(text, IMMEDIATE_FAMILY_CONTAINS)
    extended_hit = _word_matched(tokens, EXTENDED_FAMILY)

    if immediate_hit or extended_hit:
        if has_purchase:
            return "쇼핑", "tier0_purchase_over_family"
        if not has_acquaintance:
            return "가족", "tier1_immediate_family" if immediate_hit else "tier1b_extended_family"
        # 가족어 + 지인/친구/동료 신호가 같이 있으면 "남의 가족" 가능성 -> 2단계로

    if _word_matched(tokens, SOCIAL_KEYWORDS):
        return "약속/사교", "tier2_social"

    sports_hit = _prefix_matched(tokens, SPORTS_KEYWORDS) or _contains_matched(text, SPORTS_KEYWORDS)
    if sports_hit and not _contains_matched(text, SPORTS_FALSE_POSITIVES):
        return "운동", "tier3_sports"

    # ⭐ 2026-09-12 - "PT받기"(헬스장 개인 트레이닝) 전용 tier. bare "PT"만으론
    # 부족하고 개인 트레이닝 맥락(받기/등록/수업/예약/트레이너/헬스)이 같이
    # 있어야 하며, 업무 발표(PT 자료/PT 준비 등) 신호가 있으면 제외한다.
    if (_prefix_matched_ignore_case(tokens, PERSONAL_TRAINING_KEYWORDS)
            and _contains_matched(text, PERSONAL_TRAINING_CONTEXT_KEYWORDS)
            and not _contains_matched_ignore_case(text, PERSONAL_TRAINING_FALSE_POSITIVES)):
        return "운동", "tier3_personal_training"

    # ⭐ 2026-09-12 - 라켓 스포츠/구기종목 3종/기타 구기/입식 격투기 - 전부
    # 위 tier3_sports("운동")에서 갈라져 나온 종목이라 매칭 방식(prefix+
    # contains, false positives)도 그대로 승계함. tier3_sports가 원래도
    # 사교 방어(모임/동호회 신호로 defer)를 안 걸었던 것과 동일하게 여기도
    # 안 건다.
    if _prefix_matched(tokens, RACKET_SPORTS_KEYWORDS) and not _contains_matched(text, RACKET_SPORTS_FALSE_POSITIVES):
        return "라켓 스포츠", "tier3_racket_sports"
    if _prefix_matched(tokens, SOCCER_KEYWORDS) and not _contains_matched(text, SOCCER_FALSE_POSITIVES):
        return "축구", "tier3_soccer"
    if _prefix_matched(tokens, BASKETBALL_KEYWORDS) and not _contains_matched(text, BASKETBALL_FALSE_POSITIVES):
        return "농구", "tier3_basketball"
    if _prefix_matched(tokens, BASEBALL_KEYWORDS) and not _contains_matched(text, BASEBALL_FALSE_POSITIVES):
        return "야구", "tier3_baseball"
    if _prefix_matched(tokens, BALL_SPORTS_KEYWORDS):
        return "구기종목", "tier3_ball_sports"
    if _prefix_matched(tokens, COMBAT_SPORTS_KEYWORDS):
        return "입식 격투기", "tier3_combat_sports"

    # ⭐ 2026-09-01(실측 후 수정) - 신설 카테고리 3종(달리기/수영/등산)은 처음엔
    # 일반 스포츠처럼 prefix+contains로 잡았다가, "러닝메이트랑 저녁"(사교인데
    # "러닝메이트"가 "러닝"으로 시작해서 오분류), "러닝머신 매트 주문"/"등산화
    # 밑창 갈기"(장비를 사는 쇼핑인데 "러닝"/"등산"으로 시작해서 오분류) 실측
    # 충돌을 발견해서 CHORE_KEYWORDS와 같은 엄격한 매처(_verb_word_matched -
    # 어절이 그 단어 자체이거나 조사/"하다"류 활용형으로 이어질 때만 인정,
    # "메이트"/"머신"/"화"처럼 명사가 이어지면 안 잡음)로 바꿈.
    #
    # ⭐ 2026-09-01(2차) - anywhere=True로 켜서 "새벽러닝"/"주말등산"처럼 앞에
    # 다른 말이 붙어 어절이 그 단어로 "시작하지는" 않는 경우도 잡게 함(원래는
    # startswith만 인정해서 이런 흔한 시간표현+활동 붙임 표기를 놓쳤음) - 이
    # 4개 키워드는 그 자체로 뜻이 뚜렷해서(러닝/수영/등산/청소 등) 다른 말
    # 뒤에 붙어도 "컨펌"처럼 무관한 단어와 충돌할 위험이 낮다고 판단(BEAUTY_
    # PREFIX_KEYWORDS의 "펌"과는 다름 - 그쪽은 한 글자라 anywhere 금지, 아래
    # 주석 참고).
    #
    # ⭐ "산행"/"둘레길"이 "동호회"류 명시적 신호 없이 "OO클럽/모임 산행
    # 뒷풀이"처럼 동호회 회식 맥락에서도 쓰이는 걸 발견해서, 이 3개 tier
    # 한정으로 클럽/모임 신호가 있으면 통째로 defer(ML에 맡김) - 기존
    # ACTIVITY_DEFER_MARKERS("모임")보다 넓은 범위(클럽/뒷풀이/신년회/송년회/
    # 환영회도 "여럿이 모이는 자리"라는 같은 신호라 포함).
    tier3b_social_defer = _contains_matched(
        text, ["클럽", "모임", "뒷풀이", "신년회", "송년회", "환영회", "정모", "산악회"]
    )
    # ⭐ "자격증"(시험 준비가 핵심이라 공부가 더 맞음 - "네일아트 자격증 실기
    # 연습" 실측 충돌로 발견, ACTIVITY_DEFER_MARKERS의 "모임"과 같은 원리)이
    # 있으면 문화생활/금융/집안일/미용(tier3c)뿐 아니라 자전거/요가·필라테스
    # (tier3b, 2026-09-03)에도 똑같이 적용 - "요가 지도자 자격증 과정" 같은
    # 문장이 공부가 아니라 요가로 강제되는 걸 막기 위해 위로 옮김.
    cert_defer = _contains_matched(text, ["자격증"])
    if not tier3b_social_defer:
        if _verb_word_matched(tokens, RUNNING_KEYWORDS, anywhere=True) and not _contains_matched(text, RUNNING_FALSE_POSITIVES):
            return "달리기", "tier3b_running"
        if _verb_word_matched(tokens, SWIMMING_KEYWORDS, anywhere=True):
            return "수영", "tier3b_swimming"
        if _verb_word_matched(tokens, HIKING_KEYWORDS, anywhere=True) and not _contains_matched(text, HIKING_FALSE_POSITIVES):
            return "등산", "tier3b_hiking"

        # ⭐ 2026-09-03 - 자전거/요가·필라테스(신설). cert_defer 또는 구매/수리
        # 신호가 있으면 이 둘도 defer(위 주석 참고).
        cycling_yoga_defer = cert_defer or _contains_matched(text, CYCLING_YOGA_PURCHASE_OR_REPAIR_MARKERS)
        if not cycling_yoga_defer:
            if (_verb_word_matched(tokens, CYCLING_KEYWORDS, anywhere=True, stems=_CYCLING_VERB_STEMS)
                    and not _contains_matched(text, CYCLING_FALSE_POSITIVES)):
                return "자전거", "tier3b_cycling"
            if (_verb_word_matched(tokens, YOGA_KEYWORDS_ANYWHERE, anywhere=True)
                    or _verb_word_matched(tokens, YOGA_KEYWORDS_PREFIX_ONLY)):
                return "요가/필라테스", "tier3b_yoga"

    # ⭐ 2026-09-01 - 신설 카테고리 4종(문화생활/금융/집안일/미용).
    if not cert_defer and _contains_matched(text, CULTURE_KEYWORDS):
        return "문화생활", "tier3c_culture"
    # ⭐ "은행"은 contains가 아니라 prefix로 잡는다 - "문제은행"(시험 문제
    # 은행, 금융과 무관)이 contains로는 걸려서 실측 충돌 발견. "대출"은
    # "도서관 책 대출"과 겹쳐서 아예 뺌(당구/볼링과 같은 이유 - ML에 맡김).
    if not cert_defer and _prefix_matched(tokens, FINANCE_KEYWORDS) and not _contains_matched(text, FINANCE_FALSE_POSITIVES):
        return "금융", "tier3c_finance"
    # ⭐ 2026-09-01(2차) - "주말청소"/"저녁설거지"처럼 앞에 다른 말이 붙는
    # 경우도 잡게 anywhere=True (RUNNING/SWIMMING/HIKING과 같은 이유).
    if not cert_defer and _verb_word_matched(tokens, CHORE_KEYWORDS, anywhere=True):
        return "집안일", "tier3c_housework"
    # ⭐ "펌"/"커트"는 "컨펌"/"펌프형"과 충돌 위험이 있어 단순 prefix가 아니라
    # _verb_word_matched(조사/동사활용형 뒤따를 때만 인정)로 잡는다. anywhere는
    # 반드시 기본값(False)으로 둘 것 - "컨펌하기"(confirm, "펌"이 뒤에 붙어
    # anywhere였으면 오탐)가 실측으로 확인된 충돌이라 "펌"은 어절 맨 앞에서만
    # 인정해야 함.
    if not cert_defer and (_contains_matched(text, BEAUTY_CONTAINS_KEYWORDS) or _verb_word_matched(tokens, BEAUTY_PREFIX_KEYWORDS)):
        return "미용", "tier3c_beauty"

    # ⭐ 2026-09-12 - 여가/휴식(투어/관광) - 위 LEISURE_TRAVEL_KEYWORDS 주석 참고.
    if _verb_word_matched(tokens, LEISURE_TRAVEL_KEYWORDS, anywhere=True):
        return "여가/휴식", "tier3c_leisure_travel"

    # ⭐ 2026-09-06(실사용 신고) - "치킨 먹자"/"~~먹자"류의 구어체 제안형 식사
    # 표현이 하드매핑에 전혀 안 걸려서(ACTIVITY_PREFIX_KEYWORDS의 "식사"/"외식"만
    # 잡음) ML로 넘어갔는데, 학습데이터의 "식사" 라벨이 전부 "OO 시켜 먹기"류의
    # 격식체+구체 메뉴 설명이라(예: "야식으로 치킨 시켜먹기") 이렇게 짧고
    # 캐주얼한 문장은 학습 분포 밖이라 오분류가 잦았다(실측: "치킨 먹자"가
    # 병원·건강관리로 감 - 짧은 문장이라 n-gram이 몇 개 안 남아서 우연한 상관에
    # 취약함). "약 먹자"류(복용)와의 오탐을 막기 위해 복용 관련 단어가 같이
    # 있으면 이 tier는 건너뛰고 ML(건강 쪽으로 이미 잘 학습됨)에 맡긴다.
    # ⭐ "모임"이 같이 있으면(예: "동네 주민 모임에서 붕어빵 먹으러 가자고 연락
    # 옴") 핵심이 식사가 아니라 그 모임(사교)이라 ACTIVITY_DEFER_MARKERS와
    # 같은 원리로 defer(check_keyword_regressions.py 실측 검증으로 발견).
    if (not _contains_matched(text, EATING_PROPOSAL_MEDICATION_DEFER)
            and not _contains_matched(text, ACTIVITY_DEFER_MARKERS)
            and _contains_matched(text, EATING_PROPOSAL_KEYWORDS)):
        return "식사", "tier3d_eating_proposal"

    if not _contains_matched(text, ACTIVITY_DEFER_MARKERS):
        for label, keywords in ACTIVITY_PREFIX_KEYWORDS.items():
            if label == "병원·건강관리" and _contains_matched(text, HEALTH_ACTIVITY_FALSE_POSITIVES):
                continue
            if _prefix_matched(tokens, keywords):
                return label, "tier4_activity"
        for label, keywords in ACTIVITY_CONTAINS_KEYWORDS.items():
            if _contains_matched(text, keywords):
                return label, "tier4_activity"

    return None, None
