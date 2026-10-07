/**
 * 腕间通知 UI 契约 v0.1 — 设计交付，不是已接入的运行接口。
 * 平台无关 TypeScript 声明；ArkTS API 26 / V1 落地时使用显式 class，
 * 校验目标编译器支持的类型写法。页面不得接收 DeviceCredential/authKey/Cookie。
 */
export type DeviceRef = string; // 后台生成的短期不透明引用，不等于持久蓝牙地址
export type CandidateRef = string; // 导入服务拥有候选材料；页面只持有此引用
export type OperationId = string;
export type Route = 'home' | 'device' | 'notifications' | 'setup' | 'diagnostics';
export type Knowledge = 'unknown' | 'yes' | 'no';
export type ConnectionStage = 'unknown' | 'disconnected' | 'connecting' |
  'authenticating' | 'ready' | 'reconnecting' | 'stopped';
export type DeliveryStage = 'queued' | 'transport_acknowledged' |
  'device_accepted' | 'failed' | 'cancelled';
export type IssueKind = 'no_device' | 'pairing_changed' | 'unsupported_device' |
  'bluetooth_permission' | 'bluetooth_unavailable' | 'credential_missing' |
  'credential_mismatch' | 'notification_permission' | 'no_authorized_sources' |
  'build_mode' | 'connection_failed' | 'account_session' | 'import_invalid' |
  'import_timeout' | 'diagnostic_busy' | 'storage_failed' | 'unknown';

export interface SafeIssue {
  kind: IssueKind;
  severity: 'info' | 'warning' | 'error';
  userMessage: string; // 必须由受控错误映射生成，禁止 raw error.message
  recovery: 'setup' | 'reselect' | 'system_permissions' | 'import' |
    'retry_account' | 'diagnostics' | 'retry_operation' | 'none';
  technical?: { stage: string; code?: number | string }; // 不含地址/报文/会话
}
export interface FeatureEvidence {
  id: 'notifications' | 'phone_music' | 'watch_music' | 'health' |
    'device_info' | 'notification_settings' | 'time_language' | 'resources';
  protocolKnown: boolean;
  targetSupported: Knowledge;
  phoneAuthorized: Knowledge;
  implemented: boolean;
  deviceVerified: boolean;
  validationScope?: string; // 例如“固定测试提醒”；不能泛化为整个功能稳定
}
export interface PairedCandidateView {
  ref: DeviceRef;
  name: string;
  messageProtocol: 'redmi_watch_5' | 'unsupported' | 'unknown';
  callConnection: 'connected' | 'disconnected' | 'unknown'; // HFP 与消息通道分开
}
export interface SourceView {
  ref: string; // 稳定身份需含应用分身 identity；显示名不能作为身份
  displayName: string;
  authorized: boolean;
}
export interface DeviceView {
  ref: DeviceRef;
  displayName: string;
  pairing: 'selected' | 'missing' | 'unknown';
  protocolSupport: Knowledge;
  batteryPercent?: number; // 未提供即未知，禁止填 0
  firmwareVersion?: string;
}
export interface CredentialView {
  storage: 'unknown' | 'absent' | 'present';
  binding: 'unknown' | 'matches' | 'mismatch'; // 目标选择变化后重新验证
  origin?: 'log' | 'account';
  safeLabel?: string; // 型号 + 遮蔽地址后缀；禁止密钥任何部分
}
export interface ImportCandidateView {
  ref: CandidateRef;
  displayName: string;
  maskedSuffix?: string;
}
export interface ConnectionView {
  stage: ConnectionStage;
  observedAt?: number;
  observationSource: 'unknown' | 'relay' | 'diagnostics';
  currentSession: boolean;
  // ready 只适用于尚未关闭的当前会话；每条消息临时会话结束后回 unknown/disconnected
  recentOutcome?: { stage: DeliveryStage; observedAt?: number; operationId?: OperationId };
}
export interface RelayView {
  configEnabled: boolean; // 持久开关：当前 RelayConfig.enabled
  operational: 'unknown' | 'stopped' | 'armed' | 'processing' | 'blocked' | 'stopping';
  blockingIssue?: SafeIssue;
  authorizedSourceCount?: number; // 查询失败保留未知，不能补成 0
  // armed != connected；processing/stop 完成由后台明确事件提供
}
export interface PermissionView {
  buildMode: 'baseline' | 'notifications';
  bluetooth: 'unknown' | 'granted' | 'denied';
  notification: 'unknown' | 'granted' | 'denied';
  subscription: 'unknown' | 'active' | 'inactive';
  authorizedSources?: SourceView[]; // 当前 API 可得到哪些字段，映射时据实保留
  snapshotAt?: number;
  stale: boolean; // 三个系统查询全部成功才提交完整授权快照
}
export interface StatsView {
  notificationCallbacks: number; // 累计回调，不是去重独立消息数
  transportAcknowledged: number;
  failed: number;
  dropped: number;
  lastReceivedAt?: number;
  lastCode?: number;
  // 当前 RelayStats 没有 lastAckAt，不可由 lastReceivedAt 推断
}
export interface UiOperation {
  id: OperationId;
  kind: 'refresh' | 'discover' | 'select' | 'authorize' | 'import' | 'save' |
    'account_sync' | 'start_relay' | 'stop_relay' | 'diagnostics' |
    'delete_credential' | 'unsubscribe';
  phase: 'idle' | 'pending' | 'confirmed' | 'failed' | 'cancelled';
  cancellable: boolean;
  issue?: SafeIssue;
}
export interface DiagnosticsView {
  owner: 'none' | 'relay' | 'diagnostics'; // 当前通过读 RelayConfig 防冲突；单一 owner 是后续设计
  latest?: {
    operationId: OperationId;
    kind: 'channel' | 'fixed_notification' | 'vibration' | 'enable_categories_and_test';
    transmission: 'unknown' | 'acknowledged' | 'failed';
    visibility: 'unknown' | 'user_confirmed' | 'user_not_seen';
    protocolVersion?: number;
    issue?: SafeIssue;
  };
}
export interface WristViewState {
  schemaVersion: 1;
  revision: number; // 后台有序快照版本；不能用时间戳替代版本
  deviceGeneration: number; // 换设备/配对变化/清理时递增，拒绝旧结果
  route: Route;
  onboarding: { step: 1 | 2 | 3 | 4; complete: boolean };
  device?: DeviceView;
  pairedCandidates: PairedCandidateView[];
  credentials: CredentialView;
  importCandidates: ImportCandidateView[];
  permissions: PermissionView;
  connection: ConnectionView;
  relay: RelayView;
  stats: StatsView;
  features: FeatureEvidence[];
  operations: UiOperation[];
  diagnostics: DiagnosticsView;
  primaryIssue?: SafeIssue;
  account: { phase: 'idle' | 'official_login' | 'exchanging' | 'failed';
    cookieFallback: 'unverified'; issue?: SafeIssue };
}

export type CommandPayload =
  | { type: 'RefreshSnapshot' }
  | { type: 'DiscoverPairedDevices' }
  | { type: 'SelectDevice'; deviceRef: DeviceRef }
  | { type: 'OpenNotificationSettings' } // 后台关联目标后发 UI effect；系统返回再刷新
  | { type: 'ImportCredentialFromPicker' } // 由后台/平台启动选取，页面没有原文件内容
  | { type: 'SaveCredentialCandidate'; candidateRef: CandidateRef }
  | { type: 'DiscardImportCandidates' }
  | { type: 'OpenOfficialAccountLogin' }
  | { type: 'CompleteAccountLogin' } // 无任何 Cookie/token/password 参数
  | { type: 'StartRelay' }
  | { type: 'StopRelay' } // 即使权限撤销、断线或存在旧发送，也必须允许
  | { type: 'RunDiagnostics'; kind: 'channel' | 'fixed_notification' | 'vibration' }
  | { type: 'EnableNotificationCategoriesAndTest'; confirmed: true }
  | { type: 'ConfirmVisibleResult'; diagnosticOperationId: OperationId;
      result: 'seen' | 'not_seen' } // 仅人工证据；不改 ACK 计数
  | { type: 'DeleteCredential'; confirmed: true } // 后台先停转发再清理材料
  | { type: 'UnsubscribeNotifications'; confirmed: true }
  | { type: 'CancelOperation'; operationId: OperationId };
export interface Command {
  requestId: string; // 同一用户操作保持相同值以防重复提交
  expectedRevision: number;
  deviceGeneration: number;
  payload: CommandPayload;
}
export interface CommandReceipt {
  requestId: string;
  operationId: OperationId;
  accepted: boolean; // 接受处理，不等于操作成功
  issue?: SafeIssue;
}
export type EventPayload =
  | { type: 'SnapshotChanged'; snapshot: WristViewState }
  | { type: 'ConnectionChanged'; connection: ConnectionView }
  | { type: 'RelayConfigChanged'; enabled: boolean }
  | { type: 'PermissionSnapshotChanged'; permissions: PermissionView }
  | { type: 'PairingChanged' }
  | { type: 'ImportCandidatesReady'; candidates: ImportCandidateView[] }
  | { type: 'CredentialMetadataChanged'; credentials: CredentialView }
  | { type: 'StatsChanged'; stats: StatsView }
  | { type: 'OperationChanged'; operation: UiOperation }
  | { type: 'DeliveryChanged'; stage: DeliveryStage } // 不携带 WearableNotification
  | { type: 'IssueRaised'; issue: SafeIssue };
export interface ViewEvent {
  sequence: number;
  revision: number;
  deviceGeneration: number;
  operationId?: OperationId;
  payload: EventPayload;
}
export type UiEffect =
  | { type: 'ShowConfirmation'; title: string; body: string; commandType: string }
  | { type: 'PresentSystemNotificationSettings' }
  | { type: 'PresentSystemFilePicker' }
  | { type: 'PresentOfficialLoginView' }
  | { type: 'AnnounceStatus'; text: string };
export interface WristViewModel {
  snapshot(): WristViewState;
  subscribe(listener: (event: ViewEvent) => void): () => void;
  dispatch(command: Command): Promise<CommandReceipt>;
  observeEffects(listener: (effect: UiEffect) => void): () => void;
  dispose(): void; // 解除监听/取消前台导入和诊断，不能自动关掉已开启的后台通知转发
}
