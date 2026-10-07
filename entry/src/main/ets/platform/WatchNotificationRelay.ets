import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { util } from '@kit.ArkTS';
import { RelayNotification, NotificationRelayQueue } from '../core/NotificationRelay';
import { WatchTestSession } from './WatchTestSession';
import { WatchChannelError } from './WatchChannelProbe';
import { RelayStore } from './RelayStore';
import { WatchNotificationContent } from '../core/WatchProtocol';
import { resourceManager } from '@kit.LocalizationKit';
import { AppNotificationIcon } from './AppNotificationIcon';

export class WatchNotificationRelay {
  private queue: NotificationRelayQueue = new NotificationRelayQueue();
  private pumping: boolean = false;
  private closed: boolean = false;
  private session: WatchTestSession | undefined = undefined;
  private store: RelayStore;
  private resources: resourceManager.ResourceManager;
  constructor(filesDir: string, resources: resourceManager.ResourceManager) {
    this.store = new RelayStore(filesDir); this.resources = resources; this.store.setActive(false);
  }
  receive(info: notificationExtensionSubscription.NotificationInfo): void {
    if (this.closed || !this.store.config().enabled || info.bundleName === 'com.xlennart.wristnotifications') return;
    const item = new RelayNotification(info.hashCode, info.bundleName, info.appName || info.bundleName,
      info.content.title || '', info.content.text || '', info.deliveryTime || Date.now(), info.groupName || info.bundleName, info.appIndex);
    if (!item.title && !item.body) { item.clear(); return; }
    if (!this.queue.enqueue(item)) { const stats = this.store.stats(); stats.dropped++; this.store.setStats(stats); }
    this.pump().catch(() => { this.queue.clear(); });
  }
  cancel(hashes: string[]): void { this.queue.cancel(hashes); }
  close(): void { this.closed = true; this.queue.clear(); this.session?.cancel(); }
  private async pump(): Promise<void> {
    if (this.pumping || this.closed) return;
    this.pumping = true;
    try {
      this.store.setActive(true);
      while (!this.closed) {
        const config = this.store.config();
        if (!config.enabled) { this.queue.clear(); return; }
        const item = this.queue.take(); if (!item) return;
        const stats = this.store.stats();
        if (Date.now() - item.timestampMs > 60000) { item.clear(); stats.dropped++; this.store.setStats(stats); continue; }
        const session = new WatchTestSession(); this.session = session;
        const encoder = new util.TextEncoder();
        const encode = (value: string): Uint8Array => encoder.encodeInto(value);
        const content: WatchNotificationContent = { packageName: encode(item.packageName), appName: encode(item.appName), title: encode(item.title),
          body: encode(item.body), date: encode(item.timestampMs.toString()), group: encode(item.group), key: encode(item.hash), id: item.id };
        const timer = setInterval(() => {
          const current = this.store.config();
          if (this.closed || !current.enabled || current.deviceId !== config.deviceId) session.cancel();
        }, 500);
        let acknowledged = false; let errorCode = 0;
        try {
          const granted = await notificationExtensionSubscription.isUserGranted();
          const bundles = granted ? await notificationExtensionSubscription.getUserGrantedEnabledBundles() : [];
          if (!granted || !bundles.some(bundle => bundle.bundleName === item.packageName && bundle.appIndex === item.cloneIndex)) {
            throw new WatchChannelError('通知授权已撤销', -41);
          }
          await session.run(config.deviceId, () => { }, false, false, content, new AppNotificationIcon(this.resources, item.packageName));
          acknowledged = true;
        } catch (error) { errorCode = (error as WatchChannelError).code || -3; }
        finally {
          clearInterval(timer); this.session = undefined; item.clear();
          content.packageName.fill(0); content.appName.fill(0); content.title.fill(0); content.body.fill(0);
          content.date.fill(0); content.group.fill(0); content.key.fill(0);
        }
        const currentStats = this.store.stats();
        if (acknowledged) currentStats.acknowledged++; else currentStats.failed++;
        currentStats.lastIconStatus = session.iconStatus;
        currentStats.lastIconReason = session.iconReason;
        currentStats.lastCode = errorCode; this.store.setStats(currentStats);
      }
    } finally { this.pumping = false; this.store.setActive(false); }
  }
}
