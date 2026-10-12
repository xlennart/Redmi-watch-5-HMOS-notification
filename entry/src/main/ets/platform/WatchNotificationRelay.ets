import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { util } from '@kit.ArkTS';
import { RelayNotification, NotificationRelayQueue } from '../core/NotificationRelay';
import { WatchTestSession } from './WatchTestSession';
import { WatchChannelError } from './WatchChannelProbe';
import { RelayStore } from './RelayStore';
import { WatchNotificationContent } from '../core/WatchProtocol';
import { resourceManager } from '@kit.LocalizationKit';
import { AppNotificationIcon } from './AppNotificationIcon';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { clearProto, fieldInt } from '../core/WatchProtocol';
import { parseWatchMusicCommand, watchMusicStateCommand, WatchMusicState } from '../core/WatchMusic';
import { WearableMusicCommand, WearableMusicControl } from '../core/WearableServices';
import { HarmonyPhoneMediaAdapter } from './PhoneMediaAdapter';
import { MusicBackgroundTask } from './MusicBackgroundTask';

export class WatchNotificationRelay {
  private static instance: WatchNotificationRelay | undefined = undefined;
  static shared(filesDir: string, resources: resourceManager.ResourceManager): WatchNotificationRelay {
    if (!WatchNotificationRelay.instance || WatchNotificationRelay.instance.closed) {
      WatchNotificationRelay.instance = new WatchNotificationRelay(filesDir, resources);
    }
    return WatchNotificationRelay.instance;
  }
  private queue: NotificationRelayQueue = new NotificationRelayQueue();
  private pumping: boolean = false;
  private closed: boolean = false;
  private session: WatchTestSession | undefined = undefined;
  private store: RelayStore;
  private resources: resourceManager.ResourceManager;
  private media: HarmonyPhoneMediaAdapter | undefined = undefined;
  private background: MusicBackgroundTask | undefined = undefined;
  private musicReady: (() => void) | undefined = undefined;
  private musicFailed: ((error: WatchChannelError) => void) | undefined = undefined;
  private musicGeneration: number = 0;
  constructor(filesDir: string, resources: resourceManager.ResourceManager) {
    this.store = new RelayStore(filesDir); this.resources = resources;
  }
  async startMusic(context: common.UIAbilityContext, deviceId: string): Promise<void> {
    if (this.closed) throw new WatchChannelError('连接管理已关闭', -21);
    if (this.store.config().musicEnabled && this.media) return;
    const generation = ++this.musicGeneration;
    const config = this.store.config(); config.deviceId = deviceId; config.musicEnabled = true;
    this.media = new HarmonyPhoneMediaAdapter(); this.background = new MusicBackgroundTask(context);
    try {
      this.media.start();
      const current = await this.media.currentPlayer();
      if (current.state === 'permission_required') throw new WatchChannelError('未获得媒体会话权限', 201);
      this.store.setConfig(config);
      await new Promise<void>((resolve, reject) => {
        this.musicReady = resolve; this.musicFailed = reject;
        this.pump().catch(() => { reject(new WatchChannelError('音乐连接未完成', -60)); });
      });
    } catch (error) {
      if (generation === this.musicGeneration) await this.stopMusic(); throw error as WatchChannelError;
    } finally { if (generation === this.musicGeneration) { this.musicReady = undefined; this.musicFailed = undefined; } }
  }
  async stopMusic(): Promise<void> {
    this.musicGeneration++;
    this.musicFailed?.(new WatchChannelError('音乐连接已取消', -21)); this.musicReady = undefined; this.musicFailed = undefined;
    const config = this.store.config(); config.musicEnabled = false; this.store.setConfig(config);
    if (this.media) this.session?.cancel();
    const media = this.media; this.media = undefined; await media?.close();
    await this.background?.stop(); this.background = undefined;
    const stats = this.store.music(); stats.stage = 'off'; stats.updatedMs = Date.now(); this.store.setMusic(stats);
  }
  cancelSession(): void { this.session?.cancel(); }
  receive(info: notificationExtensionSubscription.NotificationInfo): void {
    if (this.closed || !this.store.config().enabled || info.bundleName === 'com.xlennart.wristnotifications') return;
    const item = new RelayNotification(info.hashCode, info.bundleName, info.appName || info.bundleName,
      info.content.title || '', info.content.text || '', info.deliveryTime || Date.now(), info.groupName || info.bundleName, info.appIndex);
    if (!item.title && !item.body) { item.clear(); return; }
    if (!this.queue.enqueue(item)) { const stats = this.store.stats(); stats.dropped++; this.store.setStats(stats); }
    this.pump().catch(() => { this.queue.clear(); });
  }
  cancel(hashes: string[]): void { this.queue.cancel(hashes); }
  close(): void { this.closed = true; this.queue.clear(); this.session?.cancel(); this.stopMusic().catch(() => {}); }
  private async sendItem(session: WatchTestSession, item: RelayNotification, deviceId: string, connected: boolean): Promise<void> {
    const encoder = new util.TextEncoder(); const encode = (value: string): Uint8Array => encoder.encodeInto(value);
    const content: WatchNotificationContent = { packageName: encode(item.packageName), appName: encode(item.appName), title: encode(item.title),
      body: encode(item.body), date: encode(item.timestampMs.toString()), group: encode(item.group), key: encode(item.hash), id: item.id };
    let acknowledged = false; let code = 0;
    try {
      const granted = await notificationExtensionSubscription.isUserGranted();
      const bundles = granted ? await notificationExtensionSubscription.getUserGrantedEnabledBundles() : [];
      if (!granted || !bundles.some(bundle => bundle.bundleName === item.packageName && bundle.appIndex === item.cloneIndex)) {
        throw new WatchChannelError('通知授权已撤销', -41);
      }
      const provider = new AppNotificationIcon(this.resources, item.packageName);
      if (connected) await session.sendNotification(content, provider);
      else await session.run(deviceId, () => {}, false, false, content, provider);
      acknowledged = true;
    } catch (error) { code = (error as WatchChannelError).code || (error as BusinessError).code || -3; }
    finally {
      item.clear(); content.packageName.fill(0); content.appName.fill(0); content.title.fill(0); content.body.fill(0);
      content.date.fill(0); content.group.fill(0); content.key.fill(0);
    }
    const stats = this.store.stats();
    if (acknowledged) stats.acknowledged++; else stats.failed++;
    stats.lastCode = code; stats.lastIconStatus = session.iconStatus; stats.lastIconReason = session.iconReason; this.store.setStats(stats);
  }
  private async maintainMusic(deviceId: string): Promise<void> {
    const session = new WatchTestSession(); this.session = session;
    const background = this.background;
    const media = this.media;
    const initial = this.store.music(); initial.stage = 'connecting'; initial.updatedMs = Date.now(); this.store.setMusic(initial);
    try {
      await session.keepConnected(deviceId, async (live: WatchTestSession) => {
        if (!media || this.media !== media || !this.store.config().musicEnabled) return;
        await background?.start();
        if (this.media !== media || !this.store.config().musicEnabled) return;
        const ready = this.store.music(); ready.stage = 'ready'; ready.lastCode = 0; ready.updatedMs = Date.now(); this.store.setMusic(ready);
        this.musicReady?.(); this.musicReady = undefined;
        let active = true; let dirty = true; let lastState = ''; let progressDue = 0;
        let publishing: Promise<void> | undefined = undefined;
        let commands: Promise<void> = Promise.resolve(); let queued = 0;
        let stateFailure: WatchChannelError | undefined = undefined;
        const valid = (): boolean => active && !this.closed && this.media === media && this.store.config().musicEnabled;
        const publish = (): void => {
          if (!valid() || publishing) return;
          publishing = (async () => {
            const player = await media.currentPlayer();
            if (!valid()) return;
            if (player.state === 'permission_required') throw new WatchChannelError('媒体授权已撤销', 201);
            const encoder = new util.TextEncoder();
            const track = encoder.encodeInto(player.title.replace(/\u0000/g, '').slice(0, 120));
            const artist = encoder.encodeInto(player.artist.replace(/\u0000/g, '').slice(0, 100));
            const state: WatchMusicState = { state: player.state === 'playing' ? 'playing' : player.state === 'paused' ? 'paused' : 'none',
              track: track, artist: artist, positionSeconds: Math.floor((player.positionMs || 0) / 1000),
              durationSeconds: Math.floor((player.durationMs || 0) / 1000), volumePercent: player.volumePercent || 0 };
            const identity = player.state + '|' + player.volumePercent + '|' + player.title + '|' + player.artist + '|' + player.durationMs;
            try {
              if (dirty || identity !== lastState || Date.now() >= progressDue) {
                dirty = false;
                await live.sendApplication(watchMusicStateCommand(state));
                lastState = identity; progressDue = Date.now() + (player.state === 'playing' ? 5000 : 30000);
                const stats = this.store.music(); stats.synced++; stats.updatedMs = Date.now(); this.store.setMusic(stats);
              }
            } finally { track.fill(0); artist.fill(0); }
          })().catch((error: BusinessError) => {
            stateFailure = new WatchChannelError('媒体状态同步失败', error.code || -64); live.cancel();
          }).finally(() => { publishing = undefined; });
        };
        // A single decrypting receiver dispatches controls independently of state/notification ACK waits.
        live.onMusic((fields) => {
          if (!valid() || fieldInt(fields, 100) > 0) return;
          const request = parseWatchMusicCommand(fields);
          if (request.action === 'request') { dirty = true; publish(); return; }
          if (request.action === 'unsupported') return;
          if (queued >= 8) { const stats = this.store.music(); stats.commandCode = -69; this.store.setMusic(stats); return; }
          const receivedMs = Date.now(); queued++;
          commands = commands.then(async () => {
            queued--;
            if (!valid()) return;
            let code = 0; let accepted = false;
            if (Date.now() - receivedMs > 1000) code = -70;
            else {
              const control: WearableMusicControl = { command: request.action === 'play' ? WearableMusicCommand.PLAY :
                request.action === 'pause' ? WearableMusicCommand.PAUSE : request.action === 'previous' ? WearableMusicCommand.PREVIOUS :
                request.action === 'next' ? WearableMusicCommand.NEXT : WearableMusicCommand.SET_VOLUME, volumePercent: request.volumePercent };
              try { await media.control(control); accepted = true; }
              catch (error) { code = (error as BusinessError).code || -62; }
            }
            if (!valid()) return;
            const stats = this.store.music(); if (accepted) stats.controlled++;
            stats.commandCode = code; stats.controlMs = Math.min(60000, Date.now() - receivedMs);
            stats.updatedMs = Date.now(); this.store.setMusic(stats);
            dirty = true; publish();
          }).catch(() => {});
        });
        const stateTimer = setInterval(publish, 250);
        let heartbeat = 0; publish();
        try {
          while (valid()) {
            if (stateFailure) throw new WatchChannelError('媒体状态同步失败', (stateFailure as WatchChannelError).code);
            const config = this.store.config(); if (config.deviceId !== deviceId) break;
            if (Date.now() >= heartbeat) {
              heartbeat = Date.now() + 3000; const stats = this.store.music(); stats.updatedMs = Date.now(); this.store.setMusic(stats);
            }
            const item = config.enabled ? this.queue.take() : undefined;
            if (!config.enabled) this.queue.clear();
            if (item) {
              if (Date.now() - item.timestampMs <= 60000) await this.sendItem(live, item, deviceId, true);
              else { item.clear(); const stats = this.store.stats(); stats.dropped++; this.store.setStats(stats); }
            } else { clearProto(await live.nextApplication(250)); }
          }
          if (stateFailure) throw new WatchChannelError('媒体状态同步失败', (stateFailure as WatchChannelError).code);
        } catch (error) { throw stateFailure || error as WatchChannelError; }
        finally { active = false; clearInterval(stateTimer); await commands; await publishing; }
      });
    } catch (error) {
      if (this.media !== media || !this.store.config().musicEnabled) return;
      const code = (error as BusinessError).code || -60;
      const stats = this.store.music(); stats.stage = code === 201 ? 'permission_required' : 'retry'; stats.lastCode = code;
      stats.updatedMs = Date.now(); this.store.setMusic(stats); this.musicFailed?.(new WatchChannelError('音乐连接未完成', code));
      if (code === 201) { const config = this.store.config(); config.musicEnabled = false; this.store.setConfig(config); }
      if (code === 201) { const media = this.media; this.media = undefined; await media?.close(); }
    } finally { this.session = undefined; await background?.stop(); }
  }
  private async pump(): Promise<void> {
    if (this.pumping || this.closed) return;
    this.pumping = true;
    try {
      this.store.setActive(true);
      while (!this.closed) {
        const config = this.store.config();
        if (config.musicEnabled && this.media) {
          let activityDue = 0;
          const timer = setInterval(() => {
            const current = this.store.config();
            if (Date.now() >= activityDue) { activityDue = Date.now() + 2000; this.store.setActive(true); }
            if (this.closed || !current.musicEnabled || current.deviceId !== config.deviceId) this.session?.cancel();
          }, 500);
          try { await this.maintainMusic(config.deviceId); } finally { clearInterval(timer); }
          if (this.store.config().musicEnabled && this.media && !this.closed) {
            // Reconnect only the channel. A failed notification is never replayed.
            for (let i = 0; i < 30 && this.store.config().musicEnabled && !this.closed; i++) {
              await new Promise<void>(resolve => { setTimeout(resolve, 100); });
            }
          }
          continue;
        }
        if (!config.enabled) { this.queue.clear(); return; }
        const item = this.queue.take(); if (!item) return;
        const stats = this.store.stats();
        if (Date.now() - item.timestampMs > 60000) { item.clear(); stats.dropped++; this.store.setStats(stats); continue; }
        const session = new WatchTestSession(); this.session = session;
        const encoder = new util.TextEncoder();
        const encode = (value: string): Uint8Array => encoder.encodeInto(value);
        const content: WatchNotificationContent = { packageName: encode(item.packageName), appName: encode(item.appName), title: encode(item.title),
          body: encode(item.body), date: encode(item.timestampMs.toString()), group: encode(item.group), key: encode(item.hash), id: item.id };
        let activityDue = 0;
        const timer = setInterval(() => {
          const current = this.store.config();
          if (Date.now() >= activityDue) { activityDue = Date.now() + 2000; this.store.setActive(true); }
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
