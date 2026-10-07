import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

class Selection { id: string = ''; }
// The OS device reference is private to the platform adapter and revalidated against current pairing.
export class DeviceSelectionStore {
  private path: string;
  constructor(filesDir: string) { this.path = `${filesDir}/ui-device.json`; }
  read(): string {
    try {
      const selection = JSON.parse(fileIo.readTextSync(this.path)) as Selection;
      return typeof selection.id === 'string' && selection.id.length <= 256 ? selection.id : '';
    } catch (_) { return ''; }
  }
  write(id: string): void {
    if (!id || id.length > 256) throw new Error('DEVICE_SELECTION');
    const selection = new Selection(); selection.id = id;
    const file = fileIo.openSync(`${this.path}.tmp`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(selection));
      if (fileIo.writeSync(file.fd, bytes.buffer) !== bytes.length) throw new Error('DEVICE_SELECTION');
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    fileIo.renameSync(`${this.path}.tmp`, this.path);
  }
}
