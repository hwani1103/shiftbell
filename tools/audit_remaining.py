import csv,pathlib
p=pathlib.Path('docs/next_version/전수검증_자료_2026-09-30/기능_상태전이.csv')
for r in csv.DictReader(p.open(encoding='utf-8-sig')):
 if r['상태'] not in ('PASS','PASS(현 정책)','수정 후 PASS','해당 없음','취소(기능삭제)'):
  print(r['ID'],r['상태'],r['준비와조작'])
