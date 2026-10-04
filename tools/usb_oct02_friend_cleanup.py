from usb_audit_device import evaluate
from usb_audit_scenarios import scenario
evaluate('friend_ui_network_restored','services/friend_sync_service.dart',"(() async {await FirebaseFirestore.instance.enableNetwork();return 'network restored';})()")
scenario('friend_ui_fixture_cleanup','providers/friend_provider.dart',"""
final d=await DatabaseService.instance.database;final n=FriendNotifier();
try{await n.load();for(final row in await d.query('friends',where:'owner_id=?',whereArgs:['usb_audit_oct02_offline'])){await n.removeFriend(row['id'] as int);}}
finally{n.dispose();}
check((await d.query('friends')).isEmpty,'original empty friend list restored');
""")
