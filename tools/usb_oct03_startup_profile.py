"""Dev-phone measurements, separately labelled from release/user reports."""
import json
import re
import sys
import time
from usb_audit_device import adb, evaluate, OUT, PACKAGE

stage=sys.argv[1]
if stage=='prepare_large':
    evaluate('startup_fresh_classifier','services/memo_category_classifier.dart',"""(() async {
      rootBundle.evict('assets/ml/memo_category_model.json');
      final model=MemoCategoryClassifier._();final watch=Stopwatch()..start();
      await model.ensureLoaded();final cold=watch.elapsedMilliseconds;watch.reset();await model.ensureLoaded();
      return jsonEncode({'fresh_classifier_asset_evicted_ms':cold,'warm_ms':watch.elapsedMilliseconds,
        'classification':model.classify('엄마한테 전화하기').categoryKey});})()""".replace('\n',' '))
    evaluate('startup_large_db_seed','services/database_service.dart',"""(() async {
      final d=await DatabaseService.instance.database;final before=(await d.query('date_memos')).length;
      final watch=Stopwatch()..start();
      await d.transaction((tx) async {final batch=tx.batch();for(var i=0;i<20000;i++){
        batch.insert('date_memos',{'date':'2035-01-01','memo_text':'OCT03_HOST_SAFE_SYNTHETIC_$i','order_index':i,'created_at':'2026-10-03T00:00:00'});
      }await batch.commit(noResult:true);});
      final count=(await d.rawQuery('SELECT COUNT(*) n FROM date_memos')).single['n'];
      if(count!=before+20000)throw StateError('fixture count mismatch');
      return jsonEncode({'before':before,'after':count,'insert_ms':watch.elapsedMilliseconds});})()""".replace('\n',' '),timeout=120)
elif stage in ['baseline','large']:
    results=[]
    for i in range(3):
        adb('shell','am','force-stop',PACKAGE)
        output=adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity').decode('utf-8',errors='replace')
        (OUT/f'startup_{stage}_{i}_am.txt').write_text(output,encoding='utf-8')
        pid=adb('shell','pidof',PACKAGE).decode().strip()
        for _ in range(20):
            log=adb('logcat','-d','--pid='+pid,'-s','flutter').decode('utf-8',errors='replace')
            match=re.search(r'Startup core ready: (\d+)ms',log)
            if match:break
            time.sleep(1)
        assert match,'No core-ready log'
        (OUT/f'startup_{stage}_{i}_flutter.log').write_text(log,encoding='utf-8')
        results.append({'iteration':i,'pid':pid,'core_ms':int(match.group(1)),
            'am_total_ms':int(re.search(r'TotalTime: (\d+)',output).group(1)),
            'clock_changed':False,'build':'dev debug'})
        print(results[-1],flush=True)
        time.sleep(2)
    (OUT/f'startup_{stage}_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
else:raise ValueError(stage)
