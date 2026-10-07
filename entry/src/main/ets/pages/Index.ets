import { AppCommand, AppState, DeviceCandidateView, CredentialCandidateView } from '../core/AppState';
import { AppViewModel } from '../platform/AppViewModel';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { FITNESS_LOGIN_URL, xiaomiLoginUrlAllowed } from '../core/MiFitnessCloud';
import { MI_LOGIN_USER_AGENT } from '../platform/MiFitnessAccount';

@Entry
@Component
struct Index {
  @State private view: AppState = new AppState();
  @State private availableWidth: number = 0;
  private model: AppViewModel | undefined = undefined;
  private loginController: webview.WebviewController = new webview.WebviewController();
  private pageScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.model = new AppViewModel(this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.loginController, (state: AppState) => {
        const resetScroll = state.route !== this.view.route || state.step !== this.view.step;
        this.view = state;
        if (resetScroll && !state.loginVisible) {
          try { this.pageScroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_) { }
        }
      });
    this.model.initialize();
  }
  aboutToDisappear(): void { this.model?.dispose(); this.model = undefined; }
  onBackPress(): boolean {
    if (this.view.loginVisible) { this.send(AppCommand.CLOSE_LOGIN); return true; }
    if (this.view.route === 'home') return false;
    if (this.view.route === 'setup') this.send(AppCommand.EXIT_SETUP);
    else if (this.view.route === 'diagnostics') this.send(AppCommand.DEVICE);
    else this.send(AppCommand.HOME);
    return true;
  }
  private send(command: AppCommand, reference: number = -1): void { this.model?.dispatch(command, reference); }
  private fp(value: number): number { return value; }
  private pageColor(): ResourceColor { return $r('app.color.wrist_page'); }
  private surface(): ResourceColor { return $r('app.color.wrist_surface'); }
  private alt(): ResourceColor { return $r('app.color.wrist_alt'); }
  private ink(): ResourceColor { return $r('app.color.wrist_text'); }
  private muted(): ResourceColor { return $r('app.color.wrist_muted'); }
  private accent(): ResourceColor { return $r('app.color.wrist_action'); }
  private onAccent(): ResourceColor { return $r('app.color.wrist_on_action'); }
  private soft(): ResourceColor { return $r('app.color.wrist_action_surface'); }
  private warning(): ResourceColor { return $r('app.color.wrist_warning'); }
  private warningSurface(): ResourceColor { return $r('app.color.wrist_warning_surface'); }
  private danger(): ResourceColor { return $r('app.color.wrist_danger'); }
  private busy(): boolean { return this.view.pendingKind.length > 0; }
  private deviceName(): string {
    return this.view.hasDevice ? this.view.deviceName : '还没有选择手表';
  }
  private relayTitle(): string {
    if (!this.view.relayEnabled) return '通知转发已停止';
    if (!this.view.permissionKnown) return '转发已开启 · 授权待检查';
    if (!this.view.permission) return '转发已开启 · 权限阻断';
    if (this.view.connection === 'disconnected') return '转发已开启 · 等待恢复';
    return '通知转发已开启';
  }
  private relayDescription(): string {
    if (!this.view.notificationMode) return '当前构建未启用通知订阅，需要通知模式构建。';
    if (!this.view.hasDevice) return '先选择已配对设备并完成初始化。';
    if (!this.view.supported) return '候选已识别，消息协议暂未适配。';
    if (!this.view.permissionKnown) return '请刷新系统授权状态；过去的授权记录不能代表当前权限。';
    if (!this.view.permission) return '授权恢复前，新通知无法转发。转发意图与权限状态分别保留。';
    return this.view.relayEnabled ? '新通知到来时连接和认证。当前不保证常驻在线。' :
      '开启后，只转发系统授权应用的新通知。';
  }
  private relayLabel(): string {
    if (this.view.pendingKind === 'start') return '正在检查前置条件…';
    if (this.view.pendingKind === 'stop') return '正在停止…';
    if (this.view.relayEnabled) return '停止通知转发';
    if (!this.view.hasDevice) return '开始初始化';
    if (!this.view.material) return '准备认证材料';
    if (!this.view.permissionKnown) return '检查系统授权';
    if (!this.view.permission) return '允许系统通知';
    return '开启通知转发';
  }
  private channelText(): string {
    if (this.view.connection === 'connecting') return '消息通道正在连接';
    if (this.view.connection === 'authenticating') return '消息通道正在认证';
    if (this.view.connection === 'disconnected') return '最近消息通道连接失败';
    return this.view.sessionBusy ? '通知转发会话正在处理' : '消息通道按需连接，本次状态未知';
  }
  private issueTitle(): string {
    if (!this.view.notificationMode) return '当前构建不支持通知订阅';
    if (!this.view.hasDevice) return '先选择你的手表';
    if (!this.view.supported) return '这台手表暂未适配';
    if (!this.view.material) return this.view.issue === 'import_error' ? '日志未能读取' : '还差一步：准备认证材料';
    if (!this.view.permissionKnown) return '系统通知授权待检查';
    if (!this.view.permission) return '系统通知权限待恢复';
    if (this.view.relayEnabled && this.view.connection === 'disconnected') return '最近连接未完成';
    if (this.view.sourceCount === 0) return '还没有选择应用来源';
    if (this.view.issue === 'import_cancelled') return '本次导入已取消';
    return '';
  }
  private issueDescription(): string {
    if (!this.view.notificationMode) return '通知模式安装包才能请求系统通知授权。';
    if (!this.view.hasDevice) return '从系统已配对候选中选择。本轮适配 Redmi Watch 5。';
    if (!this.view.supported) return '设备识别与消息协议支持是两项独立能力。';
    if (!this.view.material) return '从手机日志导入并确认保存，也可尝试账号同步。';
    if (!this.view.permissionKnown) return '请刷新状态或打开系统授权，查询失败时保留未知。';
    if (!this.view.permission) return '重新打开系统授权；转发仍可手动停止。';
    if (this.view.connection === 'disconnected') return '检查蓝牙与手表距离。失败通知不会盲目重发。';
    if (this.view.sourceCount === 0) return '系统授权允许，但没有获准应用。开启后暂无来源。';
    return '本次未保存新材料，原有已保存材料保留。';
  }
  private recover(): void {
    if (!this.view.notificationMode || this.view.connection === 'disconnected') this.send(AppCommand.DIAGNOSTICS);
    else if (this.view.hasDevice && this.view.material && (!this.view.permissionKnown || !this.view.permission || this.view.sourceCount === 0)) this.authorize();
    else this.send(AppCommand.SETUP);
  }
  private confirm(title: string, message: string, command: AppCommand): void {
    this.getUIContext().showAlertDialog({
      title: title, message: message,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '确认', action: () => { this.send(command); } }
    });
  }
  private authorize(): void {
    if (!this.view.hasDevice) { this.send(AppCommand.SETUP); return; }
    this.send(AppCommand.AUTHORIZE);
  }
  private permissionText(): string { return !this.view.permissionKnown ? '尚未确认' : this.view.permission ? '已允许' : '待授权'; }
  private iconText(): string {
    if (this.view.iconStatus === 'uploaded') return '图标分片已收包，实际显示待验证';
    if (this.view.iconStatus === 'notRequested') return '尚未收到手表图标请求';
    return '来源图标不可用或上传未完成，保留默认图标';
  }
  private feature(title: string, message: string): void {
    this.getUIContext().showAlertDialog({ title: title, message: message,
      confirm: { value: '知道了', action: () => {} } });
  }
  private goMaterial(): void {
    this.send(AppCommand.SETUP);
    if (this.view.step === 4) {
      this.send(AppCommand.PREVIOUS_STEP);
      this.send(AppCommand.PREVIOUS_STEP);
    } else if (this.view.step === 3) this.send(AppCommand.PREVIOUS_STEP);
  }

  @Builder
  private title(title: string, subtitle: string) {
    Column({ space: 8 }) {
      Text(title).fontSize(this.fp(28)).fontWeight(FontWeight.Bold).fontColor(this.ink())
        .accessibilityLevel('yes').accessibilityText(title)
      Text(subtitle).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 8 })
  }
  @Builder
  private action(label: string, command: AppCommand, primary: boolean, enabled: boolean) {
    Button(label).fontSize(this.fp(15)).fontWeight(FontWeight.Medium)
      .fontColor(primary ? this.onAccent() : this.ink())
      .backgroundColor(primary ? this.accent() : this.alt())
      .constraintSize({ minHeight: 48 }).padding({ left: 18, right: 18, top: 12, bottom: 12 })
      .width('100%').borderRadius(999).enabled(enabled)
      .onClick(() => { this.send(command); }).accessibilityText(label)
  }
  @Builder
  private note(text: string) {
    Text(text).fontSize(this.fp(12)).fontColor(this.muted()).lineHeight(this.fp(19)).width('100%')
  }
  @Builder
  private row(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(this.fp(15)).fontColor(this.ink()).layoutWeight(1)
      Text(value).fontSize(this.fp(14)).fontColor(this.muted()).textAlign(TextAlign.End).layoutWeight(0.8)
    }.width('100%').padding({ top: 12, bottom: 12 })
  }
  @Builder
  private homeHero() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text('你的手表').fontSize(this.fp(12)).fontColor(this.accent())
          Text(this.deviceName()).fontSize(this.fp(23)).fontWeight(FontWeight.Bold).fontColor(this.ink())
          Text(this.view.hasDevice ? '已选择系统配对设备' : '从已有配对开始').fontSize(this.fp(14)).fontColor(this.muted())
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (!this.view.large && this.availableWidth >= 350) {
          Image($rawfile('watch.svg')).width(104).height(138).objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
        }
      }.width('100%')
      Text(this.channelText()).fontSize(this.fp(12)).fontColor(this.accent())
        .padding(10).backgroundColor(this.soft()).borderRadius(14).width('100%')
      Divider().color($r('app.color.wrist_divider'))
      Text(this.relayTitle()).fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%')
      Text(this.relayDescription()).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22)).width('100%')
      this.action(this.relayLabel(), this.view.relayEnabled ? AppCommand.STOP_RELAY : AppCommand.START_RELAY,
        true, this.view.relayEnabled ? this.view.pendingKind !== 'stop' :
          !this.busy() && (!this.view.hasDevice || this.view.supported) && (!this.view.hasDevice || this.view.notificationMode))
      this.action('刷新状态', AppCommand.REFRESH, false, !this.busy())
      this.note(this.view.relayEnabled ? '可随时停止。已发出的帧可能已到手表。' : '停止转发时，系统通知授权仍保留。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24)
      .alignItems(HorizontalAlign.Start)
  }
  @Builder
  private preparation() {
    Column({ space: 14 }) {
      Text('转发准备').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      Column({ space: 6 }) {
        Text('系统通知 · ' + this.permissionText()).fontSize(this.fp(16)).fontColor(this.ink())
        Text(this.view.permission ? '已允许 ' + this.view.sourceCount + ' 个应用' : '请打开系统授权选择应用')
          .fontSize(this.fp(14)).fontColor(this.muted())
      }.alignItems(HorizontalAlign.Start).width('100%')
      Divider().color($r('app.color.wrist_divider'))
      Column({ space: 6 }) {
        Text(this.view.material ? '认证材料已准备' : '认证材料待准备').fontSize(this.fp(16)).fontColor(this.ink())
        Text('仅保存在手机安全存储，页面不持有密钥').fontSize(this.fp(14)).fontColor(this.muted())
      }.alignItems(HorizontalAlign.Start).width('100%')
      this.note(this.channelText())
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24)
      .alignItems(HorizontalAlign.Start)
  }
  @Builder
  private stats() {
    Column({ space: 16 }) {
      Row() {
        Text('本机累计记录').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1)
        Text('本机累计').fontSize(this.fp(12)).fontColor(this.muted())
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text(this.view.received.toString()).fontSize(this.fp(28)).fontWeight(FontWeight.Bold).fontColor(this.ink())
          Text('通知回调').fontSize(this.fp(12)).fontColor(this.muted())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text(this.view.acknowledged.toString()).fontSize(this.fp(28)).fontWeight(FontWeight.Bold).fontColor(this.ink())
          Text('手表收包').fontSize(this.fp(12)).fontColor(this.muted())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text(this.view.failed.toString()).fontSize(this.fp(28)).fontWeight(FontWeight.Bold).fontColor(this.ink())
          Text('转发失败').fontSize(this.fp(12)).fontColor(this.muted())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      this.note('收包只代表传输确认，是否显示仍需确认。只记录来源与计数，不保存正文。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24)
      .alignItems(HorizontalAlign.Start)
  }
  @Builder
  private futureFeatures() {
    Column({ space: 12 }) {
      Text('逐步完善腕间体验').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('以下扩展尚未实现，不显示虚构数据或可用操作。')
      Button('手机音乐控制 · 尚未实现').fontSize(this.fp(15)).fontColor(this.muted())
        .backgroundColor(this.alt()).width('100%').constraintSize({ minHeight: 48 }).borderRadius(16)
        .onClick(() => { this.feature('手机音乐控制 · 尚未实现',
          '媒体会话权限、目标播放器与手表双向事件待接入。手表本地音乐传输是另一项能力。'); })
      Button('睡眠、活动与运动 · 尚未实现').fontSize(this.fp(15)).fontColor(this.muted())
        .backgroundColor(this.alt()).width('100%').constraintSize({ minHeight: 48 }).borderRadius(16)
        .onClick(() => { this.feature('健康数据 · 尚未实现', '目前只有数据模型与分页契约，不读取健康数据，不补零。'); })
      Button('设备设置 · 部分能力待实现').fontSize(this.fp(15)).fontColor(this.muted())
        .backgroundColor(this.alt()).width('100%').constraintSize({ minHeight: 48 }).borderRadius(16)
        .onClick(() => { this.feature('设备设置', '已有通知类别诊断读写；时间、语言等设置尚未实现。'); })
      Button('表盘与资源 · 尚未实现').fontSize(this.fp(15)).fontColor(this.muted())
        .backgroundColor(this.alt()).width('100%').constraintSize({ minHeight: 48 }).borderRadius(16)
        .onClick(() => { this.feature('表盘与资源 · 尚未实现', '容量、文件校验、传输、取消与安装都需要后续实现和设备验收。'); })
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24)
      .alignItems(HorizontalAlign.Start)
  }
  @Builder
  private home() {
    this.title('今日', '让需要的消息来到手腕。')
    if (this.issueTitle().length > 0) {
      Column({ space: 10 }) {
        Text(this.issueTitle()).fontSize(this.fp(16)).fontWeight(FontWeight.Medium).fontColor(this.warning())
        Text(this.issueDescription()).fontSize(this.fp(14)).fontColor(this.warning()).lineHeight(this.fp(22))
        Button('处理这个问题').fontSize(this.fp(14)).fontColor(this.warning()).backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: 48 }).onClick(() => { this.recover(); })

      }.width('100%').padding(16).backgroundColor(this.warningSurface()).borderRadius(16)
        .alignItems(HorizontalAlign.Start)
    }
    if (this.availableWidth >= 840 && !this.view.large) {
      Row({ space: 20 }) {
        Column({ space: 20 }) { this.homeHero() }.layoutWeight(1.2)
        Column({ space: 20 }) { this.preparation(); this.stats() }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      this.homeHero()
      this.preparation()
      this.stats()
    }
    this.futureFeatures()
  }
  @Builder
  private device() {
    this.title('你的设备', '状态、初始化和诊断各有入口。')
    Column({ space: 14 }) {
      Text(this.deviceName()).fontSize(this.fp(23)).fontWeight(FontWeight.Bold).fontColor(this.ink())
      Text(this.channelText()).fontSize(this.fp(14)).fontColor(this.accent())
      this.row('系统配对', this.view.hasDevice ? '已选择系统配对设备' : '未选择')
      this.row('电量', '暂未读取')
      this.row('固件版本', '暂未读取')
      this.action('设备初始化', AppCommand.SETUP, true, !this.busy())
      Button('选择另一台设备').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy()).onClick(() => {
          if (this.view.relayEnabled) this.confirm('切换前停止转发',
            '先停止转发，再进入初始化重新选择。原有材料保留，后台须校验与新设备是否匹配。', AppCommand.CHANGE_DEVICE);
          else this.send(AppCommand.CHANGE_DEVICE);
        })
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('认证与授权').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.row('本机认证材料', this.view.material ? '已准备' : '待准备')
      Button('管理认证材料').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).onClick(() => { this.goMaterial(); })
      this.row('系统通知授权', this.permissionText())
      Button('管理系统授权').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).enabled(this.view.notificationMode && this.view.hasDevice && !this.busy())
        .onClick(() => { this.authorize(); })
      Text('账号同步 · 待验证').fontSize(this.fp(16)).fontColor(this.ink())
      Text(this.view.accountFailed ? '网页登录完成，设备同步未完成；原有材料保留。' :
        '可尝试登录小米账号获取设备。同步失败时，可继续使用日志导入。')
        .fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
      Button('登录并同步设备').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).onClick(() => {
          this.send(AppCommand.ACCOUNT_LOGIN);
        })
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('需要排查时').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('诊断与转发共用通道。运行诊断前必须停止通知转发。')
      this.action('诊断与验证', AppCommand.DIAGNOSTICS, false, !this.busy())
      Text('高级管理').fontSize(this.fp(16)).fontColor(this.ink())
      Button('停止系统通知订阅').fontSize(this.fp(15)).fontColor(this.muted()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy())
        .onClick(() => { this.confirm('停止系统通知订阅？',
          '先停止转发，再停止订阅；材料保留，再次接收需重新关联。', AppCommand.UNSUBSCRIBE); })
      Button('删除本机认证材料').fontSize(this.fp(15)).fontColor(this.danger()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy() && this.view.material)
        .onClick(() => { this.confirm('删除本机认证材料？',
          '会先停止转发，再删除本应用材料；之后需重新导入。原有设备绑定不会被改变。', AppCommand.DELETE_CREDENTIAL); })
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private notifications() {
    this.title('通知，由你决定。', '只转发系统授予的来源。')
    Column({ space: 14 }) {
      Text(this.relayTitle()).fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      Text(this.relayDescription()).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
      this.action(this.relayLabel(), this.view.relayEnabled ? AppCommand.STOP_RELAY : AppCommand.START_RELAY,
        true, this.view.relayEnabled ? this.view.pendingKind !== 'stop' :
          !this.busy() && (!this.view.hasDevice || this.view.supported) && (!this.view.hasDevice || this.view.notificationMode))
      this.note('停止后保留系统授权；已经发送的帧可能已到达手表。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('系统通知授权').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      Button('管理系统通知授权').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 }).enabled(this.view.hasDevice && this.view.notificationMode && !this.busy())
        .onClick(() => { this.authorize(); })
      Text(!this.view.permissionKnown ? '当前授权状态待检查' :
        this.view.permission ? '系统已允许 ' + this.view.sourceCount + ' 个应用来源' : '尚未取得系统通知授权')
        .fontSize(this.fp(14)).fontColor(this.muted())
      this.note('在系统授权页选择需要转发的应用。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('本轮转发规则').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('同一待发通知更新会替换内容；过时积压跳过。取消移除待发条目，不保证撤销已显示提醒。')
      this.note('消息正文仅短暂驻留内存。失败不盲目重发，ACK 不等于实际显示。')
      this.row('免打扰时段', '尚未实现')
      this.row('应用内筛选规则', '尚未实现')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private setup() {
    this.action('返回', AppCommand.EXIT_SETUP, false, true)
    this.title('把手表准备好。', '选择设备 → 准备认证 → 允许通知 → 完成设置')
    Text('第 ' + this.view.step + ' 步 / 共 4 步').fontSize(this.fp(14)).fontColor(this.accent()).width('100%')
    Column({ space: 16 }) {
      if (this.view.step === 1) {
        Text('选择系统已配对的手表').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note('当前协议适配 Redmi Watch 5。未配对时先在系统蓝牙设置中完成。')
        this.action('查找已配对设备', AppCommand.DISCOVER, true, !this.busy())
        if (this.view.candidatesVisible) {
          ForEach(this.view.candidates, (device: DeviceCandidateView) => {
            Button() {
              Column({ space: 6 }) {
                Text(device.name).fontSize(this.fp(16)).fontColor(this.ink())
                Text(device.supported ? '消息协议已适配 · ' + device.detail : '消息协议暂未适配 · ' + device.detail)
                  .fontSize(this.fp(12)).fontColor(this.muted())
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').padding(16).borderRadius(16).backgroundColor(this.soft())
              .enabled(!this.busy()).onClick(() => { this.send(AppCommand.SELECT_DEVICE, device.reference); })
          }, (device: DeviceCandidateView) => device.reference.toString())
          if (this.view.candidates.length === 0) { this.note('没有找到候选。请确认系统已配对手环或手表，再重新查找。') }
          this.note('选择候选不代表通道已认证或设备当前在线。')
        }
      } else if (this.view.step === 2) {
        Text('准备手表认证材料').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note(this.view.material ? '已有材料；重新导入取消或失败时，原材料保留。' : '从手机日志导入是当前推荐路线。')
        Text('在小米运动健康“我的 → 关于”连续点橙色图标导出日志，再保存到手机文件管理。')
          .fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
        this.note('文件须小于 64 MB，单份日志小于 16 MB。只确认本人的设备记录。')
        this.action('从手机日志导入', AppCommand.IMPORT, true, !this.busy())
        if (this.view.importPhase === 'reading') {
          Text('正在读取与识别…').fontSize(this.fp(14)).fontColor(this.accent())
          this.action('取消本次导入', AppCommand.CANCEL_IMPORT, false, true)
        } else if (this.view.importPhase === 'cancelled') {
          this.note('本次导入已取消，原有材料保留。')
        } else if (this.view.importPhase === 'error') {
          Text('日志未能读取，请重新导出符合限制的文件。').fontSize(this.fp(14)).fontColor(this.danger())
        } else if (this.view.importPhase === 'saved') {
          Text('认证材料已保存。').fontSize(this.fp(14)).fontColor(this.accent())
        }
        if (this.view.importCandidate) {
          ForEach(this.view.credentialCandidates, (candidate: CredentialCandidateView) => {
            Text(candidate.label).fontSize(this.fp(14)).fontColor(this.ink())
            Button('确认并保存此记录').fontSize(this.fp(15)).fontColor(this.onAccent()).backgroundColor(this.accent())
              .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy())
              .onClick(() => { this.send(AppCommand.SAVE_CANDIDATE, candidate.reference); })
          }, (candidate: CredentialCandidateView) => candidate.reference.toString())
          this.action('取消本次导入', AppCommand.DISCARD_CANDIDATE, false, !this.busy())
        }
        this.action('继续设置通知', AppCommand.NEXT_STEP, true, this.view.material && !this.busy())
        this.action('上一步', AppCommand.PREVIOUS_STEP, false, !this.busy())
      } else if (this.view.step === 3) {
        Text('允许需要转发的通知').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note('系统返回结果后完整刷新授权状态；取消操作不更改旧快照。')
        this.row('通知授权', this.permissionText())
        Button('打开系统通知授权').fontSize(this.fp(15)).fontColor(this.onAccent()).backgroundColor(this.accent())
          .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy() && this.view.notificationMode)
          .onClick(() => { this.authorize(); })
        this.action('检查设置结果', AppCommand.NEXT_STEP, true, this.view.permission && !this.busy())
        this.action('上一步', AppCommand.PREVIOUS_STEP, false, !this.busy())
      } else {
        Text('准备好，按你的节奏开启。').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note('设备、材料与系统授权已准备。初始化完成不会自动开启转发。')
        Text(this.relayTitle()).fontSize(this.fp(16)).fontColor(this.accent())
        this.action('完成并回首页', AppCommand.HOME, true, true)
        this.action('返回授权设置', AppCommand.PREVIOUS_STEP, false, true)
      }
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private diagnostics() {
    this.action('返回设备', AppCommand.DEVICE, false, true)
    this.title('诊断与验证', '技术细节集中在高级入口。')
    if (this.view.relayEnabled || this.view.sessionBusy) {
      Column({ space: 12 }) {
        Text('通知转发开启，诊断暂不可用').fontSize(this.fp(16)).fontWeight(FontWeight.Medium).fontColor(this.warning())
        Text('两者共用通道。明确停止后再执行诊断，结束后不会自动重新开启。')
          .fontSize(this.fp(14)).fontColor(this.warning()).lineHeight(this.fp(22))
        Button('停止转发并继续诊断').fontSize(this.fp(15)).fontColor(this.warning()).backgroundColor(this.alt())
          .width('100%').constraintSize({ minHeight: 48 }).onClick(() => {
            this.confirm('停止转发并进入诊断？', '停止期间不会转发新通知，诊断结束由你重新开启。', AppCommand.STOP_RELAY);
          })
      }.width('100%').padding(16).backgroundColor(this.warningSurface()).borderRadius(16).alignItems(HorizontalAlign.Start)
    }
    Column({ space: 14 }) {
      Text('消息通道与固定测试').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.action('检查消息通道', AppCommand.CHECK_CHANNEL, false,
        !this.view.relayEnabled && !this.view.sessionBusy && this.view.material && this.view.supported && !this.busy())
      this.action('认证并发送固定测试提醒', AppCommand.TEST_NOTIFICATION, false,
        !this.view.relayEnabled && !this.view.sessionBusy && this.view.material && this.view.supported && !this.busy())
      this.action('测试手表震动', AppCommand.TEST_VIBRATION, false,
        !this.view.relayEnabled && !this.view.sessionBusy && this.view.material && this.view.supported && !this.busy())
      Button('开启手表通知类别并测试').fontSize(this.fp(15)).fontColor(this.accent()).backgroundColor(this.alt())
        .width('100%').constraintSize({ minHeight: 48 })
        .enabled(!this.view.relayEnabled && !this.view.sessionBusy && this.view.material && this.view.supported && !this.busy())
        .onClick(() => { this.confirm('修改通知类别并测试？',
          '开启手表通知总开关与“其他应用”类别，保留其余类别。这会实际修改手表通知设置。', AppCommand.ENABLE_CATEGORIES); })
      Text(this.view.diagnosticResult).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
        .padding(16).backgroundColor(this.alt()).borderRadius(16).width('100%')
      if (this.view.confirmationRequired) {
        this.action('我在表上看到了 / 已执行', AppCommand.CONFIRM_VISIBLE, true, true)
        this.action('未看到 / 未执行', AppCommand.CONFIRM_NOT_VISIBLE, false, true)
      }
      this.note('人工确认只记录本次结果，不能代替其他来源或后台稳定性验收。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    this.stats()
    Column({ space: 12 }) {
      Text('安全技术详情').fontSize(this.fp(18)).fontWeight(FontWeight.Medium).fontColor(this.ink())
      Text('构建：' + (this.view.notificationMode ? '通知模式' : '基础模式') +
        '\n会话：' + this.view.connection + '\n最近错误码：' + this.view.lastCode +
        '\n跳过条目：' + this.view.dropped + '\n账号服务回退：待真机验证')
        .fontSize(this.fp(13)).fontColor(this.muted()).lineHeight(this.fp(22))
      this.note(this.iconText())
      this.note('认证密钥、会话 Cookie、原始报文、日志与消息正文都不进入页面。')

      this.note('截至 2026-10-07，固定提醒与“腕间测试源2”的自动转发已由用户确认显示。锁屏、后台、重连和重启仍待验收。')
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private accountLogin() {
    Column({ space: 12 }) {
      Text('登录小米账号').fontSize(this.fp(23)).fontWeight(FontWeight.Bold).fontColor(this.ink())
      Text(this.view.loginNotice).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
      Row({ space: 12 }) {
        Button('返回设备').fontColor(this.ink()).backgroundColor(this.alt())
          .constraintSize({ minHeight: 48 }).onClick(() => { this.send(AppCommand.CLOSE_LOGIN); })
        Button(this.busy() ? '正在同步…' : '登录后同步设备').fontColor(this.onAccent()).backgroundColor(this.accent())
          .layoutWeight(1).constraintSize({ minHeight: 48 }).enabled(!this.busy())
          .onClick(() => { this.send(AppCommand.ACCOUNT_SYNC); })
      }.width('100%')
      Web({ src: FITNESS_LOGIN_URL, controller: this.loginController, incognitoMode: true })
        .visibility(this.view.loginSensitivePage ? Visibility.Hidden : Visibility.Visible)
        .layoutWeight(1).width('100%').javaScriptAccess(true).domStorageAccess(true)
        .mixedMode(MixedMode.None).copyOptions(CopyOptions.None)
        .onControllerAttached(() => { this.loginController.setCustomUserAgent(MI_LOGIN_USER_AGENT); })
        .onPageEnd((event) => { this.model?.onLoginPage(event.url); })
        .onOverrideUrlLoading((request: WebResourceRequest) => {
          return request.isMainFrame() && !xiaomiLoginUrlAllowed(request.getRequestUrl());
        })
      this.note('密码与验证码在小米官方页面输入，应用不保存账号会话。')
    }.width('100%').height('100%').padding(16).backgroundColor(this.pageColor())
  }
  build() {
    if (this.view.loginVisible) { this.accountLogin() } else {
    Column() {
      Column({ space: 10 }) {
        Row() {
          Text('腕间通知').fontSize(this.fp(20)).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1)
          Text(this.view.notificationMode ? '通知模式' : '基础模式').fontSize(this.fp(12)).fontColor(this.accent()).padding(8).backgroundColor(this.soft()).borderRadius(12)
        }.width('100%')
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).backgroundColor(this.surface())
      Scroll(this.pageScroller) {
        Column({ space: 20 }) {
          if (this.view.route === 'home') { this.home() }
          else if (this.view.route === 'device') { this.device() }
          else if (this.view.route === 'notifications') { this.notifications() }
          else if (this.view.route === 'setup') { this.setup() }
          else { this.diagnostics() }
          if (this.view.notice.length > 0) {
            Text(this.view.notice).fontSize(this.fp(14)).fontColor(this.ink()).lineHeight(this.fp(22))
              .padding(16).width('100%').backgroundColor(this.alt()).borderRadius(16)
              .accessibilityLevel('yes').accessibilityText(this.view.notice)
          }
          if (this.busy()) {
            Text('正在处理，请稍候…').fontSize(this.fp(14)).fontColor(this.accent())
              .accessibilityLevel('yes').accessibilityText('正在处理')
          }
          this.note('通知正文与认证材料留在本机。')
        }.width('100%').constraintSize({ maxWidth: 1100 }).padding(16).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
      Row({ space: 6 }) {
        Button('今日').fontSize(this.fp(14)).fontColor(this.view.route === 'home' ? this.accent() : this.muted())
          .backgroundColor(this.view.route === 'home' ? this.soft() : this.surface()).layoutWeight(1).height(56)
          .onClick(() => { this.send(AppCommand.HOME); }).accessibilityText('今日')
        Button('设备').fontSize(this.fp(14)).fontColor(this.view.route === 'device' || this.view.route === 'setup' ||
          this.view.route === 'diagnostics' ? this.accent() : this.muted())
          .backgroundColor(this.view.route === 'device' || this.view.route === 'setup' || this.view.route === 'diagnostics' ?
            this.soft() : this.surface()).layoutWeight(1).height(56)
          .onClick(() => { this.send(AppCommand.DEVICE); }).accessibilityText('设备')
        Button('通知').fontSize(this.fp(14)).fontColor(this.view.route === 'notifications' ? this.accent() : this.muted())
          .backgroundColor(this.view.route === 'notifications' ? this.soft() : this.surface()).layoutWeight(1).height(56)
          .onClick(() => { this.send(AppCommand.NOTIFICATIONS); }).accessibilityText('通知')
      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 12 }).backgroundColor(this.surface())
    }.width('100%').height('100%').backgroundColor(this.pageColor())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        if (this.availableWidth !== width) this.availableWidth = width;
      })
    }
  }
}
