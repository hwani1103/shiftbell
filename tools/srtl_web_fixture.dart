// Local SRTL layout fixture using the exact production friend calendar widget.
// No Firebase upload, no production deployment, no mock claims about installation.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/screens/friend_calendar_view.dart';
import 'package:shiftbell/widgets/app_text_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final q = Uri.base.queryParameters;
  final ko = q['lang'] != 'en';
  final names = ko
      ? ['주간', '야간집중근무', '휴무', '오전지원근무', '연차']
      : ['Day', 'Late Night Shift', 'Off', 'Morning Support', 'Leave'];
  runApp(ScreenUtilInit(
    designSize: const Size(360, 780),
    minTextAdapt: true,
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(double.tryParse(q['scale'] ?? '') ?? 1.0),
        ),
        child: AppTextScale(child: child!),
      ),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      locale: ko ? const Locale('ko') : const Locale('en', 'US'),
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: FriendCalendarView(
        friendName: ko ? '교대근무 동료의 일정' : 'Colleague Work Schedule',
        data: FriendScheduleData(ownerName: 'SRTL layout fixture', isRegular: true,
          pattern: [names[0],names[0],names[2],names[2],names[1],names[1],names[2],names[2]],
          todayIndex: 4, startDate: DateTime(2026,10,3),
          shiftColors: {names[0]:0xFF90CAF9,names[1]:0xFFCE93D8,names[2]:0xFFC8E6C9,names[3]:0xFF80CBC4,names[4]:0xFFB0BEC5},
          assignedDates: {'2026-10-07':names[3],'2026-10-16':names[4],'2026-10-22':names[3]}, updatedAt: DateTime.now()),
        showInstallPrompt: true,
        showPwaAddressBarHint: q['inapp'] != '1',
        showQuickInstallButton: q['pwa'] == '1',
        onQuickInstallTap: () {}, onInstallTap: () {},
      ),
    ),
  ));
}
