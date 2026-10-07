import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { DeviceCredential } from '../core/MiFitnessCredentials';
import { decodeMiFitnessExport } from './MiFitnessDecode';

export class MiFitnessImportJob {
  private cancelled: boolean = false;
  private task: taskpool.Task | undefined = undefined;
  private timer: number = -1;
  private rejectPending: ((reason: Error) => void) | undefined = undefined;

  cancel(): void {
    this.cancelled = true;
    this.rejectPending?.(new Error('IMPORT_CANCELLED'));
    if (this.task) {
      try { taskpool.cancel(this.task); } catch (_) { }
    }
  }

  async pick(context: common.UIAbilityContext): Promise<DeviceCredential[]> {
    const selection = await new picker.DocumentViewPicker(context).select({
      maxSelectNumber: 1, fileSuffixFilters: ['运动健康日志|.zip,.log,.txt']
    });
    if (this.cancelled || selection.length === 0) return [];
    const deadline = new Promise<DeviceCredential[]>((_resolve, reject) => {
      this.rejectPending = reject;
      this.timer = setTimeout(() => {
        this.rejectPending = undefined;
        this.cancel();
        reject(new Error('IMPORT_TIMEOUT'));
      }, 30000);
    });
    try {
      return await Promise.race([this.readAndDecode(selection[0]), deadline]);
    } finally {
      if (this.timer !== -1) clearTimeout(this.timer);
      this.rejectPending = undefined;
    }
  }

  private async readAndDecode(uri: string): Promise<DeviceCredential[]> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let buffer: ArrayBuffer;
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size < 1 || size > 64 * 1024 * 1024) throw new Error('LOG_TOO_LARGE');
      buffer = new ArrayBuffer(size);
      let offset = 0;
      while (offset < size) {
        if (this.cancelled) throw new Error('IMPORT_CANCELLED');
        const part = new ArrayBuffer(Math.min(1024 * 1024, size - offset));
        const count = await fileIo.read(file.fd, part);
        if (count < 1) throw new Error('INVALID_LOG');
        new Uint8Array(buffer).set(new Uint8Array(part, 0, count), offset);
        new Uint8Array(part).fill(0);
        offset += count;
      }
    } finally {
      await fileIo.close(file);
    }
    try {
      if (this.cancelled) throw new Error('IMPORT_CANCELLED');
      this.task = new taskpool.Task(decodeMiFitnessExport, buffer);
      this.task.setCloneList([buffer]);
      const found = await taskpool.execute(this.task) as DeviceCredential[];
      if (this.cancelled) {
        for (let i = 0; i < found.length; i++) found[i].authKey = '';
        throw new Error('IMPORT_CANCELLED');
      }
      return found;
    } finally {
      this.task = undefined;
      new Uint8Array(buffer).fill(0);
    }
  }
}
