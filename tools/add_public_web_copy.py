import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
copy={
 'publicWebIntroBody':['교대근무자를 위한 일정 관리와 알람 앱입니다.\n근무 일정과 수면 리듬을 한곳에서 편하게 관리해 보세요.','An app for your shifts and alarms. Keep your shift schedule, notes and work hours together.','Um app para seus turnos e alarmes. Organize sua escala, notas e horas de trabalho em um só lugar.','Eine App für deine Schichten und Wecker. Behalte Schichtplan, Notizen und Arbeitszeit an einem Ort.','आपकी शिफ्ट और अलार्म के लिए ऐप। शिफ्ट शेड्यूल, नोट और काम के घंटे एक जगह रखें।'],
 'publicWebShareTitle':['친구와 근무 일정 공유','View a shared shift calendar','Ver um calendário de turnos compartilhado','Geteilten Schichtkalender ansehen','शेयर किया गया शिफ्ट कैलेंडर देखें'],
 'publicWebShareBody':['친구에게 받은 공유 링크는 그대로 열면 최신 근무 일정을 확인할 수 있습니다.','Open a shared link to view the latest shift schedule.','Abra um link compartilhado para ver a escala atualizada.','Öffne einen geteilten Link, um den aktuellen Schichtplan anzusehen.','शेयर किया गया लिंक खोलकर नया शिफ्ट शेड्यूल देखें।'],
 'publicWebPrivacyBody':['앱의 데이터 처리와 광고·분석 이용 안내를 확인할 수 있습니다.','Read about the app’s data handling, advertising and analytics.','Veja como o app usa dados, publicidade e estatísticas.','Lies, wie die App Daten, Werbung und Nutzungsstatistiken verarbeitet.','ऐप के डेटा उपयोग, विज्ञापनों और इस्तेमाल के आंकड़ों के बारे में पढ़ें।'],
 'publicWebPrivacyAction':['개인정보처리방침 보기','View Privacy Policy','Ver política de privacidade','Datenschutzerklärung ansehen','निजता नीति देखें'],
 'publicWebStoreButton':['Google Play에서 교대시계 보기','View ShiftBell on Google Play','Ver ShiftBell no Google Play','ShiftBell bei Google Play ansehen','Google Play पर ShiftBell देखें'],
}
for i,lang in enumerate(['ko','en','pt','de','hi']):
 p=ROOT/f'lib/l10n/app_{lang}.arb';d=json.loads(p.read_text('utf-8'))
 for k,v in copy.items():d[k]=v[i]
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n','utf-8')
