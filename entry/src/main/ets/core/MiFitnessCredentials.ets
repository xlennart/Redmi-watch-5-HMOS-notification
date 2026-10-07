// Independently implemented reader for device records in Xiaomi Fitness exports.
// Account cookies are never treated as device credentials. No input is logged.
interface DeviceDetail {
  mac?: string;
  macAddress?: string;
  mac_address?: string;
  encrypt_key?: string;
  encryptKey?: string;
}

interface DeviceRecord {
  name?: string;
  model?: string;
  mac?: string;
  macAddress?: string;
  detail?: DeviceDetail;
}

export class DeviceCredential {
  name: string;
  model: string;
  address: string;
  authKey: string;

  constructor(name: string, model: string, address: string, authKey: string) {
    this.name = name;
    this.model = model;
    this.address = address;
    this.authKey = authKey;
  }
}

function text(value: string | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function recordCredential(fragment: string): DeviceCredential | undefined {
  if (!fragment.includes('"encrypt_key"') && !fragment.includes('"encryptKey"')) return undefined;
  try {
    const record = JSON.parse(fragment) as DeviceRecord;
    if (!record.detail || typeof record.detail !== 'object') return undefined;
    const name = text(record.name);
    // Candidate filtering supports all wrist wearables; this protocol stage supports Redmi Watch 5 only.
    if (!/^redmi\s+watch\s+5(?:\s+[0-9a-f]{4})?$/i.test(name)) return undefined;
    const detail = record.detail;
    const address = text(detail.mac || detail.macAddress || detail.mac_address || record.mac || record.macAddress)
      .replace(/-/g, ':').toUpperCase();
    const key = text(detail.encrypt_key || detail.encryptKey).toLowerCase();
    if (!/^[0-9a-f]{32}$/.test(key)) return undefined;
    // A redacted suffix is retained as such, never expanded into a guessed Bluetooth address.
    if (!/^(?:[0-9A-F]{2}:){1,5}[0-9A-F]{2}$/.test(address)) return undefined;
    return new DeviceCredential(name, text(record.model), address, key);
  } catch (_) {
    return undefined;
  }
}

export function readMiFitnessLog(source: string): DeviceCredential[] {
  if (source.length > 16 * 1024 * 1024) throw new Error('LOG_TOO_LARGE');
  const starts: number[] = [];
  const found: DeviceCredential[] = [];
  let quoted = false;
  let escaped = false;
  for (let i = 0; i < source.length; i++) {
    const c = source.charAt(i);
    if (quoted) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') quoted = false;
      continue;
    }
    if (c === '"' && starts.length > 0) quoted = true;
    else if (c === '{') {
      if (starts.length >= 64) throw new Error('LOG_TOO_DEEP');
      starts.push(i);
    } else if (c === '}' && starts.length > 0) {
      const start = starts.pop()!;
      if (i - start > 1024 * 1024) continue;
      const candidate = recordCredential(source.substring(start, i + 1));
      if (candidate) {
        const existing = found.findIndex(item => item.address === candidate.address);
        // Later log records supersede older keys for the same address.
        if (existing >= 0) found[existing] = candidate;
        else found.push(candidate);
        if (found.length > 32) throw new Error('TOO_MANY_DEVICES');
      }
    }
  }
  return found;
}
