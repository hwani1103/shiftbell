"""Apply reviewed U02/U03/U07/U08 once, preserving all other resource values."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
changes = {
    'ko': {'permissionOpenFailed': '설정을 열지 못했어요. 휴대폰 설정에서 바꾸려는 권한을 검색한 뒤 ShiftBell을 선택해 주세요. 알림은 설정 → 앱 → ShiftBell → 알림에서도 확인할 수 있어요. 기기에 따라 이름이 다를 수 있어요.'},
    'pt': {
        'permissionOpenFailed': 'Não foi possível abrir as configurações. Nas configurações do celular, busque a permissão que quer alterar e selecione ShiftBell. Para notificações, acesse Apps → ShiftBell → Notificações. Os nomes podem variar conforme o aparelho.',
        'permissionNotApplicable': 'Não requer configuração separada nesta versão do Android',
    },
    'de': {'permissionOpenFailed': 'Die Einstellungen konnten nicht geöffnet werden. Suche in den Telefoneinstellungen nach der gewünschten Berechtigung und wähle ShiftBell. Benachrichtigungen findest du auch unter Apps → ShiftBell → Benachrichtigungen. Die Namen können je nach Gerät abweichen.'},
    'en': {
        'permissionOpenFailed': 'Could not open settings. In your phone’s Settings, search for the permission you want to change and select ShiftBell. For notifications, open Apps → ShiftBell → Notifications. Names may vary by device.',
        'settingsPaydayBasisDesc': 'Monthly totals based on a reference date you choose',
    },
    'hi': {
        'permissionOpenFailed': 'सेटिंग नहीं खुल सकी। फ़ोन की सेटिंग में जिस अनुमति को बदलना है, उसे खोजें और ShiftBell चुनें। सूचनाओं के लिए ऐप्स → ShiftBell → सूचनाएं भी खोल सकते हैं। नाम डिवाइस के अनुसार अलग हो सकते हैं।',
        'settingsPaydayBasisDesc': 'चुनी हुई संदर्भ तारीख के आधार पर महीने का कुल समय',
    },
}
key = 'workHoursLegacyClockTimeHint'
scoped_path = ROOT / 'lib/l10n/korean_only/messages_ko.json'
scoped = json.loads(scoped_path.read_text('utf-8'))
assert key not in scoped, 'Already applied'
for lang in ['ko', 'pt', 'de', 'en', 'hi']:
    path = ROOT / f'lib/l10n/app_{lang}.arb'
    data = json.loads(path.read_text('utf-8'))
    if lang == 'ko':
        scoped[key] = data[key]
        if '@' + key in data:
            scoped['@' + key] = data['@' + key]
    del data[key]
    data.pop('@' + key, None)
    data.update(changes[lang])
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', 'utf-8')
scoped_path.write_text(json.dumps(scoped, ensure_ascii=False, indent=2) + '\n', 'utf-8')
print('Applied reviewed resource changes; run both generators next.')
