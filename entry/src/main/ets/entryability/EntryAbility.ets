import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WatchNotificationRelay } from '../platform/WatchNotificationRelay';

export default class EntryAbility extends UIAbility {
  onDestroy(): void { WatchNotificationRelay.shared(this.context.filesDir, this.context.resourceManager).close(); }
  onForeground(): void { this.context.eventHub.emit('wrist.foreground'); }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) hilog.error(0x0000, 'WristProbe', 'Page load failed, code=%{public}d', error.code);
    });
  }
}
