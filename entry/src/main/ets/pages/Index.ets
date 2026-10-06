import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { connection, hfp } from '@kit.ConnectivityKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NOTIFICATION_PROBE_ENABLED } from '../config/ProbeMode';
import { ProbeStats, receiveNotification, decodeStats } from '../core/ProbeStats';
import { ProbeStore } from '../platform/ProbeStore';

class PairedDevice {
  id: string;
  name: string;
  callConnection: string;

  constructor(id: string, name: string, callConnection: string) {
    this.id = id;
    this.name = name;
    this.callConnection = callConnection;
  }
}

const INK: string = '#142C3F';
const MUTED: string = '#5B6F7D';
const ACCENT: string = '#087F8C';

@Entry
@Component
struct Index {
  @State private devices: PairedDevice[] = [];
  @State private selectedId: string = '';
  @State private selectedName: string = '';
  @State private stats: ProbeStats = new ProbeStats();
  @State private busy: boolean = false;
  @State private notice: string = '先选择已配对的手表，再设置通知授权。';
  @State private failed: boolean = false;
  @State private grantStatus: string = '尚未检查';
  @State private subscribedDevices: number = 0;
  @State private allowedApps: number = 0;
  @State private detailsVisible: boolean = false;

  aboutToAppear(): void {
    this.readStats();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private readStats(): void {
    this.stats = new ProbeStore(this.context().filesDir).read();
  }

  private async runAction(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.failed = false;
    try {
      await action();
    } catch (error) {
      const code = (error as BusinessError).code;
      this.failed = true;
      if (code === 201) {
        this.notice = '权限不足或设备不支持此操作。请检查蓝牙授权；通知模式还需签名中的通知权限。错误码：201';
      } else if (code === 1600023) {
        this.notice = '当前安装包未启用通知订阅。请安装通知模式的构建。错误码：1600023';
      } else {
        this.notice = `操作未完成，请确认蓝牙已开启后重试。错误码：${code === undefined ? '未提供' : code}`;
      }
    } finally {
      this.busy = false;
    }
  }

  private async loadDevices(): Promise<void> {
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      this.context(), ['ohos.permission.ACCESS_BLUETOOTH']);
    if (permission.authResults.length === 0 || permission.authResults[0] !== 0) {
      this.failed = true;
      this.notice = '需要蓝牙权限才能识别手表。可在系统设置中授权后重试。';
      return;
    }
    const ids = connection.getPairedDevices();
    let callIds: string[] = [];
    let callQueryAvailable = true;
    try {
      callIds = hfp.createHfpAgProfile().getConnectedDevices();
    } catch (_) {
      callQueryAvailable = false;
    }
    const found: PairedDevice[] = [];
    for (let index = 0; index < ids.length; index++) {
      let name = '已配对设备';
      try {
        name = connection.getRemoteDeviceName(ids[index]) || name;
      } catch (_) {
        // A paired device can be temporarily unreachable; keep it selectable.
      }
      const callStatus = !callQueryAvailable ? '通话连接：未能检查' :
        (callIds.includes(ids[index]) ? '通话连接：已连接' : '通话连接：未连接');
      found.push(new PairedDevice(ids[index], name, callStatus));
    }
    this.devices = found;
    // OS-provided virtual IDs can change; never retain an old selection across scans.
    this.selectedId = '';
    this.selectedName = '';
    this.notice = found.length === 0 ? '未找到已配对设备。请先在手机系统蓝牙设置中配对手表。' :
      '请选择你的 Redmi Watch 5。通话连接状态仅用于检查配对条件。';
  }

  private async refreshAuthorization(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED) return;
    // Commit a status snapshot only when every platform query has succeeded.
    const granted = await notificationExtensionSubscription.isUserGranted();
    const subscriptions = await notificationExtensionSubscription.getSubscribeInfo();
    const bundles = await notificationExtensionSubscription.getUserGrantedEnabledBundles();
    this.grantStatus = granted ? '已允许获取通知' : '尚未允许获取通知';
    this.subscribedDevices = subscriptions.length;
    this.allowedApps = bundles.length;
  }

  private async subscribeSelected(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED || this.selectedId.length === 0) return;
    // Revalidate a session-only device ID before asking the notification service to use it.
    if (!connection.getPairedDevices().includes(this.selectedId)) {
      this.selectedId = '';
      this.selectedName = '';
      this.notice = '手表配对信息已变化，请重新查找并选择设备。';
      this.failed = true;
      return;
    }
    const info: notificationExtensionSubscription.NotificationExtensionSubscriptionInfo[] = [{
      addr: this.selectedId,
      type: notificationExtensionSubscription.SubscribeType.BLUETOOTH
    }];
    await notificationExtensionSubscription.subscribe(info);
    this.notice = '设备已关联。请打开通知授权，选择允许获取通知的应用。';
    await this.refreshAuthorization();
  }

  private async openAuthorization(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED) return;
    await notificationExtensionSubscription.openSubscriptionSettingsWithResult(this.context());
    await this.refreshAuthorization();
    this.notice = '授权状态已更新。让已授权的其他应用产生一条通知，再刷新接收记录。';
  }

  private async stopSubscription(): Promise<void> {
    if (!NOTIFICATION_PROBE_ENABLED) return;
    await notificationExtensionSubscription.unsubscribe();
    this.subscribedDevices = 0;
    this.notice = '已停止通知订阅。再次接收需手动关联设备。';
    await this.refreshAuthorization();
  }

  private async refreshResults(): Promise<void> {
    this.readStats();
    await this.refreshAuthorization();
    this.notice = '接收记录已刷新。记录来自手机系统的通知回调，不代表已送达手表。';
  }

  private async selfCheck(): Promise<void> {
    const sample = receiveNotification(new ProbeStats(), 'local.synthetic', 'self', 1);
    const restored = decodeStats(JSON.stringify(sample));
    this.failed = restored.received !== 1 || restored.lastReceivedAt !== 1;
    this.notice = this.failed ? '本地核心自检失败。' :
      '本地核心自检通过。使用的是合成数据，没有读取手机通知，也没有向手表发送消息。';
  }

  @Builder
  private sectionTitle(number: string, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Text(number).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ACCENT)
        .width(32).height(32).textAlign(TextAlign.Center).backgroundColor('#E7F3F4').borderRadius(12)
      Column({ space: 4 }) {
        Text(title).fontSize(19).fontWeight(FontWeight.Medium).fontColor(INK)
        Text(subtitle).fontSize(13).fontColor(MUTED)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%')
  }

  @Builder
  private metric(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(30).fontWeight(FontWeight.Bold).fontColor(INK)
      Text(label).fontSize(12).fontColor(MUTED)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Column({ space: 5 }) {
            Text('腕间通知').fontSize(30).fontWeight(FontWeight.Bold).fontColor(INK)
            Text('让手机消息，走到手腕上').fontSize(14).fontColor(MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('开发预览').fontSize(12).fontColor(ACCENT).padding(10)
            .backgroundColor('#E7F3F4').borderRadius(14)
        }.width('100%').margin({ top: 12, bottom: 4 })

        Column({ space: 10 }) {
          Text('先打通通知，再连接提醒').fontSize(21).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          Text('第一轮验证手机端接收能力。手表消息转发正在开发，当前不会在手表上显示通知。')
            .fontSize(14).fontColor('#D3E2EC').lineHeight(22)
          Text(NOTIFICATION_PROBE_ENABLED ? '通知验证模式' : '基础诊断模式')
            .fontSize(12).fontColor('#B5F2E9')
        }.alignItems(HorizontalAlign.Start).width('100%').padding(22).backgroundColor(INK).borderRadius(24)

        Column({ space: 16 }) {
          this.sectionTitle('01', '选择手表', '使用手机系统中已有的配对')
          if (this.selectedName.length > 0) {
            Text(`已选择：${this.selectedName}`).fontSize(15).fontColor(ACCENT).width('100%')
          }
          Button(this.devices.length === 0 ? '查找已配对设备' : '重新查找设备')
            .width('100%').height(48).backgroundColor(ACCENT).enabled(!this.busy)
            .onClick(() => { this.runAction(() => this.loadDevices()); })
          ForEach(this.devices, (device: PairedDevice, index: number) => {
            Button() {
              Column({ space: 6 }) {
                Text(`${this.selectedId === device.id ? '✓ ' : ''}${device.name}`)
                  .fontSize(16).fontColor(INK).fontWeight(FontWeight.Medium)
                Text(`设备 ${index + 1} · ${device.callConnection}`).fontSize(12).fontColor(MUTED)
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').type(ButtonType.Normal).padding(16).borderRadius(16)
              .backgroundColor(this.selectedId === device.id ? '#E7F3F4' : '#F3F6F8').enabled(!this.busy)
              .onClick(() => {
                this.selectedId = device.id;
                this.selectedName = device.name;
                this.failed = false;
                this.notice = '手表已选择。通知模式下可继续关联设备与授权。';
              })
          }, (device: PairedDevice) => device.id)
        }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(24)

        Column({ space: 16 }) {
          this.sectionTitle('02', '允许通知', '由你决定哪些应用可以被读取')
          if (NOTIFICATION_PROBE_ENABLED) {
            Text(`${this.grantStatus} · 已授权 ${this.allowedApps} 个应用`).fontSize(14).fontColor(MUTED)
            Button('关联选中的手表').width('100%').height(48).backgroundColor(ACCENT)
              .enabled(!this.busy && this.selectedId.length > 0)
              .onClick(() => { this.runAction(() => this.subscribeSelected()); })
            Button('打开通知授权').width('100%').height(48).backgroundColor('#E7F3F4').fontColor(ACCENT)
              .enabled(!this.busy).onClick(() => { this.runAction(() => this.openAuthorization()); })
            Button('停止通知订阅').backgroundColor('#F3F6F8').fontColor(MUTED).enabled(!this.busy)
              .onClick(() => { this.runAction(() => this.stopSubscription()); })
          } else {
            Text('这一构建用于检查页面和蓝牙配对。完成本地通知权限配置后，安装通知模式构建即可继续。')
              .fontSize(14).fontColor(MUTED).lineHeight(22)
          }
        }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(24)

        Column({ space: 16 }) {
          this.sectionTitle('03', '检查接收', '只记录来源和次数，不保存消息正文')
          Row({ space: 10 }) {
            this.metric(`${this.stats.received}`, '累计通知回调')
            this.metric(`${this.stats.cancelledItems}`, '累计取消条目')
          }.width('100%')
          Text(this.stats.lastReceivedAt === 0 ? '还没有接收记录' :
            `最近接收：${new Date(this.stats.lastReceivedAt).toLocaleString()}`)
            .fontSize(13).fontColor(MUTED)
          Button('刷新接收记录').width('100%').height(48).backgroundColor('#E7F3F4').fontColor(ACCENT)
            .enabled(!this.busy).onClick(() => { this.runAction(() => this.refreshResults()); })
        }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(24)

        Text(this.busy ? '正在处理，请稍候…' : this.notice).fontSize(14).lineHeight(22)
          .fontColor(this.failed ? '#9B3F19' : INK).width('100%').padding(16)
          .backgroundColor(this.failed ? '#FFF0E6' : '#E8EFF4').borderRadius(16)
          .accessibilityLevel('yes').accessibilityText(this.busy ? '正在处理' : this.notice)

        Button(this.detailsVisible ? '收起验证详情' : '查看验证详情').fontColor(MUTED)
          .backgroundColor(Color.Transparent).onClick(() => { this.detailsVisible = !this.detailsVisible; })
        if (this.detailsVisible) {
          Column({ space: 12 }) {
            Text(`版本 0.1.0 · API 26\n订阅设备：${this.subscribedDevices}\n自身通知已忽略：${this.stats.ignoredSelf}\n取消回调：${this.stats.cancelCallbacks}\n最近来源：${this.stats.lastBundleName || '暂无'}`)
              .fontSize(13).fontColor(MUTED).lineHeight(22)
            Text('配对和通话连接不代表手表消息通道已认证。后台接收、权限撤销和扩展重启都需要本机实测。')
              .fontSize(13).fontColor(MUTED).lineHeight(21)
            Button('运行本地核心自检').fontColor(ACCENT).backgroundColor('#E7F3F4').enabled(!this.busy)
              .onClick(() => { this.runAction(() => this.selfCheck()); })
          }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(20)
        }
        Text('通知留在本机 · 无需登录账号').fontSize(12).fontColor(MUTED).margin({ bottom: 16 })
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 20 })
    }.width('100%').height('100%').backgroundColor('#F3F6F8')
  }
}
