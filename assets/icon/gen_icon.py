# -*- coding: utf-8 -*-
#
# 앱 아이콘("오로라 페일" 확정 디자인) 생성 스크립트. Pillow(PIL)만 있으면 됨
# (pip install pillow). 저장소 루트에서 `python assets/icon/gen_icon.py` 실행하면
# app_icon.png / app_icon_foreground.png / app_icon_background.png 세 장이
# 이 폴더에 갱신됨 - 그 다음 `flutter pub run flutter_launcher_icons`로 실제
# android/app/src/main/res/mipmap-*/ 아이콘에 반영. 색만 바꾸고 싶으면 아래
# GRAD/HANDS/BELL_BG 상수만 고치면 됨.

from PIL import Image, ImageDraw
import math

SIZE = 1024

# 확정된 "오로라 페일" 아이콘 색상
GRAD = [(0xDA,0xCE,0xF9), (0xCE,0xDE,0xFC), (0xBF,0xF5,0xF1)]  # 라벤더 -> 스카이 -> 민트
HANDS = (0x3B,0x2E,0x7A)   # 짙은 남색 (시계 바늘)
BELL_BG = (0xEF,0x6C,0x00) # 앰버/오렌지 (종 배지 배경)
WHITE = (0xFF,0xFF,0xFF)

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
    # 시침(짧고 두꺼움, 10시 방향) + 분침(길고 얇음, 2시 방향) - 흔한 시계 아이콘 관습(10:10)
    hour_len = r * 0.42
    minute_len = r * 0.62
    hour_ang = math.radians(-90 - 60)   # 10시 방향
    minute_ang = math.radians(-90 + 60) # 2시 방향
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

    # 시계 얼굴(흰 원) - 캔버스 대비 지름 비율. 적응형 아이콘 safe-zone(중앙 ~66%)을
    # 감안해 배경 없는 foreground 레이어는 조금 더 안쪽으로 당김.
    face_d_ratio = 0.60 if not with_background else 0.66
    cx, cy = SIZE/2, SIZE/2
    r = SIZE * face_d_ratio / 2
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=WHITE)
    draw_clock_hands(draw, cx, cy, r, HANDS)

    # 종 배지 - 2시 방향, 우상단(foreground 레이어는 safe-zone 감안해 살짝 작게)
    badge_r = SIZE * (0.135 if not with_background else 0.145)
    bx = SIZE * 0.855
    by = SIZE * 0.145
    border_w = max(6, int(SIZE*0.012))
    draw.ellipse([bx-badge_r-border_w, by-badge_r-border_w, bx+badge_r+border_w, by+badge_r+border_w], fill=WHITE)
    draw.ellipse([bx-badge_r, by-badge_r, bx+badge_r, by+badge_r], fill=BELL_BG)
    draw_bell(draw, bx, by, badge_r*0.62, WHITE)

    img.save(out_path)
    print("saved", out_path, img.size)

build(True, "assets/icon/app_icon.png")             # 레거시(배경 포함) 아이콘
build(False, "assets/icon/app_icon_foreground.png") # 적응형 아이콘 전경(투명 배경)

# 적응형 아이콘 배경 레이어(그라데이션 단독, 불투명)
bg_only = make_gradient(SIZE, SIZE)
bg_only.save("assets/icon/app_icon_background.png")
print("saved assets/icon/app_icon_background.png", bg_only.size)
