import test from 'node:test';
import assert from 'node:assert/strict';
import { WatchVersionDecoder, watchVersionRequest } from '../.cloud-build/out/WatchWire.js';

test('version exchange survives split headers and coalesced serial reads', () => {
  assert.equal(Buffer.from(watchVersionRequest()).toString('hex'), 'badcfe00c00300000000ef');
  const response = Buffer.from('badcfe0080040000000002ef', 'hex');
  const decoder = new WatchVersionDecoder();
  assert.equal(decoder.feed(response.subarray(0, 2)).length, 0);
  const frames = decoder.feed(Buffer.concat([response.subarray(2), response]));
  assert.equal(frames.length, 2);
  assert.equal(frames[0].channel, 0);
  assert.equal(frames[0].payload[0], 2);
  decoder.clear();
});

test('version decoder resynchronizes noise and rejects unbounded input', () => {
  const decoder = new WatchVersionDecoder();
  const response = Buffer.from('badcfe0080040000000002ef', 'hex');
  const invalid = Buffer.from(response); invalid[invalid.length - 1] = 0;
  assert.equal(decoder.feed(Buffer.concat([Buffer.from([0, 1]), invalid, response])).length, 1);
  assert.throws(() => decoder.feed(new Uint8Array(131073)), /WATCH_BUFFER_LIMIT/);
  decoder.clear();
});
