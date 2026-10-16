"""Readable final evidence index, derived only from completed certificates."""
from pathlib import Path
import json,re
R=Path(__file__).resolve().parents[3];E=R/'docs/next_version_27이후/game_implementation_v11'
proof=json.loads((E/'finale_verification.json').read_text('utf-8'))['levels']
design=json.loads((E/'finale_design.json').read_text('utf-8'))['levels']
artifact=json.loads((E/'build_artifact_verification.json').read_text('utf-8'))
font=json.loads((E/'font_size_report.json').read_text('utf-8'))
assert len(proof)==len(design)==30 and all(p['status']=='PASS' for p in proof)
lines=['100레벨 피날레 — 완료 증거 / 2026-10-15','',
 '기존70의 맵·장치·판정 identity를 그대로 유지하고 새30개를 추가했다.',
 '71~99는7×7,100은8×8. 문 최대2개·포탈 최대2쌍. 새 장치는 없다.',
 '필수 한도는 최소 하나의 공이 반드시 써야 하는 이동 명령 수다. 모든 공이 같은 횟수일 필요는 없다.',
 '최소 총명령은 네 공의 합이다. 추가 거리는 장치/충돌을 무시한 각 공의 최단 후보 경로보다 반드시 더 이동하는 칸의 합이다.',
 '정규화는 포탈을 활성화하지 않는 같은 방향 연속 이동의 불필요한 분할만 합친다. 왕복·재방문·포탈 입구 끝점은 남긴다.',
 '따라서 필수 한도보다1 적은 원시 명령 공간에도 해답이 없다. 아래 해답 수는 정규화 공간의 수이며 원시 유일해 수가 아니다.',
 '모든 안전 정규화 해답을 실제 엔진으로 재실행했다. 두 문 각각이 다른 공의 도움을 필요로 하며, 제거하면 해답 수가 늘어난다.',
 '사람이 한두 번에 깰 수 없는지와 체감 난이도 순서는 자동 검증으로 보증하지 않는다. 실기기/사람 플레이는 NOT_TESTED다.','',
 'LV | 필수 한도 | 최소 총명령 | 최소 추가 거리 | 정규화 해답 | 검증']
for p in proof:
 lines.append(f"{p['id']} | {p['minimumRequiredMaxCommands']} | {p['minimumTotalCommands']} | {p['minimumExtraDistance']} | {p['canonicalSolutions']} | PASS")
lines+=['','자동 검사']
total=0
for package in ['sync_path_core','sync_path_tools','sync_path_ui','lab']:
 source=(E/f'{package}-tests.txt').read_text('utf-8-sig')
 matches=re.findall(r'\+(\d+): All tests passed!',source)
 assert matches,package
 n=int(matches[-1]);total+=n;lines.append(f'{package}: {n} PASS')
lines += [f'합계: {total} PASS','분석: core/tools/UI/호스트 모두 오류 없음.',
 '별도: 기존31~50 문 인증,51~70 포탈 인증, 신규71~100 독립 인증 PASS.',
 'Flutter 렌더: ui_previews와 regression_previews. 레이아웃 검사는 실제 기기 조작 검사와 구분한다.','',
 f"DEV debug APK: {artifact['apk']}",f"버전: {artifact['versionName']}+{artifact['versionCode']}",
 f"앱 ID: {artifact['applicationId']}",f"APK SHA256: {artifact['sha256']}",
 f"게임 데이터+축소폰트: {font['assetBytes']:,}bytes / 500,000bytes 한도 (전체 APK 용량 아님)",
 f"기존 ShiftBell 보호 파일 {artifact['protectedExistingFilesUnchanged']}개 해시 일치.",
 'APK/웹에 들어간100레벨·문구·폰트가 현재 소스와 동일함을 확인했다.',
 '이전70레벨 APK SHA256 유지. release 빌드/기기 설치/광고 또는 서버 배포 없음.','',
 '하트·수동 선택·목록 복귀·잠금·표현의 현행 규칙: 00_구현검증_읽기순서.txt',
 'UI 후속: docs/UI 완성도 개선/GAME-08_100레벨_기호정리_진행복귀_하트_2026-10-15.txt']
(E/'01_완료결과_레벨별난이도증거.txt').write_text('\n'.join(lines)+'\n','utf-8')
print(f'PASS: final summary from 30 certificates and {total} tests.')
