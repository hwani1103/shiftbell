from usb_audit_device import connect_vm,evaluate
connect_vm()
evaluate('audit_semantics_kept','main.dart',"(() {WidgetsBinding.instance.ensureSemantics();return 'semantics retained for UI audit until process restart';})()",wait=False)
