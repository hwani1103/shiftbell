# -*- coding: utf-8 -*-
#
# 앱 아이콘 생성 스크립트. Pillow + numpy 필요(pip install pillow numpy). 저장소
# 루트에서 `python assets/icon/gen_icon.py` 실행하면 app_icon.png /
# app_icon_foreground.png / app_icon_background.png 세 장이 이 폴더에 갱신됨 -
# 그 다음 `dart run flutter_launcher_icons`로 실제 android/app/src/main/res/mipmap-*/
# 아이콘에 반영. 색만 바꾸고 싶으면 아래 BG_STOPS/HANDS/BELL_BG 상수만 고치면 됨.
#
# ⭐ 2026-08-25 5차 개정 - "2번"(인디고·앰버) 팔레트로 재교체 + 그라데이션 배경
# 부활. 배경: 인디고에서 시작해 좀 더 밝은 "오로라"색(블루→틴트 청록)으로 끝나는
# 대각선(좌상→우하) 그라데이션(1번 후보 스타일 참고, 시작색만 인디고로 고정).
# 종 배지 색은 앰버(#FFC107) 대신 3/4번과 같은 코랄(#FF7043)로 변경. 배경이
# 다시 그라데이션이라 pubspec.yaml의 adaptive_icon_background도 hex 대신
# app_icon_background.png 이미지 경로로 되돌림 - flutter_launcher_icons 실행 전에
# pubspec.yaml도 같이 확인할 것.
#
# ⭐ 2026-08-25 4차 개정 - 최종 확정(네이비/골드/코랄). 종 배지 원 크기(badge_r)는
# 그대로 두고, 그 안의 종 글자(글리프) 자체만 키워달라는 요청으로 draw_bell
# 호출 시 크기 배율을 0.62 → 0.76으로 올림(배지 원 대비 종이 꽉 차 보이게).
# 이 비율은 이번 개정에서도 그대로 유지.
#
# ⭐ 2026-08-25 3차 개정 - "오로라 페일"(그라데이션) 대신 예전 팔레트 후보 중
# "17번"(네이비/골드/코랄, 채도가 더 쨍함)으로 교체했던 라운드. 배경이 단색이라
# 그라데이션 계산이 필요 없어져서 그때 한 번 제거했던 걸 이번에 다시 부활시킴.
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

# 확정된 아이콘 색상 - "2번"(인디고·앰버) 팔레트를 그라데이션+코랄 종으로 변형.
# 배경: 인디고(시작) → 살짝 밝은 오로라 블루 → 밝은 청록(끝) 대각선 그라데이션.
BG_STOPS = [
    (0x3F, 0x51, 0xB5),  # 인디고 (좌상단, 시작색)
    (0x3D, 0x7B, 0xF5),  # 블루 (중간)
    (0x1D, 0xE1, 0xC7),  # 밝은 청록/오로라 (우하단, 끝색)
]
HANDS = (0x1A, 0x23, 0x7E)   # 다크 네이비 (시계 바늘 - 흰 시계판 위 대비용)
BELL_BG = (0xFF, 0x70, 0x43) # 코랄 (종 배지 배경, 3/4번과 동일)
WHITE = (0xFF, 0xFF, 0xFF)

# flutter_launcher_icons가 적응형 아이콘 foreground에 자동으로 씌우는 인셋 비율.
# mipmap-anydpi-v26/ic_launcher.xml의 <inset android:inset="..."/> 값과 반드시
# 같아야 함 - 어긋나면 다시 크기가 안 맞게 됨.
ADAPTIVE_AUTO_INSET = 0.16

# 108dp 캔버스 중 실제로 화면에 "확대 없이 그대로" 보이는 영역의 지름(dp) -
# 공식 스펙은 66(세이프존, 모든 마스크에서 보장)~72(원형 등 덜 공격적인
# 마스크의 최대치) 사이. 실기기 관찰값으로 역산한 값과도 잘 맞는 70을 씀.
ADAPTIVE_VISIBLE_WINDOW_DP = 70.0
CANVAS_DP = 108.0

# 레거시(배경 포함) 아이콘의 시계 지름 비율(인셋/크롭 영향 없이 그린 그대로
# 보임) / 적응형 foreground의 최종 화면 노출 목표 비율.
LEGACY_FACE_RATIO = 0.62
ADAPTIVE_TARGET_FINAL_RATIO = 0.59

def rounded_mask(w, h, radius):
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, w-1, h-1], radius=radius, fill=255)
    return mask

def make_gradient(w, h, stops):
    # 좌상단(0,0) → 우하단(w,h) 대각선 방향 다단(multi-stop) 그라데이션.
    # Flutter 쪽 정적 배경(Alignment.topLeft → bottomRight)과 동일한 방향이라
    # 나중에 Flutter에서 회전 애니메이션의 시작 각도를 맞출 때도 기준이 됨.
    xs = np.linspace(0.0, 1.0, w)
    ys = np.linspace(0.0, 1.0, h)
    xv, yv = np.meshgrid(xs, ys)
    t = (xv + yv) / 2.0  # 0=좌상단, 1=우하단

    stops_arr = np.array(stops, dtype=np.float64)
    n = len(stops_arr) - 1
    seg = np.clip(t * n, 0.0, n - 1e-9)
    idx = seg.astype(int)
    frac = (seg - idx)[..., None]
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

def draw_face_and_bell(img, face_d_ratio):
    draw = ImageDraw.Draw(img)
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
    draw_bell(draw, bx, by, badge_r*0.76, WHITE)

def build_legacy(out_path: str):
    # 배경 있는 레거시 아이콘 - 그라데이션 + 둥근 사각 마스크 + 시계/종.
    gradient = make_gradient(SIZE, SIZE, BG_STOPS)
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
    gradient = make_gradient(SIZE, SIZE, BG_STOPS).convert("RGB")
    gradient.save(out_path)
    print("saved", out_path, gradient.size)

build_legacy("assets/icon/app_icon.png")
build_adaptive_foreground("assets/icon/app_icon_foreground.png")
build_adaptive_background("assets/icon/app_icon_background.png")
print("배경이 다시 그라데이션 이미지라 pubspec.yaml의 adaptive_icon_background를 hex가 아니라 assets/icon/app_icon_background.png 경로로 지정해야 함.")
