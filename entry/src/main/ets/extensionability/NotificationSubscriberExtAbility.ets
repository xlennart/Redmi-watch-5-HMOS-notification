import { notificationExtensionSubscription, NotificationSubscriberExtensionAbility } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { receiveNotification, cancelNotifications } from '../core/ProbeStats';
import { ProbeStore } from '../platform/ProbeStore';
import { WatchNotificationRelay } from '../platform/WatchNotificationRelay';

export default class NotificationSubscriberExtAbility extends NotificationSubscriberExtensionAbility {
  private relay: WatchNotificationRelay | undefined = undefined;
  onReceiveMessage(info: notificationExtensionSubscription.NotificationInfo): void {
    try {
      const store = new ProbeStore(this.context.filesDir);
      const stats = receiveNotification(store.read(), info.bundleName, this.context.applicationInfo.name, Date.now());
      store.write(stats);
      hilog.info(0x0000, 'WristProbe', 'Receive callback persisted');
      if (!this.relay) this.relay = new WatchNotificationRelay(this.context.filesDir, this.context.resourceManager);
      this.relay.receive(info);
    } catch (_) {
      hilog.error(0x0000, 'WristProbe', 'Receive callback persistence failed');
    }
  }

  onCancelMessages(hashCodes: Array<string>): void {
    try {
      const store = new ProbeStore(this.context.filesDir);
      store.write(cancelNotifications(store.read(), hashCodes.length, Date.now()));
      this.relay?.cancel(hashCodes);
      hilog.info(0x0000, 'WristProbe', 'Cancel callback persisted');
    } catch (_) {
      hilog.error(0x0000, 'WristProbe', 'Cancel callback persistence failed');
    }
  }

  onDestroy(): void {
    this.relay?.close(); this.relay = undefined;
    hilog.info(0x0000, 'WristProbe', 'Extension destroyed');
  }
}
