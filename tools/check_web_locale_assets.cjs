// Functional head/manifest checks. No browser layout or screenshot checks.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'web/locale_bootstrap.js'), 'utf8');
const shell = fs.readFileSync(path.join(root, 'web/index.html'), 'utf8');
const defaultManifest = JSON.parse(fs.readFileSync(path.join(root, 'web/manifest.json'), 'utf8'));
assert.equal(defaultManifest.name, 'ShiftBell');
assert.equal(defaultManifest.short_name, 'ShiftBell');
assert.match(shell, /<title>ShiftBell<\/title>/);
assert.ok(shell.indexOf('locale_bootstrap.js') < shell.indexOf('flutter_bootstrap.js'));
let checks = 0;
for (const [primary, expected] of [['pt-BR', 'pt'], ['pt-PT', 'pt'], ['de-DE', 'de'], ['en-GB', 'en'], ['hi-IN', 'hi'], ['ja-JP', 'en'], ['ko-KR', 'ko'], ['', 'en']]) {
  const elements = new Map();
  const listeners = {};
  const document = {documentElement: {}, title: '', querySelector(selector) {
    if (!elements.has(selector)) elements.set(selector, {setAttribute(key, value) { this[key] = value; }});
    return elements.get(selector);
  }};
  const navigator = {languages: [primary, 'ko-KR'], language: primary};
  vm.runInNewContext(script, {document, navigator, window: {addEventListener(name, fn) { listeners[name] = fn; }}});
  assert.equal(document.documentElement.lang, expected);
  const manifestPath = elements.get('link[rel="manifest"]').href;
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'web', manifestPath), 'utf8'));
  assert.equal(manifest.lang, expected);
  if (expected !== 'ko') {
    const arb = JSON.parse(fs.readFileSync(path.join(root, `lib/l10n/app_${expected}.arb`), 'utf8'));
    assert.equal(document.title, `${arb.appTitle} - ${arb.friendShareTitle}`);
    assert.equal(manifest.description, arb.publicWebShareBody);
    assert.doesNotMatch(JSON.stringify([...elements.values()]) + JSON.stringify(manifest), /[가-힣]/);
  }
  navigator.languages = ['hi-IN', 'ko-KR'];
  listeners.languagechange();
  assert.equal(document.documentElement.lang, 'hi');
  assert.equal(elements.get('link[rel="manifest"]').href, 'manifest_hi.json');
  assert.doesNotMatch(document.title, /[가-힣]/);
  checks++;
}
console.log(`PASS: ${checks} web locale/fallback cases and language-change checks; no layout validation.`);
