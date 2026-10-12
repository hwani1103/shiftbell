import json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
lang=sys.argv[1];offset=int(sys.argv[2]);count=int(sys.argv[3])
data=json.loads((root/f'lib/l10n/app_{lang}.arb').read_text('utf-8'))
ko=json.loads((root/'lib/l10n/app_ko.arb').read_text('utf-8'))
items=[(k,v) for k,v in data.items() if not k.startswith('@')]
for index,(k,v) in enumerate(items[offset:offset+count],offset):
 print((f'{index} {k} | '+('' if len(sys.argv)>4 else ko[k]+' | ')+v).replace('\n',' / '))
print('TOTAL',len(items))
