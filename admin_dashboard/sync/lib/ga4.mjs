// admin_dashboard/sync/lib/ga4.mjs
//
// GA4 Data API(v1beta) 호출부. 응답을 가공하는 로직은 transform.mjs에 있고, 여기는 "무엇을 어떻게 물어볼지"만 안다.
//
// ⭐ 출시 버전만 집계한다(사용자 요구): 모든 쿼리에 streamId 필터를 건다.
//   - 15763725797 = shiftbell (android)      ← 플레이 스토어에 출시된 앱(com.hwani1103.shiftbell)
//   - 15763791924 = shiftbell (android-dev)  ← 개발용 앱(제외)
//   - 15763713126 = shiftbell (web)          ← 친구 공유 웹 뷰어 방문자(제외, 앱 사용자가 아님)
//   Firebase 콘솔 → 프로젝트 설정 → 통합 → Google Analytics에서 확인한 값이며, 바뀌면 GA4_STREAM_ID로 덮어쓴다.

import { GoogleAuth } from 'google-auth-library';

export const DEFAULTS = {
  propertyId: '553838010',
  streamId: '15763725797',
};

const SCOPE = 'https://www.googleapis.com/auth/analytics.readonly';
const API = 'https://analyticsdata.googleapis.com/v1beta';

/** 서비스 계정 JSON(문자열 또는 파일 경로 환경변수)로 인증된 클라이언트를 만든다. */
export function makeAuthClient({ serviceAccountJson, keyFile } = {}) {
  const options = { scopes: [SCOPE] };
  if (serviceAccountJson) options.credentials = JSON.parse(serviceAccountJson);
  else if (keyFile) options.keyFile = keyFile;
  // 둘 다 없으면 GOOGLE_APPLICATION_CREDENTIALS 등 기본 자격 증명을 쓴다.
  return new GoogleAuth(options);
}

/** streamId 조건. 모든 리포트에 AND로 붙인다. */
export function streamFilter(streamId) {
  return { filter: { fieldName: 'streamId', stringFilter: { matchType: 'EXACT', value: String(streamId) } } };
}

/** 기존 필터와 streamId 필터를 합친다. */
export function withStream(streamId, extra) {
  const base = streamFilter(streamId);
  if (!extra) return base;
  return { andGroup: { expressions: [base, extra] } };
}

export class Ga4 {
  constructor({ auth, propertyId = DEFAULTS.propertyId, streamId = DEFAULTS.streamId, fetchImpl }) {
    this.auth = auth;
    this.propertyId = propertyId;
    this.streamId = streamId;
    this.fetch = fetchImpl;
  }

  async _token() {
    const client = await this.auth.getClient();
    const t = await client.getAccessToken();
    return typeof t === 'string' ? t : t.token;
  }

  async runReport(body) {
    const token = await this._token();
    const res = await (this.fetch ?? fetch)(`${API}/properties/${this.propertyId}:runReport`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    if (!res.ok) {
      const err = new Error(`GA4 runReport ${res.status}: ${text.slice(0, 400)}`);
      err.status = res.status;
      throw err;
    }
    return JSON.parse(text);
  }

  /** 실패해도 대시보드 전체를 막지 않는 부가 리포트용(광고·리텐션 등). 실패하면 null. */
  async tryReport(label, body, log = console) {
    try {
      return await this.runReport(body);
    } catch (e) {
      log.warn?.(`⚠️ ${label} 조회 실패(건너뜀): ${e.message}`);
      return null;
    }
  }

  // ─────────────────────────── 리포트 정의 ───────────────────────────

  /** 일별 핵심 지표(활성 사용자 1/7/28일, 신규, 세션, 참여시간). */
  coreDaily(days) {
    return {
      dateRanges: [{ startDate: `${days}daysAgo`, endDate: 'yesterday' }],
      dimensions: [{ name: 'date' }],
      metrics: [
        { name: 'active1DayUsers' },
        { name: 'active7DayUsers' },
        { name: 'active28DayUsers' },
        { name: 'newUsers' },
        { name: 'sessions' },
        { name: 'userEngagementDuration' },
      ],
      dimensionFilter: streamFilter(this.streamId),
      orderBys: [{ dimension: { dimensionName: 'date' } }],
      keepEmptyRows: true,
      limit: '100000',
    };
  }

  /** 일별 광고 지표. AdMob이 GA4에 연결돼 있지 않으면 값이 0이거나 오류가 난다(그땐 null 처리). */
  adsDaily(days) {
    return {
      dateRanges: [{ startDate: `${days}daysAgo`, endDate: 'yesterday' }],
      dimensions: [{ name: 'date' }],
      metrics: [{ name: 'publisherAdImpressions' }, { name: 'publisherAdClicks' }, { name: 'totalAdRevenue' }],
      dimensionFilter: streamFilter(this.streamId),
      orderBys: [{ dimension: { dimensionName: 'date' } }],
      keepEmptyRows: true,
      limit: '100000',
    };
  }

  /** 일별 × 이벤트별 횟수(설치=first_open, 삭제=app_remove, 사용자 행동 이벤트 전부). */
  eventsDaily(days) {
    return {
      dateRanges: [{ startDate: `${days}daysAgo`, endDate: 'yesterday' }],
      dimensions: [{ name: 'date' }, { name: 'eventName' }],
      metrics: [{ name: 'eventCount' }],
      dimensionFilter: streamFilter(this.streamId),
      orderBys: [{ dimension: { dimensionName: 'date' } }],
      limit: '250000',
    };
  }

  /** 최근 30일 이벤트 요약(횟수 + 실행한 사용자 수). */
  eventsSummary() {
    return {
      dateRanges: [{ startDate: '30daysAgo', endDate: 'yesterday' }],
      dimensions: [{ name: 'eventName' }],
      metrics: [{ name: 'eventCount' }, { name: 'totalUsers' }],
      dimensionFilter: streamFilter(this.streamId),
      orderBys: [{ metric: { metricName: 'eventCount' }, desc: true }],
      limit: '100',
    };
  }

  /** 최근 28일 활성 사용자 분포(앱 버전·OS·언어·국가·기기). */
  breakdown(dimension, limit = 8) {
    return {
      dateRanges: [{ startDate: '28daysAgo', endDate: 'yesterday' }],
      dimensions: [{ name: dimension }],
      metrics: [{ name: 'activeUsers' }],
      dimensionFilter: streamFilter(this.streamId),
      orderBys: [{ metric: { metricName: 'activeUsers' }, desc: true }],
      limit: String(limit),
    };
  }

  /**
   * 리텐션 코호트: 첫 방문일이 [from, to]인 사용자가 N일차에 다시 활성이 된 비율.
   * 코호트 리포트는 dateRanges를 쓰지 않고 cohortSpec을 쓴다.
   */
  cohort({ from, to, endOffset = 14 }) {
    return {
      dimensions: [{ name: 'cohort' }, { name: 'cohortNthDay' }],
      metrics: [{ name: 'cohortActiveUsers' }],
      cohortSpec: {
        cohorts: [{ name: 'c', dimension: 'firstSessionDate', dateRange: { startDate: from, endDate: to } }],
        cohortsRange: { granularity: 'DAILY', startOffset: 0, endOffset },
      },
      dimensionFilter: streamFilter(this.streamId),
    };
  }
}
