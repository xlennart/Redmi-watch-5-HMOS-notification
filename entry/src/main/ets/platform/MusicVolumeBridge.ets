import { WatchChannelError } from './WatchChannelProbe';

// Only the visible native page may drive AVVolumePanel. Never use an invisible/background panel.
export class MusicVolumeBridge {
  private static foreground: boolean = false;
  private static panelVisible: boolean = false;
  private static listener: ((level: number) => void) | undefined = undefined;
  static setForeground(value: boolean): void { MusicVolumeBridge.foreground = value; }
  static setPanelVisible(value: boolean): void { MusicVolumeBridge.panelVisible = value; }
  static bind(listener: (level: number) => void): () => void {
    MusicVolumeBridge.listener = listener;
    return () => {
      if (MusicVolumeBridge.listener === listener) { MusicVolumeBridge.listener = undefined; MusicVolumeBridge.panelVisible = false; }
    };
  }
  static request(level: number): void {
    if (!MusicVolumeBridge.foreground || !MusicVolumeBridge.panelVisible || !MusicVolumeBridge.listener)
      throw new WatchChannelError('需要打开腕间通知的音乐页，显示系统音量面板', -66);
    MusicVolumeBridge.listener(level);
  }
}
