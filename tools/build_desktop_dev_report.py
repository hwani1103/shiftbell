"""Attach complete audit inventories to the readable desktop report."""
import csv,subprocess,collections
from pathlib import Path
root=Path(__file__).resolve().parents[1]
path=root/'docs/next_version/dev_전체변경과_남은작업_SRTL_정리_2026-10-03.txt'
body=path.read_text(encoding='utf-8-sig').split('\n[자동 생성 부록 시작]')[0].rstrip()
parts=[body,'','[자동 생성 부록 시작]','', '='*70,
       '부록 1. 부분 확인·환경 대기·직접 확인·정책 검토 전체 목록', '='*70,
       '완료/해당 없음/삭제 기능을 제외한 모든 행이다. 현 상태와 기존 판정 문구를 보존했다.',
       '과거 판정에 미완이라고 적힌 세부 조건은 이번 보고서에서 임의로 완료로 올리지 않았다.','']
base=root/'docs/next_version/전수검증_자료_2026-09-30'
with (base/'기능_상태전이.csv').open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
pending=[r for r in rows if 'PASS' not in r['상태'] and r['상태'] not in ['해당 없음','취소(기능삭제)']]
parts.append(f'총 {len(pending)}행. 전체 202행 중 나머지와 구분.\n')
for r in pending:
    parts.extend([f"{r['ID']} [{r['상태']}]",
                  f"  할 검사: {r['준비와조작']}",
                  f"  통과 기준: {r['기대결과']}",
                  '  지금까지의 판정: '+(r['Codex판정'].replace('\n',' ') or '개별 실기기 완료 판정 없음. 본문 기기/환경 조건과 로컬 증거를 함께 확인.'),''])
parts.extend(['='*70,'부록 2. SRTL에서 빠짐없이 확인할 기존 화면 목록','='*70,
              '각 줄은 화면과 기존 목록상의 기기 판정이다. 대기 표시는 아직 갱신되지 않은 원본 상태이며,',
              'SRTL 과거 부분 확인을 최신 APK 전체 PASS로 승격하지 않았다. UI-033 등 삭제 대상은 제외 표시.',''])
with (base/'화면_체크리스트.csv').open(encoding='utf-8-sig',newline='') as f:screens=list(csv.DictReader(f))
cols=['Fold8_KO','Fold8_EN','Fold8Ultra_KO','Fold8Ultra_EN','Flip8_KO','Flip8_EN','S26_EN']
parts.append(f'원본 화면 목록 {len(screens)}행.\n')
for r in screens:
    parts.extend([f"{r['ID']} {r['화면과상태']}",f"  코드: {r['소스']}",
                  '  '+ ' / '.join(c+': '+(r.get(c) or '미기록').replace('\n',' ') for c in cols),''])
parts.extend(['='*70,'부록 3. 실제 제품·운영 코드 변경 파일 목록','='*70,
              '비교: 로컬 main(a89614c) → 현재 dev 작업 트리. M=수정, A=추가, D=삭제, R=이동.',
              '신규 미추적 파일도 별도 포함. 문서·테스트·빌드산출물은 제외했으며 사용자 기능 구분은 본문 기준.',
              '파일 추가가 곧 활성 사용자 기능 신설은 아니다. 예: 현재 진입이 제한된 영어 수면 화면의 소스.',
              '서버·Play에 실제 배포되었다는 의미는 아니다.',''])
scope=['lib','android/app/src/main','admin_dashboard','web','assets','pubspec.yaml','pubspec.lock','firebase.json','.github/workflows']
result=subprocess.run(['git','-c','core.quotePath=false','diff','--name-status','main','--',*scope],cwd=root,capture_output=True,check=True,encoding='utf-8')
lines=[line for line in result.stdout.splitlines() if '/test/' not in line and '/test_' not in line]
parts.extend(lines)
untracked=subprocess.run(['git','-c','core.quotePath=false','ls-files','--others','--exclude-standard','--',*scope],cwd=root,capture_output=True,check=True,encoding='utf-8')
new=[p for p in untracked.stdout.splitlines() if '/test/' not in p and '/test_' not in p]
parts.extend(['','추가된 미추적 제품 파일:']+['A(미추적)\t'+p for p in new])
parts.extend(['',f'변경 파일 {len(lines)}개 + 신규 미추적 {len(new)}개. 동일 기능의 여러 파일을 각각 기능 개수로 세지 않는다.','',
              '끝. 이 파일은 정리 결과이며 이번 요청에서 SRTL 실행·운영 배포·PC 종료를 새로 수행하지 않았다.'])
with path.open('w',encoding='utf-8-sig',newline='') as f:f.write('\r\n'.join('\n'.join(parts).splitlines())+'\r\n')
print(f'Created {path.name}: {len(pending)} pending transitions, {len(screens)} screen rows, {len(lines)+len(new)} changed product files; {path.stat().st_size} bytes')
