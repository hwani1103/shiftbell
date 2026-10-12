"""Check current rendered memo/header bounds before staging review images."""
import os, sys, json, time
sys.path.insert(0, 'tools')
import srtl_numbered_captures as captures
from srtl_current_audit import ev
from usb_audit_device import OUT

PROBE = r'''(() {
 String encode(dynamic value) {
  if(value is String)return '"'+value.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('\n','\\n')+'"';
  if(value is List)return '['+value.map(encode).join(',')+']';
  if(value is Map)return '{'+value.entries.map((e)=>encode(e.key)+':'+encode(e.value)).join(',')+'}';
  return value.toString();
 }
 final failures=<String>[]; final memos=<Map<String,dynamic>>[];
 final headers=<Map<String,dynamic>>[];
 final view=WidgetsBinding.instance.platformDispatcher.views.first;
 final screen=Offset.zero & (view.physicalSize/view.devicePixelRatio);
 Rect? bounds(Element e) { final r=e.findRenderObject();
   return r is RenderBox && r.hasSize ? Rect.fromPoints(r.localToGlobal(Offset.zero),r.localToGlobal(Offset(r.size.width,r.size.height))) : null; }
 void visit(Element e) {
  if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;
  if(e.widget is TickerMode&&!(e.widget as TickerMode).enabled)return;
  if(e.widget is CompleteCellMemoText) {
   final outer=bounds(e);
   if(outer!=null && outer.left>=0 && outer.right<=screen.right && screen.overlaps(outer)) {
    final memo=e.widget as CompleteCellMemoText;
    void label(Element child) {
     if(child.widget is Text) {
      final t=child.widget as Text; final rect=bounds(child)!; final shown=t.data??'';
      final p=TextPainter(text:TextSpan(text:shown,style:t.style),
        textDirection:Directionality.of(child),locale:Localizations.maybeLocaleOf(child),
        textScaler:t.textScaler??MediaQuery.textScalerOf(child),maxLines:1)..layout();
      if(shown.contains('...')||shown.contains('…')||memo.text.characters.take(shown.characters.length).join()!=shown)
        failures.add('invalid prefix: $shown');
      final local=(child.findRenderObject() as RenderBox).size;
      if(p.width>local.width+.1||p.height>local.height+.1)failures.add('text bounds: $shown');
      if(rect.left<outer.left+.5||rect.right>outer.right-.5)failures.add('no safe inset: $shown');
      child.visitAncestorElements((a) {
       if(a.widget is ClipRect) {final clip=bounds(a);
        if(clip!=null&&(rect.left<clip.left-.1||rect.right>clip.right+.1||rect.top<clip.top-.1||rect.bottom>clip.bottom+.1))
          failures.add('ancestor clipping: $shown');
       }return true;
      });
      memos.add({'source':memo.text,'shown':shown,'inkWidth':p.width,'available':rect.width,'x':rect.left,'y':rect.top});
      p.dispose();
     } child.visitChildren(label);
    }e.visitChildren(label);
   }
  }
  if(e.widget is CalendarTitleActionsRow) {
   final row=bounds(e)!; final buttons=<Rect>[];
   void action(Element c) {if(c.widget is TextButton||c.widget is IconButton){final b=bounds(c);if(b!=null)buttons.add(b);} c.visitChildren(action);}
   e.visitChildren(action);
   for(final b in buttons) {if(b.top<row.top-.1||b.bottom>row.bottom+.1||b.left<row.left-.1||b.right>row.right+.1)failures.add('header button outside title row');}
   headers.add({'buttons':buttons.length,'top':row.top,'height':row.height});
  }
  e.visitChildren(visit);
 }
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 return encode({'memos':memos,'headers':headers,'failures':failures});
})()'''

original_save=captures.save
def checked_save(row, fixture, status='captured'):
 if status=='captured' and row['screen']=='main':
  time.sleep(.5)
  result=json.loads(ev('pre_capture_'+row['number'],'screens/calendar_tab.dart',PROBE))
  result.update(number=row['number'],scale=os.environ.get('SRTL_SCALE','1.0'))
  path=OUT/('verified_'+row['number']+'_'+result['scale']+'.json')
  path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
  assert result['memos'],result
  assert not result['failures'],result
  if row['variant'] in ['underline','editorial']:
   assert len(result['headers'])==1 and result['headers'][0]['buttons']==4,result
 original_save(row,fixture,status)

if __name__=='__main__':
 captures.save=checked_save
 captures.run()
