// admin_dashboard/public/assets/js/store.js - 대시보드 문서(summary/series/events) 읽기.

const EMPTY_SERIES = { dates: [], dau: [], wau: [], mau: [], newUsers: [], sessions: [], engagementSec: [], installs: [], uninstalls: [], adImpressions: [], adClicks: [], adRevenue: [] };

/** demo=true면 모의 데이터(로컬 ?demo 전용). 아니면 Firestore dashboard/* 를 읽는다. */
export async function loadDocs({ demo = false } = {}) {
  if (demo) {
    const { buildMockDocs } = await import('./mock.js');
    return buildMockDocs();
  }
  const col = firebase.firestore().collection('dashboard');
  const [s, ser, ev] = await Promise.all(['summary', 'series', 'events'].map((id) => col.doc(id).get()));
  if (!s.exists) throw Object.assign(new Error('아직 동기화된 데이터가 없어요.'), { code: 'no-data' });
  return {
    summary: s.data(),
    series: ser.exists ? ser.data() : { ...EMPTY_SERIES },
    events: ev.exists ? ev.data() : { dates: [], series: {}, totals: {} },
  };
}
