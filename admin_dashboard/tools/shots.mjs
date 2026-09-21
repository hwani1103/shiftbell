// admin_dashboard/tools/shots.mjs - 에뮬레이터에서 대시보드를 실제 브라우저(Chrome)로 열어 화면·동작·보안 규칙을 검증한다.
//   BASE=http://127.0.0.1:5010 node shots.mjs
// 결과: tools/shots/*.png 와 콘솔에 PASS/FAIL 요약.

import { chromium } from 'playwright-core';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

const BASE = process.env.BASE || 'http://127.0.0.1:5010';
const OUT = path.resolve('shots');
await mkdir(OUT, { recursive: true });

const ADMIN = { email: 'rlaworms0905@naver.com', password: 'emu-pass-1234' };
const results = [];
const check = (name, ok, extra = '') => { results.push({ name, ok }); console.log(`${ok ? '✅ PASS' : '❌ FAIL'}  ${name}${extra ? '  · ' + extra : ''}`); };

const browser = await chromium.launch({ channel: process.env.BROWSER || 'chrome', headless: true });
const errors = [];

async function newPage({ width = 390, height = 844, scheme = 'light', dpr = 2, mobile = true } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: dpr, colorScheme: scheme, isMobile: mobile, hasTouch: mobile, locale: 'ko-KR', timezoneId: 'Asia/Seoul' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error' && !/favicon|icon-192|icon-512|Failed to load resource.*(40[14])/.test(m.text())) errors.push(`console: ${m.text()}`); });
  return { ctx, page };
}

async function login(page, { email, password, remember = true }) {
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.fill('input[name="email"]', email);
  await page.fill('input[name="password"]', password);
  const box = page.locator('input[name="remember"]');
  if ((await box.isChecked()) !== remember) await page.locator('.check').click();
  await page.click('button[type="submit"]');
}

// 1) 로그인 화면(모바일)
{
  const { ctx, page } = await newPage();
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForSelector('#login');
  await page.screenshot({ path: `${OUT}/01-login-mobile.png` });
  check('로그인 화면이 뜬다', await page.locator('#login').isVisible());

  // 2) 틀린 비밀번호
  await page.fill('input[name="email"]', ADMIN.email);
  await page.fill('input[name="password"]', 'wrong-password');
  await page.click('button[type="submit"]');
  await page.waitForSelector('.msg.err');
  const msg = (await page.textContent('.msg.err')) || '';
  check('틀린 비밀번호는 한국어 오류를 보여준다', /맞지 않아요/.test(msg), msg.trim());
  await page.screenshot({ path: `${OUT}/02-login-error.png` });
  await ctx.close();
}

// 3) 로그인 → 대시보드(모바일, 라이트)
{
  const { ctx, page } = await newPage();
  await login(page, ADMIN);
  await page.waitForSelector('.kpis', { timeout: 20000 });
  await page.waitForTimeout(1300); // 차트 애니메이션
  await page.screenshot({ path: `${OUT}/03-dashboard-30d-mobile.png`, fullPage: true });
  const kpiCount = await page.locator('.kpi').count();
  check('대시보드에 KPI 카드 4개', kpiCount === 4, `count=${kpiCount}`);
  check('사용자 추이 차트(SVG)가 그려진다', (await page.locator('#ch-users svg path.line').count()) >= 1);
  check('설치·삭제 막대가 그려진다', (await page.locator('#ch-installs svg rect.bar').count()) > 5);
  check('데모 문구 없이 운영 모드(모의 데이터는 footer에 명시)', /데모\(모의\)/.test((await page.textContent('.foot')) || ''));
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('가로 스크롤이 생기지 않는다(390px)', overflow <= 1, `overflow=${overflow}`);

  // 툴팁(터치 훑기 대신 pointermove)
  const box = await page.locator('#ch-users .hit').boundingBox();
  await page.mouse.move(box.x + box.width * 0.6, box.y + 40);
  await page.waitForTimeout(150);
  check('차트 위에 포인터를 올리면 툴팁이 뜬다', await page.locator('#ch-users .tip').isVisible());
  await page.locator('#ch-users').scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${OUT}/04-tooltip.png` });

  // 기간 전환
  for (const r of [7, 100, 365]) {
    await page.click(`.seg button[data-key="${r}"]`);
    await page.waitForTimeout(1200);
    const pressed = await page.locator(`.seg button[data-key="${r}"]`).getAttribute('aria-pressed');
    check(`${r}일 기간 전환`, pressed === 'true');
    if (r === 365) await page.screenshot({ path: `${OUT}/05-dashboard-365d-mobile.png`, fullPage: true });
  }
  await page.click('.seg button[data-key="30"]');

  // 범례 토글
  await page.click('.chip[data-key="wau"]');
  check('범례를 끄면 해당 선이 사라진다', (await page.locator('#ch-users svg path.line').count()) === 2);

  // 이벤트 상세 시트
  await page.locator('li[data-event="alarm_dismissed"]').scrollIntoViewIfNeeded();
  await page.click('li[data-event="alarm_dismissed"]');
  await page.waitForSelector('.sheet #ch-event svg');
  await page.waitForTimeout(900);
  check('이벤트를 누르면 상세 시트와 차트가 뜬다', await page.locator('.sheet').isVisible());
  await page.screenshot({ path: `${OUT}/06-event-sheet.png` });
  await page.click('.sheet [data-action="close-sheet"]');

  // 분포 탭
  await page.locator('.tab[data-key="device"]').scrollIntoViewIfNeeded();
  await page.click('.tab[data-key="device"]');
  check('분포 탭 전환(기기)', (await page.locator('.dlegend li').count()) >= 3);

  // 계정 메뉴 + 비밀번호 변경 검증
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.click('.avatar');
  await page.waitForSelector('.sheet .who');
  await page.screenshot({ path: `${OUT}/07-account-menu.png` });
  await page.click('[data-action="pwd"]');
  await page.fill('input[name="cur"]', ADMIN.password);
  await page.fill('input[name="next"]', '123');
  await page.fill('input[name="again"]', '123');
  await page.click('#pwform button[type="submit"]');
  check('6자 미만 새 비밀번호는 거부', /6자 이상/.test((await page.textContent('#pwmsg')) || ''));
  await page.fill('input[name="next"]', 'new-pass-5678');
  await page.fill('input[name="again"]', 'new-pass-9999');
  await page.click('#pwform button[type="submit"]');
  check('확인 값이 다르면 거부', /일치하지 않아요/.test((await page.textContent('#pwmsg')) || ''));
  await page.fill('input[name="cur"]', 'not-my-password');
  await page.fill('input[name="again"]', 'new-pass-5678');
  await page.click('#pwform button[type="submit"]');
  await page.waitForFunction(() => /맞지 않아요/.test(document.querySelector('#pwmsg')?.textContent || ''), null, { timeout: 8000 });
  check('현재 비밀번호가 틀리면 변경 실패', /맞지 않아요/.test((await page.textContent('#pwmsg')) || ''));
  await page.fill('input[name="cur"]', ADMIN.password);
  await page.click('#pwform button[type="submit"]');
  await page.waitForSelector('.toast', { timeout: 8000 });
  check('올바르게 입력하면 비밀번호가 변경된다', /변경했어요/.test((await page.textContent('.toast')) || ''));

  // 로그아웃 → 새 비밀번호로 재로그인
  await page.click('.avatar');
  await page.click('[data-action="logout"]');
  await page.waitForSelector('#login');
  check('로그아웃하면 로그인 화면으로 돌아온다', true);
  await page.fill('input[name="email"]', ADMIN.email);
  await page.fill('input[name="password"]', 'new-pass-5678');
  await page.click('button[type="submit"]');
  await page.waitForSelector('.kpis', { timeout: 20000 });
  check('바꾼 비밀번호로 다시 로그인된다', true);
  await ctx.close();
}

// 4) 로그인 유지(remember): 같은 컨텍스트에서 새 탭으로 열어도 로그인 상태
{
  const { ctx, page } = await newPage();
  await login(page, { email: ADMIN.email, password: 'new-pass-5678', remember: true });
  await page.waitForSelector('.kpis', { timeout: 20000 });
  const page2 = await ctx.newPage();
  await page2.goto(BASE, { waitUntil: 'domcontentloaded' });
  await page2.waitForSelector('.kpis, #login', { timeout: 15000 });
  check('로그인 유지: 새 탭에서도 로그인 상태', await page2.locator('.kpis').count() > 0);
  await ctx.close();
}

// 5) 다크 모드 + 데스크톱
{
  const { ctx, page } = await newPage({ scheme: 'dark' });
  await login(page, { email: ADMIN.email, password: 'new-pass-5678' });
  await page.waitForSelector('.kpis', { timeout: 20000 });
  await page.waitForTimeout(1300);
  await page.screenshot({ path: `${OUT}/08-dashboard-dark-mobile.png`, fullPage: true });
  await ctx.close();
}
{
  const { ctx, page } = await newPage({ width: 1280, height: 900, dpr: 1, mobile: false });
  await login(page, { email: ADMIN.email, password: 'new-pass-5678' });
  await page.waitForSelector('.kpis', { timeout: 20000 });
  await page.waitForTimeout(1300);
  await page.screenshot({ path: `${OUT}/09-dashboard-desktop.png`, fullPage: true });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('데스크톱에서도 가로 넘침 없음', overflow <= 1);
  await ctx.close();
}

// 6) 작은 화면(320px) 레이아웃
{
  const { ctx, page } = await newPage({ width: 320, height: 640 });
  await login(page, { email: ADMIN.email, password: 'new-pass-5678' });
  await page.waitForSelector('.kpis', { timeout: 20000 });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${OUT}/10-dashboard-320.png`, fullPage: true });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('320px 작은 화면에서 가로 넘침 없음', overflow <= 1, `overflow=${overflow}`);
  await ctx.close();
}


// 6-b) 삼성 인터넷(갤럭시 S24 크기·UA) + 손가락으로 차트 훑기(touch-action: pan-y)
{
  const ctx = await browser.newContext({
    viewport: { width: 412, height: 915 }, deviceScaleFactor: 2.625, isMobile: true, hasTouch: true, locale: 'ko-KR', timezoneId: 'Asia/Seoul',
    userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-S928N) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/24.0 Chrome/117.0.0.0 Mobile Safari/537.36',
  });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(`pageerror(samsung): ${e.message}`));
  await login(page, { email: ADMIN.email, password: 'new-pass-5678' });
  await page.waitForSelector('.kpis', { timeout: 20000 });
  await page.waitForTimeout(1300);
  await page.screenshot({ path: `${OUT}/12-galaxy-samsung.png` });
  await page.screenshot({ path: `${OUT}/12b-galaxy-samsung-full.png`, fullPage: true });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('삼성 인터넷(412px)에서 가로 넘침 없음', overflow <= 1, `overflow=${overflow}`);
  const ua = await page.evaluate(() => navigator.userAgent);
  check('삼성 인터넷 UA로 실행됨', /SamsungBrowser/.test(ua));

  // 손가락으로 좌우로 훑을 때 툴팁이 따라오는지(세로 스크롤은 브라우저에 맡김)
  await page.locator('#ch-users').scrollIntoViewIfNeeded();
  const box = await page.locator('#ch-users .hit').boundingBox();
  const cdp = await ctx.newCDPSession(page);
  const y = box.y + 60;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x + box.width * 0.2, y }] });
  for (let k = 1; k <= 8; k += 1) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: box.x + box.width * (0.2 + k * 0.08), y }] });
  }
  const tipShown = await page.locator('#ch-users .tip').isVisible();
  await page.screenshot({ path: `${OUT}/13-galaxy-touch-tooltip.png` });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  check('손가락으로 차트를 훑으면 툴팁이 따라온다', tipShown);
  await ctx.close();
}

// 7) 보안 규칙: 관리자가 아닌 계정 / 이메일 미인증 계정은 데이터를 못 읽는다
for (const [label, acct] of [['다른 사람 계정', { email: 'someone@example.com', password: 'other-pass-1234' }],
  ['이메일 미인증 가짜 관리자', { email: 'fakeworms0905@naver.com', password: 'x-pass-1234' }]]) {
  const { ctx, page } = await newPage();
  await login(page, acct);
  await page.waitForSelector('.empty, .kpis', { timeout: 20000 });
  const denied = await page.locator('.empty b').first().textContent().catch(() => '');
  check(`보안 규칙: ${label}는 데이터를 못 본다`, /열람 권한이 없어요/.test(denied || ''), (denied || '').trim());
  if (label === '다른 사람 계정') await page.screenshot({ path: `${OUT}/11-denied.png` });
  await ctx.close();
}

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n── 결과: ${results.length - failed.length}/${results.length} 통과${errors.length ? ` · 콘솔 오류 ${errors.length}건` : ' · 콘솔 오류 없음'}`);
errors.slice(0, 12).forEach((e) => console.log('   ', e));
process.exitCode = failed.length ? 1 : 0;
