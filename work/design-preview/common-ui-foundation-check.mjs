import { chromium } from '../../admin_dashboard/tools/node_modules/playwright-core/index.mjs';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const preview = new URL('./common-ui-foundation-preview.html', import.meta.url);
const browser = await chromium.launch({executablePath:'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',headless:true});
try {
  const page = await browser.newPage({viewport:{width:736,height:1000}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto(preview.href);
  const frame=page.frames().find(f=>f!==page.mainFrame());
  await frame.waitForSelector('#shiftbell-foundation .sf-phone');
  await frame.locator('[data-open="name"]').click();
  await frame.locator('#sf-new-name').fill('오후');
  await frame.locator('[data-confirm]').click();
  const added=await frame.locator('.sf-card .sf-chip').last().textContent();
  if(added!=='오후')throw Error('Preview addition failed');
  await frame.locator('[data-open="delete"]').click();
  await frame.locator('[data-close]').first().click();
  const widths=[];
  for(const width of [736,320]){
    await page.setViewportSize({width,height:1100});
    const contentHeight=await frame.evaluate(()=>document.body.scrollHeight);
    await page.locator('iframe').evaluate((element,height)=>element.style.height=height+'px',contentHeight);
    await page.screenshot({path:fileURLToPath(new URL('./common-ui-foundation-'+width+'.png',import.meta.url)),fullPage:true});
    const overflow=await frame.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth);
    widths.push({width,overflow});
    if(overflow)throw Error('Preview horizontal overflow '+width);
  }
  if(errors.length)throw Error(errors.join('\n'));
  const result={added,errors,widths,note:'HTML preview only; not Flutter/device verification'};
  await fs.writeFile(new URL('./common-ui-foundation-check.json',import.meta.url),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result));
} finally {await browser.close();}
