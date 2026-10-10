// admin_dashboard/public/assets/js/store.js - 대시보드 문서(summary/series/events) 읽기.

const EMPTY_SERIES = { dates: [], dau: [], wau: [], mau: [], newUsers: [], sessions: [], engagementSec: [], installs: [], uninstalls: [], adImpressions: [], adClicks: [], adRevenue: [] };

/** demo=true면 모의 데이터(로컬 ?demo 전용). 아니면 Firestore dashboard/* 를 읽는다. */
export async function loadDocs({ demo = false, retry = true } = {}) {
  if (demo) {
    const { buildMockDocs } = await import('./mock.js');
    return buildMockDocs({ today: new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Seoul" }) });
  }
  const col = firebase.firestore().collection('dashboard');
  const [s, ser, ev, ops] = await Promise.all(['summary', 'series', 'events', 'operations'].map((id) => col.doc(id).get({ source: 'server' })));
  if (!s.exists) throw Object.assign(new Error('아직 동기화된 데이터가 없어요.'), { code: 'no-data' });
  if (s.data().pipelineVersion >= 2 && [ser, ev, ops].some((doc) => !doc.exists || doc.data().updatedAt !== s.data().updatedAt)) {
    if (retry) return loadDocs({ retry: false });
    throw new Error('새 집계가 저장되는 중입니다. 잠시 후 다시 불러오세요.');
  }
  return {
    summary: s.data(),
    operations: ops.exists ? ops.data() : null,
    series: ser.exists ? ser.data() : { ...EMPTY_SERIES },
    events: ev.exists ? ev.data() : { dates: [], series: {}, totals: {} },
  };
}
