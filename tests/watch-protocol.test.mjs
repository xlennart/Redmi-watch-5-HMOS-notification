import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac, hkdfSync} from 'node:crypto';
import {crc16Arc, encodeWatchV2, WatchV2Decoder, watchHmac, watchSessionKeys, authCommand,
  readProto, fieldInt, fieldBytes, protoBytes, equalBytes, watchNotificationCommand, watchVibrationTestCommand} from '../.cloud-build/out/WatchProtocol.js';
const sha256 = async data => new Uint8Array(createHash('sha256').update(data).digest());

test('HMAC and handshake derivation match independent Node crypto implementations', async () => {
  const key = new Uint8Array(16).fill(0x12), phone = new Uint8Array(16).fill(0x34), watch = new Uint8Array(16).fill(0x56);
  assert.deepEqual(Buffer.from(await watchHmac(key, phone, sha256)), createHmac('sha256', key).update(phone).digest());
  assert.deepEqual(Buffer.from(await watchSessionKeys(key, phone, watch, sha256)),
    Buffer.from(hkdfSync('sha256', key, Buffer.concat([phone, watch]), 'miwear-auth', 64)));
  assert.equal(equalBytes(new Uint8Array([1]), new Uint8Array([1, 0])), false);
});

test('single notification carries epoch milliseconds, an app group, and every required field', () => {
  const encoded = watchNotificationCommand({packageName: Buffer.from('synthetic.test'), appName: Buffer.from('Test'),
    title: Buffer.from('Title'), body: Buffer.from('Body'), date: Buffer.from('1791296574933'), group: Buffer.from('synthetic.test'),
    key: Buffer.from('synthetic-key'), id: 123});
  const command = readProto(encoded); assert.equal(fieldInt(command, 1), 7); assert.equal(fieldInt(command, 2), 0);
  const notification = readProto(fieldBytes(command, 9)); const data = readProto(fieldBytes(notification, 1));
  for (const field of [1,2,3,4,5,6,7,9,10,12]) assert.ok(data.some(item => item.id === field), `required field ${field}`);
  assert.equal(Buffer.from(fieldBytes(data, 6)).toString(), '1791296574933');
  assert.equal(Buffer.from(fieldBytes(data, 9)).toString(), 'synthetic.test'); assert.equal(fieldBytes(data, 10).length, 0);
  assert.equal(data.some(item => item.id === 8), false);
  assert.equal(Buffer.from(fieldBytes(data, 12)).toString(), 'synthetic-key');
});
test('vibration diagnostic uses SYSTEM 59 with two bounded short pulses', () => {
  const packet = readProto(watchVibrationTestCommand());
  assert.equal(fieldInt(packet, 1), 2); assert.equal(fieldInt(packet, 2), 59);
  const system = readProto(fieldBytes(packet, 4)); const effect = readProto(fieldBytes(system, 41));
  const segments = effect.filter(item => item.id === 1).map(item => readProto(item.bytes));
  assert.deepEqual(segments.map(fields => fieldInt(fields, 1)), [1, 0, 1]);
  assert.deepEqual(segments.map(fields => fieldInt(fields, 2)), [120, 180, 120]);
  assert.deepEqual(segments.map(fields => fieldInt(fields, 3)), [60, 0, 60]);
});
test('V2 framing matches CRC-16/ARC check value and detects corruption across split reads', () => {
  assert.equal(crc16Arc(Buffer.from('123456789')), 0xbb3d);
  const frame = encodeWatchV2(3, 254, new Uint8Array([1, 1, 8, 1]));
  const decoder = new WatchV2Decoder();
  assert.equal(decoder.feed(frame.subarray(0, 5)).length, 0);
  const parsed = decoder.feed(frame.subarray(5)); assert.equal(parsed[0].sequence, 254);
  frame[frame.length - 1] ^= 1;
  assert.throws(() => decoder.feed(frame), /WATCH_FRAME_CRC/);
  decoder.clear();
});
test('nonce command uses expected protobuf nesting and malformed inputs are rejected', () => {
  const nonce = new Uint8Array(16).fill(1);
  const command = readProto(authCommand(26, 30, protoBytes(1, nonce)));
  assert.equal(fieldInt(command, 1), 1); assert.equal(fieldInt(command, 2), 26);
  const account = readProto(fieldBytes(command, 3)); const verify = readProto(fieldBytes(account, 30));
  assert.deepEqual(fieldBytes(verify, 1), nonce);
  assert.throws(() => readProto(new Uint8Array([10, 127, 1])), /PROTO_TRUNCATED/);
  assert.throws(() => readProto(new Uint8Array([8, 255, 255, 255, 255, 127])), /PROTO_INTEGER/);
});
