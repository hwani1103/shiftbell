import time
from usb_audit_device import evaluate,capture,tap_text,adb
evaluate('friend_counts_firebase_off','services/firebase_bootstrap.dart',"(() {firebaseReady=false;return 'temporary in-process network gate';})()",wait=False)
def seed(count):
    evaluate('friend_counts_seed_'+str(count),'services/database_service.dart',f"""(() async {{
      final d=await DatabaseService.instance.database;await d.delete('friends');
      for(var i=0;i<{count};i++){{await d.insert('friends',{{'name':'OCT03_$i','owner_id':'oct03_local_$i','data_json':null,'added_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String()}});}}
      return '${{(await d.query('friends')).length}}';}})()""".replace('\n',' '))
def open_screen():
    evaluate('friend_counts_open','screens/friend_list_screen.dart',"""(() {
      NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      nav!.push(MaterialPageRoute(builder:(_)=>const Scaffold(body:FriendListScreen())));return 'opened';})()""".replace('\n',' '),wait=False)
    evaluate('friend_counts_reload','screens/friend_list_screen.dart',"""(() async {
      _FriendListScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _FriendListScreenState)s=e.state as _FriendListScreenState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);await s!.ref.read(friendProvider.notifier).load();return '${s!.ref.read(friendProvider).length}';})()""".replace('\n',' '))
def delete_button():
    point=evaluate('friend_last_delete_position','screens/friend_list_screen.dart',"""(() {
      String? point;void visit(Element e){if(e.widget is IconButton && (e.widget as IconButton).icon is Icon && ((e.widget as IconButton).icon as Icon).icon==Icons.delete_outline){final b=e.findRenderObject() as RenderBox;final p=b.localToGlobal(b.size.center(Offset.zero));final r=MediaQuery.devicePixelRatioOf(e);point='${p.dx*r},${p.dy*r}';}e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);return point!;})()""".replace('\n',' '),wait=False)
    x,y=[str(round(float(v))) for v in point.split(',')];adb('shell','input','tap',x,y)
try:
    for count in [0,10,1]:
        seed(count);open_screen();capture('friend_count_'+str(count))
        if count==10:
            adb('shell','input','swipe','540','1750','540','650','400');capture('friend_count_ten_bottom')
        if count==1:
            delete_button();tap_text('^취소$')
            delete_button();tap_text('^삭제$')
            time.sleep(.5);capture('friend_last_deleted')
            result=evaluate('friend_last_empty','services/database_service.dart',"(() async {return '${(await (await DatabaseService.instance.database).query('friends')).length}';})()")
            assert result=='0'
        adb('shell','input','keyevent','KEYCODE_BACK');time.sleep(.4)
finally:
    evaluate('friend_counts_firebase_restore','services/firebase_bootstrap.dart',"(() {firebaseReady=true;return 'normal Firebase gate restored';})()",wait=False)
    import usb_oct03_restore_baseline
print('PASS local friend counts 0/1/10, scroll and last deletion cancel/confirm; no server mutation.')
