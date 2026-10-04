import { chromium } from 'playwright-core';
import { mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const out = '../../build/dashboard_chart_check';
await mkdir(out, { recursive: true });
try {
  for (const width of [360, 752]) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/__/firebase/**', route => route.fulfill({ body: '', contentType: 'text/javascript' }));
    await page.goto('http://127.0.0.1:8767/?demo');
    await page.locator('#ch-users .hit').waitFor();
    assert.equal(await page.getByRole('button', { name: 'WAU 주간' }).count(), 0);
    assert.equal(await page.locator('#ch-installs path.line').count(), 2);
    await page.getByRole('button', { name: '7일', exact: true }).click();
    const hit = page.locator('#ch-users .hit');
    await hit.scrollIntoViewIfNeeded();
    const box = await hit.boundingBox();
    await page.mouse.click(box.x + box.width * .35, box.y + box.height * .6);
    const line = page.locator('#ch-users .xh');
    const x1 = await line.getAttribute('x1');
    await page.mouse.move(0, 0);
    assert.equal(await line.evaluate(e => e.style.display), '');
    assert.equal(await page.locator('#ch-users .tip').evaluate(e => e.hidden), false);
    await page.mouse.move(box.x + box.width * .35, box.y + box.height * .6);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width * .85, box.y + box.height * .6, { steps: 5 });
    await page.mouse.up();
    assert.notEqual(await line.getAttribute('x1'), x1);
    const selected = await page.locator('#ch-users .tip .td').textContent();
    await page.setViewportSize({ width: width + 10, height: 900 });
    await page.waitForTimeout(100);
    assert.equal(await page.locator('#ch-users .tip .td').textContent(), selected);
    assert.equal(await page.locator('#ch-users .xh').evaluate(e => e.style.display), '');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await page.screenshot({ path: `${out}/chart-${width}.png`, fullPage: true });
    assert.deepEqual(errors, []);
    console.log(`PASS ${width}: no WAU, line series, persistent selection, drag, resize, no overflow`);
    await page.close();
  }
} finally { await browser.close(); }
