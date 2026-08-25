# -*- coding: utf-8 -*-
#
# 앱 아이콘 생성 스크립트. Pillow + numpy 필요(pip install pillow numpy). 저장소
# 루트에서 `python assets/icon/gen_icon.py` 실행하면 app_icon.png /
# app_icon_foreground.png / app_icon_background.png 세 장이 이 폴더에 갱신됨.
#
# ⭐ 빠르게 확인하는 법(VS Code에서 직접 만져볼 때) ⭐
#   1) 아래 "TUNABLE KNOBS" 구역의 값만 고침(그 아래 draw_* 함수들은 안 건드려도 됨)
#   2) 저장소 루트에서: python assets/icon/gen_icon.py
#      (1초 내로 끝남 - 세 PNG가 갱신됨)
#   3) VS Code 탐색기에서 assets/icon/app_icon.png를 클릭해서 미리보기 탭으로
#      열어두면, 2번을 다시 실행할 때마다 VS Code가 자동으로 새로고침해줌.
#      이 파일은 "레거시"(적응형 인셋/크롭 없이 그대로 보이는) 버전이라 바늘
#      길이·굵기·배지 크기 등 "비율"을 눈으로 맞추기엔 이걸로 충분함.
#   4) 실제 홈 화면(적응형 마스크 적용 후) 모양까지 최종 확인하고 싶을 때만:
#      dart run flutter_launcher_icons
#      flutter build apk --release --flavor dev
#      flutter install --uninstall-only -d <기기ID> --flavor dev   (아이콘은
#        캐시 때문에 재설치가 아니라 완전 삭제 후 재설치해야 확실히 바뀜)
#      flutter install -d <기기ID> --release --flavor dev
#      (<기기ID>는 `flutter devices`로 확인. 매번 다 돌리면 느리니 3번으로
#      비율을 먼저 다 맞추고 나서 마지막에 한 번만 이 4단계를 돌리는 걸 추천)
#
# ⭐ 2026-08-25 8차 개정(코드 변경 없음, 기록용) - 7차 개정에서는 "아이콘 색을
# 앱 메인 보라(kAppMainAccent)에 맞추자" 방향이었는데, 바로 다음 라운드에서
# 사용자가 "메인색이 꼭 보라일 필요는 없다"며 방향을 뒤집음 - 이제 반대로
# kAppMainAccent 쪽이 이 아이콘의 인디고~블루 톤을 따라가도록 바뀜
# (lib/theme/app_colors.dart 참고). 즉 이 파일의 BG_STOPS가 지금부터 "기준"이고
# 앱 테마가 여기 맞추는 방향 - 나중에 아이콘 그라데이션 색을 또 바꾸면
# app_colors.dart의 kAppMainAccent도 같이 재계산해서 맞출 것.
#
# ⭐ 2026-08-25 6차 개정 - 사용자가 직접 튜닝할 수 있도록 하드코딩되어 있던
# 모든 크기/두께/색 비율을 아래 "TUNABLE KNOBS" 구역의 이름 있는 상수로 전부
# 추출함(이전엔 draw_clock_hands/draw_face_and_bell 안에 r*0.42 식으로 흩어져
# 있어서 조정하려면 함수 내부를 읽어야 했음). 이번 요청으로 같이 바뀐 값:
# 바늘(길이+굵기) 소폭 확대, 시계판 원 소폭 확대, 종 배지 원 소폭 확대, 종
# 글리프 소폭 확대, 시계판 테두리(링) 두께 확대. 종 배지의 흰 테두리는
# "지금 정도가 괜찮다"고 해서 그대로 둠(다만 knob 자체는 만들어둠).
#
# ⭐ 2026-08-25 5차 개정 - "2번"(인디고·앰버) 팔레트로 재교체 + 그라데이션 배경
# 부활. 배경: 인디고에서 시작해 좀 더 밝은 "오로라"색(블루→틴트 청록)으로 끝나는
# 대각선(좌상→우하) 그라데이션(1번 후보 스타일 참고, 시작색만 인디고로 고정).
# 종 배지 색은 앰버(#FFC107) 대신 3/4번과 같은 코랄(#FF7043)로 변경. 배경이
# 다시 그라데이션이라 pubspec.yaml의 adaptive_icon_background도 hex 대신
# app_icon_background.png 이미지 경로로 되돌림 - flutter_launcher_icons 실행 전에
# pubspec.yaml도 같이 확인할 것.
#
# ⭐ 2026-08-25 4차 개정 - 종 배지 원 크기는 그대로 두고 그 안의 종 글리프
# 자체만 키움(배지 원 대비 종이 꽉 차 보이게).
#
# ⭐ 2026-08-25 3차 개정 - 그라데이션을 한 번 뺐다가(단색 팔레트로 교체) 5차
# 개정에서 다시 부활시킨 라운드.
#
# ⭐ 2026-08-25 2차 개정 - 적응형 아이콘 크기 계산을 두 번 잘못 짚었던 경위:
# 처음엔 flutter_launcher_icons가 자동으로 씌우는 <inset 16%>만 보상하려다
# (0.60→0.80) 실기기에서 시계가 아이콘의 90%를 차지하는 반대 방향 실수가 남.
# 원인: 108dp 캔버스 중 실제로 화면에 보이는 건 중앙 66~72dp뿐이고, 이 영역이
# "확대 없이 그대로" 최종 아이콘이 됨(공식 문서: "crop without scaling") -
# 즉 108/70(대략 중간값)≈1.54배만큼 상대적으로 더 커 보이는 효과가 이미
# 있는데 그걸 빠뜨리고 반대로 보정해서 이중으로 커진 것. 최종 공식:
#   실제_보이는_비율 ≈ source_비율 × (1 - 2×인셋) × (108/약70)
# 이 공식으로 목표 비율을 역산해서 source_비율을 구함(아래 build() 참고).

from PIL import Image, ImageDraw
import numpy as np
import math

SIZE = 1024

# ============================================================
# ⭐ TUNABLE KNOBS ⭐ - 여기 값들만 고치면 됨. draw_* 함수들은
# 전부 이 상수를 참조해서 그리므로 함수 내부를 건드릴 필요 없음.
# ============================================================

# --- 색상 ---------------------------------------------------

# 배경 그라데이션 색 - 좌상단(시작)→우하단(끝) 방향으로 이 순서대로 이어짐.
# 색을 늘리거나 줄이려면 아래 BG_STOP_POSITIONS도 같이 원소 개수를 맞출 것.
#
# ⭐ 2026-08-25 7차 개정 - 앱 메인 테마색(kAppMainAccent = #6A4FD9, 보라)과
# 아이콘 색(원래 인디고/블루 쪽)이 살짝 안 맞는다는 피드백. 그렇다고 바로
# 보라로 바꾸긴 부담스럽다고 해서, 시작/중간 색만 kAppMainAccent 쪽으로
# 15~20%만 블렌드해서 "그라데이션은 그대로, 톤만 살짝 보라 쪽" 으로 이동.
# 끝 색(청록/오로라)은 그대로 - 여기까지 보라로 밀면 정체성이 흐려짐.
BG_STOPS = [
    (0x48, 0x50, 0xBC),  # 인디고 (좌상단, 시작색) - 보라 쪽으로 20% 블렌드
    (0x44, 0x74, 0xF1),  # 블루 (중간) - 보라 쪽으로 15% 블렌드
    (0x1D, 0xE1, 0xC7),  # 밝은 청록/오로라 (우하단, 끝색) - 그대로
]
# 위 BG_STOPS 각 색이 그라데이션의 어느 "위치"(0.0=좌상단 ~ 1.0=우하단)에
# 오는지. 기본은 균등 배치(0, 0.5, 1) - 예를 들어 인디고가 더 오래 유지되게
# 하려면 [0.0, 0.65, 1.0]처럼 중간 색 위치를 뒤로 밀면 됨. BG_STOPS와 길이가
# 같아야 하고, 반드시 0.0으로 시작해서 1.0으로 끝나는 오름차순이어야 함.
BG_STOP_POSITIONS = [0.0, 0.7, 1.0]

HANDS = (0x1A, 0x23, 0x7E)          # 시계 바늘 색 (다크 네이비)
FACE_BORDER_COLOR = HANDS           # 시계판 원 테두리(링) 색 - 기본은 바늘과 동일
BELL_BG = (0xFF, 0x70, 0x43)        # 종 배지 원 배경색 (코랄)
BELL_GLYPH_COLOR = (0xFF, 0xFF, 0xFF)   # 종 글리프(종 모양 자체) 색
BADGE_BORDER_COLOR = (0xFF, 0xFF, 0xFF) # 종 배지 원의 바깥 테두리(흰 띠) 색

# --- 크기/두께 (전부 "시계판 반지름 r 대비 비율") -------------

# 시계판(흰 원) 지름 - 전체 아이콘 대비 얼마나 큰지. 레거시(배경 포함 정사각
# 아이콘)와 적응형(홈 화면 실제 노출분) 두 버전이 최종 화면 노출 크기가
# 서로 다르게 계산되므로 따로 존재함 - 12행 아래 "6차 개정" 주석 및 파일
# 상단 "2차 개정" 공식 설명 참고. 지난 라운드 대비 소폭 확대(0.62→0.65,
# 0.59→0.62).
LEGACY_FACE_RATIO = 0.70
ADAPTIVE_TARGET_FINAL_RATIO = 0.67

# 시침/분침 길이 (r 대비 비율). 소폭 확대(0.42→0.46, 0.62→0.68).
HAND_HOUR_LENGTH_RATIO = 0.46
HAND_MINUTE_LENGTH_RATIO = 0.68
# 시침/분침 굵기 (r 대비 비율, 최소 픽셀값은 draw_clock_hands 안의 max()로
# 보장됨). 소폭 확대(0.11→0.12, 0.08→0.09).
HAND_HOUR_WIDTH_RATIO = 0.13
HAND_MINUTE_WIDTH_RATIO = 0.10
# 바늘 중심 축(피벗) 원 반지름 (r 대비 비율) - 이번 라운드에서 요청 없어 유지.
HAND_PIVOT_RADIUS_RATIO = 0.07
# 시계판 테두리(링) 두께 (r 대비 비율) - "약간 더 두껍게" 요청으로 확대
# (0.035→0.05).
FACE_BORDER_WIDTH_RATIO = 0.10

# 종 배지 원 반지름 (시계판 반지름 r 대비 비율). 소폭 확대(0.30→0.33).
BADGE_RADIUS_RATIO = 0.33
# 종 배지가 시계판 테두리에 겹치는 정도 (1.0=배지 중심이 시계판 테두리 선
# 위, 작을수록 시계판 안쪽으로 더 들어옴) - 이번 라운드에서 요청 없어 유지.
BADGE_OVERLAP_RATIO = 0.95
# 종 배지의 바깥 흰 테두리 두께 (badge_r 대비 비율) - "종 원(배지)은 지금이
# 괜찮다"고 해서 이번엔 그대로 둠. 조정하고 싶으면 이 값만 고치면 됨.
BADGE_BORDER_WIDTH_RATIO = 0.14
# 종 글리프(배지 안 종 모양) 크기 (badge_r 대비 비율). 소폭 확대(0.76→0.82).
BELL_GLYPH_SCALE_RATIO = 0.92
# 종 글리프를 배지 중심에서 아래로 얼마나 내릴지 (badge_r 대비 비율, 양수 =
# 아래로) - 종 모양 자체가 위쪽에 쏠려 그려져서(돔+손잡이가 위로 많이 뻗음)
# 배지 중심(cy)에 맞춰 그리면 시각적으로 위에 붙어 보임. "종이 위쪽에 붙어
# 보인다"는 피드백으로 추가 - 0이면 예전처럼 중심 기준 그대로.
BELL_GLYPH_Y_OFFSET_RATIO = 0.08

# --- 적응형 아이콘 인셋/크롭 계산 (임의로 건드리지 말 것) -------
# flutter_launcher_icons가 자동으로 씌우는 인셋 비율 - mipmap-anydpi-v26/
# ic_launcher.xml의 <inset android:inset="..."/> 값과 반드시 같아야 함.
ADAPTIVE_AUTO_INSET = 0.16
# 108dp 캔버스 중 실제로 화면에 "확대 없이 그대로" 보이는 영역의 지름(dp).
ADAPTIVE_VISIBLE_WINDOW_DP = 70.0
CANVAS_DP = 108.0

# ============================================================
# 아래부터는 위 knob들을 그대로 사용해서 그리는 로직 - 보통은 건드릴 필요 없음.
# ============================================================

def rounded_mask(w, h, radius):
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, w-1, h-1], radius=radius, fill=255)
    return mask

def make_gradient(w, h, stops, positions):
    # 좌상단(0,0) → 우하단(w,h) 대각선 방향 다단(multi-stop) 그라데이션.
    # Flutter 쪽 정적/애니메이션 배경(topLeft→bottomRight 기준)과 동일한
    # 방향이라 나중에 Flutter의 회전 애니메이션 시작 각도를 맞출 때도 기준이 됨.
    assert len(stops) == len(positions), "BG_STOPS와 BG_STOP_POSITIONS 길이가 달라요"
    xs = np.linspace(0.0, 1.0, w)
    ys = np.linspace(0.0, 1.0, h)
    xv, yv = np.meshgrid(xs, ys)
    t = (xv + yv) / 2.0  # 0=좌상단, 1=우하단

    stops_arr = np.array(stops, dtype=np.float64)
    pos_arr = np.array(positions, dtype=np.float64)
    # 각 픽셀의 t가 어느 구간(pos[i]~pos[i+1])에 속하는지 찾아서 그 구간 안에서
    # 선형 보간(np.interp를 채널별로 적용하는 것과 동일한 효과).
    idx = np.clip(np.searchsorted(pos_arr, t, side="right") - 1, 0, len(pos_arr) - 2)
    seg_start = pos_arr[idx]
    seg_end = pos_arr[idx + 1]
    seg_len = np.where(seg_end - seg_start == 0, 1.0, seg_end - seg_start)
    frac = ((t - seg_start) / seg_len)[..., None]
    c0 = stops_arr[idx]
    c1 = stops_arr[idx + 1]
    rgb = c0 + (c1 - c0) * frac
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    alpha = np.full((h, w, 1), 255, dtype=np.uint8)
    arr = np.concatenate([rgb, alpha], axis=-1)
    return Image.fromarray(arr, "RGBA")

def draw_clock_hands(draw, cx, cy, r, color):
    # 4시 정각: 시침(짧고 두꺼움)은 "4" 방향, 분침(길고 얇음)은 "12" 방향.
    # 각도 계산: clock_angle(12시=0, 시계방향 증가)을 math_angle=-90+clock_angle로
    # 변환(이미지 좌표는 y가 아래로 증가하므로 x=cx+len*cos, y=cy+len*sin로 그대로 사용).
    hour_len = r * HAND_HOUR_LENGTH_RATIO
    minute_len = r * HAND_MINUTE_LENGTH_RATIO
    hour_ang = math.radians(-90 + 4 * 30)   # 4시 방향(시침)
    minute_ang = math.radians(-90 + 0)      # 12시 방향(분침, 0분)
    hx = cx + hour_len * math.cos(hour_ang)
    hy = cy + hour_len * math.sin(hour_ang)
    mx = cx + minute_len * math.cos(minute_ang)
    my = cy + minute_len * math.sin(minute_ang)
    draw.line([(cx, cy), (hx, hy)], fill=color, width=max(6, int(r*HAND_HOUR_WIDTH_RATIO)))
    draw.line([(cx, cy), (mx, my)], fill=color, width=max(5, int(r*HAND_MINUTE_WIDTH_RATIO)))
    # 중심 축(피벗) 작은 원
    pr = max(4, int(r*HAND_PIVOT_RADIUS_RATIO))
    draw.ellipse([cx-pr, cy-pr, cx+pr, cy+pr], fill=color)
    # 시계 테두리 링 (흰 원과 배경 경계를 또렷하게)
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=FACE_BORDER_COLOR, width=max(3, int(r*FACE_BORDER_WIDTH_RATIO)))

def draw_bell(draw, cx, cy, s, color):
    # 종 모양을 도형 조합으로 근사: 돔(상단 반원) + 몸통(사다리꼴) + 손잡이(작은 원) + 추(작은 원)
    body_top = cy - s*0.55
    body_bottom = cy + s*0.30
    dome_w = s*0.62
    base_w = s*0.90
    # 돔(위쪽 반원)
    draw.pieslice([cx-dome_w/2, body_top-dome_w/2, cx+dome_w/2, body_top+dome_w/2], 180, 360, fill=color)
    # 몸통(사다리꼴 - 아래로 갈수록 넓어짐)
    draw.polygon([
        (cx-dome_w/2, body_top),
        (cx+dome_w/2, body_top),
        (cx+base_w/2, body_bottom),
        (cx-base_w/2, body_bottom),
    ], fill=color)
    # 받침(살짝 둥근 바닥 라인)
    draw.pieslice([cx-base_w/2, body_bottom-s*0.10, cx+base_w/2, body_bottom+s*0.10], 0, 180, fill=color)
    # 손잡이(꼭대기 작은 원)
    knob_r = s*0.07
    draw.ellipse([cx-knob_r, body_top-dome_w/2-knob_r*0.6, cx+knob_r, body_top-dome_w/2+knob_r*1.2], fill=color)
    # 추(아래 작은 원)
    clap_r = s*0.11
    draw.ellipse([cx-clap_r, body_bottom+s*0.14-clap_r, cx+clap_r, body_bottom+s*0.14+clap_r], fill=color)

def draw_face_and_bell(img, face_d_ratio):
    draw = ImageDraw.Draw(img)
    cx, cy = SIZE/2, SIZE/2
    r = SIZE * face_d_ratio / 2
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(0xFF, 0xFF, 0xFF))
    draw_clock_hands(draw, cx, cy, r, HANDS)

    # 종 배지 - 시계 원 테두리에 살짝 겹치도록(2시 방향=45°) 배치해서 "하나의
    # 배지"처럼 보이게 함. 크기는 시계 지름 비례.
    badge_r = r * BADGE_RADIUS_RATIO
    bx = cx + r * BADGE_OVERLAP_RATIO * math.cos(math.radians(-45))
    by = cy + r * BADGE_OVERLAP_RATIO * math.sin(math.radians(-45))
    border_w = max(6, int(badge_r * BADGE_BORDER_WIDTH_RATIO))
    draw.ellipse([bx-badge_r-border_w, by-badge_r-border_w, bx+badge_r+border_w, by+badge_r+border_w], fill=BADGE_BORDER_COLOR)
    draw.ellipse([bx-badge_r, by-badge_r, bx+badge_r, by+badge_r], fill=BELL_BG)
    draw_bell(draw, bx, by + badge_r*BELL_GLYPH_Y_OFFSET_RATIO, badge_r*BELL_GLYPH_SCALE_RATIO, BELL_GLYPH_COLOR)

def build_legacy(out_path: str):
    # 배경 있는 레거시 아이콘 - 그라데이션 + 둥근 사각 마스크 + 시계/종.
    gradient = make_gradient(SIZE, SIZE, BG_STOPS, BG_STOP_POSITIONS)
    mask = rounded_mask(SIZE, SIZE, int(SIZE*0.23))
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(gradient, (0, 0), mask)
    draw_face_and_bell(img, LEGACY_FACE_RATIO)
    img.save(out_path)
    print("saved", out_path, img.size, "face_d_ratio=%.3f" % LEGACY_FACE_RATIO)

def build_adaptive_foreground(out_path: str):
    # 적응형 아이콘 전경 - 배경 없이 시계/종만(투명), 배경은 별도 레이어.
    visible_scale_up = CANVAS_DP / ADAPTIVE_VISIBLE_WINDOW_DP  # ≈1.54
    face_d_ratio = ADAPTIVE_TARGET_FINAL_RATIO / ((1 - 2 * ADAPTIVE_AUTO_INSET) * visible_scale_up)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_face_and_bell(img, face_d_ratio)
    img.save(out_path)
    print("saved", out_path, img.size, "face_d_ratio=%.3f" % face_d_ratio)

def build_adaptive_background(out_path: str):
    # 적응형 아이콘 배경 레이어 - 마스크/둥근모서리 없이 그라데이션 전체 채움
    # (마스크는 OS가 알아서 씌움). flutter_launcher_icons의
    # adaptive_icon_background 옵션에 이 경로를 그대로 지정.
    gradient = make_gradient(SIZE, SIZE, BG_STOPS, BG_STOP_POSITIONS).convert("RGB")
    gradient.save(out_path)
    print("saved", out_path, gradient.size)

build_legacy("assets/icon/app_icon.png")
build_adaptive_foreground("assets/icon/app_icon_foreground.png")
build_adaptive_background("assets/icon/app_icon_background.png")
print("배경이 그라데이션 이미지라 pubspec.yaml의 adaptive_icon_background는 hex가 아니라 assets/icon/app_icon_background.png 경로여야 함(이미 그렇게 되어있으면 그대로 두면 됨).")
