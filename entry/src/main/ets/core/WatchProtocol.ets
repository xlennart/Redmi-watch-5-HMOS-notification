// Wire-level facts researched from Gadgetbridge; implementation is independent and bounded.
export function joinBytes(parts: Uint8Array[]): Uint8Array {
  let length = 0;
  for (let i = 0; i < parts.length; i++) length += parts[i].length;
  if (length > 131072) throw new Error('WATCH_MESSAGE_LIMIT');
  const result = new Uint8Array(length);
  let pos = 0;
  for (let i = 0; i < parts.length; i++) { result.set(parts[i], pos); pos += parts[i].length; }
  return result;
}

function varint(value: number): Uint8Array {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) throw new Error('PROTO_INTEGER');
  const bytes: number[] = [];
  do { const next = value % 128; value = Math.floor(value / 128); bytes.push(next | (value > 0 ? 128 : 0)); } while (value > 0);
  return new Uint8Array(bytes);
}
export function protoInt(field: number, value: number): Uint8Array { return joinBytes([varint(field * 8), varint(value)]); }
export function protoBytes(field: number, value: Uint8Array): Uint8Array {
  return joinBytes([varint(field * 8 + 2), varint(value.length), value]);
}
export function protoFloat(field: number, value: number): Uint8Array {
  const data = new Uint8Array(4); new DataView(data.buffer).setFloat32(0, value, true);
  return joinBytes([varint(field * 8 + 5), data]);
}
export class ProtoField {
  id: number;
  integer: number;
  bytes: Uint8Array;
  constructor(id: number, integer: number, bytes: Uint8Array) { this.id = id; this.integer = integer; this.bytes = bytes; }
}
export function readProto(data: Uint8Array): ProtoField[] {
  if (data.length > 65535) throw new Error('PROTO_LIMIT');
  const fields: ProtoField[] = [];
  let pos = 0;
  const readInt = (): number => {
    let value = 0;
    for (let i = 0; i < 5; i++) {
      if (pos >= data.length) throw new Error('PROTO_TRUNCATED');
      const byte = data[pos++]; value += (byte & 127) * Math.pow(128, i);
      if ((byte & 128) === 0) { if (value > 0xffffffff) throw new Error('PROTO_INTEGER'); return value; }
    }
    throw new Error('PROTO_INTEGER');
  };
  while (pos < data.length) {
    const tag = readInt(); const id = Math.floor(tag / 8); const wire = tag % 8;
    if (id === 0 || fields.length >= 128) throw new Error('PROTO_FIELDS');
    if (wire === 0) fields.push(new ProtoField(id, readInt(), new Uint8Array()));
    else {
      const length = wire === 2 ? readInt() : (wire === 5 ? 4 : (wire === 1 ? 8 : -1));
      if (length < 0 || pos + length > data.length) throw new Error('PROTO_TRUNCATED');
      fields.push(new ProtoField(id, -1, data.slice(pos, pos + length))); pos += length;
    }
  }
  return fields;
}
export function fieldInt(fields: ProtoField[], id: number): number { return fields.find(item => item.id === id)?.integer ?? -1; }
export function fieldBytes(fields: ProtoField[], id: number): Uint8Array { return fields.find(item => item.id === id)?.bytes || new Uint8Array(); }
export function clearProto(fields: ProtoField[]): void { for (let i = 0; i < fields.length; i++) fields[i].bytes.fill(0); }

export function crc16Arc(data: Uint8Array): number {
  let crc = 0;
  for (let i = 0; i < data.length; i++) {
    crc ^= data[i];
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xa001 : 0);
  }
  return crc & 65535;
}
export class WatchV2Frame {
  type: number;
  sequence: number;
  payload: Uint8Array;
  constructor(type: number, sequence: number, payload: Uint8Array) { this.type = type; this.sequence = sequence; this.payload = payload; }
}
export function encodeWatchV2(type: number, sequence: number, payload: Uint8Array): Uint8Array {
  if (payload.length > 65535) throw new Error('WATCH_MESSAGE_LIMIT');
  const result = new Uint8Array(8 + payload.length);
  result.set([0xa5, 0xa5, type & 15, sequence & 255]);
  const view = new DataView(result.buffer); view.setUint16(4, payload.length, true); view.setUint16(6, crc16Arc(payload), true);
  result.set(payload, 8); return result;
}
export class WatchV2Decoder {
  private pending: Uint8Array = new Uint8Array();
  feed(chunk: Uint8Array): WatchV2Frame[] {
    const data = joinBytes([this.pending, chunk]); this.pending.fill(0);
    const frames: WatchV2Frame[] = []; let pos = 0;
    while (pos + 2 <= data.length) {
      if (data[pos] !== 0xa5 || data[pos + 1] !== 0xa5) { pos++; continue; }
      if (data.length - pos < 8) break;
      const view = new DataView(data.buffer, pos); const length = view.getUint16(4, true);
      if (data.length - pos < length + 8) break;
      const payload = data.slice(pos + 8, pos + 8 + length);
      if (crc16Arc(payload) !== view.getUint16(6, true)) { payload.fill(0); throw new Error('WATCH_FRAME_CRC'); }
      frames.push(new WatchV2Frame(data[pos + 2] & 15, data[pos + 3], payload));
      if (frames.length > 64) throw new Error('WATCH_FRAME_LIMIT');
      pos += length + 8;
    }
    this.pending = data.slice(pos); data.fill(0); return frames;
  }
  clear(): void { this.pending.fill(0); this.pending = new Uint8Array(); }
}
export function watchSessionConfig(): Uint8Array {
  // TLVs: version 1.0.0, max frame 4096, one in-flight packet, send timeout 8 seconds.
  return new Uint8Array([1, 1, 3, 0, 1, 0, 0, 2, 2, 0, 0, 16, 3, 2, 0, 1, 0, 4, 2, 0, 64, 31]);
}
export function authCommand(subtype: number, field: number, payload: Uint8Array): Uint8Array {
  return joinBytes([protoInt(1, 1), protoInt(2, subtype), protoBytes(3, protoBytes(field, payload))]);
}

export interface WatchNotificationContent {
  packageName: Uint8Array;
  appName: Uint8Array;
  title: Uint8Array;
  body: Uint8Array;
  date: Uint8Array;
  group: Uint8Array;
  key: Uint8Array;
  id: number;
}
export function watchNotificationCommand(input: WatchNotificationContent): Uint8Array {
  // Newer firmwares require the complete NotifyData record, including empty strings.
  const empty = new Uint8Array();
  const data = joinBytes([protoBytes(1, input.packageName), protoBytes(2, input.appName), protoBytes(3, input.title),
    protoBytes(4, empty), protoBytes(5, input.body), protoBytes(6, input.date), protoInt(7, input.id),
    protoBytes(9, input.group), protoBytes(10, empty), protoInt(11, 0), protoBytes(12, input.key), protoInt(13, 0)]);
  return joinBytes([protoInt(1, 7), protoInt(2, 0), protoBytes(9, protoBytes(1, data))]);
}
export function watchVibrationTestCommand(): Uint8Array {
  // SYSTEM / TEST_VIBRATOR, System field 41. Two short pulses, no persistent setting.
  const segment = (on: boolean, duration: number): Uint8Array => joinBytes([
    protoInt(1, on ? 1 : 0), protoInt(2, duration), protoInt(3, on ? 60 : 0)]);
  const effect = joinBytes([protoBytes(1, segment(true, 120)), protoBytes(1, segment(false, 180)),
    protoBytes(1, segment(true, 120))]);
  return joinBytes([protoInt(1, 2), protoInt(2, 59), protoBytes(4, protoBytes(41, effect))]);
}
export function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  let mismatch = left.length ^ right.length;
  for (let i = 0; i < left.length; i++) mismatch |= left[i] ^ (right[i] || 0);
  return mismatch === 0;
}

// RFC 2104 HMAC and RFC 5869 HKDF with injected SHA-256 from the phone crypto service.
export async function watchHmac(key: Uint8Array, data: Uint8Array, sha256: (data: Uint8Array) => Promise<Uint8Array>): Promise<Uint8Array> {
  const material = key.length > 64 ? await sha256(key) : key.slice();
  const inner = new Uint8Array(64); inner.fill(0x36);
  const outer = new Uint8Array(64); outer.fill(0x5c);
  for (let i = 0; i < material.length; i++) { inner[i] ^= material[i]; outer[i] ^= material[i]; }
  const first = joinBytes([inner, data]); let intermediate: Uint8Array = new Uint8Array(); let second: Uint8Array = new Uint8Array();
  try { intermediate = await sha256(first); second = joinBytes([outer, intermediate]); return await sha256(second); }
  finally { material.fill(0); inner.fill(0); outer.fill(0); first.fill(0); intermediate.fill(0); second.fill(0); }
}
export async function watchSessionKeys(secret: Uint8Array, phone: Uint8Array, watch: Uint8Array,
  sha256: (data: Uint8Array) => Promise<Uint8Array>): Promise<Uint8Array> {
  if (secret.length !== 16 || phone.length !== 16 || watch.length !== 16) throw new Error('WATCH_NONCE_SIZE');
  const salt = joinBytes([phone, watch]); const prk = await watchHmac(salt, secret, sha256); salt.fill(0);
  const info = new Uint8Array([109, 105, 119, 101, 97, 114, 45, 97, 117, 116, 104]);
  let first: Uint8Array = new Uint8Array(); let second: Uint8Array = new Uint8Array(); let input: Uint8Array = new Uint8Array();
  try {
    input = joinBytes([info, new Uint8Array([1])]); first = await watchHmac(prk, input, sha256); input.fill(0);
    input = joinBytes([first, info, new Uint8Array([2])]); second = await watchHmac(prk, input, sha256);
    return joinBytes([first, second]);
  } finally { prk.fill(0); first.fill(0); second.fill(0); input.fill(0); }
}
