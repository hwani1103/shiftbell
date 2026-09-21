// 카드별 확대 캡처(디자인 세부 확인용). BASE=... node clip.mjs
import { chromium } from 'playwright-core';
import path from 'node:path';
const BASE = process.env.BASE || 'http://127.0.0.1:5010';
const OUT = path.resolve('shots');
const browser = await chromium.launch({ channel: process.env.BROWSER || 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: process.env.SCHEME || 'light', locale: 'ko-KR' });
const page = await ctx.newPage();
await page.goto(BASE, { waitUntil: 'networkidle' });
await page.fill('input[name="email"]', 'rlaworms0905@naver.com');
await page.fill('input[name="password"]', process.env.PW || 'emu-pass-1234');
await page.click('button[type="submit"]');
await page.waitForSelector('.kpis', { timeout: 20000 });
await page.waitForTimeout(1400);
const range = process.env.RANGE;
if (range) { await page.click(`.seg button[data-key="${range}"]`); await page.waitForTimeout(1300); }
const cards = { installs: '#ch-installs', behavior: '.card:has(.hbars)', dist: '.card:has(.dist)', retention: '.card:has(.ret)', ads: '.card:has(#ch-ads)', engage: '.card:has(#ch-sessions)', users: '.card:has(#ch-users)' };
for (const [name, sel] of Object.entries(cards)) {
  const el = page.locator(sel).first();
  const target = name === 'installs' ? page.locator('.card:has(#ch-installs)').first() : el;
  await target.scrollIntoViewIfNeeded();
  await page.waitForTimeout(900);
  await target.screenshot({ path: `${OUT}/clip-${name}${range ? '-' + range : ''}.png` });
}
await browser.close();
console.log('clips saved');
