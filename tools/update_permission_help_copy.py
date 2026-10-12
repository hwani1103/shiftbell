import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/후속재점검_2026-10-05'
changes = {
 'pt': ['Datas e início da semana', 'Feriados e fins de semana não transformam um turno em folga automaticamente.', 'O fim de semana não transforma um turno em folga automaticamente.', 'Algumas permissões precisam de atenção', 'Confira as permissões do alarme', '• Tela de bloqueio: permitir notificações em tela cheia para mostrar a tela do alarme com o celular bloqueado.', 'Abra Configurações → Permissões do alarme no ShiftBell para conferir cada permissão, incluindo a tela de bloqueio. Volte ao app após configurar. Na primeira configuração, toque em Avançar quando terminar.'],
 'de': ['Datum und Wochenbeginn', 'Ein Feiertag oder Wochenende macht eine eingetragene Schicht nicht automatisch zu einem freien Tag.', 'Ein Wochenende macht eine eingetragene Schicht nicht automatisch zu einem freien Tag.', 'Einige Berechtigungen müssen geprüft werden', 'Weckerberechtigungen prüfen', '• Sperrbildschirm: Vollbildbenachrichtigungen erlauben, um den Wecker bei gesperrtem Telefon anzuzeigen.', 'Öffne Einstellungen → Weckerberechtigungen in ShiftBell und prüfe jede Berechtigung, auch für den Sperrbildschirm. Kehre nach dem Einstellen zur App zurück. Tippe bei der ersten Einrichtung anschließend auf Weiter.'],
 'en': ['Dates and week start', 'A holiday or weekend does not automatically make a shift a day off.', 'A weekend does not automatically make a shift a day off.', 'Some permissions need attention', 'Check alarm permissions', '• Lock screen display: allow full-screen notifications to show the alarm screen while the phone is locked.', 'Open Settings → Alarm permissions in ShiftBell to check each permission, including lock screen display. Return to the app after changing settings. During first setup, tap Next when you are ready.'],
 'hi': ['तारीख और सप्ताह की शुरुआत', 'सार्वजनिक छुट्टी या सप्ताहांत होने से शिफ्ट अपने आप छुट्टी में नहीं बदलती।', 'सप्ताहांत होने से शिफ्ट अपने आप छुट्टी में नहीं बदलती।', 'कुछ अनुमतियों की जांच करनी है', 'अलार्म की अनुमतियां जांचें', '• लॉक स्क्रीन: फ़ोन लॉक होने पर अलार्म स्क्रीन दिखाने के लिए फ़ुल-स्क्रीन सूचनाओं की अनुमति।', 'ShiftBell में सेटिंग → अलार्म की अनुमतियाँ खोलकर हर अनुमति जांचें, जिसमें लॉक स्क्रीन पर दिखाना भी शामिल है। सेटिंग बदलने के बाद ऐप में वापस आएं। पहली बार सेट करते समय तैयार होने पर आगे पर टैप करें।'],
 'ko': [None, None, None, '일부 권한을 확인해 주세요', '알람 권한 확인 필요', '• 잠금화면 알람 표시: 휴대전화가 잠겼을 때 알람 화면을 표시하기 위한 전체 화면 알림 권한입니다.', 'ShiftBell의 설정 → 알람 권한 설정에서 잠금화면 표시를 포함한 각 권한을 확인해 주세요. 설정을 마친 뒤 앱으로 돌아오세요. 첫 설정 중에는 준비가 되면 다음을 눌러 주세요.'],
}
records=[]
for lang, values in changes.items():
 p=ROOT/f'lib/l10n/app_{lang}.arb'; data=json.loads(p.read_text('utf-8'))
 before=dict(data)
 title,old,new,warning,banner,privacy,guide=values
 if title:
  data['helpCalendarLocaleTitle']=title
  assert old in data['helpCalendarLocaleBody'], (lang,old)
  data['helpCalendarLocaleBody']=data['helpCalendarLocaleBody'].replace(old,new)
 data['permissionSomeDenied']=warning
 data['permissionRequiredNotGranted']=banner
 data['privacyPermissionsBody']+='\n\n'+privacy
 for key in ['helpStartOnboardingBody','helpAlarmAlarmNotRingingBody','helpTroubleshootAlarmIssueBody']:
  data[key]+='\n\n'+guide
 for key,value in data.items():
  if before.get(key)!=value: records.append({'language':lang,'key':key,'before':before.get(key),'after':value,'reason':'AK fourth permission and individual settings flow; unknown is not denied' if not key.startswith('helpCalendarLocale') else 'Foreign calendar has no public holiday function; remove unrelated description'})
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
(OUT/'도움말_권한_수정후보와결과.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),'utf-8')
