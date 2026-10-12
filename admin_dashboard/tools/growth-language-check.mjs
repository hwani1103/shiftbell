import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const publicDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../public');
const out = path.resolve(publicDir, '../../artifacts/dashboard_country_language_2026_10_12/ui');
await mkdir(out, { recursive: true });
const server = createServer(async (req, res) => {
  const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.resolve(publicDir, '.' + (relative === '/' ? '/index.html' : relative));
  if (!file.startsWith(publicDir + path.sep)) { res.writeHead(403).end(); return; }
  try {
    const body = await readFile(file);
    res.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.svg') ? 'image/svg+xml' : 'text/html');
    res.end(body);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const results = [];
try {
  for (const width of [360, 752, 1440]) {
    const page = await browser.newPage({ viewport: {width, height: 900} });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.route('**/__/firebase/**', route => route.fulfill({body: '', contentType:'text/javascript'}));
    await page.goto('http://127.0.0.1:' + server.address().port + '/?demo');
    await page.locator('[data-action="section"][data-key="growth"]').click();
    await page.locator('#ch-country .hit').waitFor();
    assert.equal(await page.locator('.market-table thead').count(), 1);
    assert.equal(await page.locator('#ch-language').count(), 0);
    assert.equal(await page.locator('[data-action="language"]').count(), 0);
    assert.equal(await page.locator('.market-table thead th').nth(1).textContent(), '언어');
    const usKorean = page.locator('[data-action="country"]').filter({hasText:'미국'}).filter({hasText:'한국어'});
    const usEnglish = page.locator('[data-action="country"]').filter({hasText:'미국'}).filter({hasText:'영어'});
    const southAfrica = page.locator('[data-action="country"]').filter({hasText:'남아프리카공화국'}).filter({hasText:'영어'});
    assert.equal(await usKorean.count(),1);assert.equal(await usEnglish.count(),1);assert.equal(await southAfrica.count(),1);
    await usKorean.click();
    assert.ok((await page.locator('.market-chart-head').textContent()).includes('미국 / 한국어'));
    await usEnglish.focus();await page.keyboard.press('Enter');
    assert.ok((await page.locator('.market-chart-head').textContent()).includes('미국 / 영어'));
    await southAfrica.click();
    assert.ok((await page.locator('.market-chart-head').textContent()).includes('남아프리카공화국 / 영어'));
    await page.locator('[data-action="market-sort"][data-key="newUsers"]').click();
    await page.getByRole('button', {name:'7일', exact:true}).click();
    assert.equal(await page.locator('#ch-country .hit').count(),1);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await page.screenshot({path:out + '/growth-' + width + '.png', fullPage:true});
    await page.evaluate(() => document.documentElement.setAttribute('data-theme','dark'));
    await page.screenshot({path:out + '/growth-dark-' + width + '.png', fullPage:true});
    assert.deepEqual(errors, []);
    results.push({width, singleCountryLanguageTable:true, alarmSavedUsers:true, separateUSLanguages:true, southAfricaEnglish:true, keyboard:true, range:true, noPageOverflow:true, errors});
    await page.close();
  }
  await writeFile(path.resolve(out,'../browser-results.json'), JSON.stringify(results,null,2));
  console.log(JSON.stringify(results));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
