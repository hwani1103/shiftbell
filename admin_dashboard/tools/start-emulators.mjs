// 로컬 에뮬레이터 시작: 루트 firestore.rules(원본)를 복사하고, 운영 firebase.json에 에뮬레이터 설정을 얹은 임시 설정으로 띄운다.
//   node tools/start-emulators.mjs
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dash = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
copyFileSync(path.resolve(dash, '..', 'firestore.rules'), path.join(dash, '.emulator.rules'));
const cfg = JSON.parse(readFileSync(path.join(dash, 'firebase.json'), 'utf8'));
cfg.firestore = { rules: '.emulator.rules' };
cfg.emulators = { auth: { port: 9099 }, firestore: { port: 8080 }, hosting: { port: 5010 }, ui: { enabled: false }, singleProjectMode: true };
writeFileSync(path.join(dash, '.emulator.firebase.json'), JSON.stringify(cfg, null, 2));

const child = spawn('firebase', ['emulators:start', '--config', '.emulator.firebase.json', '--only', 'auth,firestore,hosting', '--project', 'shiftbell-29f31'],
  { cwd: dash, stdio: 'inherit', shell: true });
child.on('exit', (code) => process.exit(code ?? 0));
