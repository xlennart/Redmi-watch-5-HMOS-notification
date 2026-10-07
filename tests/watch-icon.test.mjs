import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { NotificationIconExchange, encodeWatchIcon, iconCrc32, iconMassPayload, iconMassChunk, validateIconData } from '../.cloud-build/out/WatchIcon.js';
import { protoBytes, protoInt, joinBytes, readProto, fieldInt, fieldBytes } from '../.cloud-build/out/WatchProtocol.js';

const name = Buffer.from('example.notification.source');
const query = (pkg = name) => protoBytes(16, protoBytes(1, pkg));
const ready = (side = 2, format = 3, compression = 0) => protoBytes(15,
  joinBytes([protoInt(1, 0), protoInt(2, format), protoInt(3, side), protoInt(4, compression)]));
function fixture(replyOptions = {}) {
  const commands = [], chunks = [];
  let calls = 0, digest;
  const pixels = new Uint8Array(16).fill(127);
  const transport = {
    async sendCommand(bytes) { commands.push(bytes.slice()); },
    async md5(bytes) { digest = new Uint8Array(createHash('md5').update(bytes).digest()); return digest.slice(); },
    async massReply() { return joinBytes([protoBytes(1, replyOptions.wrongId ? new Uint8Array(16) : digest),
      protoInt(2, replyOptions.status ?? 0), protoInt(3, replyOptions.compression ?? 0),
      protoInt(4, replyOptions.resume ?? 0), protoInt(5, replyOptions.slice ?? 64)]); },
    async sendChunk(bytes) { chunks.push(bytes.slice()); if (replyOptions.rejectChunk) throw new Error('NACK'); }
  };
  const exchange = new NotificationIconExchange(name, { async load() { calls++; return pixels; } }, transport);
  return { exchange, commands, chunks, pixels, transport, calls: () => calls };
}

test('known pixels use negotiated RGB565 endianness and alpha-bearing channel layouts', () => {
  const red = new Uint8Array([0, 0, 255, 255]);
  assert.deepEqual([...encodeWatchIcon(red, 1, 1, 1, 0, false)], [0, 248]);
  assert.deepEqual([...encodeWatchIcon(red, 1, 1, 1, 1, false)], [248, 0]);
  assert.deepEqual([...encodeWatchIcon(red, 1, 1, 1, 7, false)], [0, 248, 255]);
  assert.deepEqual([...encodeWatchIcon(red, 1, 1, 1, 8, false)], [31, 0, 255]);
  const semitransparent = new Uint8Array([16, 32, 64, 128]);
  assert.deepEqual([...encodeWatchIcon(semitransparent, 1, 1, 1, 3, true)], [32, 64, 128, 128]);
  assert.deepEqual([...encodeWatchIcon(new Uint8Array([10, 20, 30, 0]), 1, 1, 1, 2, true)], [0, 0, 0, 0]);
});

test('non-square icons retain aspect ratio and reject oversized or unknown formats', () => {
  const pixels = new Uint8Array([0, 0, 255, 255, 255, 0, 0, 255]);
  const encoded = encodeWatchIcon(pixels, 2, 1, 4, 3, false);
  assert.equal(encoded.length, 64);
  assert.deepEqual([...encoded.subarray(0, 16)], new Array(16).fill(0));
  assert.deepEqual([...encoded.subarray(16, 20)], [0, 0, 255, 255]);
  assert.throws(() => encodeWatchIcon(pixels, 2, 1, 129, 3, false), /ICON_SIZE/);
  assert.throws(() => encodeWatchIcon(pixels, 2, 1, 0, 3, false), /ICON_SIZE/);
  assert.throws(() => encodeWatchIcon(pixels, 2, 1, 2, 6, false), /ICON_FORMAT/);
  assert.throws(() => encodeWatchIcon(pixels, 2000, 1, 2, 3, false), /ICON_PIXELS/);
});

test('mass header, MD5, CRC32 and fragment counters preserve the complete binary icon', () => {
  assert.equal(iconCrc32(Buffer.from('123456789')), 0xcbf43926);
  const pixels = Buffer.from(Array.from({ length: 160 }, (_, i) => i));
  const md5 = new Uint8Array(createHash('md5').update(pixels).digest());
  const payload = iconMassPayload(pixels, md5);
  assert.equal(payload[0], 0); assert.equal(payload[1], 50);
  assert.deepEqual(payload.subarray(2, 18), md5);
  assert.equal(new DataView(payload.buffer).getUint32(18, true), 160);
  assert.equal(new DataView(payload.buffer).getUint32(payload.length - 4, true), iconCrc32(payload.subarray(0, -4)));
  const total = Math.ceil(payload.length / 58), parts = [];
  for (let i = 0; i < total; i++) {
    const chunk = iconMassChunk(payload, 64, i), view = new DataView(chunk.buffer);
    assert.equal(view.getUint16(0, true), total); assert.equal(view.getUint16(2, true), i + 1);
    assert.ok(chunk.length + 2 <= 64); parts.push(chunk.subarray(4));
  }
  assert.deepEqual(Buffer.concat(parts), Buffer.from(payload));
  assert.throws(() => iconMassChunk(payload, 0, 0), /ICON_SLICE/);
  assert.throws(() => iconMassChunk(payload, 64, total), /ICON_PART/);
});

test('scripted watch query negotiates, uploads and clears pixels; duplicate requests are harmless', async () => {
  const f = fixture();
  await f.exchange.handle(16, query(name.subarray(0, 16)));
  const prepare = readProto(f.commands[0]);
  assert.equal(fieldInt(prepare, 1), 7); assert.equal(fieldInt(prepare, 2), 15);
  const notification = readProto(fieldBytes(prepare, 9));
  assert.deepEqual(Buffer.from(fieldBytes(readProto(fieldBytes(notification, 14)), 1)), name.subarray(0, 16));
  await f.exchange.handle(15, ready());
  assert.equal(f.exchange.status, 'uploaded'); assert.equal(f.calls(), 1); assert.ok(f.chunks.length > 0);
  assert.equal(f.pixels.some(Boolean), false);
  const count = f.commands.length;
  await f.exchange.handle(16, query()); await f.exchange.handle(15, ready());
  assert.equal(f.commands.length, count); assert.equal(f.calls(), 1);
  const mass = readProto(f.commands[1]); assert.equal(fieldInt(mass, 1), 22);
  const request = readProto(fieldBytes(readProto(fieldBytes(mass, 24)), 1));
  assert.equal(fieldInt(request, 1), 50); assert.equal(fieldInt(request, 3), 16);
});

test('unsolicited, foreign or ambiguous short package requests never resolve an app icon', async () => {
  const f = fixture();
  await f.exchange.handle(15, ready());
  await f.exchange.handle(16, query(Buffer.from('unrelated.package')));
  await f.exchange.handle(16, query(Buffer.from('exam')));
  assert.equal(f.commands.length, 0); assert.equal(f.calls(), 0);
  assert.equal(await f.exchange.handle(0, new Uint8Array()), false);
});

test('unsupported image format, dimensions and compression keep the text-only path', async () => {
  for (const response of [ready(129), ready(2, 12), ready(2, 3, 1)]) {
    const f = fixture(); await f.exchange.handle(16, query()); await f.exchange.handle(15, response);
    assert.equal(f.exchange.status, 'unsupported'); assert.equal(f.calls(), 0); assert.equal(f.chunks.length, 0);
  }
});

test('proactive prepare works without a repeated watch query and honors the icon-specific slice', async () => {
  const f = fixture();
  await f.exchange.request(); await f.exchange.request();
  assert.equal(f.commands.length, 1); assert.equal(f.exchange.status, 'pending');
  await f.exchange.handle(15, protoBytes(15, joinBytes([protoInt(1, 0), protoInt(2, 3), protoInt(3, 2), protoInt(5, 64)])));
  assert.equal(f.exchange.status, 'uploaded'); assert.equal(f.exchange.reason, 'transport_ack');
  assert.equal(f.commands.length, 1); // The ready response already negotiated the upload; no MASS prepare.
  assert.ok(f.chunks.length > 0);
});

test('watch cached response and a concrete provider failure stay distinct from visible success', async () => {
  const f = fixture(); await f.exchange.request();
  await f.exchange.handle(15, protoBytes(15, protoInt(1, 2)));
  assert.equal(f.exchange.status, 'cached'); assert.equal(f.exchange.reason, 'watch_cached'); assert.equal(f.calls(), 0);
  const exchange = new NotificationIconExchange(name, { reason: 'media_9001002', async load() { return undefined; } }, {
    async sendCommand() {}, async massReply() { throw new Error('unexpected'); },
    async sendChunk() { throw new Error('unexpected'); }, async md5() { throw new Error('unexpected'); }
  });
  await exchange.request(); await exchange.handle(15, ready());
  assert.equal(exchange.status, 'unavailable'); assert.equal(exchange.reason, 'media_9001002');
});

test('encoded PNG icons accept bounded dimensions and reject malformed or oversized input', () => {
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==', 'base64');
  validateIconData(png, 2, 6);
  assert.throws(() => validateIconData(new Uint8Array(33), 2, 6), /ICON_PNG/);
  const oversized = png.slice(); oversized.writeUInt32BE(3, 16);
  assert.throws(() => validateIconData(oversized, 2, 6), /ICON_PNG_SIZE/);
  assert.throws(() => validateIconData(new Uint8Array(65537), 2, 6), /ICON_LENGTH/);
});

test('PNG negotiation uploads the encoded file length rather than a raw-pixel length', async () => {
  const f = fixture();
  const bytes = new Uint8Array(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==', 'base64'));
  const length = bytes.length;
  const exchange = new NotificationIconExchange(name, { async load() { return bytes; } }, f.transport);
  await exchange.request(); await exchange.handle(15, ready(2, 6));
  assert.equal(exchange.status, 'uploaded');
  const request = readProto(fieldBytes(readProto(fieldBytes(readProto(f.commands[1]), 24)), 1));
  assert.equal(fieldInt(request, 3), length);
  assert.ok(bytes.every(value => value === 0));
});

test('missing icon resources fall back without starting a mass transfer', async () => {
  const f = fixture();
  const exchange = new NotificationIconExchange(name, { async load() { return undefined; } }, {
    async sendCommand(bytes) { f.commands.push(bytes); }, async massReply() { throw new Error('unexpected'); },
    async sendChunk() { throw new Error('unexpected'); }, async md5() { throw new Error('unexpected'); }
  });
  await exchange.handle(16, query()); await exchange.handle(15, ready());
  assert.equal(exchange.status, 'unavailable'); assert.equal(f.commands.length, 1);
});

test('wrong digest, rejected upload, resume, compression, invalid slices and NACK cancel only the icon upload', async () => {
  for (const options of [{ wrongId: true }, { status: 1 }, { resume: 1 }, { compression: 1 }, { slice: 0 }, { rejectChunk: true }]) {
    const f = fixture(options); await f.exchange.handle(16, query()); await f.exchange.handle(15, ready());
    assert.equal(f.exchange.status, 'failed'); assert.equal(f.pixels.some(Boolean), false);
    const cancel = readProto(f.commands.at(-1)); assert.equal(fieldInt(cancel, 1), 22); assert.equal(fieldInt(cancel, 2), 1);
    const control = readProto(fieldBytes(readProto(fieldBytes(cancel, 24)), 3));
    assert.equal(fieldInt(control, 1), 2); assert.equal(fieldInt(control, 2), 50);
  }
});
