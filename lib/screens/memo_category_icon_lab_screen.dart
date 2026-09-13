// lib/screens/memo_category_icon_lab_screen.dart
//
// ⭐ 2026-08-27 - 메모 자동분류(ml/, 메모_자동분류_ML_계획.md) Phase 5용으로 받아온
// 카테고리 아이콘 10종(assets/icons/memo_category/, Lucide SVG)을 실제 Flutter
// 렌더링 파이프라인(flutter_svg + colorFilter)에 태워 한눈에 확인하기 위한 임시
// 미리보기 화면. calendar_theme_lab_screen/ui_theme_lab_screen과 같은 용도(후보를
// 실제 렌더링으로 눈으로 비교) - 어디에도 라우팅 안 돼 있으므로 확인할 땐
// main.dart의 home을 잠깐 이걸로 바꿔서 실행할 것. 다 쓰고 나면(카테고리 아이콘이
// 실제 화면에 적용되고 나면) 이 파일은 지워도 됨.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// assets/icons/memo_category/README.md의 매핑과 동일하게 유지할 것.
/// ⭐ 2026-09-01 - 10종 -> 17종(7개 신설). 2026-09-03 - 17종 -> 19종(자전거/
/// 요가·필라테스 신설). 2026-09-12 - 19종 -> 25종("운동"에서 6종 세분화 -
/// 라켓 스포츠/축구/농구/야구/구기종목/입식 격투기). lib/screens/
/// schedule_management_tab.dart의 _kScheduleCategoryIcons도 같은 목록.
const List<(String key, String label, String asset)> kMemoCategoryIcons = [
  ('work', '업무', 'assets/icons/memo_category/work.svg'),
  ('study', '공부', 'assets/icons/memo_category/study.svg'),
  ('exercise', '운동', 'assets/icons/memo_category/exercise.svg'),
  ('health', '병원·건강관리', 'assets/icons/memo_category/health.svg'),
  ('meal', '식사', 'assets/icons/memo_category/meal.svg'),
  ('social', '약속/사교', 'assets/icons/memo_category/social.svg'),
  ('family', '가족', 'assets/icons/memo_category/family.svg'),
  ('shopping', '쇼핑', 'assets/icons/memo_category/shopping.svg'),
  ('leisure', '여가/휴식', 'assets/icons/memo_category/leisure.svg'),
  ('running', '달리기', 'assets/icons/memo_category/running.svg'),
  ('swimming', '수영', 'assets/icons/memo_category/swimming.svg'),
  ('hiking', '등산', 'assets/icons/memo_category/hiking.svg'),
  ('culture', '문화생활', 'assets/icons/memo_category/culture.svg'),
  ('finance', '금융', 'assets/icons/memo_category/finance.svg'),
  ('housework', '집안일', 'assets/icons/memo_category/housework.svg'),
  ('beauty', '미용', 'assets/icons/memo_category/beauty.svg'),
  ('cycling', '자전거', 'assets/icons/memo_category/cycling.svg'),
  ('yoga', '요가/필라테스', 'assets/icons/memo_category/yoga.svg'),
  // ⭐ 2026-09-01 - etc.svg를 순수 도형 10종(etc1~10)으로 교체 확정 - "기타"로
  // 분류될 때마다 순서대로 순환 배정됨(schedule_management_tab.dart의
  // _nextEtcIconIndex 참고). 이 화면은 그리기 확인용이라 10개 다 나열만 함.
  ('etc', '기타', 'assets/icons/memo_category/etc1.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc2.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc3.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc4.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc5.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc6.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc7.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc8.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc9.svg'),
  ('etc', '기타', 'assets/icons/memo_category/etc10.svg'),
  // ⭐ 2026-09-12 - 신설 6종(라켓 스포츠/축구/농구/야구/구기종목/입식 격투기) -
  // schedule_management_tab.dart의 _kScheduleCategoryIcons와 동일 목록.
  ('racket_sports', '라켓 스포츠', 'assets/icons/memo_category/racket_sports.svg'),
  ('soccer', '축구', 'assets/icons/memo_category/soccer.svg'),
  ('basketball', '농구', 'assets/icons/memo_category/basketball.svg'),
  ('baseball', '야구', 'assets/icons/memo_category/baseball.svg'),
  ('ball_sports', '구기종목', 'assets/icons/memo_category/ball_sports.svg'),
  ('combat_sports', '입식 격투기', 'assets/icons/memo_category/combat_sports.svg'),
];

class MemoCategoryIconLabScreen extends StatelessWidget {
  const MemoCategoryIconLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('메모 카테고리 아이콘 (Lucide, 실제 렌더링)')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            color: Colors.grey.shade100,
            child: Text(
              'assets/icons/memo_category/의 SVG 25종을 flutter_svg로 그대로 그린 것. '
              '색은 앱 메인 액센트(kAppMainAccent)로 tint. 실제 적용 화면(일정관리 등)에서는 '
              '카테고리별 다른 색을 쓸 수도 있음 - 이 화면은 "아이콘 모양 자체"만 확인하는 용도.',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 20.h,
                crossAxisSpacing: 10.w,
                mainAxisExtent: 108.h,
              ),
              itemCount: kMemoCategoryIcons.length,
              itemBuilder: (context, index) {
                final (key, label, asset) = kMemoCategoryIcons[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56.w,
                      height: 56.w,
                      decoration: BoxDecoration(
                        color: kAppMainAccent.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(14.w),
                      child: SvgPicture.asset(
                        asset,
                        colorFilter: const ColorFilter.mode(kAppMainAccent, BlendMode.srcIn),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                    Text(key, style: TextStyle(fontSize: 9.sp, color: Colors.grey.shade500)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
