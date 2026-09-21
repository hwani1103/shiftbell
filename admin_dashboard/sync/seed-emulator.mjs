#!/usr/bin/env node
// 로컬 에뮬레이터용: 관리자 계정 + 모의 대시보드 문서를 채운다. (에뮬레이터 실행 중일 때만 동작)
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node seed-emulator.mjs
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { buildMockDocs } from '../public/assets/js/mock.js';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('에뮬레이터 환경변수(FIRESTORE_EMULATOR_HOST, FIREBASE_AUTH_EMULATOR_HOST)가 없어서 중단합니다(운영 데이터를 건드리지 않기 위함).');
  process.exit(1);
}
const app = initializeApp({ projectId: 'shiftbell-29f31' });
const auth = getAuth(app); const db = getFirestore(app);
const ADMIN = { email: 'rlaworms0905@naver.com', password: 'emu-pass-1234' };
const OTHER = { email: 'someone@example.com', password: 'other-pass-1234' };

for (const u of [{ ...ADMIN, emailVerified: true }, { ...OTHER, emailVerified: true },
  { email: 'rlaworms0905@naver.com'.replace('rla', 'fake'), password: 'x-pass-1234', emailVerified: false }]) {
  try { await auth.createUser(u); } catch (e) {
    if (e.code !== 'auth/email-already-exists') throw e;
    await auth.updateUser((await auth.getUserByEmail(u.email)).uid, { password: u.password, emailVerified: u.emailVerified });
  }
}
const docs = buildMockDocs();
await Promise.all(['summary', 'series', 'events'].map((id) => db.collection('dashboard').doc(id).set(docs[id])));
console.log('✅ 에뮬레이터 시드 완료 - 관리자', ADMIN.email, '/', ADMIN.password);
