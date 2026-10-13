import test from 'node:test';
import assert from 'node:assert/strict';
import { alreadySyncedInSlot, syncPolicy } from '../lib/sync-policy.mjs';
const at = value => new Date(value);
const saved = value => ({ pipelineVersion: 2, syncPolicy: syncPolicy(at(value)) });
test('12:17 KST refresh is followed by 15:17 even on the same date', () => {
  const noon = saved('2026-10-11T03:17:00Z');
  assert.equal(alreadySyncedInSlot(noon, at('2026-10-11T03:40:00Z')), true);
  assert.equal(alreadySyncedInSlot(noon, at('2026-10-11T06:16:59Z')), true);
  assert.equal(alreadySyncedInSlot(noon, at('2026-10-11T06:17:00Z')), false);
});
test('legacy daily metadata does not suppress the newly scheduled refresh', () => {
  assert.equal(alreadySyncedInSlot({pipelineVersion:2,syncPolicy:{frequency:'daily',day:'2026-10-11'}}, at('2026-10-11T03:18:00Z')), false);
  assert.equal(alreadySyncedInSlot(null, at('2026-10-11T03:18:00Z')), false);
});
test('all eight slots including midnight are distinct and use the KST calendar day', () => {
  const slots = Array.from({length:8}, (_,i) => syncPolicy(new Date(Date.parse('2026-10-10T15:17:00Z') + i*3*3600000)));
  assert.equal(new Set(slots.map(s=>s.slot)).size,8);
  assert.ok(slots.every(s=>s.day==='2026-10-11' && s.endDate==='yesterday'));
  assert.equal(alreadySyncedInSlot(saved('2026-10-11T12:18:00Z'),at('2026-10-11T15:17:00Z')),false);
});
test('scheduler delay keeps one refresh per slot instead of adding a sliding 3-hour cooldown', () => {
  assert.equal(alreadySyncedInSlot(saved('2026-10-11T03:50:00Z'),at('2026-10-11T06:20:00Z')),false);
});

test('hourly catch-up retries a missed slot but skips a successful slot', () => {
  const old=saved('2026-10-11T00:18:00Z');
  assert.equal(alreadySyncedInSlot(old,at('2026-10-11T04:17:00Z')),false);
  assert.equal(alreadySyncedInSlot(old,at('2026-10-11T05:17:00Z')),false);
  const recovered=saved('2026-10-11T04:18:00Z');
  assert.equal(alreadySyncedInSlot(recovered,at('2026-10-11T05:17:00Z')),true);
  assert.equal(alreadySyncedInSlot(recovered,at('2026-10-11T06:17:00Z')),false);
});
