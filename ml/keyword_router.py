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
]

IMMEDIATE_FAMILY = [
    "엄마", "어머니", "아빠", "아버지", "아들", "딸", "남편", "아내", "배우자",
    "할머니", "할아버지", "부모님", "친정엄마", "친정아빠", "아이",
]
# "가족"은 "온가족/전가족"처럼 다른 어절 뒤에 붙는 복합어로도 자주 쓰여서
# contains(부분일치)로 따로 잡는다. "가족"은 그 자체로 오탐 위험 낮음.
IMMEDIATE_FAMILY_CONTAINS = ["가족"]

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
ACQUAINTANCE_MARKERS = [
    "친구", "동료", "지인", "소개", "동창", "직장동료", "회사동료",
]

# "모임"은 뺐다 — "스터디 모임", "독서 모임"처럼 실제로는 공부/개인활동 쪽
# 문맥에서도 흔히 쓰여서(실사용 데이터에서 확인), 사교로 강제로 보내면 오히려
# 틀림. "정모/동호회"는 그 자체로 "사람 만나는 모임"이라는 뜻이 뚜렷해서 유지.
SOCIAL_KEYWORDS = [
    "친구", "동창", "동기", "선배", "후배", "동료", "지인", "정모", "동호회",
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
SPORTS_KEYWORDS = [
    "테니스", "골프", "라운딩", "탁구", "축구", "배드민턴", "스쿼시",
    "클라이밍", "필라테스", "복싱", "웨이트", "마라톤", "농구", "배구",
    "야구", "줄넘기", "크로스핏",
]
# "골프공"처럼 운동 이름 + 공(볼)이 마사지 도구 등 완전히 다른 용도로 쓰이는
# 경우를 걸러낸다("족저근막염 마사지용 골프공" 같은 실사용 사례로 발견).
SPORTS_FALSE_POSITIVES = ["골프공", "테니스공", "야구공", "축구공", "탁구공"]


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
    return rest in _COMMON_PARTICLES


def _word_matched(tokens, keywords):
    return [kw for tok in tokens for kw in keywords if _word_matches_token(tok, kw)]


def _prefix_matched(tokens, keywords):
    return [kw for tok in tokens for kw in keywords if tok.startswith(kw)]


def _contains_matched(text, keywords):
    return [kw for kw in keywords if kw in text]


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

    return None, None
