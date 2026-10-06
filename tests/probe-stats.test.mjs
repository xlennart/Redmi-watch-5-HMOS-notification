import test from 'node:test';
import assert from 'node:assert/strict';
import { ProbeStats, receiveNotification, cancelNotifications, decodeStats } from '../.cloud-build/out/ProbeStats.js';

test('a received notification persists after an extension recreation', () => {
  const first = receiveNotification(new ProbeStats(), 'example.chat', 'example.bridge', 1234);
  const restored = decodeStats(JSON.stringify(first));
  const second = receiveNotification(restored, 'example.mail', 'example.bridge', 5678);
  assert.equal(second.received, 2);
  assert.equal(second.lastBundleName, 'example.mail');
  assert.equal(second.lastReceivedAt, 5678);
  assert.equal(first.received, 1);
});

test('own notifications are counted separately without overwriting the last source', () => {
  const first = receiveNotification(new ProbeStats(), 'example.chat', 'example.bridge', 10);
  const next = receiveNotification(first, 'example.bridge', 'example.bridge', 20);
  assert.equal(next.ignoredSelf, 1);
  assert.equal(next.received, 1);
  assert.equal(next.lastBundleName, 'example.chat');
  assert.equal(next.lastReceivedAt, 10);
});

test('callbacks and cancellation items are separate measures, including empty cancellations', () => {
  const first = cancelNotifications(new ProbeStats(), 3, 10);
  const second = cancelNotifications(first, 0, 20);
  assert.equal(second.cancelCallbacks, 2);
  assert.equal(second.cancelledItems, 3);
  assert.equal(second.received, 0);
  assert.equal(second.lastCancelledAt, 20);
});

test('only metadata survives restored data, including previously saved sensitive fields', () => {
  const dirty = { ...new ProbeStats(), received: 1, title: 'private title', text: 'private body',
    hashCodes: ['private-key'], deviceId: 'private-device', authKey: 'secret', lastBundleName: 'example.chat' };
  const clean = receiveNotification(decodeStats(JSON.stringify(dirty)), 'example.mail', 'bridge', 1);
  assert.deepEqual(Object.keys(clean).sort(), Object.keys(new ProbeStats()).sort());
  const serialized = JSON.stringify(clean);
  for (const secret of ['private title', 'private body', 'private-key', 'private-device', 'secret']) {
    assert.equal(serialized.includes(secret), false);
  }
});

test('truncated storage, primitives and unsupported schema recover to empty counters', () => {
  for (const raw of ['{', 'null', '[]', '42', '"text"', '{"schemaVersion":2,"received":1}']) {
    assert.deepEqual(decodeStats(raw), new ProbeStats());
  }
});

test('invalid counter types, negative values and unbounded source names are sanitized', () => {
  const malformed = { schemaVersion: 1, received: -1, ignoredSelf: '2', cancelCallbacks: 1.5,
    cancelledItems: null, lastReceivedAt: -100, lastCancelledAt: 1e20, lastBundleName: 'a'.repeat(1000) };
  const result = decodeStats(JSON.stringify(malformed));
  assert.equal(result.received, 0);
  assert.equal(result.ignoredSelf, 0);
  assert.equal(result.cancelCallbacks, 0);
  assert.equal(result.cancelledItems, 0);
  assert.equal(result.lastReceivedAt, 0);
  assert.equal(result.lastCancelledAt, 0);
  assert.equal(result.lastBundleName.length, 256);
});

test('counter saturation never persists an unsafe integer', () => {
  const initial = new ProbeStats();
  initial.received = Number.MAX_SAFE_INTEGER;
  initial.cancelledItems = Number.MAX_SAFE_INTEGER;
  const result = cancelNotifications(receiveNotification(initial, 'chat', 'bridge', 1), 2, 1);
  assert.equal(result.received, Number.MAX_SAFE_INTEGER);
  assert.equal(result.cancelledItems, Number.MAX_SAFE_INTEGER);
});

test('repeat notifications count callbacks without making an unsupported delivery claim', () => {
  const first = receiveNotification(new ProbeStats(), 'chat', 'bridge', 1);
  const repeat = receiveNotification(first, 'chat', 'bridge', 1);
  assert.equal(repeat.received, 2);
  assert.equal(Object.hasOwn(repeat, 'deliveredToWatch'), false);
});
