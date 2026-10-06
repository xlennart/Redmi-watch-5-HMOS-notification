import { notificationExtensionSubscription, NotificationSubscriberExtensionAbility } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { receiveNotification, cancelNotifications } from '../core/ProbeStats';
import { ProbeStore } from '../platform/ProbeStore';

export default class NotificationSubscriberExtAbility extends NotificationSubscriberExtensionAbility {
  onReceiveMessage(info: notificationExtensionSubscription.NotificationInfo): void {
    try {
      const store = new ProbeStore(this.context.filesDir);
      const stats = receiveNotification(store.read(), info.bundleName, this.context.applicationInfo.name, Date.now());
      store.write(stats);
      hilog.info(0x0000, 'WristProbe', 'Receive callback persisted');
    } catch (_) {
      hilog.error(0x0000, 'WristProbe', 'Receive callback persistence failed');
    }
  }

  onCancelMessages(hashCodes: Array<string>): void {
    try {
      const store = new ProbeStore(this.context.filesDir);
      store.write(cancelNotifications(store.read(), hashCodes.length, Date.now()));
      hilog.info(0x0000, 'WristProbe', 'Cancel callback persisted');
    } catch (_) {
      hilog.error(0x0000, 'WristProbe', 'Cancel callback persistence failed');
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, 'WristProbe', 'Extension destroyed');
  }
}
