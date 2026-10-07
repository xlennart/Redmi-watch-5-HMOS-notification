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
    else if (this.view.route === 'diagnostics') this.send(AppCommand.HOME);
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
    if (!this.view.relayEnabled) return '通知转发已关闭';
    if (!this.view.permissionKnown) return '转发已开启 · 授权待检查';
    if (!this.view.permission) return '转发已开启 · 权限阻断';
    if (this.view.connection === 'disconnected') return '转发已开启 · 等待恢复';
    return '通知转发已开启';
  }
  private relayDescription(): string {
    if (!this.view.notificationMode) return '当前构建未启用通知订阅，需要通知模式构建。';
    if (!this.view.hasDevice) return '先选择已配对设备并完成初始化。';
    if (!this.view.supported) return '候选已识别，消息协议暂未适配。';
    if (!this.view.permissionKnown) return '请检查系统通知授权。';
    if (!this.view.permission) return '需要恢复系统授权才能继续转发。';
    return this.view.relayEnabled ? '等待已授权应用的新通知。' :
      '开启后，只转发系统授权应用的新通知。';
  }
  private relayLabel(): string {
    if (this.view.pendingKind === 'start') return '正在开启…';
    if (this.view.pendingKind === 'stop') return '正在停止…';
    if (this.view.relayEnabled) return '停止通知转发';
    if (!this.view.hasDevice) return '开始初始化';
    if (!this.view.supported) return '重新选择手表';
    if (!this.view.material) return '继续设置';
    if (!this.view.permissionKnown) return '检查系统授权';
    if (!this.view.permission) return '允许系统通知';
    return '开启通知转发';
  }
  private channelText(): string {
    if (this.view.connection === 'connecting') return '消息通道正在连接';
    if (this.view.connection === 'authenticating') return '消息通道正在认证';
    if (this.view.connection === 'disconnected') return '最近消息通道连接失败';
    return this.view.sessionBusy ? '正在处理新通知' : '新通知到来时连接手表';
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
  @Builder
  private title(title: string, subtitle: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(this.fp(22)).fontWeight(FontWeight.Bold).fontColor(this.ink())
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
      .width('100%').borderRadius(12).enabled(enabled)
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

  private pageTitle(): string {
    if (this.view.route === 'device') return '设置';
    if (this.view.route === 'setup') return '设置通知转发';
    if (this.view.route === 'diagnostics') return '问题排查';
    return '腕间通知';
  }
  private sendTest(): void {
    if (this.view.relayEnabled || this.view.sessionBusy) {
      this.confirm('暂停转发并测试？', '测试期间暂停新通知转发。测试结束后可点击“继续通知转发”。', AppCommand.QUICK_TEST);
    } else this.send(AppCommand.QUICK_TEST);
  }
  private readyToTest(): boolean { return this.view.hasDevice && this.view.supported && this.view.material && !this.busy(); }
  @Builder
  private entry(label: string, value: string, command: AppCommand) {
    Button() {
      Row({ space: 12 }) {
        Text(label).fontSize(16).fontColor(this.ink()).layoutWeight(1)
        Text(value).fontSize(13).fontColor(this.muted())
        Text('›').fontSize(22).fontColor(this.muted())
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }.width('100%').constraintSize({ minHeight: 52 }).borderRadius(12).backgroundColor(this.surface())
      .enabled(!this.busy()).onClick(() => { this.send(command); }).accessibilityText(label + '，' + value)
  }
  @Builder
  private home() {
    Column({ space: 14 }) {
      Text(this.deviceName()).fontSize(15).fontColor(this.muted())
      Text(this.relayTitle()).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink())
      Text(this.relayDescription()).fontSize(14).fontColor(this.muted()).lineHeight(22)
      this.action(this.relayLabel(), this.view.relayEnabled ? AppCommand.STOP_RELAY : AppCommand.START_RELAY,
        true, this.view.relayEnabled ? this.view.pendingKind !== 'stop' : !this.busy())
      if (this.view.sessionBusy) { this.note('正在处理新通知…') }
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(18).alignItems(HorizontalAlign.Start)
    if (this.issueTitle().length > 0 && this.view.hasDevice) {
      Column({ space: 8 }) {
        Text(this.issueTitle()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.warning())
        Button('处理设置').fontSize(14).fontColor(this.warning()).backgroundColor(this.warningSurface())
          .constraintSize({ minHeight: 44 }).enabled(!this.busy()).onClick(() => { this.recover(); })
      }.padding(16).width('100%').borderRadius(14).backgroundColor(this.warningSurface()).alignItems(HorizontalAlign.Start)
    }
    Column({ space: 8 }) {
      this.entry('管理系统通知授权', this.permissionText(), AppCommand.AUTHORIZE)
      Text(this.view.permissionKnown && this.view.permission ? '已允许 ' + this.view.sourceCount + ' 个应用来源' :
        '在系统授权页选择要转发的应用').fontSize(12).fontColor(this.muted()).padding({ left: 16 })
    }.width('100%')
    Button('发送测试通知').fontSize(16).fontColor(this.accent()).backgroundColor(this.soft())
      .width('100%').constraintSize({ minHeight: 52 }).borderRadius(12).enabled(this.readyToTest())
      .onClick(() => { this.sendTest(); })
    this.testResult()
    this.entry('问题排查', '', AppCommand.DIAGNOSTICS)
  }
  @Builder
  private testResult() {
    if (this.view.testState !== 'idle') {
      Column({ space: 12 }) {
        Text(this.view.testState === 'running' ? '正在发送测试通知…' :
          this.view.testState === 'awaiting' ? this.view.testKind === 'vibration' ? '请确认手表是否震动' : '请查看手表通知中心' :
          this.view.testState === 'confirmed' ? '已记录本次测试确认' :
          this.view.testState === 'notVisible' ? '本次测试未显示或未执行' :
          this.view.testState === 'cancelled' ? '测试已取消' : '测试未完成')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink())
        if (this.view.confirmationRequired && !this.busy()) {
          this.note(this.view.testKind === 'vibration' ? '手表是否短震两次？' : '是否看到了“腕间通知测试”？')
          Row({ space: 12 }) {
            Button(this.view.testKind === 'vibration' ? '震动了' : '看到了').fontColor(this.onAccent()).backgroundColor(this.accent()).layoutWeight(1)
              .constraintSize({ minHeight: 48 }).onClick(() => { this.send(AppCommand.CONFIRM_VISIBLE); })
            Button(this.view.testKind === 'vibration' ? '没有震动' : '没看到').fontColor(this.ink()).backgroundColor(this.alt()).layoutWeight(1)
              .constraintSize({ minHeight: 48 }).onClick(() => { this.send(AppCommand.CONFIRM_NOT_VISIBLE); })
          }.width('100%')
        }
        if (this.view.testPausedRelay && !this.view.relayEnabled) {
          this.note('通知转发暂时关闭，请完成测试后继续转发。')
          this.action('继续通知转发', AppCommand.START_RELAY, true, !this.busy())
        }
      }.padding(16).width('100%').backgroundColor(this.surface()).borderRadius(14).alignItems(HorizontalAlign.Start)
    }
  }
  @Builder
  private device() {
    this.title('手表与认证', '已有设置会保留，无需重复初始化。')
    Column({ space: 4 }) {
      this.row('当前手表', this.deviceName())
      this.row('认证材料', this.view.material ? '已保存' : '待导入')
      this.entry('重新选择手表', '', AppCommand.CHANGE_DEVICE)
      this.entry('管理认证材料', this.view.material ? '已保存' : '待导入', AppCommand.MATERIAL)
    }.width('100%').padding(12).backgroundColor(this.surface()).borderRadius(16)
    this.entry('检查当前状态', '', AppCommand.REFRESH)
    this.entry('问题排查', '', AppCommand.DIAGNOSTICS)
    Column({ space: 12 }) {
      Text('高级管理').fontSize(16).fontColor(this.ink())
      Button('停止系统订阅').fontColor(this.muted()).backgroundColor(this.alt()).width('100%')
        .constraintSize({ minHeight: 48 }).enabled(!this.busy()).onClick(() => {
          this.confirm('停止系统订阅？', '会停止转发并取消订阅。再次接收通知需要重新开启，认证材料保留。', AppCommand.UNSUBSCRIBE);
        })
      Button('删除认证材料').fontColor(this.danger()).backgroundColor(this.alt()).width('100%')
        .constraintSize({ minHeight: 48 }).enabled(!this.busy() && this.view.material).onClick(() => {
          this.confirm('删除认证材料？', '会先停止转发，再删除本应用的认证材料。之后需重新导入。', AppCommand.DELETE_CREDENTIAL);
        })
    }.width('100%').padding(16).backgroundColor(this.surface()).borderRadius(16).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private diagnostics() {
    Column({ space: 12 }) {
      Text('先检查这些设置').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('手机蓝牙已开启，手表在附近；系统已允许需要转发的应用。')
      this.entry('打开系统通知授权', this.permissionText(), AppCommand.AUTHORIZE)
      Button('发送测试通知').fontColor(this.onAccent()).backgroundColor(this.accent()).width('100%')
        .constraintSize({ minHeight: 48 }).enabled(this.readyToTest()).onClick(() => { this.sendTest(); })
    }.width('100%').padding(16).backgroundColor(this.surface()).borderRadius(16).alignItems(HorizontalAlign.Start)
    this.testResult()
    Column({ space: 12 }) {
      Text('进阶检查').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.ink())
      if (this.view.relayEnabled || this.view.sessionBusy) {
        this.note('进阶检查需要先停止转发。普通测试可在上方直接发送。')
        this.action('停止通知转发', AppCommand.STOP_RELAY, false, !this.busy())
      }
      this.action('检查消息通道', AppCommand.CHECK_CHANNEL, false,
        !this.view.relayEnabled && !this.view.sessionBusy && this.readyToTest())
      this.action('测试手表震动', AppCommand.TEST_VIBRATION, false,
        !this.view.relayEnabled && !this.view.sessionBusy && this.readyToTest())
      Button('开启手表通知类别并测试').fontColor(this.accent()).backgroundColor(this.alt()).width('100%')
        .constraintSize({ minHeight: 48 }).enabled(!this.view.relayEnabled && !this.view.sessionBusy && this.readyToTest())
        .onClick(() => { this.confirm('修改手表通知设置？', '开启手表通知总开关与“其他应用”类别，保留其余类别。', AppCommand.ENABLE_CATEGORIES); })
      Text(this.view.diagnosticResult).fontSize(13).fontColor(this.muted()).lineHeight(21)
    }.width('100%').padding(16).backgroundColor(this.surface()).borderRadius(16).alignItems(HorizontalAlign.Start)
    Column({ space: 8 }) {
      Text('累计记录').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.row('手机通知回调', this.view.received.toString())
      this.row('手表传输收包', this.view.acknowledged.toString())
      this.row('失败 / 跳过', this.view.failed + ' / ' + this.view.dropped)
      this.note('收包记录不能代替手表上的实际显示结果。')
      this.row('最近错误码', this.view.lastCode.toString())
      Text('最近转发图标：' + this.view.iconStatus + ' · ' + this.view.iconReason).fontSize(13).fontColor(this.muted())
      Text('本次测试图标：' + this.view.diagnosticIconStatus + ' · ' + this.view.diagnosticIconReason).fontSize(13).fontColor(this.muted())
    }.width('100%').padding(16).backgroundColor(this.surface()).borderRadius(16).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private setup() {
    this.note('选择手表 → 导入认证 → 允许通知 → 完成')
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

        }
      } else if (this.view.step === 2) {
        Text('准备手表认证材料').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note(this.view.material ? '已有材料；重新导入取消或失败时，原材料保留。' : '从手机日志导入是当前推荐路线。')
        Text('在小米运动健康“我的 → 关于”连续点橙色图标导出日志，再保存到手机文件管理。')
          .fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
        this.note('文件须小于 64 MB，单份日志小于 16 MB。只确认本人的设备记录。')
        this.action('从手机日志导入', AppCommand.IMPORT, true, !this.busy())
        this.action('尝试小米账号同步', AppCommand.ACCOUNT_LOGIN, false, !this.busy())
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
        this.note('在系统页面选择需要转发的应用，返回后自动更新状态。')
        this.row('通知授权', this.permissionText())
        Button('打开系统通知授权').fontSize(this.fp(15)).fontColor(this.onAccent()).backgroundColor(this.accent())
          .width('100%').constraintSize({ minHeight: 48 }).enabled(!this.busy() && this.view.notificationMode)
          .onClick(() => { this.authorize(); })
        this.action('继续', AppCommand.NEXT_STEP, true, this.view.permissionKnown && this.view.permissionKnown && this.view.permission && !this.busy())
        this.action('上一步', AppCommand.PREVIOUS_STEP, false, !this.busy())
      } else {
        Text('准备好，按你的节奏开启。').fontSize(this.fp(20)).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note('设备、材料与系统授权已准备。初始化完成不会自动开启转发。')
        Text(this.relayTitle()).fontSize(this.fp(16)).fontColor(this.accent())
        this.action('开启通知转发', AppCommand.START_RELAY, true, !this.busy())
        this.action('完成', AppCommand.HOME, false, true)
        this.action('返回授权设置', AppCommand.PREVIOUS_STEP, false, true)
      }
    }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private accountLogin() {
    Column({ space: 12 }) {
      Text('登录小米账号').fontSize(this.fp(23)).fontWeight(FontWeight.Bold).fontColor(this.ink())
      Text(this.view.loginNotice).fontSize(this.fp(14)).fontColor(this.muted()).lineHeight(this.fp(22))
      Row({ space: 12 }) {
        Button('返回设置').fontColor(this.ink()).backgroundColor(this.alt())
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
        Row({ space: 12 }) {
          if (this.view.route !== 'home' && this.view.route !== 'notifications') {
            Button('返回').fontSize(14).fontColor(this.accent()).backgroundColor(this.surface())
              .constraintSize({ minHeight: 48 }).onClick(() => { this.onBackPress(); })
          }
          Text(this.pageTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1)
          if (this.view.route === 'home' || this.view.route === 'notifications') {
            Button('设置').fontSize(14).fontColor(this.accent()).backgroundColor(this.surface())
              .constraintSize({ minHeight: 48 }).enabled(!this.busy()).onClick(() => { this.send(AppCommand.DEVICE); })
          }
        }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 }).backgroundColor(this.surface())
        Scroll(this.pageScroller) {
          Column({ space: 16 }) {
            if (this.view.route === 'home' || this.view.route === 'notifications') { this.home() }
            else if (this.view.route === 'device') { this.device() }
            else if (this.view.route === 'setup') { this.setup() }
            else { this.diagnostics() }
            if (this.view.notice.length > 0 && this.view.testState !== 'running') {
              Text(this.view.notice).fontSize(13).fontColor(this.view.noticeFailed ? this.danger() : this.muted())
                .lineHeight(21).padding(12).width('100%').backgroundColor(this.alt()).borderRadius(12)
                .accessibilityText(this.view.notice)
            }
            if (this.busy() && this.view.testState !== 'running') {
              Text('正在处理…').fontSize(13).fontColor(this.accent()).accessibilityText('正在处理')
            }
          }.width('100%').constraintSize({ maxWidth: 600 }).padding(16).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(this.pageColor())
    }
  }
}
