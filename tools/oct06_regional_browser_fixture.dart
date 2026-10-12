// Device-browser functional fixture using the production calendar and delegates.
// Synthetic schedule; no publishing, Firebase upload, or installation claim.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/l10n/regional_material_localizations.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/screens/friend_calendar_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  await initializeDateFormatting();
  runApp(const RegionalFixture());
}
class RegionalFixture extends StatefulWidget {
  const RegionalFixture({super.key});
  @override
  State<RegionalFixture> createState()=>_RegionalFixtureState();
}
class _RegionalFixtureState extends State<RegionalFixture> {
  Locale locale=const Locale('ko');
  final schedule=FriendScheduleData(ownerName:'Regional Audit',isRegular:true,
    pattern:['Day','Night','Off'],todayIndex:0,startDate:DateTime(2026,10,1),
    shiftColors:{'Day':0xFF90CAF9,'Night':0xFFCE93D8,'Off':0xFFC8E6C9},
    assignedDates:{},updatedAt:DateTime(2026,10,6));
  @override
  Widget build(BuildContext context)=>ScreenUtilInit(
    designSize:const Size(360,780),minTextAdapt:true,
    builder:(_,__)=>MaterialApp(debugShowCheckedModeBanner:false,
      locale:locale,supportedLocales:releaseSupportedLocales,
      localizationsDelegates:const [AppLocalizations.delegate,releaseRegionalMaterialDelegate,GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],
      home:Builder(builder:(context)=>Scaffold(body:SafeArea(child:Column(children:[
        Wrap(children:[for(final l in releaseSupportedLocales) TextButton(
          onPressed:()=>setState(()=>locale=l),child:Text(l.toLanguageTag()))]),
        Text('FORMAT ${MaterialLocalizations.of(context).formatCompactDate(DateTime(2026,4,5))} FIRST ${MaterialLocalizations.of(context).firstDayOfWeekIndex}'),
        Expanded(child:FriendCalendarView(friendName:'Regional Audit',data:schedule,publicWebViewer:true,
          showInstallPrompt:false,showPwaAddressBarHint:false)),
      ])))),
    ));
}
