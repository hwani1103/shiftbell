#!/usr/bin/env node
// admin_dashboard/sync/sync.mjs
//
// GA4 → Firestore(dashboard/summary · series · events) 동기화.
//
//   node sync.mjs                 실제 GA4에서 읽어 Firestore에 쓴다(서비스 계정 필요)
//   node sync.mjs --mock          모의 데이터를 쓴다(에뮬레이터/데모용)
//   node sync.mjs --out ./out     Firestore 대신 JSON 파일 3개로 저장(확인용)
//
// 환경변수
//   GA4_PROPERTY_ID   기본 553838010
//   GA4_STREAM_ID     기본 15763725797  ← 출시 앱(android) 스트림만 집계. dev·웹 스트림은 제외한다.
//   FIREBASE_PROJECT_ID  기본 shiftbell-29f31
//   SERVICE_ACCOUNT_JSON 서비스 계정 키 JSON 문자열(GitHub Actions 시크릿용) 또는
//   GOOGLE_APPLICATION_CREDENTIALS 키 파일 경로(로컬용)
//   FIRESTORE_EMULATOR_HOST  있으면 에뮬레이터에 쓴다(자격 증명 불필요)

import { parseArgs } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { buildMockDocs } from '../public/assets/js/mock.js';
import { Ga4, DEFAULTS, makeAuthClient } from './lib/ga4.mjs';
import { buildDocs, table, ymd } from './lib/transform.mjs';

const { values: args } = parseArgs({
  options: {
    mock: { type: 'boolean', default: false },
    force: { type: 'boolean', default: false },
    out: { type: 'string' },
    days: { type: 'string', default: '400' },
  },
});

const env = process.env;
const propertyId = env.GA4_PROPERTY_ID || DEFAULTS.propertyId;
const streamId = env.GA4_STREAM_ID || DEFAULTS.streamId;
const projectId = env.FIREBASE_PROJECT_ID || 'shiftbell-29f31';
const days = Math.min(Math.max(parseInt(args.days, 10) || 400, 30), 500);

const iso = (d) => d.toISOString().slice(0, 10);
const daysAgo = (n) => { const d = new Date(); d.setUTCDate(d.getUTCDate() - n); return d; };

async function fetchReal() {
  const auth = makeAuthClient({ serviceAccountJson: env.SERVICE_ACCOUNT_JSON, keyFile: env.GOOGLE_APPLICATION_CREDENTIALS });
  const ga = new Ga4({ auth, propertyId, streamId });
  const webGa = new Ga4({ auth, propertyId, streamId: env.GA4_WEB_STREAM_ID || DEFAULTS.webStreamId });
  const cohortRange = { from: iso(daysAgo(45)), to: iso(daysAgo(15)) };

  // 핵심 리포트는 실패하면 동기화 자체를 중단(빈 문서로 덮어쓰지 않기 위함)
  const [core, eventsDaily] = await Promise.all([
    ga.runReport(ga.coreDaily(days)),
    ga.runReport(ga.eventsDaily(days)),
  ]);
  const dates = table(core).map((r) => ymd(r.d[0]));
  const eventRanges = [7, 30, 100, 365];
  const eventsByRange = Object.fromEntries(await Promise.all(eventRanges.map(async (range) => {
    const from = dates[Math.max(0, dates.length - range)];
    const to = dates[dates.length - 1];
    if (!from || !to) return [range, null];
    const report = await ga.runReport(ga.eventsSummary(from, to));
    return [range, { from, to, report }];
  })));
  // 나머지는 실패해도 대시보드 일부만 비워 두고 계속한다
  const [ads, appVersion, os, language, country, device, manufacturer, cohort, webFriendViews, countryDaily] = await Promise.all([
    ga.tryReport('광고', ga.adsDaily(days)),
    ga.tryReport('앱 버전 분포', ga.breakdown('appVersion')),
    ga.tryReport('OS 분포', ga.breakdown('operatingSystemVersion')),
    ga.tryReport('언어 분포', ga.breakdown('language')),
    ga.tryReport('국가 분포', ga.breakdown('country')),
    ga.tryReport('기기 분포', ga.breakdown('deviceModel')),
    ga.tryReport('제조사 분포', ga.breakdown('mobileDeviceBranding', 30)),
    ga.tryReport('리텐션', ga.cohort({ ...cohortRange, endOffset: 14 })),
    webGa.tryReport('웹 친구 근무표 열람', webGa.webFriendViews()),
    ga.tryReport('국가 일별 추이', ga.countryDaily(100)),
  ]);
  const operationsByRange = {};
  // Limit concurrency: eight optional reports at a time, not every range at once.
  for (const range of eventRanges) {
    const from = dates[Math.max(0, dates.length - range)]; const to = dates.at(-1);
    if (!from || !to) continue;
    const previousTo = iso(new Date(Date.parse(from) - 86400000));
    const previousFrom = iso(new Date(Date.parse(from) - Math.min(range, dates.length) * 86400000));
    const [current, previous, countries, previousCountries, countryEvents, manufacturers, manufacturerEvents] = await Promise.all([
      ga.tryReport('기간 이용자', ga.periodSummary(from, to)),
      ga.tryReport('직전 기간 이용자', ga.periodSummary(previousFrom, previousTo)),
      ga.tryReport('국가 운영 지표', ga.segmentSummary('country', from, to)),
      ga.tryReport('직전 국가 운영 지표', ga.segmentSummary('country', previousFrom, previousTo)),
      ga.tryReport('국가 기능 활용', ga.segmentEvents('country', from, to)),
      ga.tryReport('제조사 이용자', ga.segmentSummary('mobileDeviceBranding', from, to)),
      ga.tryReport('제조사 알람 관측', ga.segmentEvents('mobileDeviceBranding', from, to)),
    ]);
    operationsByRange[range] = { from, to, current, previous, countries, previousCountries, countryEvents, manufacturers, manufacturerEvents };
  }
  const docs = buildDocs({
    raw: { core, ads, eventsDaily, eventsByRange, appVersion, os, language, country, device, manufacturer, cohort, webFriendViews, countryDaily, operationsByRange },
    meta: { now: new Date(), propertyId, streamId, cohortRange, source: 'ga4' },
  });
  docs.summary.currency = core?.metadata?.currencyCode || 'USD';
  return docs;
}

async function openFirestore() {
  const { initializeApp, cert, applicationDefault } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  const opts = { projectId };
  if (!env.FIRESTORE_EMULATOR_HOST) {
    opts.credential = env.SERVICE_ACCOUNT_JSON ? cert(JSON.parse(env.SERVICE_ACCOUNT_JSON)) : applicationDefault();
  }
  return getFirestore(initializeApp(opts));
}

/** 이미 Firestore에 저장된 일별 데이터 일수(없으면 0). */
async function storedDays(db) {
  const snap = await db.collection('dashboard').doc('series').get();
  return snap.exists ? (snap.data()?.dates?.length ?? 0) : 0;
}

async function writeFirestore(db, docs) {
  const col = db.collection('dashboard');
  const batch = db.batch();
  for (const [name, doc] of Object.entries(docs)) {
    if (Buffer.byteLength(JSON.stringify(doc)) > 900000) throw new Error('Dashboard document exceeds safe size: ' + name);
    batch.set(col.doc(name), doc);
  }
  await batch.commit();
}

async function writeFiles(docs, dir) {
  await mkdir(dir, { recursive: true });
  for (const [name, doc] of Object.entries(docs)) {
    await writeFile(path.join(dir, `${name}.json`), JSON.stringify(doc, null, 2), 'utf8');
  }
}

const started = Date.now();
try {
  if (args.mock && !args.out && !env.FIRESTORE_EMULATOR_HOST) throw new Error('Mock data may only be written to files or an emulator.');
  const db = args.out ? null : await openFirestore();
  const syncDay = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
  if (db && !args.mock && !args.force) {
    const previous = await db.collection('dashboard').doc('summary').get();
    if (previous.data()?.pipelineVersion === 2 && previous.data()?.syncPolicy?.day === syncDay) {
      console.log('Already synchronized today; preserving one daily update.');
      process.exit(0);
    }
  }
  const docs = args.mock ? buildMockDocs() : await fetchReal();
  const n = docs.series.dates.length;
  // ⭐ 2026-09-23 - GA4 조회는 성공했는데 0건인 경우(권한 문제면 runReport가 403으로 먼저 던짐):
  //  - 이미 쌓인 데이터가 있으면 빈 값으로 덮어쓰지 않고 실패 처리(스트림 ID 오설정 등 이상 신호)
  //  - 처음부터 없으면(출시 버전 데이터가 아직 안 들어옴) 빈 문서를 써서 대시보드가 "아직 집계된 날짜가 없어요"를
  //    보여주게 하고 성공 처리 - 예전엔 여기서 매번 실패해 출시 전까지 3시간마다 Actions 실패가 쌓였음
  if (args.out) {
    if (!args.mock && n === 0) throw new Error('GA4에서 받은 일별 데이터가 0건입니다. 스트림 ID/속성 접근 권한을 확인하세요.');
    await writeFiles(docs, args.out);
  } else {
    // db opened before querying so the daily guard can avoid duplicate API calls.
    if (!args.mock && n === 0) {
      const prev = await storedDays(db);
      if (prev > 0) throw new Error(`GA4에서 받은 일별 데이터가 0건인데 기존 문서에는 ${prev}일치가 있어 덮어쓰지 않았습니다. 스트림 ID/속성 접근 권한을 확인하세요.`);
      console.log('ℹ️ 출시 버전(prod 스트림) 데이터가 아직 없어 빈 문서로 기록합니다 - 대시보드에는 "아직 집계된 날짜가 없어요"가 표시됩니다.');
    }
    await writeFirestore(db, docs);
  }
  const k = docs.summary.kpi;
  console.log(`✅ 동기화 완료(${args.mock ? '모의' : 'GA4'}) - ${n}일치, 최신 ${docs.summary.latest}, DAU ${k?.dau ?? '-'}, MAU ${k?.mau ?? '-'}, ${Date.now() - started}ms`);
  if (!args.mock) console.log(`   속성 ${propertyId} · 스트림 ${streamId}(출시 앱만 집계)`);
} catch (e) {
  console.error('❌ 동기화 실패:', e.message);
  process.exitCode = 1;
}
