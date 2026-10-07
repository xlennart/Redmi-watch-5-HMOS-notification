import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { connection, hfp } from '@kit.ConnectivityKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { AppCommand, AppState, DeviceCandidateView, CredentialCandidateView } from '../core/AppState';
import { NOTIFICATION_PROBE_ENABLED } from '../config/ProbeMode';
import { isWristWearableCandidate } from '../core/WearableCandidates';
import { DeviceCredential } from '../core/MiFitnessCredentials';
import { FITNESS_LOGIN_URL, xiaomiLoginUrlAllowed } from '../core/MiFitnessCloud';
import { ProbeStore } from './ProbeStore';
import { RelayStore, RelayConfig } from './RelayStore';
import { DeviceSelectionStore } from './DeviceSelectionStore';
import { WatchCredentialStore } from './WatchCredentialStore';
import { MiFitnessImportJob } from './MiFitnessImporter';
import { syncMiFitnessAccount, clearMiFitnessAccountSession, MI_LOGIN_CAPTURE_SCRIPT, MiAccountSyncError } from './MiFitnessAccount';
import { WatchChannelProbe, WatchChannelError } from './WatchChannelProbe';
import { WatchTestSession } from './WatchTestSession';
import { AppNotificationIcon } from './AppNotificationIcon';

// Owns platform calls and sensitive temporary candidates. Pages receive only AppState snapshots.
export class AppViewModel {
  private current: AppState = new AppState();
  private context: common.UIAbilityContext;
  private loginController: webview.WebviewController;
  private listener: (state: AppState) => void;
  private disposed: boolean = false;
  private operationEpoch: number = 0;
  private deviceGeneration: number = 0;
  private candidateGeneration: number = 0;
  private deviceIds: string[] = [];
  private selectedId: string = '';
  private credentials: DeviceCredential[] = [];
  private importJob: MiFitnessImportJob | undefined = undefined;
  private channelProbe: WatchChannelProbe | undefined = undefined;
  private testSession: WatchTestSession | undefined = undefined;
  private poll: number = -1;
  private loginResolve: ((payload: string) => void) | undefined = undefined;
  private loginReject: ((reason: MiAccountSyncError) => void) | undefined = undefined;
  private loginCaptureRunning: boolean = false;
  private foreground: () => void = () => { this.dispatch(AppCommand.REFRESH); };

  constructor(context: common.UIAbilityContext, controller: webview.WebviewController, listener: (state: AppState) => void) {
    this.context = context; this.loginController = controller; this.listener = listener;
    this.current.notificationMode = NOTIFICATION_PROBE_ENABLED;
  }
  snapshot(): AppState { return this.current.copy(); }
  private publish(): void {
    if (this.disposed) return;
    this.current.revision++; this.listener(this.current.copy());
  }
  initialize(): void {
    this.context.eventHub.on('wrist.foreground', this.foreground);
    this.restoreSelection(); this.readStats(); this.publish();
    this.execute('refresh', () => this.refresh()).catch(() => {});
    this.poll = setInterval(() => {
      if (this.disposed) return;
      try { this.readStats(); this.publish(); } catch (_) { }
    }, 2000);
  }
  private restoreSelection(): void {
    try {
      const relay = new RelayStore(this.context.filesDir).config();
      const stored = new DeviceSelectionStore(this.context.filesDir).read();
      const id = relay.deviceId || stored;
      if (!id || !connection.getPairedDevices().includes(id)) return;
      this.selectedId = id; this.current.hasDevice = true;
      this.current.deviceName = connection.getRemoteDeviceName(id) || '已配对手表';
      this.current.supported = this.supported(this.current.deviceName);
    } catch (_) { /* Unavailable pairing is unknown until the user grants Bluetooth and rescans. */ }
  }
  private supported(name: string): boolean { return /^redmi\s+watch\s+5(?:\s+[0-9a-f]{4})?$/i.test(name); }
  private readStats(): void {
    const probe = new ProbeStore(this.context.filesDir).read();
    const store = new RelayStore(this.context.filesDir); const stats = store.stats();
    this.current.received = probe.received; this.current.acknowledged = stats.acknowledged;
    this.current.failed = stats.failed; this.current.dropped = stats.dropped; this.current.lastCode = stats.lastCode;
    this.current.iconStatus = stats.lastIconStatus; this.current.relayEnabled = store.config().enabled;
    this.current.sessionBusy = store.active();
    this.current.lastAcknowledged = stats.acknowledged > 0;
    // No current connection stage can be inferred from an old cumulative counter.
  }
  private async refresh(): Promise<void> {
    const epoch = this.operationEpoch;
    this.readStats(); const material = await new WatchCredentialStore().present();
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.current.material = material;
    if (this.selectedId) {
      try {
        if (!connection.getPairedDevices().includes(this.selectedId)) {
          this.selectedId = ''; this.current.hasDevice = false; this.current.supported = false;
        }
      } catch (_) { }
    }
    await this.authorization();
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.current.notice = '状态已刷新。收包记录不代表当前在线或实际显示。';
  }
  private async authorization(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED) return;
    const epoch = this.operationEpoch;
    try {
      const granted = await notificationExtensionSubscription.isUserGranted();
      await notificationExtensionSubscription.getSubscribeInfo();
      const sources = await notificationExtensionSubscription.getUserGrantedEnabledBundles();
      if (epoch !== this.operationEpoch || this.disposed) return;
      this.current.permission = granted; this.current.permissionKnown = true;
      this.current.sources = sources.map(item => `${item.appName || item.bundleName}${item.appIndex > 0 ? ' · 应用分身 ' + item.appIndex : ''}`);
      this.current.sourceCount = sources.length;
    } catch (error) {
      if (epoch === this.operationEpoch && !this.disposed) this.current.permissionKnown = false;
      throw new WatchChannelError('通知权限查询未完成', (error as BusinessError).code || -3);
    }
  }
  private async execute(kind: string, action: () => Promise<void>): Promise<void> {
    if (this.disposed || this.current.pendingKind) return;
    const epoch = ++this.operationEpoch;
    this.current.pendingKind = kind; this.current.noticeFailed = false; this.publish();
    try { await action(); }
    catch (error) {
      if (epoch !== this.operationEpoch || this.disposed) return;
      this.current.noticeFailed = true;
      const code = (error as BusinessError).code || -3;
      this.current.notice = code === 201 ? '当前操作未获允许，请检查相关权限或设备支持。错误码：201' :
        (code === 1600023 ? '当前安装包未启用通知订阅，请使用通知模式构建。' :
          `操作未完成，可重试或查看诊断。错误码：${code}`);
    } finally {
      if (epoch === this.operationEpoch && !this.disposed) { this.current.pendingKind = ''; this.publish(); }
    }
  }
  private clearCandidates(): void {
    for (let i = 0; i < this.credentials.length; i++) this.credentials[i].authKey = '';
    this.credentials = []; this.candidateGeneration++;
    this.current.credentialCandidates = []; this.current.importCandidate = false;
  }
  private cancelPending(): void {
    this.operationEpoch++; this.importJob?.cancel(); this.channelProbe?.cancel(); this.testSession?.cancel();
    this.loginReject?.(new MiAccountSyncError('已取消账号同步', -17));
    this.current.pendingKind = ''; this.current.connection = 'unknown'; this.current.confirmationRequired = false;
  }
  private navigate(route: string): void {
    this.cancelPending(); this.clearCandidates(); this.current.loginVisible = false;
    clearMiFitnessAccountSession(); this.current.route = route;
  }
  dispose(): void {
    this.disposed = true; clearInterval(this.poll); this.cancelPending(); this.clearCandidates();
    this.context.eventHub.off('wrist.foreground', this.foreground); clearMiFitnessAccountSession();
  }
  dispatch(command: AppCommand, reference: number = -1): void {
    if (this.disposed) return;
    switch (command) {
      case AppCommand.HOME: this.navigate('home'); break;
      case AppCommand.DEVICE: this.navigate('device'); break;
      case AppCommand.NOTIFICATIONS: this.navigate('notifications'); break;
      case AppCommand.EXIT_SETUP: this.navigate(this.current.origin); break;
      case AppCommand.CLOSE_LOGIN: this.navigate('device'); break;
      case AppCommand.CANCEL_IMPORT:
        this.cancelPending(); this.clearCandidates(); this.current.importPhase = 'cancelled';
        this.current.notice = '本次导入已取消，原有材料保留。'; break;
      case AppCommand.STOP_RELAY:
        this.cancelPending(); this.execute('stop', () => this.stopRelay()).catch(() => {}); return;
      default:
        if (this.current.pendingKind) return;
        this.dispatchIdle(command, reference); return;
    }
    this.publish();
  }
  private dispatchIdle(command: AppCommand, reference: number): void {
    switch (command) {
      case AppCommand.DIAGNOSTICS: this.current.route = 'diagnostics'; break;
      case AppCommand.SETUP:
        this.current.origin = this.current.route; this.current.route = 'setup';
        this.current.step = !this.current.hasDevice ? 1 : !this.current.material ? 2 : (!this.current.permissionKnown || !this.current.permission) ? 3 : 4; break;
      case AppCommand.CHANGE_DEVICE:
        this.execute('change-device', async () => {
          const epoch = this.operationEpoch;
          await this.stopRelay();
          if (epoch !== this.operationEpoch || this.disposed) return;
          this.clearCandidates(); this.current.origin = 'device';
          this.current.route = 'setup'; this.current.step = 1; this.current.candidatesVisible = false;
        }).catch(() => {}); return;
      case AppCommand.REFRESH: this.execute('refresh', () => this.refresh()).catch(() => {}); return;
      case AppCommand.DISCOVER: this.execute('discover', () => this.discover()).catch(() => {}); return;
      case AppCommand.SELECT_DEVICE: this.execute('select', async () => { this.select(reference); }).catch(() => {}); return;
      case AppCommand.START_RELAY:
        if (!this.current.hasDevice || !this.current.material || !this.current.permission || !this.current.permissionKnown) {
          this.dispatchIdle(AppCommand.SETUP, -1); return;
        }
        this.execute('start', () => this.startRelay()).catch(() => {}); return;
      case AppCommand.AUTHORIZE: this.execute('authorize', () => this.authorize()).catch(() => {}); return;
      case AppCommand.IMPORT: this.execute('import', () => this.importCredentials()).catch(() => {}); return;
      case AppCommand.SAVE_CANDIDATE: this.execute('save', () => this.save(reference)).catch(() => {}); return;
      case AppCommand.DISCARD_CANDIDATE: this.clearCandidates(); this.current.importPhase = 'cancelled'; break;
      case AppCommand.NEXT_STEP:
        if (this.current.step === 2 && this.current.material) this.current.step = 3;
        else if (this.current.step === 3 && this.current.permissionKnown && this.current.permission) this.current.step = 4; break;
      case AppCommand.PREVIOUS_STEP: if (this.current.step > 1) this.current.step--; break;
      case AppCommand.ACCOUNT_LOGIN:
        this.clearCandidates(); clearMiFitnessAccountSession(); this.current.loginVisible = true;
        this.current.loginNotice = '请在小米官方页面完成登录与验证码，然后点击同步。'; break;
      case AppCommand.ACCOUNT_SYNC: this.execute('account', () => this.syncAccount()).catch(() => {}); return;
      case AppCommand.DELETE_CREDENTIAL:
        this.execute('delete', async () => {
          await this.stopRelay(); await new WatchCredentialStore().remove(); this.clearCandidates();
          this.current.material = false; this.current.notice = '本应用的认证材料已删除，之后可重新导入。';
        }).catch(() => {}); return;
      case AppCommand.UNSUBSCRIBE:
        this.execute('unsubscribe', async () => {
          await this.stopRelay(); await notificationExtensionSubscription.unsubscribe(); await this.authorization();
          this.current.notice = '系统通知订阅已停止。材料与授权保留，再次接收需重新关联设备。';
        }).catch(() => {}); return;
      case AppCommand.CHECK_CHANNEL:
      case AppCommand.TEST_NOTIFICATION:
      case AppCommand.TEST_VIBRATION:
      case AppCommand.ENABLE_CATEGORIES:
        this.execute('diagnostic', () => this.diagnose(command)).catch(() => {}); return;
      case AppCommand.CONFIRM_VISIBLE:
        if (this.current.confirmationRequired) {
          this.current.confirmationRequired = false; this.current.diagnosticResult += '\n已记录本次人工确认：提醒可见 / 震动已执行。';
        } break;
      case AppCommand.CONFIRM_NOT_VISIBLE:
        if (this.current.confirmationRequired) {
          this.current.confirmationRequired = false; this.current.diagnosticResult += '\n本次人工反馈：未显示 / 未执行。收包证据保留。';
        } break;
    }
    this.publish();
  }
  private async discover(): Promise<void> {
    if (new RelayStore(this.context.filesDir).config().enabled) {
      this.current.notice = '重新选择前请先停止通知转发。'; return;
    }
    const epoch = this.operationEpoch;
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, ['ohos.permission.ACCESS_BLUETOOTH']);
    if (epoch !== this.operationEpoch || this.disposed) return;
    if (!result.authResults.length || result.authResults[0] !== 0) {
      this.current.notice = '需要蓝牙权限才能识别手表。可在系统设置中授权后重试。'; return;
    }
    const ids = connection.getPairedDevices(); let calls: string[] = []; let callKnown = true;
    try { calls = hfp.createHfpAgProfile().getConnectedDevices(); } catch (_) { callKnown = false; }
    this.deviceGeneration++; this.deviceIds = []; this.current.candidates = [];
    this.selectedId = ''; this.current.hasDevice = false; this.current.supported = false; this.current.deviceName = '';
    for (let i = 0; i < ids.length; i++) {
      let name = '已配对设备'; let deviceClass = 0;
      try { name = connection.getRemoteDeviceName(ids[i]) || name; } catch (_) { }
      try { deviceClass = connection.getRemoteDeviceClass(ids[i]).majorMinorClass; } catch (_) { }
      if (!isWristWearableCandidate(name, deviceClass)) continue;
      const reference = this.deviceGeneration * 1000 + this.deviceIds.length;
      this.deviceIds.push(ids[i]);
      const detail = !callKnown ? '通话连接未能检查' : calls.includes(ids[i]) ? '通话连接已连接' : '通话连接未连接';
      this.current.candidates.push(new DeviceCandidateView(reference, name, this.supported(name), detail));
    }
    this.current.candidatesVisible = true;
    this.current.notice = this.deviceIds.length ? '已筛选手环和手表。候选识别不代表消息协议已适配。' : '未找到已配对的手环或手表，请检查系统蓝牙设置。';
  }
  private select(reference: number): void {
    const index = reference - this.deviceGeneration * 1000;
    if (index < 0 || index >= this.deviceIds.length || !Number.isInteger(index)) return;
    const id = this.deviceIds[index];
    if (!connection.getPairedDevices().includes(id)) { this.current.notice = '配对记录已变化，请重新查找。'; return; }
    new DeviceSelectionStore(this.context.filesDir).write(id);
    this.selectedId = id; const selected = this.current.candidates[index];
    this.current.hasDevice = true; this.current.deviceName = selected.name; this.current.supported = selected.supported;
    this.current.connection = 'unknown'; this.current.confirmationRequired = false; this.current.step = 2;
    this.current.notice = selected.supported ? '已选择手表。材料与目标的匹配仍由密钥认证确认。' : '已识别手表；当前消息协议暂未适配。';
  }
  private async subscribe(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED || !this.selectedId) throw new WatchChannelError('先选择设备并使用通知模式', -20);
    if (!connection.getPairedDevices().includes(this.selectedId)) throw new WatchChannelError('重新选择配对手表', -20);
    const subscriptions: notificationExtensionSubscription.NotificationExtensionSubscriptionInfo[] = [{
      addr: this.selectedId, type: notificationExtensionSubscription.SubscribeType.BLUETOOTH
    }];
    await notificationExtensionSubscription.subscribe(subscriptions);
  }
  private async authorize(): Promise<void> {
    const epoch = this.operationEpoch;
    await this.subscribe();
    if (epoch !== this.operationEpoch || this.disposed) return;
    await notificationExtensionSubscription.openSubscriptionSettingsWithResult(this.context);
    if (epoch !== this.operationEpoch || this.disposed) return;
    await this.authorization();
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.current.notice = '系统授权状态已更新。请选择需要转发的应用。';
  }
  private async startRelay(): Promise<void> {
    const epoch = this.operationEpoch;
    if (!this.current.supported || !NOTIFICATION_PROBE_ENABLED) return;
    const material = await new WatchCredentialStore().present();
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.current.material = material;
    if (!this.current.material) throw new WatchChannelError('需要认证材料', -31);
    await this.authorization(); if (!this.current.permission) throw new WatchChannelError('需要通知授权', -41);
    if (epoch !== this.operationEpoch || this.disposed) return;
    await this.subscribe();
    if (epoch !== this.operationEpoch || this.disposed) return;
    const config = new RelayConfig(); config.enabled = true; config.deviceId = this.selectedId;
    new RelayStore(this.context.filesDir).setConfig(config); this.current.relayEnabled = true;
    this.current.notice = '通知转发已开启，等待已授权应用的新通知。消息通道按需连接。';
  }
  private async stopRelay(): Promise<void> {
    const store = new RelayStore(this.context.filesDir); store.setConfig(new RelayConfig());
    this.current.relayEnabled = false; this.current.sessionBusy = store.active(); this.publish();
    const until = Date.now() + 2500;
    while (store.active() && Date.now() < until) await new Promise<void>(resolve => { setTimeout(resolve, 100); });
    this.current.sessionBusy = store.active();
    this.current.notice = this.current.sessionBusy ? '已停止新增转发，当前会话尚未确认关闭。诊断仍暂停，请稍后刷新。' :
      '通知转发已停止，当前转发会话已释放。已发出的帧可能已到手表，系统授权仍保留。';
    if (this.current.sessionBusy) throw new WatchChannelError('转发会话尚未释放', -42);
  }
  private async importCredentials(): Promise<void> {
    this.clearCandidates(); this.current.importPhase = 'reading'; this.publish();
    const job = new MiFitnessImportJob(); this.importJob = job; const epoch = this.operationEpoch;
    try {
      const found = await job.pick(this.context);
      if (epoch !== this.operationEpoch || this.disposed) { for (const item of found) item.authKey = ''; return; }
      this.useCandidates(found);
      this.current.importPhase = found.length ? 'candidate' : 'error';
      this.current.notice = found.length ? '已识别设备记录。确认自己的记录后，材料才会保存。' : '未找到目标手表认证记录，请重新导出小米运动健康日志。';
    } catch (error) {
      if (epoch !== this.operationEpoch || this.disposed) return;
      const reason = (error as Error).message; this.clearCandidates();
      this.current.importPhase = reason === 'IMPORT_CANCELLED' ? 'cancelled' : 'error';
      this.current.noticeFailed = reason !== 'IMPORT_CANCELLED';
      this.current.notice = reason === 'IMPORT_CANCELLED' ? '本次导入已取消，原有材料保留。' :
        reason === 'IMPORT_TIMEOUT' ? '日志处理超时，可重新导出后重试。' : '日志未能读取。ZIP 文件需小于 64 MB，单份日志需小于 16 MB。';
    } finally { if (this.importJob === job) this.importJob = undefined; }
  }
  private useCandidates(found: DeviceCredential[]): void {
    this.clearCandidates(); this.credentials = found; this.current.importCandidate = found.length > 0;
    this.current.credentialCandidates = found.map((item, index) => new CredentialCandidateView(
      this.candidateGeneration * 1000 + index, `${item.name} · 地址末尾 ${item.address.slice(-5)}`));
  }
  private async save(reference: number): Promise<void> {
    const epoch = this.operationEpoch;
    const index = reference - this.candidateGeneration * 1000;
    if (!Number.isInteger(index) || index < 0 || index >= this.credentials.length) return;
    await new WatchCredentialStore().save(this.credentials[index]);
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.clearCandidates(); this.current.material = true; this.current.importPhase = 'saved';
    this.current.notice = '认证材料已保存在手机安全存储中。设备匹配由后续认证确认。';
  }
  private async diagnose(command: AppCommand): Promise<void> {
    const epoch = this.operationEpoch;
    const store = new RelayStore(this.context.filesDir);
    if (store.config().enabled || store.active()) { this.current.diagnosticResult = '转发仍占用通道，请明确停止并等待释放后重试。'; return; }
    if (!this.current.supported || !this.selectedId || !await new WatchCredentialStore().present()) return;
    if (epoch !== this.operationEpoch || this.disposed) return;
    this.current.confirmationRequired = false;
    this.current.connection = 'connecting'; this.current.diagnosticResult = '正在检查消息通道…'; this.publish();
    try {
      if (command === AppCommand.CHECK_CHANNEL) {
        const probe = new WatchChannelProbe(); this.channelProbe = probe;
        try {
          const version = await probe.check(this.selectedId);
          if (epoch === this.operationEpoch) this.current.diagnosticResult = `消息通道可通信，协议版本 ${version}；尚未完成密钥认证。`;
        } finally { if (this.channelProbe === probe) this.channelProbe = undefined; }
      } else {
        const session = new WatchTestSession(); this.testSession = session;
        try {
          await session.run(this.selectedId, (message: string) => {
            if (epoch !== this.operationEpoch || this.disposed) return;
            this.current.diagnosticResult = message; this.current.connection = 'authenticating'; this.publish();
          }, command === AppCommand.ENABLE_CATEGORIES, command === AppCommand.TEST_VIBRATION, undefined,
            new AppNotificationIcon(this.context.resourceManager, 'com.xlennart.wristnotifications'));
          if (epoch === this.operationEpoch) {
            this.current.confirmationRequired = true;
            this.current.diagnosticResult += command === AppCommand.TEST_VIBRATION ? '\n请确认手表是否短震两次。' : '\n请查看手表通知中心是否出现“腕间通知测试”。';
          }
        } finally { if (this.testSession === session) this.testSession = undefined; }
      }
    } catch (error) {
      if (epoch === this.operationEpoch) {
        const failure = error as WatchChannelError;
        this.current.diagnosticResult = `操作未完成。阶段：${failure.stage || '消息通道'}，错误码：${failure.code || -3}`;
      }
      throw error as WatchChannelError;
    } finally { if (epoch === this.operationEpoch) this.current.connection = 'unknown'; }
  }

  onLoginPage(url: string): void {
    if (!this.loginResolve) { if (!url.includes('_json=true')) this.current.loginSensitivePage = false; this.publish(); return; }
    if (!xiaomiLoginUrlAllowed(url) || !url.includes('_json=true') || this.loginCaptureRunning) return;
    this.loginCaptureRunning = true; this.captureLogin(this.operationEpoch).catch(() => {});
  }
  private async captureLogin(epoch: number): Promise<void> {
    try {
      await this.loginController.runJavaScript(MI_LOGIN_CAPTURE_SCRIPT);
      while (this.loginResolve && !this.disposed && epoch === this.operationEpoch) {
        let payload = await this.loginController.runJavaScript('(() => { const value = window.__wristLoginCapture || ""; delete window.__wristLoginCapture; return value; })()');
        if (epoch !== this.operationEpoch || this.disposed) { payload = ''; return; }
        if (payload.startsWith('"')) payload = JSON.parse(payload) as string;
        if (payload.length > 0) { this.loginResolve?.(payload); payload = ''; break; }
        await new Promise<void>(resolve => { setTimeout(resolve, 150); });
      }
    } catch (_) { if (epoch === this.operationEpoch) this.loginReject?.(new MiAccountSyncError('读取浏览服务响应', -16)); }
    finally { this.loginCaptureRunning = false; }
  }
  private async browserLoginResponse(): Promise<string> {
    this.current.loginSensitivePage = true; this.publish(); let timer = -1;
    let ownResolve: ((payload: string) => void) | undefined = undefined;
    try {
      return await new Promise<string>((resolve, reject) => {
        ownResolve = resolve; this.loginResolve = resolve; this.loginReject = reject;
        timer = setTimeout(() => { reject(new MiAccountSyncError('等待浏览服务响应', -17)); }, 25000);
        this.loginController.loadUrl(`${FITNESS_LOGIN_URL}&_json=true`);
      });
    } finally {
      clearTimeout(timer);
      if (this.loginResolve === ownResolve) { this.loginResolve = undefined; this.loginReject = undefined; }
    }
  }
  private async syncAccount(): Promise<void> {
    const epoch = this.operationEpoch;
    try {
      const found = await syncMiFitnessAccount(await this.browserLoginResponse());
      if (epoch !== this.operationEpoch || this.disposed) { for (const item of found) item.authKey = ''; return; }
      this.useCandidates(found); this.current.loginVisible = false; this.current.accountFailed = false;
      this.current.route = 'setup'; this.current.origin = 'device'; this.current.step = 2;
      this.current.importPhase = found.length ? 'candidate' : 'error'; clearMiFitnessAccountSession();
      this.current.notice = found.length ? '设备已同步，账号会话已清理。请选择自己的记录并保存。' : '账号中未找到有效的 Redmi Watch 5 认证记录，可继续使用日志路线。';
    } catch (error) {
      if (epoch !== this.operationEpoch || this.disposed) return;
      const failure = error as MiAccountSyncError; this.current.accountFailed = true;
      this.current.loginNotice = `登录或同步未完成。阶段：${failure.stage || '账号服务'}，错误码：${failure.code || -3}。可重试或返回使用日志路线。`;
      this.loginController.loadUrl(FITNESS_LOGIN_URL);
    } finally { if (epoch === this.operationEpoch) this.current.loginSensitivePage = false; }
  }
}
