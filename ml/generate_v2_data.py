"""
카테고리 확장(10 -> 17개) - 신설 카테고리 7종(달리기/수영/등산/문화생활/금융/
집안일/미용) 학습 데이터 대량 생성.

relabel_v2.py로 기존 데이터에서 옮겨온 것만으로는 카테고리별 표본 수가 너무
적어서(예: 미용 3개, 금융 10개) pilot_dataset.jsonl의 기존 카테고리(범주당
~500개) 수준으로 끌어올리기 위해 템플릿 조합 방식으로 대량 생성한다.

원칙(ml/data/README.md의 pilot_dataset 다양성 원칙과 동일):
  - 직접 키워드형("러닝화 신고 한강 러닝") + 간접 표현형("퇴근하고 한강에서
    5km 뛰기" - 하드매핑 키워드 없이 ML이 문맥으로 배워야 하는 케이스) 혼합
  - 길이 다양화, 시간 표현 다양화, 구어체/축약형/영어 혼용 섞음
  - 슬롯(시간/장소/동사어미)을 조합해서 생성하되, 최종 텍스트는 전부
    중복 제거하고 기존 데이터셋과도 안 겹치게 함

사용법: python ml/generate_v2_data.py  (data/pilot_dataset.jsonl에 append)
"""
import itertools
import json
import pathlib
import random

DATA_DIR = pathlib.Path(__file__).parent / "data"
PILOT_PATH = DATA_DIR / "pilot_dataset.jsonl"

random.seed(20260901)

TARGET_PER_CATEGORY = 300


def existing_texts():
    texts = set()
    for fn in ["pilot_dataset.jsonl", "boundary_cases.jsonl", "eval_holdout.jsonl"]:
        with open(DATA_DIR / fn, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                texts.add(json.loads(line)["text"])
    return texts


def gen_sentences(templates, slots, n, seen):
    """templates: 각 원소는 "{a} {b} {c}" 형태의 문자열, slots: dict[key] = list.
    조합을 랜덤으로 뽑아 n개(중복/기존 데이터 제외) 만들어 반환."""
    out = []
    tried = 0
    max_tries = n * 60
    while len(out) < n and tried < max_tries:
        tried += 1
        t = random.choice(templates)
        try:
            filled = {}
            for key in slots:
                if "{" + key + "}" in t:
                    filled[key] = random.choice(slots[key])
            text = t.format(**filled)
        except (KeyError, IndexError):
            continue
        text = " ".join(text.split())  # 공백 정리
        if text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


# ============================================================
# 시간/공통 슬롯 (여러 카테고리가 공유)
# ============================================================
TIME_CASUAL = [
    "아침에", "새벽에", "출근 전에", "퇴근하고", "점심시간에", "오후에", "저녁에",
    "자기 전에", "주말에", "이번 주말", "다음 주말", "오늘", "내일", "모레",
    "이따가", "쉬는 날", "휴무일에", "비번날", "다음 휴무에", "D-3",
]

# ============================================================
# 1. 달리기 (running)
# ============================================================
RUNNING_DIRECT = [
    "{time} 한강 러닝 {dist} 뛰기",
    "{time} 러닝화 신고 동네 한바퀴 달리기",
    "{time} 조깅 {dist} 나가기",
    "{time} 러닝 크루 정기 훈련 참여",
    "{time} 인터벌 러닝 훈련하기",
    "헬스장 러닝머신에서 {dist} 뛰기",
    "{time} 새벽 조깅 다녀오기",
    "마라톤 대회 {dist} 완주 목표로 훈련",
    "{time} 러닝 앱 기록 확인하며 뛰기",
    "다음 달 하프 마라톤 대회 참가 신청",
    "{time} 트랙 뛰면서 페이스 훈련",
    "GPS 워치 차고 {dist} 러닝",
    "{time} 러닝 스트레칭까지 마무리",
    "10km 마라톤 완주 후기 정리하기",
    "{time} 계단 뛰어오르기 인터벌 훈련",
]
RUNNING_INDIRECT = [
    "{time} 한강에서 {dist} 뛰고 오기",
    "{time} 동네 한바퀴 뛰고 땀 식히기",
    "{time} 숨차게 트랙 몇 바퀴 돌기",
    "{time} 아파트 단지 뛰면서 체력 다지기",
    "{time} 페이스 올려서 전력질주 연습",
    "{time} 뛰면서 스트레스 풀기",
]
RUNNING_SLOTS = {"time": TIME_CASUAL, "dist": ["3km", "5km", "7km", "10km", "한바퀴", "30분"]}

# ============================================================
# 2. 수영 (swimming)
# ============================================================
SWIMMING_DIRECT = [
    "{time} 수영장 가서 자유형 연습",
    "{time} 수영 강습 등록하고 첫 수업",
    "{time} 접영 자세 교정받기",
    "{time} 동네 수영장 {laps} 완주",
    "{time} 수영복 챙겨서 실내 수영장 가기",
    "{time} 배영 연습하러 수영장 가기",
    "수영 자격증반 등록 상담받기",
    "{time} 접영 킥판 연습하기",
    "{time} 아쿠아로빅 수업 듣기",
    "{time} 수영장 개장시간 맞춰 입수",
    "{time} 물속에서 릴레이 연습",
    "{time} 수영 마스터즈반 훈련 참여",
    "{time} 개인혼영 기록 재보기",
]
SWIMMING_INDIRECT = [
    "{time} 물속에서 몇 바퀴 돌고 나오기",
    "{time} 시원하게 물살 가르며 몸 풀기",
    "{time} 레인 왕복하며 체력 훈련",
]
SWIMMING_SLOTS = {"time": TIME_CASUAL, "laps": ["10바퀴", "20바퀴", "1km", "레인 5개"]}

# ============================================================
# 3. 등산 (hiking)
# ============================================================
HIKING_DIRECT = [
    "{time} 뒷산 등산하기",
    "{time} {mountain} 등산 코스 완주",
    "{time} 새벽 산행 다녀오기",
    "{time} 둘레길 완주 도전",
    "등산화 새로 신고 {mountain} 정상 도전",
    "{time} 트레킹 코스 답사하기",
    "{time} 야간 등산 랜턴 챙겨가기",
    "{time} 계곡 트레킹 다녀오기",
    "{mountain} 정상에서 일출 보기",
    "{time} 등산 스틱 챙겨서 산행",
    "{time} 무박 산행 준비하기",
    "동네 저수지 둘레길 걷기",
    "{time} 낮은 산 가볍게 산행",
]
HIKING_INDIRECT = [
    "{time} 산길 따라 정상까지 걸어 올라가기",
    "{time} 능선 따라 한참 걷다 내려오기",
    "{time} 숨차게 오르막길 오르기",
]
HIKING_SLOTS = {
    "time": TIME_CASUAL,
    "mountain": ["관악산", "북한산", "청계산", "도봉산", "설악산", "지리산", "동네 뒷산", "안산"],
}

# ============================================================
# 4. 문화생활 (culture)
# ============================================================
CULTURE_DIRECT = [
    "{time} 영화관 가서 신작 보기",
    "{time} 조조영화 예매해서 보러가기",
    "좋아하는 가수 콘서트 티켓팅하기",
    "{time} 미술관 전시회 관람",
    "{time} 뮤지컬 예매해서 보러가기",
    "{time} 연극 보러 대학로 가기",
    "{time} 넷플릭스 신작 정주행",
    "좋아하는 밴드 내한 공연 예매",
    "{time} 팝업 전시 구경가기",
    "{time} 영화제 상영작 예매하기",
    "{time} 갤러리 신작 전시 관람",
    "좋아하는 배우 팬미팅 응모",
    "{time} 독립영화관에서 상영작 관람",
    "{time} 클래식 공연 예매하기",
    "{time} 재즈 페스티벌 다녀오기",
    "인기 뮤지컬 재관람 티켓 구하기",
    "{time} 극장에서 액션 영화 보기",
]
CULTURE_INDIRECT = [
    "{time} 극장 가서 팝콘 먹으며 영화 보기",
    "{time} 무대 위 배우들 보러 공연장 가기",
    "{time} 큰 화면으로 신작 몰아보기",
]
CULTURE_SLOTS = {"time": TIME_CASUAL}

# ============================================================
# 5. 금융 (finance)
# ============================================================
FINANCE_DIRECT = [
    "{time} 은행 가서 통장 정리하기",
    "{time} 은행 방문해서 체크카드 재발급",
    "{time} 적금 만기 확인하러 은행 가기",
    "연말정산 서류 준비하기",
    "{time} 공과금 자동이체 등록하기",
    "{time} 환전하러 은행 들르기",
    "새 적금 상품 상담받기",
    "{time} 은행 앱으로 예금 이체하기",
    "{time} 공과금 미납 확인하고 납부",
    "연말정산 간소화 서비스 자료 내려받기",
    "{time} 은행 창구에서 인감 등록",
    "{time} 예금 만기 재예치 상담",
    "{time} 은행 가서 공인인증서 갱신",
    "적금 자동이체일 변경 신청",
]
FINANCE_INDIRECT = [
    "{time} 밀린 공과금 몰아서 납부하기",
    "{time} 통장 잔고 확인하고 정리하기",
    "{time} 카드값 결제일 확인해두기",
]
FINANCE_SLOTS = {"time": TIME_CASUAL}

# ============================================================
# 6. 집안일 (housework)
# ============================================================
HOUSEWORK_DIRECT = [
    "{time} 집 안 청소하기",
    "{time} 화장실 청소하기",
    "{time} 밀린 빨래 돌리기",
    "{time} 이불 빨래하기",
    "{time} 설거지 밀린 거 몰아서 하기",
    "{time} 분리수거 내놓기",
    "{time} 냉장고 정리 겸 청소하기",
    "{time} 창문틀 청소하기",
    "{time} 베란다 청소하기",
    "{time} 화장실 배수구 청소하기",
    "{time} 이불 커버 세탁하기",
    "쓰레기 분리수거하기",
    "{time} 싱크대 정리 겸 설거지",
    "{time} 옷장 정리하고 청소기 돌리기",
    "{time} 방 청소 싹 끝내기",
]
HOUSEWORK_INDIRECT = [
    "{time} 집안 구석구석 먼지 털어내기",
    "{time} 밀린 집안일 몰아서 해치우기",
    "{time} 널브러진 집 안 정리하기",
]
HOUSEWORK_SLOTS = {"time": TIME_CASUAL}

# ============================================================
# 7. 미용 (beauty)
# ============================================================
BEAUTY_DIRECT = [
    "{time} 미용실 예약해서 커트하기",
    "{time} 미용실 가서 염색하기",
    "{time} 네일샵 가서 손톱 관리받기",
    "{time} 네일아트 새로 하러 가기",
    "{time} 왁싱샵 예약하기",
    "{time} 미용실 가서 펌하기",
    "{time} 속눈썹 연장하러 가기",
    "뿌리 염색하러 미용실 가기",
    "{time} 미용실 가서 클리닉 받기",
    "{time} 네일샵 예약 확인하기",
    "{time} 미용실 가서 커트하고 드라이받기",
    "{time} 셀프 네일아트 해보기",
]
BEAUTY_INDIRECT = [
    "{time} 머리 다듬으러 미용실 들르기",
    "{time} 손톱 정리하고 컬러 발라두기",
]
BEAUTY_SLOTS = {"time": TIME_CASUAL}


CATEGORIES = [
    ("달리기", RUNNING_DIRECT + RUNNING_INDIRECT, RUNNING_SLOTS),
    ("수영", SWIMMING_DIRECT + SWIMMING_INDIRECT, SWIMMING_SLOTS),
    ("등산", HIKING_DIRECT + HIKING_INDIRECT, HIKING_SLOTS),
    ("문화생활", CULTURE_DIRECT + CULTURE_INDIRECT, CULTURE_SLOTS),
    ("금융", FINANCE_DIRECT + FINANCE_INDIRECT, FINANCE_SLOTS),
    ("집안일", HOUSEWORK_DIRECT + HOUSEWORK_INDIRECT, HOUSEWORK_SLOTS),
    ("미용", BEAUTY_DIRECT + BEAUTY_INDIRECT, BEAUTY_SLOTS),
]


def main():
    seen = existing_texts()
    print(f"기존 텍스트 {len(seen)}개 로드")

    new_rows = []
    for label, templates, slots in CATEGORIES:
        sentences = gen_sentences(templates, slots, TARGET_PER_CATEGORY, seen)
        print(f"{label}: {len(sentences)}개 생성")
        for s in sentences:
            new_rows.append({"text": s, "label": label})

    with open(PILOT_PATH, "a", encoding="utf-8") as f:
        for row in new_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"\n총 {len(new_rows)}개를 {PILOT_PATH}에 추가함")


if __name__ == "__main__":
    main()
