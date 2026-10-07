// Service contracts for the phone companion. Optional services have no runtime implementation yet.
import { WearableFeature, WearableDataProvider } from './WearableData';

export enum WearableConnectionStage {
  DISCONNECTED = 'disconnected', CONNECTING = 'connecting', AUTHENTICATING = 'authenticating',
  READY = 'ready', RECONNECTING = 'reconnecting', STOPPED = 'stopped'
}
export interface WearableFeatureEvidence {
  feature: WearableFeature;
  protocolKnown: boolean;
  // Undefined means not queried/verified; unknown must not be promoted to supported.
  targetSupported?: boolean;
  phoneAuthorized?: boolean;
  implemented: boolean;
  deviceVerified: boolean;
  firmwareVersion?: string;
}
export interface WearableCancellation { cancelled: boolean; }
export interface WearableOperation {
  deadlineMs: number;
  cancellation: WearableCancellation;
}
export interface WearableDeviceInfo {
  deviceId: string;
  displayName: string;
  model?: string;
  firmwareVersion?: string;
  batteryPercent?: number;
}
export interface WearableSession {
  readonly deviceId: string;
  stage(): WearableConnectionStage;
  connect(operation: WearableOperation): Promise<void>;
  disconnect(): Promise<void>;
  onStage(listener: (stage: WearableConnectionStage) => void): () => void;
}
export enum WearableDeliveryStage {
  QUEUED = 'queued', TRANSPORT_ACKNOWLEDGED = 'transport_acknowledged',
  DEVICE_ACCEPTED = 'device_accepted', FAILED = 'failed', CANCELLED = 'cancelled'
}
export interface WearableNotification {
  // Stable source ID includes app clone identity. Notification bodies remain transient.
  sourceId: string;
  id: string;
  appName: string;
  title: string;
  body: string;
  timestampMs: number;
  group?: string;
}
export interface WearableNotificationReceipt {
  sourceId: string;
  id: string;
  stage: WearableDeliveryStage;
  errorCode?: string;
}
export interface WearableNotificationService {
  send(notification: WearableNotification, operation: WearableOperation): Promise<WearableNotificationReceipt>;
  remove(sourceId: string, id: string, operation: WearableOperation): Promise<void>;
}
export enum WearableMusicCommand {
  PLAY = 'play', PAUSE = 'pause', STOP = 'stop', PREVIOUS = 'previous', NEXT = 'next', SET_VOLUME = 'set_volume'
}
export interface WearableMusicControl {
  command: WearableMusicCommand;
  volumePercent?: number;
}
export interface WearablePlayerState {
  state: 'none' | 'playing' | 'paused' | 'stopped' | 'permission_required';
  playerName: string;
  title: string;
  artist: string;
  volumePercent?: number;
  positionMs?: number;
  durationMs?: number;
}
// Separate phone control from on-watch song storage/transfer.
export interface WearablePhoneMusicService {
  publishPlayer(state: WearablePlayerState, operation: WearableOperation): Promise<void>;
  onControl(listener: (control: WearableMusicControl) => void): () => void;
}
export interface PhoneMediaAdapter {
  currentPlayer(): Promise<WearablePlayerState>;
  control(request: WearableMusicControl): Promise<void>;
  onPlayerChanged(listener: (state: WearablePlayerState) => void): () => void;
}
export interface WearableSettingsService {
  readNotificationEnabled(operation: WearableOperation): Promise<boolean>;
  setNotificationEnabled(enabled: boolean, operation: WearableOperation): Promise<boolean>;
  syncTime(timestampMs: number, utcOffsetMinutes: number, operation: WearableOperation): Promise<void>;
  setLanguage(locale: string, operation: WearableOperation): Promise<void>;
}
export interface WearableResource {
  id: string;
  kind: 'watchface' | 'application' | 'music';
  name: string;
  sizeBytes?: number;
}
export interface WearableResourceService {
  list(kind: 'watchface' | 'application' | 'music', operation: WearableOperation): Promise<WearableResource[]>;
  install(resource: WearableResource, data: Uint8Array, operation: WearableOperation,
    progress: (acknowledgedBytes: number, totalBytes: number) => void): Promise<void>;
  remove(resource: WearableResource, operation: WearableOperation): Promise<void>;
}
export interface WearableDeviceAdapter {
  readonly adapterId: string;
  readonly session: WearableSession;
  info(operation: WearableOperation): Promise<WearableDeviceInfo>;
  capabilities(): Promise<WearableFeatureEvidence[]>;
  notifications?: WearableNotificationService;
  phoneMusic?: WearablePhoneMusicService;
  settings?: WearableSettingsService;
  health?: WearableDataProvider;
  resources?: WearableResourceService;
}
