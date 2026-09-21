#!/usr/bin/env node
// admin_dashboard/sync/admin-user.mjs
//
// 관리자 계정을 만들거나(이미 있으면 비밀번호만 재설정) emailVerified:true로 고정한다.
// 보안 규칙(firestore.rules)이 email_verified 를 요구하므로, 계정은 반드시 이 스크립트(Admin SDK)로 만들 것.
//
//   ADMIN_EMAIL=me@example.com ADMIN_PASSWORD='임시비번' node admin-user.mjs
//
// 자격 증명: SERVICE_ACCOUNT_JSON 또는 GOOGLE_APPLICATION_CREDENTIALS. 에뮬레이터(FIREBASE_AUTH_EMULATOR_HOST)면 불필요.
// ⚠️ Firebase 인증은 비밀번호가 6자 이상이어야 한다(4자리 "1234"는 만들 수 없음).

import { initializeApp, cert, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
if (!email || !password) { console.error('ADMIN_EMAIL, ADMIN_PASSWORD 환경변수가 필요해요.'); process.exit(1); }
if (password.length < 6) { console.error('비밀번호는 6자 이상이어야 해요(Firebase 인증 규칙).'); process.exit(1); }

const opts = { projectId: process.env.FIREBASE_PROJECT_ID || 'shiftbell-29f31' };
if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  opts.credential = process.env.SERVICE_ACCOUNT_JSON ? cert(JSON.parse(process.env.SERVICE_ACCOUNT_JSON)) : applicationDefault();
}
const auth = getAuth(initializeApp(opts));

try {
  let user;
  try {
    user = await auth.getUserByEmail(email);
    user = await auth.updateUser(user.uid, { password, emailVerified: true, disabled: false });
    console.log(`✅ 기존 계정 갱신: ${email} (uid ${user.uid}) - 비밀번호 재설정, 이메일 인증됨`);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, password, emailVerified: true, displayName: '교대시계 관리자' });
    console.log(`✅ 계정 생성: ${email} (uid ${user.uid})`);
  }
} catch (e) {
  console.error('❌ 실패:', e.message);
  process.exitCode = 1;
}
