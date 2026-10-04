import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';

void main() {
  test('phone scale is preserved and wide design units stay bounded',
      () {
    const design = Size(360, 780);
    final phone =
        appContentMediaQuery(const MediaQueryData(size: Size(400, 900)));
    final fold =
        appContentMediaQuery(const MediaQueryData(size: Size(884, 1100)));
    expect(phone.size, const Size(400, 900));
    expect(fold.size, const Size(400, 850));
    ScreenUtil.configure(
        data: fold,
        designSize: design,
        minTextAdapt: true,
        splitScreenMode: true);
    expect(ScreenUtil().scaleWidth, closeTo(400 / 360, 0.0001));
  });

  test('bar and Flip reference windows never select the short cover', () {
    for (final size in const [Size(320,568), Size(360,640), Size(393,852),
      Size(430,932), Size(480,800), Size(500,900), Size(360,840)]) {
      final data = MediaQueryData(size: size, viewInsets: const EdgeInsets.only(bottom: 320));
      expect(AppLayout(size).kind, AppLayoutKind.phone, reason: '$size');
      expect(appContentMediaQuery(data), data);
    }
    expect(const AppLayout(Size(400,632)).kind, AppLayoutKind.shortCover);
    expect(const AppLayout(Size(662,876)).kind, AppLayoutKind.widePortrait);
    expect(const AppLayout(Size(806,895)).kind, AppLayoutKind.wideSquare);
  });
}
