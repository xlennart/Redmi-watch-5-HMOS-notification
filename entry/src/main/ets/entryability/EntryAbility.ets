import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WatchNotificationRelay } from '../platform/WatchNotificationRelay';
import { MusicVolumeBridge } from '../platform/MusicVolumeBridge';

export default class EntryAbility extends UIAbility {
  onDestroy(): void { MusicVolumeBridge.setForeground(false); WatchNotificationRelay.shared(this.context.filesDir, this.context.resourceManager).close(); }
  onForeground(): void { MusicVolumeBridge.setForeground(true); this.context.eventHub.emit('wrist.foreground'); }
  onBackground(): void { MusicVolumeBridge.setForeground(false); }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadPage(windowStage);
  }
  private async loadPage(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow = await windowStage.getMainWindow();
      // The page extends only its background into system safe areas; controls still avoid them.
      const pageColor = this.context.resourceManager.getColorSync($r('app.color.wrist_page'));
      mainWindow.setWindowBackgroundColor('#' + (pageColor >>> 0).toString(16).padStart(8, '0'));
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000', navigationBarColor: '#00000000',
        statusBarContentColor: '#182231', navigationBarContentColor: '#182231'
      });
    } catch (_) {
      hilog.warn(0x0000, 'WristProbe', 'System bar appearance could not be configured');
    }
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) hilog.error(0x0000, 'WristProbe', 'Page load failed, code=%{public}d', error.code);
    });
  }
}
