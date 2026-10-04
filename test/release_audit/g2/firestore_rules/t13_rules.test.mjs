// T13 G2 Firestore rules emulator test — target: release/g2 4a8f67e firestore.rules (repo file, read at test start)
// demo- project only; never touches production. Rules are loaded from the repo firestore.rules by initializeTestEnvironment (firebase.json has no rules path: firebase-tools refuses paths outside this folder).
// Run: npm install && npm test
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where, serverTimestamp,
} from 'firebase/firestore';

const OWNER = 'ownerUid_A';
const OTHER = 'otherUid_B';
let env;

const appPayload = (gen = 1, extra = {}) => ({
  ownerName: '홍길동', isRegular: true, pattern: ['주', '야', '비', '휴'], todayIndex: 0,
  startDate: '2026-09-14T00:00:00.000', shiftColors: { '주': 0xff2196f3 },
  assignedDates: { '2026-09-20': '휴' }, generation: gen, revoked: false,
  updatedAt: serverTimestamp(), ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shiftbell-t13',
    firestore: { rules: readFileSync(new URL('../../../../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8085 },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const asOwner = () => env.authenticatedContext(OWNER).firestore();
const asOther = () => env.authenticatedContext(OTHER).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (path, data) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path), data));

// ── friend_schedules 소유권 (#30 FS 소유권) ──
test('FS-01 소유자 본인 문서 create(앱 payload 형식) 허용', async () => {
  await assertSucceeds(setDoc(doc(asOwner(), 'friend_schedules', OWNER), appPayload()));
});
test('FS-02 다른 uid가 남의 ownerId 문서 create 거부', async () => {
  await assertFails(setDoc(doc(asOther(), 'friend_schedules', OWNER), appPayload()));
});
test('FS-03 미인증 create 거부', async () => {
  await assertFails(setDoc(doc(anon(), 'friend_schedules', OWNER), appPayload()));
});
test('FS-04 소유자 update 허용 / 다른 uid update 거부', async () => {
  await seed(`friend_schedules/${OWNER}`, appPayload());
  await assertSucceeds(updateDoc(doc(asOwner(), 'friend_schedules', OWNER), { ownerName: 'y' }));
  await assertFails(updateDoc(doc(asOther(), 'friend_schedules', OWNER), { ownerName: 'z' }));
  await assertFails(setDoc(doc(anon(), 'friend_schedules', OWNER), { ownerName: 'z' }));
});
test('FS-05 소유자 delete 허용 / 다른 uid·미인증 delete 거부', async () => {
  await seed(`friend_schedules/${OWNER}`, { ownerName: 'x', isRegular: false });
  await assertFails(deleteDoc(doc(asOther(), 'friend_schedules', OWNER)));
  await assertFails(deleteDoc(doc(anon(), 'friend_schedules', OWNER)));
  await assertSucceeds(deleteDoc(doc(asOwner(), 'friend_schedules', OWNER)));
});
test('FS-06 공유 코드 get은 미인증도 허용(제품 의도), 없는 문서 get도 허용(notFound 구분 가능)', async () => {
  await seed(`friend_schedules/${OWNER}`, { ownerName: 'x', isRegular: false });
  const snap = await assertSucceeds(getDoc(doc(anon(), 'friend_schedules', OWNER)));
  assert.equal(snap.exists(), true);
  const missing = await assertSucceeds(getDoc(doc(anon(), 'friend_schedules', 'nobody')));
  assert.equal(missing.exists(), false);
});
test('FS-07 friend_schedules list/query 거부(미인증·인증·소유자 필터 포함)', async () => {
  await seed(`friend_schedules/${OWNER}`, { ownerName: 'x', isRegular: false });
  await assertFails(getDocs(collection(anon(), 'friend_schedules')));
  await assertFails(getDocs(collection(asOwner(), 'friend_schedules')));
  await assertFails(getDocs(query(collection(asOwner(), 'friend_schedules'), where('ownerName', '==', 'x'))));
});

// ── 다른 컬렉션 ──
test('FS-08 app_config get 허용, list·write 거부', async () => {
  await seed('app_config/version', { latestVersionCode: 24 });
  await assertSucceeds(getDoc(doc(anon(), 'app_config', 'version')));
  await assertFails(getDocs(collection(anon(), 'app_config')));
  await assertFails(setDoc(doc(asOwner(), 'app_config', 'version'), { latestVersionCode: 99 }));
});
test('FS-09 삭제된 health_tips는 get·list·write 모두 거부', async () => {
  await seed('health_tips/t1', { icon: 'a', title: 'b', content: 'c' });
  await assertFails(getDoc(doc(anon(), 'health_tips', 't1')));
  await assertFails(getDocs(collection(anon(), 'health_tips')));
  await assertFails(setDoc(doc(asOwner(), 'health_tips', 't2'), { icon: 'x' }));
  await assertFails(deleteDoc(doc(asOwner(), 'health_tips', 't1')));
});
test('FS-10 정의 안 된 컬렉션·friend_schedules 하위 컬렉션 read/write 거부', async () => {
  await assertFails(getDoc(doc(anon(), 'users', OWNER)));
  await assertFails(setDoc(doc(asOwner(), 'users', OWNER), { a: 1 }));
  await assertFails(setDoc(doc(asOwner(), `friend_schedules/${OWNER}/sub`, 'x'), { a: 1 }));
  await assertFails(getDoc(doc(anon(), `friend_schedules/${OWNER}/sub`, 'x')));
});

// ── legacy 경계 (#30) ──
test('FS-11 legacy 문서(generation·revoked 없음)를 새 앱 payload로 소유자 set 허용(전환 호환)', async () => {
  await seed(`friend_schedules/${OWNER}`, { ownerName: 'old', isRegular: false, assignedDates: {} });
  await assertSucceeds(setDoc(doc(asOwner(), 'friend_schedules', OWNER), appPayload(1)));
});
test('FS-12 구버전 앱 형식(generation 없음) 소유자 set 허용', async () => {
  const legacy = appPayload(1);
  delete legacy.generation; delete legacy.revoked;
  await assertSucceeds(setDoc(doc(asOwner(), 'friend_schedules', OWNER), legacy));
});

// ── 기존 OBS 결함의 회귀: 형식/크기 제한과 v2 중지 기록 보호 ──
// 아래는 "허용된다"가 현재 사실이라 assertSucceeds로 기록한다. D7 rules 채택 시 거부로 뒤집혀야 하는 행.
test('FS-OBS-1 형식 위반 소유자 write 거부', async () => {
  await assertFails(setDoc(doc(asOwner(), 'friend_schedules', OWNER),
    { ownerName: 12345, isRegular: 'yes', pattern: 'not-a-list', evil: { nested: true } }));
});
test('FS-OBS-2 크기 경계 초과 거부', async () => {
  const big = {};
  for (let i = 0; i < 6000; i++) big[`k${i}`] = '휴';
  await assertFails(setDoc(doc(asOwner(), 'friend_schedules', OWNER),
    appPayload(1, { assignedDates: big, ownerName: 'x'.repeat(5000) })));
});
test('FS-OBS-3 v2 중지 후 delete/옛 회차 재생성 거부', async () => {
  const db = asOwner();
  await assertSucceeds(setDoc(doc(db, 'friend_schedules', OWNER), v2Payload(3)));
  await assertSucceeds(setDoc(doc(db, 'friend_schedules', OWNER), stopped(3, 2)));
  await assertFails(deleteDoc(doc(db, 'friend_schedules', OWNER)));
  await assertFails(setDoc(doc(db, 'friend_schedules', OWNER), v2Payload(2)));
  await assertFails(setDoc(doc(db, 'friend_schedules', OWNER), appPayload(99)));
  const snap = await getDoc(doc(anon(), 'friend_schedules', OWNER));
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().generation, 3);
  assert.equal(snap.data().revoked, true);
  assert.equal(snap.data().ownerName, undefined);
});
test('FS-OBS-4 v2 revoked 위에 낮은/같은 회차 active 거부', async () => {
  await seed(`friend_schedules/${OWNER}`, stopped(5, 2));
  await assertFails(setDoc(doc(asOwner(), 'friend_schedules', OWNER), v2Payload(4, 3)));
  await assertFails(setDoc(doc(asOwner(), 'friend_schedules', OWNER), v2Payload(5, 3)));
});

const SESSION = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const NEXT_SESSION = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
const v2Payload = (gen = 1, rev = 1, extra = {}) => appPayload(gen, {
  protocolVersion: 2, session: SESSION, revision: rev, ...extra,
});
const stopped = (gen = 1, rev = 1, session = SESSION) => ({
  protocolVersion: 2, session, generation: gen, revision: rev,
  revoked: true, updatedAt: serverTimestamp(),
});

test('v2 정상 수정, 오래된/동일 revision 거부, 새 세션 재공유', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  await assertSucceeds(setDoc(ref, v2Payload()));
  await assertSucceeds(setDoc(ref, v2Payload(1, 3, {ownerName:'B'})));
  await assertFails(setDoc(ref, v2Payload(1, 2)));
  await assertFails(setDoc(ref, v2Payload(1, 3, {ownerName:'A'})));
  await assertFails(setDoc(ref, v2Payload(1, 4, {session:NEXT_SESSION})));
  await assertSucceeds(setDoc(ref, stopped(1, 4)));
  await assertFails(setDoc(ref, v2Payload(2, 1)));
  await assertSucceeds(setDoc(ref, v2Payload(2, 1, {session:NEXT_SESSION})));
  await assertFails(setDoc(ref, stopped(1, 99)));
});

test('legacy -> v2 전환, 기존 public get 유지, downgrade/delete 거부', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  await assertSucceeds(setDoc(ref, appPayload(8)));
  await assertFails(setDoc(ref, v2Payload(8)));
  await assertSucceeds(setDoc(ref, v2Payload(9)));
  assert.equal((await getDoc(doc(anon(), 'friend_schedules', OWNER))).data().ownerName, '홍길동');
  await assertFails(setDoc(ref, appPayload(10)));
  await assertFails(deleteDoc(ref));
});

test('legacy writer와 불규칙/null payload 호환', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  const data = appPayload(1, {isRegular:false, pattern:null, todayIndex:null, startDate:null,
    assignedDates:null, shiftColors:null});
  delete data.generation; delete data.revoked;
  await assertSucceeds(setDoc(ref, data));
  await assertSucceeds(deleteDoc(ref));
  await assertSucceeds(setDoc(ref, {...data, ...v2Payload(1), isRegular:false,
    pattern:null, todayIndex:null, startDate:null}));
});

test('legacy 기존 긴 이름 보존은 허용, 새 초과 이름은 거부; v2는80자 제한', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  await seed(`friend_schedules/${OWNER}`, appPayload(1, {ownerName:'x'.repeat(100)}));
  await assertSucceeds(setDoc(ref, appPayload(2, {ownerName:'x'.repeat(100)})));
  await assertFails(setDoc(ref, appPayload(2, {ownerName:'y'.repeat(100)})));
  await assertFails(setDoc(ref, v2Payload(3, 1, {ownerName:'x'.repeat(100)})));
  await assertSucceeds(setDoc(ref, v2Payload(3, 1, {ownerName:'x'.repeat(80)})));
});

test('v2 tombstone에는 이름/근무표 잔존 금지; 잘못된 타입/추가 필드/시간 거부', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  for (const bad of [
    {...stopped(), ownerName:'private'}, {...stopped(), pattern:['private']},
    v2Payload(1, 1, {ownerName:123}), v2Payload(1, 1, {isRegular:'true'}),
    v2Payload(1, 1, {unexpected:true}), v2Payload(1, 1, {todayIndex:4}),
    v2Payload(1, 1, {pattern:[]}), v2Payload(1, 1, {revision:0}),
    v2Payload(1, 1, {updatedAt:new Date(0)}), v2Payload(1, 1, {protocolVersion:3}),
    v2Payload(1, 1, {generation:1.5}), v2Payload(1, 1, {session:'short'}),
  ]) await assertFails(setDoc(ref, bad));
});

test('패턴/맵/name 경계는 허용하고 각각 초과는 거부', async () => {
  const ref = doc(asOwner(), 'friend_schedules', OWNER);
  const map = Object.fromEntries(Array.from({length:5000}, (_,i)=>[`k${i}`,'D']));
  await assertSucceeds(setDoc(ref, v2Payload(1, 1, {ownerName:'x'.repeat(80), pattern:Array(128).fill('D'), assignedDates:map})));
  for (const extra of [{ownerName:'x'.repeat(81)}, {pattern:Array(129).fill('D')},
    {assignedDates:{...map, overflow:'D'}}, {shiftColors:{...map, overflow:1}}]) {
    await assertFails(setDoc(ref, v2Payload(1, 2, extra)));
  }
});

test('v2 소유권/목록 차단은 unchanged', async () => {
  await assertFails(setDoc(doc(asOther(), 'friend_schedules', OWNER), stopped()));
  await assertFails(setDoc(doc(anon(), 'friend_schedules', OWNER), v2Payload()));
  await assertSucceeds(setDoc(doc(asOwner(), 'friend_schedules', OWNER), stopped()));
  await assertFails(getDocs(collection(asOwner(), 'friend_schedules')));
});
