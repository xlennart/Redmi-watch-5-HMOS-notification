import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ProbeStats, decodeStats, cleanStats } from '../core/ProbeStats';

export class ProbeStore {
  private path: string;

  constructor(filesDir: string) {
    this.path = `${filesDir}/notification-probe.json`;
  }

  read(): ProbeStats {
    try {
      return decodeStats(fileIo.readTextSync(this.path));
    } catch (_) {
      return new ProbeStats();
    }
  }

  // The extension is the only writer; the UI only reads. Persist before callback returns.
  write(stats: ProbeStats): void {
    const tempPath = `${this.path}.tmp`;
    const file = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(cleanStats(stats)));
      const written = fileIo.writeSync(file.fd, bytes.buffer);
      if (written !== bytes.byteLength) throw new Error('Incomplete metadata write');
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(tempPath, this.path);
  }
}
