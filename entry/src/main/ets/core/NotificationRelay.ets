// Notification text is held only in this bounded in-memory queue.
export function boundedNotificationText(value: string, limit: number): string {
  let size = 0; let result = '';
  for (const char of value) {
    const code = char.codePointAt(0) || 0;
    const bytes = code < 128 ? 1 : (code < 2048 ? 2 : (code < 65536 ? 3 : 4));
    if (size + bytes > limit) break;
    result += char; size += bytes;
  }
  return result;
}
export class RelayNotification {
  hash: string; packageName: string; appName: string; title: string; body: string;
  timestampMs: number; group: string; id: number;
  cloneIndex: number;
  constructor(hash: string, packageName: string, appName: string, title: string, body: string,
    timestampMs: number, group: string, cloneIndex: number) {
    this.packageName = boundedNotificationText(packageName, 256);
    this.cloneIndex = cloneIndex;
    this.hash = boundedNotificationText(hash, 256);
    this.appName = boundedNotificationText(appName, 128);
    this.title = boundedNotificationText(title, 256); this.body = boundedNotificationText(body, 2048);
    this.timestampMs = Number.isSafeInteger(timestampMs) && timestampMs > 0 ? timestampMs : Date.now();
    this.group = boundedNotificationText(group || packageName, 256);
    // Separate app clones and stable updates. No message text contributes to identity.
    let id = 2166136261;
    const identity = `${packageName}:${cloneIndex}:${hash}`;
    for (let i = 0; i < identity.length; i++) id = Math.imul(id ^ identity.charCodeAt(i), 16777619) >>> 0;
    this.id = id;
  }
  clear(): void { this.title = ''; this.body = ''; this.hash = ''; this.appName = ''; this.packageName = ''; this.group = ''; }
}
export class NotificationRelayQueue {
  private pending: RelayNotification[] = [];
  enqueue(item: RelayNotification): boolean {
    const index = this.pending.findIndex(value => value.packageName === item.packageName && value.hash === item.hash && value.cloneIndex === item.cloneIndex);
    if (index >= 0) { this.pending[index].clear(); this.pending[index] = item; return true; }
    if (this.pending.length >= 16) { item.clear(); return false; }
    this.pending.push(item); return true;
  }
  take(): RelayNotification | undefined { return this.pending.shift(); }
  cancel(hashes: string[]): void {
    this.pending = this.pending.filter(item => {
      if (!hashes.includes(item.hash)) return true;
      item.clear(); return false;
    });
  }
  clear(): void { for (let i = 0; i < this.pending.length; i++) this.pending[i].clear(); this.pending = []; }
}
