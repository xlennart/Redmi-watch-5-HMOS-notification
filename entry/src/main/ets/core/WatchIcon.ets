import { joinBytes, protoBytes, protoInt, readProto, fieldBytes, fieldInt, clearProto, equalBytes } from './WatchProtocol';

export type NotificationIconStatus = 'notRequested' | 'uploaded' | 'unavailable' | 'unsupported' | 'failed';
export interface NotificationIconProvider { load(side: number, format: number): Promise<Uint8Array | undefined>; }
export interface NotificationIconTransport {
  sendCommand: (command: Uint8Array) => Promise<void>;
  massReply: (timeoutMs: number) => Promise<Uint8Array>;
  sendChunk: (chunk: Uint8Array) => Promise<void>;
  md5: (bytes: Uint8Array) => Promise<Uint8Array>;
}

// Raw formats observed in Xiaomi notification-icon requests. No guessed compressed formats.
export function iconBytesPerPixel(format: number): number {
  if (format === 0 || format === 1) return 2;
  if (format === 2 || format === 3) return 4;
  if (format === 7 || format === 8) return 3;
  throw new Error('ICON_FORMAT');
}
export function validateIconSize(side: number): void {
  if (!Number.isInteger(side) || side < 1 || side > 128) throw new Error('ICON_SIZE');
}
// PositionArea is BGRA. Preserve aspect ratio in a transparent square; unpremultiply alpha once.
export function encodeWatchIcon(bgra: Uint8Array, width: number, height: number, side: number,
  format: number, premultiplied: boolean): Uint8Array {
  validateIconSize(side);
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
    width > 1024 || height > 1024 || bgra.length !== width * height * 4) throw new Error('ICON_PIXELS');
  const bpp = iconBytesPerPixel(format); const result = new Uint8Array(side * side * bpp);
  const scale = Math.min(side / width, side / height);
  const drawWidth = Math.max(1, Math.round(width * scale)); const drawHeight = Math.max(1, Math.round(height * scale));
  const left = Math.floor((side - drawWidth) / 2); const top = Math.floor((side - drawHeight) / 2);
  for (let y = 0; y < drawHeight; y++) {
    for (let x = 0; x < drawWidth; x++) {
      const src = (Math.min(height - 1, Math.floor((y + 0.5) * height / drawHeight)) * width +
        Math.min(width - 1, Math.floor((x + 0.5) * width / drawWidth))) * 4;
      const alpha = bgra[src + 3];
      const channel = (value: number): number => alpha === 0 ? 0 :
        (premultiplied ? Math.min(255, Math.round(value * 255 / alpha)) : value);
      const r = channel(bgra[src + 2]); const g = channel(bgra[src + 1]); const b = channel(bgra[src]);
      const dest = ((y + top) * side + x + left) * bpp;
      if (format === 2 || format === 3) {
        result.set([b, g, r, alpha], dest);
      } else {
        const swapped = format === 8;
        const rgb = ((swapped ? b : r) >> 3) << 11 | (g >> 2) << 5 | ((swapped ? r : b) >> 3);
        result[dest] = format === 1 ? rgb >> 8 : rgb & 255;
        result[dest + 1] = format === 1 ? rgb & 255 : rgb >> 8;
        if (bpp === 3) result[dest + 2] = alpha;
      }
    }
  }
  return result;
}
export function iconPrepareCommand(packageName: Uint8Array): Uint8Array {
  if (packageName.length < 1 || packageName.length > 256) throw new Error('ICON_PACKAGE');
  return joinBytes([protoInt(1, 7), protoInt(2, 15), protoBytes(9,
    protoBytes(14, joinBytes([protoBytes(1, packageName), protoInt(2, 0)])))]);
}
export function iconMassPrepareCommand(md5: Uint8Array, length: number): Uint8Array {
  if (md5.length !== 16 || !Number.isInteger(length) || length < 1 || length > 65536) throw new Error('ICON_MASS');
  const request = joinBytes([protoInt(1, 50), protoBytes(2, md5), protoInt(3, length), protoInt(4, 0)]);
  return joinBytes([protoInt(1, 22), protoInt(2, 0), protoBytes(24, protoBytes(1, request))]);
}
export function iconMassCancelCommand(md5: Uint8Array): Uint8Array {
  return joinBytes([protoInt(1, 22), protoInt(2, 1), protoBytes(24,
    protoBytes(3, joinBytes([protoInt(1, 2), protoInt(2, 50), protoBytes(3, md5)])))]);
}
export function iconCrc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    crc ^= bytes[i];
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
export function iconMassPayload(bytes: Uint8Array, md5: Uint8Array): Uint8Array {
  if (md5.length !== 16 || bytes.length < 1 || bytes.length > 65536) throw new Error('ICON_MASS');
  const result = new Uint8Array(26 + bytes.length); result[1] = 50; result.set(md5, 2);
  const view = new DataView(result.buffer); view.setUint32(18, bytes.length, true); result.set(bytes, 22);
  view.setUint32(result.length - 4, iconCrc32(result.subarray(0, result.length - 4)), true); return result;
}
export function iconMassChunk(payload: Uint8Array, sliceLength: number, index: number): Uint8Array {
  // Slice length includes channel/op and the two uint16 part counters. Stay within negotiated 4096-byte frames.
  if (!Number.isInteger(sliceLength) || sliceLength < 64 || sliceLength > 4096 || payload.length > 65562) throw new Error('ICON_SLICE');
  const partSize = sliceLength - 6; const total = Math.ceil(payload.length / partSize);
  if (!Number.isInteger(index) || index < 0 || index >= total) throw new Error('ICON_PART');
  const body = payload.subarray(index * partSize, Math.min(payload.length, (index + 1) * partSize));
  const result = new Uint8Array(4 + body.length); const view = new DataView(result.buffer);
  view.setUint16(0, total, true); view.setUint16(2, index + 1, true); result.set(body, 4); return result;
}

// One current source per short-lived session; never resolve arbitrary packages supplied by the watch.
export class NotificationIconExchange {
  status: NotificationIconStatus = 'notRequested';
  private requested: boolean = false;
  private answered: boolean = false;
  private source: Uint8Array;
  private provider: NotificationIconProvider;
  private transport: NotificationIconTransport;
  constructor(source: Uint8Array, provider: NotificationIconProvider, transport: NotificationIconTransport) {
    this.source = source; this.provider = provider; this.transport = transport;
  }
  async handle(subtype: number, notification: Uint8Array): Promise<boolean> {
    if (subtype !== 15 && subtype !== 16) return false;
    const fields = readProto(notification);
    try {
      if (subtype === 16) {
        if (this.requested) return true;
        const query = readProto(fieldBytes(fields, 16));
        try {
          const name = fieldBytes(query, 1);
          if (name.length < Math.min(8, this.source.length) || name.length > this.source.length ||
            !equalBytes(name, this.source.subarray(0, name.length))) return true;
          this.requested = true;
          await this.transport.sendCommand(iconPrepareCommand(name));
        } finally { clearProto(query); }
        return true;
      }
      if (!this.requested || this.answered) return true;
      this.answered = true;
      const response = readProto(fieldBytes(fields, 15));
      try {
        if (fieldInt(response, 1) !== 0) { this.status = 'unsupported'; return true; }
        const side = fieldInt(response, 3); const format = fieldInt(response, 2); const compression = fieldInt(response, 4);
        try { validateIconSize(side); iconBytesPerPixel(format); }
        catch (_) { this.status = 'unsupported'; return true; }
        if (compression > 0) { this.status = 'unsupported'; return true; }
        let bytes: Uint8Array = new Uint8Array(); let digest: Uint8Array = new Uint8Array(); let payload: Uint8Array = new Uint8Array();
        let started = false; let finished = false;
        const until = Date.now() + 8000;
        try {
          const loaded = await this.provider.load(side, format);
          if (!loaded) { this.status = 'unavailable'; return true; }
          bytes = loaded;
          if (bytes.length !== side * side * iconBytesPerPixel(format)) throw new Error('ICON_LENGTH');
          digest = await this.transport.md5(bytes);
          started = true; await this.transport.sendCommand(iconMassPrepareCommand(digest, bytes.length));
          const reply = await this.transport.massReply(Math.max(1, until - Date.now()));
          const mass = readProto(reply);
          let sliceLength = 2048;
          try {
            if (!equalBytes(fieldBytes(mass, 1), digest) || fieldInt(mass, 2) !== 0 ||
              fieldInt(mass, 3) > 0 || fieldInt(mass, 4) > 0) throw new Error('ICON_MASS_RESPONSE');
            // Fresh uploads only: resume offsets differ across firmware implementations.
            const negotiated = fieldInt(mass, 5);
            if (negotiated >= 0) sliceLength = Math.min(negotiated, 4096);
            if (sliceLength < 64) throw new Error('ICON_SLICE');
          } finally { clearProto(mass); reply.fill(0); }
          payload = iconMassPayload(bytes, digest);
          const total = Math.ceil(payload.length / (sliceLength - 6));
          for (let i = 0; i < total; i++) {
            if (Date.now() >= until) throw new Error('ICON_TIMEOUT');
            const chunk = iconMassChunk(payload, sliceLength, i);
            try { await this.transport.sendChunk(chunk); } finally { chunk.fill(0); }
          }
          finished = true; this.status = 'uploaded'; // Transport ACKs, never a claim about visible UI.
        } catch (_) { this.status = 'failed'; }
        finally {
          if (started && !finished && digest.length === 16) {
            try { await this.transport.sendCommand(iconMassCancelCommand(digest)); } catch (_) { }
          }
          bytes.fill(0); digest.fill(0); payload.fill(0);
        }
      } finally { clearProto(response); }
      return true;
    } finally { clearProto(fields); }
  }
}
