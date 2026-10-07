import test from 'node:test';
import assert from 'node:assert/strict';
import {boundedNotificationText, RelayNotification, NotificationRelayQueue} from '../.cloud-build/out/NotificationRelay.js';
const item = (hash, clone = 0) => new RelayNotification(hash, 'synthetic.app', 'Test', 'Title', 'Body', 1, '', clone);
test('relay bounds UTF-8 payloads without splitting emoji or Chinese characters', () => {
  assert.equal(boundedNotificationText('中😀A', 6), '中');
  assert.equal(boundedNotificationText('中😀A', 7), '中😀');
  const message = new RelayNotification('id', 'app', 'App', '中'.repeat(1000), '😀'.repeat(1000), 1, '', 0);
  assert.ok(Buffer.byteLength(message.title) <= 256); assert.ok(Buffer.byteLength(message.body) <= 2048);
  assert.equal(message.group, 'app'); assert.notEqual(item('id').id, item('id', 1).id);
});
test('relay replaces pending updates, clears cancelled text, and rejects overflow', () => {
  const queue = new NotificationRelayQueue(); const previous = item('same'); queue.enqueue(previous);
  const update = item('same'); update.body = 'Updated'; queue.enqueue(update);
  assert.equal(previous.body, ''); assert.equal(queue.take().body, 'Updated');
  const cancelled = item('cancel'); queue.enqueue(cancelled); queue.cancel(['cancel']);
  assert.equal(cancelled.body, ''); assert.equal(queue.take(), undefined);
  for (let i = 0; i < 16; i++) assert.equal(queue.enqueue(item(String(i))), true);
  const overflow = item('overflow'); assert.equal(queue.enqueue(overflow), false); assert.equal(overflow.body, '');
  queue.clear(); assert.equal(queue.take(), undefined);
});
