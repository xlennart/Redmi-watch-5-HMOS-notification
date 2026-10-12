import { WatchChannelError } from './WatchChannelProbe';

// Only the visible native page may drive AVVolumePanel. Never use an invisible/background panel.
export class MusicVolumeBridge {
  private static foreground: boolean = false;
  private static listener: ((level: number) => void) | undefined = undefined;
  static setForeground(value: boolean): void { MusicVolumeBridge.foreground = value; }
  static bind(listener: (level: number) => void): () => void {
    MusicVolumeBridge.listener = listener;
    return () => { if (MusicVolumeBridge.listener === listener) MusicVolumeBridge.listener = undefined; };
  }
  static request(level: number): void {
    if (!MusicVolumeBridge.foreground || !MusicVolumeBridge.listener) throw new WatchChannelError('后台不支持系统音量调整，请打开腕间通知', -66);
    MusicVolumeBridge.listener(level);
  }
}
