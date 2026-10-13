import { AppCommand, AppState, DeviceCandidateView, CredentialCandidateView } from '../core/AppState';
import { AppViewModel } from '../platform/AppViewModel';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { FITNESS_LOGIN_URL, xiaomiLoginUrlAllowed } from '../core/MiFitnessCloud';
import { MI_LOGIN_USER_AGENT } from '../platform/MiFitnessAccount';
import { AVVolumePanel } from '@kit.AudioKit';

@Entry
@Component
struct Index {
  @State private view: AppState = new AppState();
  @State private advanced: boolean = false;
  @State private diagnosticDetails: boolean = false;
  @State private transportDetails: boolean = false;
  @State private musicDetails: boolean = false;
  @State private pausedRelayForCheck: boolean = false;
  @State private pausedMusicForCheck: boolean = false;
  private model: AppViewModel | undefined = undefined;
  private loginController: webview.WebviewController = new webview.WebviewController();
  private pageScroller: Scroller = new Scroller();
  private diagnosticAfterStop: AppCommand | undefined = undefined;
  private stopObserved: boolean = false;
  private diagnosticOrigin: string = 'home';

  aboutToAppear(): void {
    this.model = new AppViewModel(this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.loginController, (state: AppState) => {
        const resetScroll = state.route !== this.view.route || state.step !== this.view.step;
        const relayResumed = state.relayEnabled && !this.view.relayEnabled;
        const musicResumed = state.musicEnabled && !this.view.musicEnabled;
        if (state.route !== this.view.route) this.advanced = false;
        this.view = state;
        if (relayResumed) this.pausedRelayForCheck = false;
        if (musicResumed) this.pausedMusicForCheck = false;
        if (resetScroll && !state.loginVisible) this.scrollTop();
        // Only a completed real stop receipt may trigger the follow-up diagnostic.
        if (this.diagnosticAfterStop !== undefined) {
          if (state.pendingKind === 'stop') this.stopObserved = true;
          if (this.stopObserved && state.pendingKind.length === 0) {
            const command = this.diagnosticAfterStop;
            this.diagnosticAfterStop = undefined; this.stopObserved = false;
            if (!state.noticeFailed && !state.relayEnabled && !state.musicEnabled && !state.sessionBusy) this.model?.dispatch(command);
          }
        }
      });
    this.model.initialize();
  }
  aboutToDisappear(): void { this.diagnosticAfterStop = undefined; this.model?.dispose(); this.model = undefined; }
  private scrollTop(): void { try { this.pageScroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_) { } }
  private primaryRoute(): boolean {
    return !this.advanced && (this.view.route === 'home' || this.view.route === 'notifications' || this.view.route === 'music' || this.view.route === 'device');
  }
  onBackPress(): boolean {
    this.diagnosticAfterStop = undefined; this.stopObserved = false;
    if (this.view.loginVisible) { this.send(AppCommand.CLOSE_LOGIN); return true; }
    if (this.advanced) { this.advanced = false; this.scrollTop(); return true; }
    if (this.view.route === 'home' || this.view.route === 'notifications') return false;
    if (this.view.route === 'setup') this.send(AppCommand.EXIT_SETUP);
    else if (this.view.route === 'diagnostics') this.send(this.diagnosticOrigin === 'device' ? AppCommand.DEVICE : AppCommand.HOME);
    else this.send(AppCommand.HOME);
    return true;
  }
  private send(command: AppCommand, reference: number = -1): void {
    if (command === AppCommand.HOME || command === AppCommand.DEVICE || command === AppCommand.MUSIC || command === AppCommand.EXIT_SETUP ||
      command === AppCommand.SETUP || command === AppCommand.MATERIAL || command === AppCommand.CLOSE_LOGIN) {
      this.diagnosticAfterStop = undefined; this.stopObserved = false; this.advanced = false;
    }
    if (command === AppCommand.DIAGNOSTICS) this.diagnosticOrigin = this.view.route;
    this.model?.dispatch(command, reference);
  }
  private pageColor(): ResourceColor { return $r('app.color.wrist_page'); }
  private surface(): ResourceColor { return $r('app.color.wrist_surface'); }
  private ink(): ResourceColor { return $r('app.color.wrist_text'); }
  private muted(): ResourceColor { return $r('app.color.wrist_muted'); }
  private accent(): ResourceColor { return $r('app.color.wrist_action'); }
  private onAccent(): ResourceColor { return $r('app.color.wrist_on_action'); }
  private soft(): ResourceColor { return $r('app.color.wrist_action_surface'); }
  private warning(): ResourceColor { return $r('app.color.wrist_warning'); }
  private warningSurface(): ResourceColor { return $r('app.color.wrist_warning_surface'); }
  private danger(): ResourceColor { return $r('app.color.wrist_danger'); }
  private dividerColor(): ResourceColor { return $r('app.color.wrist_divider'); }
  private busy(): boolean { return this.view.pendingKind.length > 0 || this.diagnosticAfterStop !== undefined; }
  private deviceName(): string { return this.view.hasDevice ? this.view.deviceName : '尚未选择手表'; }
  private permissionText(): string { return !this.view.permissionKnown ? '尚未确认' : this.view.permission ? '已允许' : '待恢复'; }
  private sourceText(): string { return this.view.permissionKnown && this.view.permission ? this.view.sourceCount + ' 个获准应用 · 由系统管理' : '在系统授权页选择要转发的应用'; }
  private readyToTest(): boolean { return this.view.hasDevice && this.view.supported && this.view.material && !this.busy(); }
  private relayReady(): boolean {
    return this.view.notificationMode && this.view.hasDevice && this.view.supported && this.view.material && this.view.permissionKnown && this.view.permission;
  }
  private relayTitle(): string {
    if (this.view.pendingKind === 'start') return '正在开启转发';
    if (this.view.pendingKind === 'stop') return '正在停止转发';
    if (!this.view.notificationMode) return '通知功能不可用';
    if (!this.view.supported) return '手表暂未适配';
    if (!this.view.material) return '还差一步';
    if (!this.view.permissionKnown) return '授权待确认';
    if (!this.view.permission) return '需要恢复授权';
    return this.view.relayEnabled ? '转发已开启' : '转发已关闭';
  }
  private relayDescription(): string {
    if (!this.view.notificationMode) return '当前是基础安装包';
    if (!this.view.supported) return '当前消息协议适配 Redmi Watch 5';
    if (!this.view.material) return '先准备手表认证材料';
    if (!this.view.permissionKnown) return '查询未完成，请检查系统授权';
    if (!this.view.permission) return this.view.relayEnabled ? '转发设置已开启，权限阻断' : '重新允许需要转发的应用';
    if (this.view.sourceCount === 0) return '系统允许，但尚无获准应用来源';
    return this.view.relayEnabled ? '等待获准应用的新通知' : '开启后转发获准应用的新通知';
  }
  private channelText(): string {
    if (this.view.connection === 'connecting') return '消息通道正在连接';
    if (this.view.connection === 'authenticating') return '消息通道正在认证';
    if (this.view.connection === 'disconnected') return '最近消息通道连接失败';
    if (this.view.musicEnabled) return this.view.musicStage === 'ready' ? '通知与音乐共用认证连接' : '音乐连接状态请到音乐页查看';
    if (this.view.sessionBusy) return '当前消息会话尚未释放';
    return this.view.relayEnabled ? '新通知到来时连接手表' : '系统授权与认证材料会保留';
  }
  private issueTitle(): string {
    if (!this.view.notificationMode) return '需要通知模式安装包';
    if (!this.view.supported) return '这台手表暂未适配';
    if (!this.view.material) return '认证材料尚未准备';
    if (!this.view.permissionKnown) return '系统通知授权待确认';
    if (!this.view.permission) return '系统通知权限已撤销';
    if (this.view.connection === 'disconnected') return '最近连接未完成';
    if (this.view.sourceCount === 0) return '还没有选择应用来源';
    return '';
  }
  private issueDescription(): string {
    if (!this.view.notificationMode) return '安装包含通知能力的版本，再允许系统通知。';
    if (!this.view.supported) return '设备识别与消息协议适配是两项独立能力。';
    if (!this.view.material) return '从手机日志导入，确认并保存对应手表记录。';
    if (!this.view.permissionKnown) return '查询失败不代表权限被撤销。请刷新或打开系统授权。';
    if (!this.view.permission) return '重新允许需要转发的应用；转发仍可手动停止。';
    if (this.view.connection === 'disconnected') return '检查蓝牙与手表距离。失败通知不会自动重发。';
    return '系统已允许通知，但没有获准应用。请选择需要转发的来源。';
  }
  private recover(): void {
    if (!this.view.notificationMode || this.view.connection === 'disconnected') this.send(AppCommand.DIAGNOSTICS);
    else if (this.view.hasDevice && !this.view.supported) this.handle(AppCommand.CHANGE_DEVICE);
    else if (this.view.hasDevice && this.view.material && this.view.supported && (!this.view.permissionKnown || !this.view.permission || this.view.sourceCount === 0)) this.authorize();
    else this.send(AppCommand.SETUP);
  }
  private confirm(title: string, message: string, command: AppCommand): void {
    this.getUIContext().showAlertDialog({ title: title, message: message,
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '确认', action: () => { this.send(command); } } });
  }
  private authorize(): void { if (!this.view.hasDevice) this.send(AppCommand.SETUP); else this.send(AppCommand.AUTHORIZE); }
  private toggleRelay(): void {
    if (this.view.relayEnabled) {
      if (this.view.musicEnabled) this.confirm('同时关闭音乐控制？', '通知与音乐共用认证连接。停止通知转发会同时关闭音乐控制，之后需单独开启。', AppCommand.STOP_RELAY);
      else this.send(AppCommand.STOP_RELAY);
    } else if (!this.relayReady()) this.recover(); else this.send(AppCommand.START_RELAY);
  }
  private sendTest(): void {
    if (this.view.relayEnabled || this.view.musicEnabled || this.view.sessionBusy) {
      this.getUIContext().showAlertDialog({ title: '暂停连接，再测试？', message: '通知转发和音乐控制会暂停。测试结束后需要分别手动开启。',
        primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '暂停并测试', action: () => {
          this.pausedMusicForCheck = this.view.musicEnabled;
          this.send(AppCommand.QUICK_TEST);
        } } });
    } else this.send(AppCommand.QUICK_TEST);
  }
  private requestDiagnostic(command: AppCommand): void {
    const modifies = command === AppCommand.ENABLE_CATEGORIES;
    if (this.view.relayEnabled || this.view.musicEnabled || this.view.sessionBusy) {
      this.getUIContext().showAlertDialog({ title: modifies ? '暂停连接并修改通知设置？' : '暂停连接，再检查？',
        message: (modifies ? '开启手表通知总开关和“其他应用”类别，保留其余类别。' : '') + '通知与音乐将暂停，检查结束后需分别手动开启。会等待当前会话实际释放。',
        primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '暂停并检查', action: () => {
          this.pausedRelayForCheck = this.view.relayEnabled;
          this.pausedMusicForCheck = this.view.musicEnabled;
          this.diagnosticAfterStop = command; this.stopObserved = false; this.model?.dispatch(AppCommand.STOP_RELAY);
        } } });
    } else if (modifies) this.confirm('修改手表通知设置？', '开启手表通知总开关和“其他应用”类别，保留其余类别。', command);
    else this.send(command);
  }
  private handle(command: AppCommand): void {
    if (command === AppCommand.AUTHORIZE) this.authorize();
    else if (command === AppCommand.CHANGE_DEVICE) this.confirm('重新选择手表？', '先停止通知与音乐连接，保留手机配对关系和已保存材料。更换目标后仍需检查材料是否匹配。', command);
    else if (command === AppCommand.DELETE_CREDENTIAL) this.confirm('删除本机认证材料？', '先停止通知与音乐，再删除本应用的认证材料。之后需重新导入，不会解绑或重置手表。', command);
    else if (command === AppCommand.UNSUBSCRIBE) this.confirm('停止系统订阅？', '停止通知与音乐，并取消系统订阅。认证材料与系统授权保留。', command);
    else if (command === AppCommand.QUICK_TEST) this.sendTest();
    else if (command === AppCommand.CHECK_CHANNEL || command === AppCommand.TEST_VIBRATION || command === AppCommand.ENABLE_CATEGORIES) this.requestDiagnostic(command);
    else this.send(command);
  }
  private musicStatus(): string {
    if (this.view.pendingKind === 'music-start') return '正在连接手表';
    if (this.view.pendingKind === 'music-stop') return '正在关闭音乐控制';
    if (!this.view.musicEnabled) return this.view.musicStage === 'permission_required' ? '需要重新授权' : '音乐控制已关闭';
    if (this.view.musicStage === 'ready') return '音乐控制已开启';
    if (this.view.musicStage === 'connecting') return '正在连接手表';
    if (this.view.musicStage === 'retry') return '连接中断，正在重连';
    return '连接状态待确认';
  }
  private musicError(): string {
    const code = this.view.musicCommandCode;
    return code === -66 ? '系统不允许后台调音量，请让腕间通知保持手机前台。' : code === -67 ? '系统音量没有变化，本次未计为成功。请保持应用前台再试。' :
      code === 201 ? '最近控制未获系统许可。' : '最近控制未完成（' + code + '），请确认播放器已开始播放并支持该操作。';
  }

  @Builder private glyph(resource: Resource, size: number, color: ResourceColor) {
    SymbolGlyph(resource).fontSize(size).fontColor([color]).accessibilityLevel('no')
  }
  @Builder private mark(resource: Resource) {
    Row() { this.glyph(resource, 22, this.accent()) }.width(46).height(46).justifyContent(FlexAlign.Center).backgroundColor(this.soft()).borderRadius(16)
  }
  @Builder private lead(kicker: string, heading: string, subtitle: string) {
    Column({ space: 9 }) {
      if (kicker.length > 0) Text(kicker).fontSize(12).fontColor(this.muted()).lineHeight(20)
      Text(heading).fontSize(34).fontWeight(FontWeight.Bold).fontColor(this.ink()).lineHeight(44).accessibilityText(heading.replace('\n', ''))
      if (subtitle.length > 0) Text(subtitle).fontSize(13).fontColor(this.muted()).lineHeight(22)
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 24 })
  }
  @Builder private note(text: string) { Text(text).fontSize(12).fontColor(this.muted()).lineHeight(21).width('100%') }
  @Builder private sectionLabel(text: string) { Text(text).fontSize(12).fontColor(this.muted()).lineHeight(20).width('100%').margin({ top: 12, bottom: 2 }) }
  @Builder private deviceCaption() {
    Row({ space: 9 }) { this.glyph($r('sys.symbol.watch'), 18, this.muted()); Text(this.deviceName()).fontSize(13).fontColor(this.muted()).layoutWeight(1) }
      .width('100%').margin({ bottom: 10 })
  }
  @Builder private action(label: string, command: AppCommand, primary: boolean, enabled: boolean, symbol: Resource) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 9 }) {
        this.glyph(symbol, 18, primary ? this.onAccent() : this.accent())
        Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(primary ? this.onAccent() : this.accent()).lineHeight(22)
      }.justifyContent(FlexAlign.Center).width('100%').padding({ top: 14, bottom: 14, left: 16, right: 16 })
    }.width('100%').constraintSize({ minHeight: 50 }).borderRadius(15).backgroundColor(primary ? this.accent() : this.soft()).enabled(enabled)
      .onClick(() => { this.handle(command); }).accessibilityText(label)
  }
  @Builder private textAction(label: string, command: AppCommand) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 6 }) { Text(label).fontSize(13).fontColor(this.accent()).lineHeight(21); this.glyph($r('sys.symbol.arrow_up_right'), 14, this.accent()) }
        .justifyContent(FlexAlign.Center).padding(10)
    }.width('100%').constraintSize({ minHeight: 44 }).backgroundColor(Color.Transparent).enabled(!this.busy())
      .onClick(() => { this.handle(command); }).accessibilityText(label)
  }
  @Builder private entry(label: string, description: string, command: AppCommand, symbol: Resource, enabled: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        this.glyph(symbol, 19, this.muted())
        Column({ space: 3 }) {
          Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(23)
          if (description.length > 0) Text(description).fontSize(12).fontColor(this.muted()).lineHeight(20)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.glyph($r('sys.symbol.chevron_right'), 14, this.muted())
      }.width('100%').padding({ top: 16, bottom: 16, left: 16, right: 16 })
    }.width('100%').constraintSize({ minHeight: 70 }).borderRadius(16).backgroundColor(this.surface()).enabled(!this.busy() && enabled)
      .onClick(() => { this.handle(command); }).accessibilityText(label + '，' + description)
  }
  @Builder private metric(label: string, value: string) {
    Row({ space: 14 }) {
      Text(label).fontSize(12).fontColor(this.muted()).lineHeight(20).layoutWeight(1)
      Text(value).fontSize(12).fontColor(this.ink()).lineHeight(20).textAlign(TextAlign.End).layoutWeight(1.2)
    }.width('100%').padding({ top: 11, bottom: 11 })
    Divider().color(this.dividerColor()).strokeWidth(0.5)
  }
  @Builder private fold(label: string, expanded: boolean, kind: number) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Text(label).fontSize(13).fontColor(this.muted()).layoutWeight(1).textAlign(TextAlign.Start)
        this.glyph(expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'), 14, this.muted())
      }.padding({ top: 15, bottom: 15 }).width('100%')
    }.width('100%').constraintSize({ minHeight: 48 }).backgroundColor(Color.Transparent).onClick(() => {
      if (kind === 0) this.diagnosticDetails = !this.diagnosticDetails;
      else if (kind === 1) this.transportDetails = !this.transportDetails;
      else this.musicDetails = !this.musicDetails;
    }).accessibilityText(label + (expanded ? '，已展开，点按收起' : '，已收起，点按展开'))
  }
  @Builder private instruction(number: string, heading: string, description: string) {
    Row({ space: 14 }) {
      Text(number).fontSize(13).fontColor(this.accent()).width(22).margin({ top: 2 })
      Column({ space: 5 }) {
        Text(heading).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(22)
        Text(description).fontSize(12).fontColor(this.muted()).lineHeight(21)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.alignItems(VerticalAlign.Top).width('100%').padding({ top: 16, bottom: 16 })
    Divider().color(this.dividerColor()).strokeWidth(0.5)
  }

  @Builder private home() {
    if (!this.view.hasDevice) {
      this.lead('腕间通知', '从手表开始。', '把手机通知，带到你的腕间。')
      Column({ space: 15 }) {
        this.mark($r('sys.symbol.watch'))
        Text('设置你的 Redmi Watch 5').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink())
        this.note('选择已配对手表，准备认证材料，再允许需要转发的应用。')
        this.action('开始设置', AppCommand.SETUP, true, !this.busy(), $r('sys.symbol.arrow_right'))
      }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
      this.sectionLabel('完成后可以使用')
      this.entry('通知转发', '来自系统授权的应用', AppCommand.SETUP, $r('sys.symbol.bell'))
      this.entry('手机音乐控制', '用手表控制手机播放', AppCommand.MUSIC, $r('sys.symbol.music'))
      this.note('已有手机与手表绑定会保留，无需解绑或重置。')
    } else {
      this.lead('', '让通知，\n抵达腕间。', '')
      this.deviceCaption()
      Column({ space: 20 }) {
        Row({ space: 14 }) {
          this.mark($r('sys.symbol.bell'))
          Column({ space: 5 }) {
            Text(this.relayTitle()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
            Text(this.relayDescription()).fontSize(12).fontColor(this.muted()).lineHeight(20)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          // Confirmed-state command button: cancel/failure cannot leave a falsely enabled switch.
          Button({ type: ButtonType.Normal }) {
            Row() {
              if (this.view.relayEnabled) Blank()
              Circle().width(22).height(22).fill(this.view.relayEnabled ? this.onAccent() : this.surface())
              if (!this.view.relayEnabled) Blank()
            }.width(50).height(30).padding(4).borderRadius(20).backgroundColor(this.view.relayEnabled ? this.accent() : this.dividerColor())
          }.width(54).constraintSize({ minHeight: 46 }).backgroundColor(Color.Transparent)
            .enabled(this.view.relayEnabled ? this.view.pendingKind !== 'stop' : !this.busy()).onClick(() => { this.toggleRelay(); })
            .accessibilityText(this.view.relayEnabled ? '通知转发已开启，点按停止' : '通知转发已关闭，点按开启或完成设置')
        }.width('100%')
        Divider().color(this.dividerColor()).strokeWidth(0.5)
        Row({ space: 8 }) {
          Circle().width(6).height(6).fill(!this.relayReady() ? this.warning() : this.view.relayEnabled ? $r('app.color.wrist_success') : this.muted())
          Text(this.channelText()).fontSize(12).fontColor(this.muted()).lineHeight(20).layoutWeight(1)
        }.width('100%')
      }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24)
      if (this.issueTitle().length > 0) {
        Column({ space: 7 }) {
          Text(this.issueTitle()).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.warning()).lineHeight(22)
          Text(this.issueDescription()).fontSize(12).fontColor(this.warning()).lineHeight(21)
          Button('处理设置').fontSize(13).fontColor(this.warning()).backgroundColor(Color.Transparent).constraintSize({ minHeight: 44 })
            .padding({ left: 0, right: 12 }).enabled(!this.busy()).onClick(() => { this.recover(); })
        }.width('100%').padding(17).backgroundColor(this.warningSurface()).borderRadius(17).alignItems(HorizontalAlign.Start)
      }
      this.sectionLabel('通知来源')
      this.entry('管理应用授权', this.sourceText(), AppCommand.AUTHORIZE, $r('sys.symbol.square_grid_2x2'), this.view.notificationMode)
      this.action('发送测试通知', AppCommand.QUICK_TEST, false, this.readyToTest(), $r('sys.symbol.paperplane'))
      this.textAction('转发遇到问题？', AppCommand.DIAGNOSTICS)
      this.testResult()
    }
  }
  @Builder private testResult() {
    if (this.view.testState !== 'idle') {
      Column({ space: 14 }) {
        this.mark(this.view.testState === 'confirmed' ? $r('sys.symbol.checkmark') : $r('sys.symbol.bell'))
        Text(this.view.testState === 'running' ? '正在发送测试…' : this.view.testState === 'awaiting' ?
          this.view.testKind === 'vibration' ? '手表震动了吗？' : '手表上看到了吗？' : this.view.testState === 'confirmed' ? '已记录你的确认' :
          this.view.testState === 'notVisible' ? '本次测试未显示或未执行' : this.view.testState === 'cancelled' ? '测试已取消' : '测试未完成')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
        if (this.view.confirmationRequired && !this.busy()) {
          this.note(this.view.testKind === 'vibration' ? '请确认手表是否短震两次。' : '打开手表通知中心，查看“腕间通知测试”。')
          this.action(this.view.testKind === 'vibration' ? '震动了' : '看到了', AppCommand.CONFIRM_VISIBLE, true, true, $r('sys.symbol.checkmark'))
          this.action(this.view.testKind === 'vibration' ? '没震动' : '没看到', AppCommand.CONFIRM_NOT_VISIBLE, false, true, $r('sys.symbol.questionmark_circle'))
        } else if (this.view.testState === 'confirmed') this.note('仅记录本次人工反馈，历史收包不能代表当前在线。')
        else if (this.view.testState === 'notVisible') this.note('可以继续检查系统授权、距离和手表通知设置。')
        this.resumeActions()
      }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    }
  }
  @Builder private resumeActions() {
    if ((this.view.testPausedRelay || this.pausedRelayForCheck) && !this.view.relayEnabled) {
      this.action('继续通知转发', AppCommand.START_RELAY, true, !this.busy() && !this.view.sessionBusy, $r('sys.symbol.arrow_right'))
    }
    if (this.pausedMusicForCheck && !this.view.musicEnabled) this.textAction('音乐控制已暂停 · 前往重新开启', AppCommand.MUSIC)
  }
  @Builder private device() {
    this.lead('设置', '你的手表。', '让连接与权限各就其位。')
    Column({ space: 14 }) {
      this.mark($r('sys.symbol.watch'))
      Text(this.deviceName()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
      this.note(this.view.hasDevice ? '当前目标手表' : '从手机已配对的设备中选择')
      this.action(this.view.hasDevice ? '更换手表' : '选择手表', this.view.hasDevice ? AppCommand.CHANGE_DEVICE : AppCommand.SETUP,
        false, !this.busy(), $r('sys.symbol.watch'))
    }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    this.sectionLabel('连接设置')
    Column() {
      this.entry('认证材料', this.view.material ? '已保存在本机' : '待导入', AppCommand.MATERIAL, $r('sys.symbol.key'))
      Divider().color(this.dividerColor()).strokeWidth(0.5).width('90%')
      this.entry('系统通知授权', this.permissionText(), AppCommand.AUTHORIZE, $r('sys.symbol.checkmark_circle'), this.view.notificationMode)
      Divider().color(this.dividerColor()).strokeWidth(0.5).width('90%')
      this.entry('检查当前状态', '重新读取设备与权限状态', AppCommand.REFRESH, $r('sys.symbol.arrow_clockwise'))
    }.width('100%').backgroundColor(this.surface()).borderRadius(24)
    this.sectionLabel('帮助与管理')
    this.entry('问题排查', '测试通知与消息通道', AppCommand.DIAGNOSTICS, $r('sys.symbol.questionmark_circle'))
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        this.glyph($r('sys.symbol.gearshape'), 19, this.muted())
        Column({ space: 3 }) { Text('高级管理').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink()); Text('停止订阅与删除认证材料').fontSize(12).fontColor(this.muted()).lineHeight(20) }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.glyph($r('sys.symbol.chevron_right'), 14, this.muted())
      }.padding(16).width('100%')
    }.width('100%').constraintSize({ minHeight: 70 }).borderRadius(16).backgroundColor(this.surface()).enabled(!this.busy())
      .onClick(() => { this.advanced = true; this.scrollTop(); }).accessibilityText('高级管理，停止订阅与删除认证材料')
    this.note('认证材料仅保存在本机安全存储。更换手表不会解绑已有设备。')
  }
  @Builder private advancedPage() {
    this.lead('设置', '高级管理', '仅在需要时调整。')
    Column({ space: 14 }) {
      Text('停止系统订阅').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('停止通知与音乐连接，并取消系统订阅。认证材料和系统授权保留。')
      this.action('停止系统订阅', AppCommand.UNSUBSCRIBE, false, !this.busy(), $r('sys.symbol.bell_slash'))
    }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('删除认证材料').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink())
      this.note('只删除本应用保存的材料。之后需要重新导入，不会解绑或重置手表。')
      Button('删除本机认证材料').fontSize(14).fontColor(this.danger()).backgroundColor(this.warningSurface()).width('100%')
        .constraintSize({ minHeight: 50 }).borderRadius(15).enabled(!this.busy() && this.view.material).onClick(() => { this.handle(AppCommand.DELETE_CREDENTIAL); })
    }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
  }
  @Builder private music() {
    this.lead('手机音乐控制', '抬腕，\n掌控播放。', '播放与切歌在手机执行，手表负责遥控。')
    this.deviceCaption()
    Column({ space: 16 }) {
      this.mark($r('sys.symbol.music'))
      Text(this.musicStatus()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
      this.note(this.view.musicEnabled ? '保持认证连接，通知可共用。' : '先在手机音乐或视频应用开始播放。')
      this.action(this.view.pendingKind === 'music-start' ? '取消连接' : this.view.musicEnabled ? '关闭音乐控制' : this.view.musicAvailable ? '开启音乐控制' : '当前安装包不支持',
        this.view.pendingKind === 'music-start' || this.view.musicEnabled ? AppCommand.STOP_MUSIC : AppCommand.START_MUSIC,
        !this.view.musicEnabled, this.view.pendingKind !== 'music-stop' && (this.view.pendingKind === 'music-start' || this.view.musicEnabled ||
          (!this.busy() && this.view.musicAvailable)), $r('sys.symbol.power'))
      if (this.view.musicEnabled && this.view.musicStage === 'unknown') this.action('重新连接', AppCommand.START_MUSIC, false, !this.busy(), $r('sys.symbol.arrow_clockwise'))
    }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
    if (!this.view.musicAvailable) {
      Column({ space: 7 }) {
        Text('需要音乐模式安装包').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.warning())
        Text('该能力依赖媒体会话 ACL 权限，不能通过用户授权弹窗补齐。通知功能仍可使用。').fontSize(12).fontColor(this.warning()).lineHeight(21)
      }.width('100%').padding(17).backgroundColor(this.warningSurface()).borderRadius(17).alignItems(HorizontalAlign.Start)
    }
    if (this.view.musicCommandCode !== 0) Text(this.musicError()).fontSize(12).fontColor(this.warning()).lineHeight(21).padding(17).width('100%').backgroundColor(this.warningSurface()).borderRadius(17)
    this.sectionLabel('怎么使用')
    Column() {
      this.instruction('01', '手机先开始播放', '播放器需支持系统媒体会话。')
      this.instruction('02', '打开手表的手机音乐页', '播放、暂停、上一首与下一首。')
      this.instruction('03', '调音量时，让本应用保持前台', '后台和锁屏下，系统不允许调整音量。')
    }.width('100%')
    this.fold('连接与控制详情', this.musicDetails, 2)
    if (this.musicDetails) {
      this.metric('连接阶段', this.view.musicStage)
      this.metric('状态同步收包', this.view.musicSynced.toString())
      this.metric('手机接受控制', this.view.musicControlled.toString())
      this.metric('最近操作耗时', this.view.musicControlMs + ' ms')
      this.metric('最近连接错误', this.view.musicCode.toString())
      this.metric('最近控制错误', this.view.musicCommandCode.toString())
      this.note('系统接受控制不等于实际播放或切歌。操作耗时不含手表按键至手机的传输时间。')
      this.note('卓易通等播放器能否开放媒体会话，需要实际检查。系统会显示蓝牙持续任务通知。')
    }
  }
  @Builder private diagnostics() {
    this.lead('问题排查', '逐步，\n找到问题。', '先发一条测试，再看手表上的实际结果。')
    if (!this.view.notificationMode) this.note('基础安装包没有启用通知订阅。安装通知或音乐模式包后，才能允许并转发系统通知。')
    this.entry('检查系统通知授权', this.permissionText(), AppCommand.AUTHORIZE, $r('sys.symbol.checkmark_circle'), this.view.notificationMode)
    this.action('发送测试通知', AppCommand.QUICK_TEST, true, this.readyToTest(), $r('sys.symbol.paperplane'))
    this.testResult()
    if (this.view.testState === 'idle') this.resumeActions()
    Divider().color(this.dividerColor()).strokeWidth(0.5).margin({ top: 10 })
    this.fold('进阶检查', this.diagnosticDetails, 0)
    if (this.diagnosticDetails) {
      this.note(this.view.relayEnabled || this.view.musicEnabled || this.view.sessionBusy ? '检查将暂停通知与音乐，等待当前会话释放。完成后需分别手动重新开启。' : '请保持手机蓝牙开启，手表在附近。')
      this.action('检查消息通道', AppCommand.CHECK_CHANNEL, false, this.readyToTest(), $r('sys.symbol.arrow_left_arrow_right'))
      this.action('测试手表震动', AppCommand.TEST_VIBRATION, false, this.readyToTest(), $r('sys.symbol.waveform'))
      this.action('开启手表通知类别并测试', AppCommand.ENABLE_CATEGORIES, false, this.readyToTest(), $r('sys.symbol.bell'))
      Text(this.view.diagnosticResult).fontSize(12).fontColor(this.muted()).lineHeight(21).width('100%')
    }
    Divider().color(this.dividerColor()).strokeWidth(0.5)
    this.fold('传输记录与图标详情', this.transportDetails, 1)
    if (this.transportDetails) {
      this.metric('手机通知回调', this.view.received.toString())
      this.metric('手表传输收包', this.view.acknowledged.toString())
      this.metric('失败 / 跳过', this.view.failed + ' / ' + this.view.dropped)
      this.metric('最近错误码', this.view.lastCode.toString())
      this.metric('系统图标读取权限', this.view.iconResourceAccess === 'granted' ? '系统已许可' : this.view.iconResourceAccess === 'denied' ? '系统未许可' : '尚未确认')
      this.metric('最近图标阶段', this.view.iconStatus)
      this.metric('最近图标原因', this.view.iconReason || '暂无')
      this.metric('本次测试图标', this.view.diagnosticIconStatus)
      this.metric('本次图标原因', this.view.diagnosticIconReason || '暂无')
      this.note('内置离线图标按已核实来源精确匹配；未覆盖来源可能保留默认图标。')
      this.note('图标分片收包和缓存状态，不能替代手表上的实际显示。累计回调不等同于独立消息或送达数量。')
    }
  }
  @Builder private setup() {
    Text('设置手表 · ' + this.view.step + ' / 4').fontSize(12).fontColor(this.muted()).lineHeight(20).width('100%')
    Row({ space: 6 }) {
      ForEach([1, 2, 3, 4], (step: number) => { Row().height(3).layoutWeight(1).backgroundColor(step <= this.view.step ? this.accent() : this.dividerColor()).borderRadius(3) }, (step: number) => step.toString())
    }.width('100%').margin({ bottom: 12 }).accessibilityText('第' + this.view.step + '步，共四步')
    if (this.view.step === 1) {
      this.lead('', '选择你的\n手表。', '只显示手机系统中已经配对的设备。')
      this.action(this.view.pendingKind === 'discover' ? '正在读取…' : '查找已配对设备', AppCommand.DISCOVER, true, !this.busy(), $r('sys.symbol.magnifyingglass'))
      if (this.view.candidatesVisible) {
        ForEach(this.view.candidates, (device: DeviceCandidateView) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 14 }) {
              this.glyph($r('sys.symbol.watch'), 22, this.accent())
              Column({ space: 5 }) {
                Text(device.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(24)
                Text((device.supported ? '消息协议已适配 · ' : '消息协议暂未适配 · ') + device.detail).fontSize(12).fontColor(this.muted()).lineHeight(20)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              this.glyph($r('sys.symbol.chevron_right'), 14, this.muted())
            }.width('100%').padding(18)
          }.width('100%').borderRadius(20).backgroundColor(this.surface()).enabled(!this.busy())
            .onClick(() => { this.send(AppCommand.SELECT_DEVICE, device.reference); })
            .accessibilityText(device.name + (device.supported ? '，消息协议已适配' : '，暂未适配，仍可识别设备'))
        }, (device: DeviceCandidateView) => device.reference.toString())
        if (this.view.candidates.length === 0) this.note('没有找到候选。请先在手机系统中完成配对，再重新查找。')
      }
      this.note('当前适配 Redmi Watch 5。无需解绑或重置已有设备。')
    } else if (this.view.step === 2) {
      this.lead('', '准备认证\n材料。', this.view.material ? '原有材料会保留，重新导入失败也不会删除。' : '从手机日志离线导入。')
      this.deviceCaption()
      Column() { this.instruction('01', '导出小米运动健康日志', '我的 → 关于，连续点橙色图标。'); this.instruction('02', '将日志保存到手机文件管理', '选择文件后，确认并保存本人的手表记录。') }.width('100%')
      this.action(this.view.pendingKind === 'import' ? '正在读取与识别…' : this.view.material ? '重新导入手机日志' : '选择手机日志', AppCommand.IMPORT, true, !this.busy(), $r('sys.symbol.doc'))
      if (this.view.importPhase === 'reading') this.action('取消导入', AppCommand.CANCEL_IMPORT, false, true, $r('sys.symbol.arrow_left'))
      else if (this.view.importPhase === 'cancelled') this.note('本次导入已取消，原有材料保留。')
      else if (this.view.importPhase === 'error') Text('日志未能读取，请重新导出符合限制的文件。').fontSize(13).fontColor(this.danger()).lineHeight(22)
      else if (this.view.importPhase === 'saved') Text('材料已保存在手机安全存储中。').fontSize(13).fontColor($r('app.color.wrist_success')).lineHeight(22)
      if (this.view.importCandidate) {
        ForEach(this.view.credentialCandidates, (candidate: CredentialCandidateView) => {
          Column({ space: 12 }) {
            Text(candidate.label).fontSize(15).fontColor(this.ink()).lineHeight(23)
            this.note('保存后，设备与材料的匹配仍由密钥认证确认。')
            Button('确认并保存此记录').fontSize(14).fontColor(this.onAccent()).backgroundColor(this.accent()).width('100%').constraintSize({ minHeight: 50 })
              .borderRadius(15).enabled(!this.busy()).onClick(() => { this.send(AppCommand.SAVE_CANDIDATE, candidate.reference); })
          }.width('100%').padding(20).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
        }, (candidate: CredentialCandidateView) => candidate.reference.toString())
        this.action('放弃本次导入', AppCommand.DISCARD_CANDIDATE, false, !this.busy(), $r('sys.symbol.arrow_left'))
      }
      if (this.view.material) this.action('使用已保存材料继续', AppCommand.NEXT_STEP, false, !this.busy(), $r('sys.symbol.arrow_right'))
      this.textAction('尝试小米账号同步', AppCommand.ACCOUNT_LOGIN)
      if (this.view.accountFailed) this.note('账号同步未完成，可以继续使用日志导入。网页登录成功不等于材料同步成功。')
      this.note('文件须小于 64 MB，单份日志小于 16 MB。仅选择本人的设备记录。')
      this.textAction('上一步', AppCommand.PREVIOUS_STEP)
    } else if (this.view.step === 3) {
      this.lead('', '允许需要\n转发的应用。', '应用来源与授权开关，由系统统一管理。')
      Column({ space: 15 }) {
        this.mark($r('sys.symbol.checkmark_circle'))
        Text('系统通知授权 · ' + this.permissionText()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
        this.note(this.sourceText())
        this.action('打开系统通知授权', AppCommand.AUTHORIZE, true, !this.busy() && this.view.notificationMode, $r('sys.symbol.arrow_up_right'))
      }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
      if (!this.view.notificationMode) this.note('当前基础安装包不能请求通知订阅。需要通知或音乐模式安装包。')
      this.action('继续', AppCommand.NEXT_STEP, false, this.view.notificationMode && this.view.permissionKnown && this.view.permission && !this.busy(), $r('sys.symbol.arrow_right'))
      this.textAction('上一步', AppCommand.PREVIOUS_STEP)
    } else {
      this.lead('', this.relayReady() ? '准备好了。' : '还差一步。', this.relayReady() ? '由你决定何时开始转发。' : '请检查下方状态，补齐缺少的设置。')
      Column({ space: 15 }) {
        this.mark($r('sys.symbol.checkmark'))
        Text(this.deviceName()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).lineHeight(27)
        this.metric('消息协议', this.view.supported ? '已适配' : '暂未适配')
        this.metric('通知能力', this.view.notificationMode ? '已启用' : '需要通知模式安装包')
        this.metric('认证材料', this.view.material ? '已保存' : '待导入')
        this.metric('系统通知授权', this.permissionText())
        this.action('开启通知转发', AppCommand.START_RELAY, true, this.relayReady() && !this.busy(), $r('sys.symbol.arrow_right'))
      }.width('100%').padding(22).backgroundColor(this.surface()).borderRadius(24).alignItems(HorizontalAlign.Start)
      this.textAction('稍后再开启', AppCommand.EXIT_SETUP)
      this.textAction('返回授权设置', AppCommand.PREVIOUS_STEP)
      this.note('音乐控制可到音乐页单独开启，完成设置不会自动启动它。')
    }
  }
  @Builder private accountLogin() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Normal }) { this.glyph($r('sys.symbol.arrow_left'), 20, this.ink()) }
          .width(44).height(44).backgroundColor(Color.Transparent).onClick(() => { this.send(AppCommand.CLOSE_LOGIN); }).accessibilityText('返回认证设置')
        Text('登录小米账号').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1)
      }.width('100%')
      Text(this.view.loginNotice).fontSize(13).fontColor(this.muted()).lineHeight(22).width('100%')
      this.action(this.busy() ? '正在同步…' : '登录后同步设备', AppCommand.ACCOUNT_SYNC, true, !this.busy(), $r('sys.symbol.arrow_clockwise'))
      Web({ src: FITNESS_LOGIN_URL, controller: this.loginController, incognitoMode: true })
        .visibility(this.view.loginSensitivePage ? Visibility.Hidden : Visibility.Visible).layoutWeight(1).width('100%').javaScriptAccess(true).domStorageAccess(true)
        .mixedMode(MixedMode.None).copyOptions(CopyOptions.None)
        .onControllerAttached(() => { this.loginController.setCustomUserAgent(MI_LOGIN_USER_AGENT); })
        .onPageEnd((event) => { this.model?.onLoginPage(event.url); })
        .onOverrideUrlLoading((request: WebResourceRequest) => { return request.isMainFrame() && !xiaomiLoginUrlAllowed(request.getRequestUrl()); })
      this.note('密码与验证码在小米官方页面输入，应用不保存账号会话。')
    }.width('100%').height('100%').padding(16).backgroundColor(this.pageColor())
  }
  @Builder private header() {
    Row({ space: 10 }) {
      if (!this.primaryRoute()) {
        Button({ type: ButtonType.Normal }) { this.glyph($r('sys.symbol.arrow_left'), 20, this.ink()) }
          .width(44).height(44).backgroundColor(Color.Transparent).onClick(() => { this.onBackPress(); }).accessibilityText('返回')
      } else { Row() { this.glyph($r('sys.symbol.watch'), 18, this.pageColor()) }.width(29).height(29).backgroundColor(this.ink()).borderRadius(9).justifyContent(FlexAlign.Center) }
      Text(this.advanced ? '高级管理' : this.view.route === 'setup' ? '设置手表' : this.view.route === 'diagnostics' ? '问题排查' : '腕间通知')
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1)
      if (this.primaryRoute()) Text('为你的腕间').fontSize(11).fontColor(this.muted())
    }.width('100%').constraintSize({ minHeight: 58 }).padding({ left: 22, right: 22, top: 7, bottom: 7 })
  }
  @Builder private navItem(label: string, command: AppCommand, symbol: Resource, selected: boolean) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        this.glyph(symbol, 22, selected ? this.accent() : this.muted())
        Text(label).fontSize(12).fontWeight(selected ? FontWeight.Medium : FontWeight.Normal).fontColor(selected ? this.accent() : this.muted())
      }.width('100%').padding({ top: 12, bottom: 12 })
    }.layoutWeight(1).constraintSize({ minHeight: 64 }).backgroundColor(Color.Transparent)
      .onClick(() => { if (!selected) this.send(command); }).accessibilityText(label + (selected ? '，当前页面' : '，切换页面'))
  }
  build() {
    if (this.view.loginVisible) this.accountLogin()
    else {
      Column() {
        this.header()
        Scroll(this.pageScroller) {
          Column({ space: 14 }) {
            if (this.advanced) this.advancedPage()
            else if (this.view.route === 'home' || this.view.route === 'notifications') this.home()
            else if (this.view.route === 'device') this.device()
            else if (this.view.route === 'music') this.music()
            else if (this.view.route === 'setup') this.setup()
            else this.diagnostics()
            if (this.view.notice.length > 0 && this.view.testState !== 'running') Text(this.view.notice).fontSize(12).fontColor(this.view.noticeFailed ? this.danger() : this.muted())
              .lineHeight(21).padding(15).width('100%').backgroundColor(this.surface()).borderRadius(15).accessibilityText(this.view.notice)
            if (this.busy() && this.view.testState !== 'running') {
              Row({ space: 10 }) {
                LoadingProgress().width(18).height(18).color(this.accent()).accessibilityLevel('no')
                Text('正在处理…').fontSize(12).fontColor(this.muted())
              }.width('100%').padding(8).accessibilityText('正在处理')
            }
          }.width('100%').constraintSize({ maxWidth: 560 }).padding({ left: 22, right: 22, top: 20, bottom: 28 }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1)
        // Real foreground-bound system volume component, with a bounded height.
        if (this.view.musicEnabled && this.view.musicAvailable) AVVolumePanel({ volumeLevel: this.view.systemVolumeLevel }).width('100%').height(48)
        if (this.primaryRoute()) {
          Divider().color(this.dividerColor()).strokeWidth(0.5)
          Row() {
            this.navItem('通知', AppCommand.HOME, $r('sys.symbol.bell'), this.view.route === 'home' || this.view.route === 'notifications')
            this.navItem('音乐', AppCommand.MUSIC, $r('sys.symbol.music'), this.view.route === 'music')
            this.navItem('设置', AppCommand.DEVICE, $r('sys.symbol.watch'), this.view.route === 'device')
          }.width('100%').padding({ left: 18, right: 18 }).backgroundColor(this.pageColor())
        }
      }.width('100%').height('100%').backgroundColor(this.pageColor())
    }
  }
}
