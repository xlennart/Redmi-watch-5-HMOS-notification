// Safe presentation contracts. No AuthKey, Bluetooth address, account response or notification body.
export enum AppCommand {
  HOME, DEVICE, NOTIFICATIONS, DIAGNOSTICS, SETUP, EXIT_SETUP,
  START_RELAY, STOP_RELAY, CHANGE_DEVICE, REFRESH, DISCOVER, SELECT_DEVICE,
  IMPORT, CANCEL_IMPORT, SAVE_CANDIDATE, DISCARD_CANDIDATE,
  AUTHORIZE, NEXT_STEP, PREVIOUS_STEP, ACCOUNT_LOGIN, ACCOUNT_SYNC, CLOSE_LOGIN,
  DELETE_CREDENTIAL, UNSUBSCRIBE, CHECK_CHANNEL, TEST_NOTIFICATION, TEST_VIBRATION,
  ENABLE_CATEGORIES, CONFIRM_VISIBLE, CONFIRM_NOT_VISIBLE
}
export class DeviceCandidateView {
  reference: number;
  name: string;
  supported: boolean;
  detail: string;
  constructor(reference: number, name: string, supported: boolean, detail: string) {
    this.reference = reference; this.name = name; this.supported = supported; this.detail = detail;
  }
}
export class CredentialCandidateView {
  reference: number;
  label: string;
  constructor(reference: number, label: string) { this.reference = reference; this.label = label; }
}
export class AppState {
  revision: number = 0;
  route: string = 'home';
  origin: string = 'home';
  hasDevice: boolean = false;
  deviceName: string = '';
  supported: boolean = false;
  material: boolean = false;
  permission: boolean = false;
  permissionKnown: boolean = false;
  sourceCount: number = 0;
  sources: string[] = [];
  notificationMode: boolean = false;
  relayEnabled: boolean = false;
  connection: string = 'unknown';
  lastAcknowledged: boolean = false;
  received: number = 0;
  acknowledged: number = 0;
  failed: number = 0;
  dropped: number = 0;
  lastCode: number = 0;
  iconStatus: string = 'notRequested';
  pendingKind: string = '';
  sessionBusy: boolean = false;
  step: number = 1;
  candidatesVisible: boolean = false;
  candidates: DeviceCandidateView[] = [];
  importPhase: string = 'idle';
  importCandidate: boolean = false;
  credentialCandidates: CredentialCandidateView[] = [];
  accountFailed: boolean = false;
  diagnosticResult: string = '尚未检查消息通道。';
  confirmationRequired: boolean = false;
  issue: string = '';
  notice: string = '';
  noticeFailed: boolean = false;
  large: boolean = false;
  loginVisible: boolean = false;
  loginSensitivePage: boolean = false;
  loginNotice: string = '请在小米官方页面完成登录与验证码，然后点击同步。';

  copy(): AppState {
    const next = new AppState();
    next.revision = this.revision; next.route = this.route; next.origin = this.origin;
    next.hasDevice = this.hasDevice; next.deviceName = this.deviceName; next.supported = this.supported;
    next.material = this.material; next.permission = this.permission; next.permissionKnown = this.permissionKnown;
    next.sourceCount = this.sourceCount; next.sources = this.sources.slice();
    next.notificationMode = this.notificationMode; next.relayEnabled = this.relayEnabled;
    next.connection = this.connection; next.lastAcknowledged = this.lastAcknowledged;
    next.received = this.received; next.acknowledged = this.acknowledged; next.failed = this.failed;
    next.dropped = this.dropped; next.lastCode = this.lastCode; next.iconStatus = this.iconStatus;
    next.pendingKind = this.pendingKind; next.sessionBusy = this.sessionBusy; next.step = this.step;
    next.candidatesVisible = this.candidatesVisible;
    next.candidates = this.candidates.map(item => new DeviceCandidateView(item.reference, item.name, item.supported, item.detail));
    next.importPhase = this.importPhase; next.importCandidate = this.importCandidate;
    next.credentialCandidates = this.credentialCandidates.map(item => new CredentialCandidateView(item.reference, item.label));
    next.accountFailed = this.accountFailed; next.diagnosticResult = this.diagnosticResult;
    next.confirmationRequired = this.confirmationRequired; next.issue = this.issue;
    next.notice = this.notice; next.noticeFailed = this.noticeFailed; next.large = this.large;
    next.loginVisible = this.loginVisible; next.loginSensitivePage = this.loginSensitivePage; next.loginNotice = this.loginNotice;
    return next;
  }
}
