export class FitnessLogEntry {
  method: number;
  size: number;
  crc: number;
  bytes: Uint8Array;

  constructor(method: number, size: number, crc: number, bytes: Uint8Array) {
    this.method = method;
    this.size = size;
    this.crc = crc;
    this.bytes = bytes;
  }
}

function ascii(bytes: Uint8Array): string {
  let value = '';
  for (let i = 0; i < bytes.length; i++) value += String.fromCharCode(bytes[i]);
  return value;
}

// Read only bounded log entries, in memory. Never extract archive paths to disk.
export function fitnessArchiveEntries(bytes: Uint8Array): FitnessLogEntry[] {
  if (bytes.length < 22 || bytes.length > 64 * 1024 * 1024) throw new Error('INVALID_ARCHIVE');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50 && i + 22 + view.getUint16(i + 20, true) === bytes.length) {
      end = i;
      break;
    }
  }
  if (end < 0 || view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0) {
    throw new Error('INVALID_ARCHIVE');
  }
  const count = view.getUint16(end + 10, true);
  const directorySize = view.getUint32(end + 12, true);
  let cursor = view.getUint32(end + 16, true);
  const directoryEnd = cursor + directorySize;
  if (count > 4096 || count !== view.getUint16(end + 8, true) || directoryEnd > end) {
    throw new Error('INVALID_ARCHIVE');
  }
  let total = 0;
  const logs: FitnessLogEntry[] = [];
  for (let i = 0; i < count; i++) {
    if (cursor + 46 > directoryEnd || view.getUint32(cursor, true) !== 0x02014b50) throw new Error('INVALID_ARCHIVE');
    const flags = view.getUint16(cursor + 8, true);
    const method = view.getUint16(cursor + 10, true);
    const crc = view.getUint32(cursor + 16, true);
    const packed = view.getUint32(cursor + 20, true);
    const size = view.getUint32(cursor + 24, true);
    const nameLength = view.getUint16(cursor + 28, true);
    const next = cursor + 46 + nameLength + view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
    if (next > directoryEnd) throw new Error('INVALID_ARCHIVE');
    const name = ascii(bytes.subarray(cursor + 46, cursor + 46 + nameLength));
    const basename = name.split(/[\\/]/).pop() || '';
    if (/^XiaomiFit\.(device|main)\.log(?:\.bak\.\d+)?$/.test(basename)) {
      if ((flags & 1) !== 0 || (method !== 0 && method !== 8) || size > 16 * 1024 * 1024) {
        throw new Error('UNSUPPORTED_ARCHIVE');
      }
      total += size;
      if (total > 32 * 1024 * 1024 || logs.length >= 64) throw new Error('ARCHIVE_TOO_LARGE');
      const offset = view.getUint32(cursor + 42, true);
      if (offset + 30 > cursor || view.getUint32(offset, true) !== 0x04034b50 ||
          view.getUint16(offset + 8, true) !== method || view.getUint16(offset + 6, true) !== flags) {
        throw new Error('INVALID_ARCHIVE');
      }
      const dataOffset = offset + 30 + view.getUint16(offset + 26, true) + view.getUint16(offset + 28, true);
      if (dataOffset + packed > view.getUint32(end + 16, true)) throw new Error('INVALID_ARCHIVE');
      logs.push(new FitnessLogEntry(method, size, crc, bytes.slice(dataOffset, dataOffset + packed)));
    }
    cursor = next;
  }
  if (cursor !== directoryEnd) throw new Error('INVALID_ARCHIVE');
  return logs;
}

export function logCrc32(bytes: Uint8Array): number {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let entry = i;
    for (let bit = 0; bit < 8; bit++) entry = (entry >>> 1) ^ ((entry & 1) === 1 ? 0xedb88320 : 0);
    table[i] = entry >>> 0;
  }
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) crc = (crc >>> 8) ^ table[(crc ^ bytes[i]) & 255];
  return (crc ^ 0xffffffff) >>> 0;
}
