import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class RelayConfig { enabled: boolean = false; musicEnabled: boolean = false; deviceId: string = ''; }
class RelayActivity { active: boolean = false; updatedMs: number = 0; }
export class RelayStats { acknowledged: number = 0; failed: number = 0; dropped: number = 0; lastCode: number = 0; lastIconStatus: string = 'notRequested'; lastIconReason: string = ''; }
export class RelayStore {
  private directory: string;
  constructor(filesDir: string) { this.directory = filesDir; }
  config(): RelayConfig {
    try {
      const parsed = JSON.parse(fileIo.readTextSync(`${this.directory}/relay-config.json`)) as RelayConfig;
      const result = new RelayConfig();
      if (typeof parsed.deviceId === 'string' && parsed.deviceId.length <= 256) result.deviceId = parsed.deviceId;
      result.musicEnabled = parsed.musicEnabled === true && result.deviceId.length > 0;
      result.enabled = parsed.enabled === true && result.deviceId.length > 0; return result;
    } catch (_) { return new RelayConfig(); }
  }
  stats(): RelayStats {
    try {
      const parsed = JSON.parse(fileIo.readTextSync(`${this.directory}/relay-stats.json`)) as RelayStats;
      const result = new RelayStats();
      result.acknowledged = this.count(parsed.acknowledged); result.failed = this.count(parsed.failed); result.dropped = this.count(parsed.dropped);
      result.lastCode = Number.isSafeInteger(parsed.lastCode) ? parsed.lastCode : 0;
      if (['notRequested', 'pending', 'cached', 'uploaded', 'unavailable', 'unsupported', 'failed'].includes(parsed.lastIconStatus)) result.lastIconStatus = parsed.lastIconStatus;
      if (typeof parsed.lastIconReason === 'string' && /^[a-z0-9_-]{0,80}$/.test(parsed.lastIconReason)) result.lastIconReason = parsed.lastIconReason;
      return result;
    } catch (_) { return new RelayStats(); }
  }
  private count(value: number): number { return Number.isSafeInteger(value) && value >= 0 ? Math.min(value, 2147483647) : 0; }
  active(): boolean {
    try {
      const parsed = JSON.parse(fileIo.readTextSync(`${this.directory}/relay-activity.json`)) as RelayActivity;
      const age = Date.now() - parsed.updatedMs;
      return parsed.active === true && Number.isSafeInteger(parsed.updatedMs) && age >= 0 && age < 8000;
    }
    catch (_) { return false; }
  }
  setActive(active: boolean): void { const activity = new RelayActivity(); activity.active = active; activity.updatedMs = Date.now(); this.write('relay-activity.json', JSON.stringify(activity)); }
  // UI writes config; extension writes stats. Neither file contains notification text or keys.
  setConfig(config: RelayConfig): void { this.write('relay-config.json', JSON.stringify(config)); }
  setStats(stats: RelayStats): void {
    // A connection failure before icon negotiation must not erase the last concrete icon result.
    if (stats.lastIconStatus === 'notRequested') {
      const previous = this.stats(); stats.lastIconStatus = previous.lastIconStatus; stats.lastIconReason = previous.lastIconReason;
    }
    this.write('relay-stats.json', JSON.stringify(stats));
  }
  music(): MusicRuntimeStats {
    try {
      const parsed = JSON.parse(fileIo.readTextSync(`${this.directory}/music-stats.json`)) as MusicRuntimeStats;
      const result = new MusicRuntimeStats();
      if (['off', 'connecting', 'ready', 'retry', 'permission_required'].includes(parsed.stage)) result.stage = parsed.stage;
      result.synced = this.count(parsed.synced); result.controlled = this.count(parsed.controlled);
      result.lastCode = Number.isSafeInteger(parsed.lastCode) ? parsed.lastCode : 0;
      result.commandCode = Number.isSafeInteger(parsed.commandCode) ? parsed.commandCode : 0;
      result.controlMs = this.count(parsed.controlMs);
      result.updatedMs = Number.isSafeInteger(parsed.updatedMs) ? parsed.updatedMs : 0;
      return result;
    } catch (_) { return new MusicRuntimeStats(); }
  }
  setMusic(stats: MusicRuntimeStats): void { this.write('music-stats.json', JSON.stringify(stats)); }
  setTestIcon(status: string, reason: string): void {
    const result = new TestIconStats();
    if (['notRequested', 'pending', 'cached', 'uploaded', 'unavailable', 'unsupported', 'failed'].includes(status)) result.status = status;
    if (/^[a-z0-9_-]{0,80}$/.test(reason)) result.reason = reason;
    result.completedMs = Date.now(); this.write('test-icon-stats.json', JSON.stringify(result));
  }
  private write(name: string, data: string): void {
    const path = `${this.directory}/${name}`; const file = fileIo.openSync(`${path}.tmp`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(data);
      if (fileIo.writeSync(file.fd, bytes.buffer) !== bytes.length) throw new Error('RELAY_WRITE_FAILED');
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    fileIo.renameSync(`${path}.tmp`, path);
  }
}
// Persist only operational metadata. Song titles, artists, session IDs and playback URLs are never stored.
export class MusicRuntimeStats {
  stage: string = 'off'; synced: number = 0; controlled: number = 0;
  lastCode: number = 0; commandCode: number = 0; updatedMs: number = 0;
  controlMs: number = 0;
}
class TestIconStats { status: string = 'notRequested'; reason: string = ''; completedMs: number = 0; }
