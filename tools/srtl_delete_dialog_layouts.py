import os
"""Cancellation-only layout checks for destructive confirmations."""
import time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import locale,fold,tab,invoke,inspect,back,push
from usb_team_rules_audit import tap
from srtl_extra_layouts import bottom
connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
        p=lang+('_open_' if opened else '_closed_')+'deletion_confirm_'
        tab(4)
        invoke('screens/settings_tab.dart','_SettingsTabState','_resetSchedule()')
        inspect(p+'reset');bottom(p+'reset');back()
        tap('all_delete_dialog',"e.widget is Text && (e.widget as Text).data==context.l10n.alarmDeleteAllPermanently".replace('context.l10n','e.l10n'),'screens/settings_tab.dart')
        inspect(p+'all_alarms');bottom(p+'all_alarms');back()
        push('screens/all_alarms_history_view.dart','AllAlarmsHistoryView()')
        invoke('screens/all_alarms_history_view.dart','_AllAlarmsHistoryViewState','_deleteAllHistory()')
        inspect(p+'history');bottom(p+'history');back();back()
adb('shell','settings','put','system','font_scale','1.0')
