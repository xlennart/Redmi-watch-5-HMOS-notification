// Independently written bounded decoder for Xiaomi's serial-port version exchange.
// Wire-format research reference and revision are recorded in third-party-notices.md.
export class WatchVersionFrame {
  channel: number;
  dataType: number;
  payload: Uint8Array;
  constructor(channel: number, dataType: number, payload: Uint8Array) {
    this.channel = channel;
    this.dataType = dataType;
    this.payload = payload;
  }
}

export function watchVersionRequest(): Uint8Array {
  return new Uint8Array([0xba, 0xdc, 0xfe, 0, 0xc0, 3, 0, 0, 0, 0, 0xef]);
}

export class WatchVersionDecoder {
  private pending: Uint8Array = new Uint8Array();
  feed(chunk: Uint8Array): WatchVersionFrame[] {
    if (chunk.length + this.pending.length > 131072) throw new Error('WATCH_BUFFER_LIMIT');
    const data = new Uint8Array(this.pending.length + chunk.length);
    data.set(this.pending);
    data.set(chunk, this.pending.length);
    this.pending.fill(0);
    const frames: WatchVersionFrame[] = [];
    let pos = 0;
    while (pos + 3 <= data.length) {
      if (data[pos] !== 0xba || data[pos + 1] !== 0xdc || data[pos + 2] !== 0xfe) { pos++; continue; }
      if (data.length - pos < 7) break;
      const length = data[pos + 5] | (data[pos + 6] << 8);
      if (length < 3) { pos++; continue; }
      const total = length + 8;
      if (data.length - pos < total) break;
      if (data[pos + total - 1] !== 0xef) { pos++; continue; }
      frames.push(new WatchVersionFrame(data[pos + 3], data[pos + 9], data.slice(pos + 10, pos + total - 1)));
      if (frames.length > 64) throw new Error('WATCH_FRAME_LIMIT');
      pos += total;
    }
    this.pending = data.slice(pos);
    data.fill(0);
    return frames;
  }
  clear(): void { this.pending.fill(0); this.pending = new Uint8Array(); }
}
