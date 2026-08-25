# -*- coding: utf-8 -*-
#
# 앱 아이콘("오로라 페일" 확정 디자인) 생성 스크립트. Pillow(PIL)만 있으면 됨
# (pip install pillow). 저장소 루트에서 `python assets/icon/gen_icon.py` 실행하면
# app_icon.png / app_icon_foreground.png / app_icon_background.png 세 장이
# 이 폴더에 갱신됨 - 그 다음 `dart run flutter_launcher_icons`로 실제
# android/app/src/main/res/mipmap-*/ 아이콘에 반영. 색만 바꾸고 싶으면 아래
# GRAD/HANDS/BELL_BG 상수만 고치면 됨.
#
# ⭐ 2026-08-25 2차 개정 - 실기기 설치 후 "샘플이랑 완전 딴판"이라는 피드백으로
# 원인 조사한 결과: flutter_launcher_icons가 적응형 아이콘 foreground를 생성할
# 때 android/.../mipmap-anydpi-v26/ic_launcher.xml에 자동으로
# <inset android:inset="16%"/>를 씌움(=68% 크기로 축소) - 이걸 보상하려고
# foreground 지름 비율을 0.60→0.80으로 키웠는데, 그 결과 "이제 시계가 아이콘의
# 90%를 차지한다"는 정반대 피드백을 받음. 원인: 인셋 보상 계산에서 안드로이드
# 적응형 아이콘의 두 번째 단계를 빠뜨림 - 108dp 캔버스 중 실제로 화면에 보이는
# 건 중앙 66~72dp뿐이고(나머지 18dp 안팎은 마스킹용 여백), 이 보이는 영역이
# "확대 없이 그대로" 최종 아이콘이 됨(공식 문서: "crop without scaling"). 즉
# 내 그림이 108dp 캔버스에서 차지하는 비율이 아니라, 그 중 실제로 보이는
# 66~72dp 영역에서 차지하는 비율이 최종 크기가 됨 - 108/70(대략 중간값)≈1.54배
# 만큼 한 번 더 "확대돼 보이는" 효과가 생기는데 이걸 빠뜨리고 오히려 반대
# 방향(더 키우는 쪽)으로 보정해서 이중으로 커져버린 것.
#
# 최종 공식: 실제_보이는_비율 ≈ source_비율 × (1-2×인셋) × (108/약70)
# 실기기 관찰값(source=0.80 → 실제 약 0.90)으로 역산한 계수(≈1.05~1.1)와
# 공식 문서 수치(66~72dp)가 서로 잘 맞음 - 이 계수를 써서 다시 계산:
#   1. foreground(적응형): 최종 0.55를 목표로 역산 → source ≈ 0.55/1.06 ≈ 0.52
#      (처음 값 0.60에 더 가까움 - 애초에 "인셋 때문에 작아 보인다"는 첫 진단
#      자체가 틀렸었고, 실제 문제는 아래 3번 종 위치였던 것으로 결론)
#   2. 레거시(배경 포함) 아이콘: 인셋/크롭 영향이 없어 그대로 보이므로 0.58 유지.
#   3. 종 배지를 시계 원 모서리에서 멀리 띄우지 말고, 원 테두리에 약간
#      겹치도록(overlap) 위치를 원 중심 기준 반지름의 95% 지점에 배치 -
#      "하나의 배지"처럼 보이게 함. 배지 크기도 시계 지름의 30%로 통일(예전엔
#      절대 크기라 배율이 안 맞았음).
#   4. 시계 바늘을 "4시 정각"(시침=4, 분침=12) 방향으로 변경.
#   5. 색상 자체는 직접 렌더링해서 재확인함(라벤더~스카이~민트 그라데이션 /
#      흰 시계 얼굴 / 짙은 남색 바늘 / 앰버 종배지+흰 테두리) - 문제 없음, 유지.

from PIL import Image, ImageDraw
import math

SIZE = 1024

# 확정된 "오로라 페일" 아이콘 색상
GRAD = [(0xDA,0xCE,0xF9), (0xCE,0xDE,0xFC), (0xBF,0xF5,0xF1)]  # 라벤더 -> 스카이 -> 민트
HANDS = (0x3B,0x2E,0x7A)   # 짙은 남색 (시계 바늘)
BELL_BG = (0xEF,0x6C,0x00) # 앰버/오렌지 (종 배지 배경)
WHITE = (0xFF,0xFF,0xFF)

# flutter_launcher_icons가 적응형 아이콘 foreground에 자동으로 씌우는 인셋 비율.
# mipmap-anydpi-v26/ic_launcher.xml의 <inset android:inset="..."/> 값과 반드시
# 같아야 함 - 어긋나면 다시 크기가 안 맞게 됨.
ADAPTIVE_AUTO_INSET = 0.16

# 108dp 캔버스 중 실제로 화면에 "확대 없이 그대로" 보이는 영역의 지름(dp) -
# 공식 스펙은 66(세이프존, 모든 마스크에서 보장)~72(원형 등 덜 공격적인
# 마스크의 최대치) 사이. 실기기 관찰값으로 역산한 값과도 잘 맞는 70을 씀.
ADAPTIVE_VISIBLE_WINDOW_DP = 70.0
CANVAS_DP = 108.0

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i]-a[i])*t) for i in range(3))

def grad_color(t):
    t = max(0.0, min(1.0, t))
    if t <= 0.5:
        return lerp(GRAD[0], GRAD[1], t/0.5)
    else:
        return lerp(GRAD[1], GRAD[2], (t-0.5)/0.5)

def make_gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x/w + y/h) / 2.0
            px[x, y] = grad_color(t)
    return img

def rounded_mask(w, h, radius):
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, w-1, h-1], radius=radius, fill=255)
    return mask

def draw_clock_hands(draw, cx, cy, r, color):
    # 4시 정각: 시침(짧고 두꺼움)은 "4" 방향, 분침(길고 얇음)은 "12" 방향.
    # 각도 계산: clock_angle(12시=0, 시계방향 증가)을 math_angle=-90+clock_angle로
    # 변환(이미지 좌표는 y가 아래로 증가하므로 x=cx+len*cos, y=cy+len*sin로 그대로 사용).
    hour_len = r * 0.42
    minute_len = r * 0.62
    hour_ang = math.radians(-90 + 4 * 30)   # 4시 방향(시침)
    minute_ang = math.radians(-90 + 0)      # 12시 방향(분침, 0분)
    hx = cx + hour_len * math.cos(hour_ang)
    hy = cy + hour_len * math.sin(hour_ang)
    mx = cx + minute_len * math.cos(minute_ang)
    my = cy + minute_len * math.sin(minute_ang)
    draw.line([(cx, cy), (hx, hy)], fill=color, width=max(6, int(r*0.11)))
    draw.line([(cx, cy), (mx, my)], fill=color, width=max(5, int(r*0.08)))
    # 중심 축(피벗) 작은 원
    pr = max(4, int(r*0.07))
    draw.ellipse([cx-pr, cy-pr, cx+pr, cy+pr], fill=color)
    # 시계 테두리 링 (살짝, 흰 원과 배경 경계를 또렷하게)
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=color, width=max(3, int(r*0.035)))

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

def build(with_background: bool, out_path: str):
    img = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    if with_background:
        grad = make_gradient(SIZE, SIZE).convert("RGBA")
        mask = rounded_mask(SIZE, SIZE, int(SIZE*0.23))
        img.paste(grad, (0,0), mask)

    draw = ImageDraw.Draw(img)

    # 시계 얼굴(흰 원) - 캔버스 대비 지름 비율.
    # - 레거시(배경 포함) 아이콘: 인셋/크롭 영향이 없어 그린 그대로 보임. 0.58.
    # - 적응형 foreground: 최종 화면에 보이는 비율이 레거시와 비슷해지도록
    #   (목표 0.55) 역산 - 인셋(16%×2)으로 한 번 줄고, "108dp 중 실제 보이는
    #   70dp 영역이 확대 없이 그대로 최종 아이콘이 되는" 단계에서 상대적으로
    #   한 번 더 커 보이므로, 그 두 단계를 거꾸로 계산해서 source 비율을 구함.
    TARGET_FINAL_RATIO = 0.55
    if with_background:
        face_d_ratio = 0.58
    else:
        visible_scale_up = CANVAS_DP / ADAPTIVE_VISIBLE_WINDOW_DP  # ≈1.54
        face_d_ratio = TARGET_FINAL_RATIO / ((1 - 2 * ADAPTIVE_AUTO_INSET) * visible_scale_up)  # ≈0.52
    cx, cy = SIZE/2, SIZE/2
    r = SIZE * face_d_ratio / 2
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=WHITE)
    draw_clock_hands(draw, cx, cy, r, HANDS)

    # 종 배지 - 시계 원 테두리에 살짝 겹치도록(중심에서 반지름의 95% 지점, 2시
    # 방향=45°) 배치해서 "하나의 배지"처럼 보이게 함. 크기는 시계 지름 비례.
    badge_r = r * 0.30
    overlap_k = 0.95
    bx = cx + r * overlap_k * math.cos(math.radians(-45))
    by = cy + r * overlap_k * math.sin(math.radians(-45))
    border_w = max(6, int(badge_r * 0.14))
    draw.ellipse([bx-badge_r-border_w, by-badge_r-border_w, bx+badge_r+border_w, by+badge_r+border_w], fill=WHITE)
    draw.ellipse([bx-badge_r, by-badge_r, bx+badge_r, by+badge_r], fill=BELL_BG)
    draw_bell(draw, bx, by, badge_r*0.62, WHITE)

    img.save(out_path)
    print("saved", out_path, img.size, "face_d_ratio=%.3f" % face_d_ratio)

build(True, "assets/icon/app_icon.png")             # 레거시(배경 포함) 아이콘
build(False, "assets/icon/app_icon_foreground.png") # 적응형 아이콘 전경(투명 배경)

# 적응형 아이콘 배경 레이어(그라데이션 단독, 불투명)
bg_only = make_gradient(SIZE, SIZE)
bg_only.save("assets/icon/app_icon_background.png")
print("saved assets/icon/app_icon_background.png", bg_only.size)
