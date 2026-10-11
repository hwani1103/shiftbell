import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/services/app_analytics.dart';
import 'package:shiftbell/services/operations_analytics.dart';
import 'package:shiftbell/services/backup_policy.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now=DateTime(2026,10,11,12);
  late List<String> sent;
  Map<dynamic,dynamic> data(List<Map<String,Object>> rows) => {'manufacturer':'samsung','battery':'restricted','permissions':{'notification':'granted','exactAlarm':'denied','overlay':'granted','fullScreen':'unknown','alarmChannel':'granted'},'observations':rows};
  Map<String,Object> row(String token, {String event='alarm_fired', DateTime? at}) => {'token':token,'event':event,'atMs':(at??now).millisecondsSinceEpoch};
  setUp((){SharedPreferences.setMockInitialValues({});sent=[];AppAnalytics.debugSink=(name,params){sent.add(name);expect(params,{'manufacturer':'samsung'});};});
  tearDown(()=>AppAnalytics.debugSink=null);
  test('first observation establishes baseline; daily restrictions send once',() async {
    await OperationsAnalytics.report(now:now,snapshot:() async=>data([row('old')]));
    expect(sent,['ops_daily_restricted','ops_battery_restricted','ops_exact_denied']);
    sent.clear();
    await OperationsAnalytics.report(now:now,snapshot:() async=>data([row('old'),row('new')]));
    expect(sent,['alarm_fired']);
    sent.clear();
    await OperationsAnalytics.report(now:now,snapshot:() async=>data([row('old'),row('new')]));
    expect(sent,isEmpty);
    await OperationsAnalytics.report(now:now.add(const Duration(days:1)),snapshot:() async=>data([row('old'),row('new')]));
    expect(sent,['ops_daily_restricted','ops_battery_restricted','ops_exact_denied']);
  });
  test('stale future unapproved events and overflow excluded without replay',() async {
    SharedPreferences.setMockInitialValues({OperationsAnalytics.cursorKey:<String>[] ,OperationsAnalytics.dailyKey:'2026-10-11'});
    final rows=[row('stale',at:now.subtract(const Duration(hours:73))),row('future',at:now.add(const Duration(minutes:1))),row('unknown',event:'private_event'),for(var i=0;i<100;i++) row('fresh'+i.toString())];
    await OperationsAnalytics.report(now:now,snapshot:() async=>data(rows));
    expect(sent.length,40);expect(sent.toSet(),{'alarm_fired'});
    sent.clear();await OperationsAnalytics.report(now:now,snapshot:() async=>data(rows));expect(sent,isEmpty);
  });
  test('snapshot failure does not advance cursor',() async {
    SharedPreferences.setMockInitialValues({OperationsAnalytics.cursorKey:['kept']});
    await OperationsAnalytics.report(now:now,snapshot:() async=>throw StateError('unavailable'));
    expect(sent,isEmpty);expect((await SharedPreferences.getInstance()).getStringList(OperationsAnalytics.cursorKey),['kept']);
  });
  test('device observations stay out of backups',(){expect(isBackupPreferenceKey(OperationsAnalytics.cursorKey),false);expect(isBackupPreferenceKey(OperationsAnalytics.dailyKey),false);});
}
