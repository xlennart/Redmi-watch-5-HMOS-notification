// Contracts only: no health data is queried, persisted or displayed by this version.
export enum WearableFeature {
  NOTIFICATION = 'notification',
  SLEEP = 'sleep',
  ACTIVITY = 'activity',
  WORKOUTS = 'workouts',
  PHONE_MUSIC_CONTROL = 'phone_music_control',
  WATCH_MUSIC_LIBRARY = 'watch_music_library',
  DEVICE_SETTINGS = 'device_settings',
  WEATHER = 'weather',
  ALARMS = 'alarms',
  CONTACTS = 'contacts',
  WATCHFACES = 'watchfaces',
  WATCH_APPS = 'watch_apps',
  NETWORK = 'network'
}

export enum FeatureAvailability {
  UNKNOWN = 'unknown',
  UNSUPPORTED = 'unsupported',
  AVAILABLE = 'available',
  AUTHORIZATION_REQUIRED = 'authorization_required'
}

export interface WearableCapability {
  feature: WearableFeature;
  availability: FeatureAvailability;
}

export interface WearableSource {
  // App-assigned stable ID. Do not use a changing OS Bluetooth ID or a raw MAC in the UI.
  deviceId: string;
  adapterId: string;
  recordedAtMs: number;
  importedAtMs: number;
}

export interface WearableDataQuery {
  fromInclusiveMs: number;
  toExclusiveMs: number;
  pageSize: number;
  cursor?: string;
}

export interface WearableDataPage<T> {
  items: T[];
  nextCursor?: string;
  // Only true after the adapter has read the entire requested interval.
  complete: boolean;
}

export enum SleepStage {
  UNKNOWN = 'unknown',
  AWAKE = 'awake',
  LIGHT = 'light',
  DEEP = 'deep',
  REM = 'rem'
}

export interface SleepStageInterval {
  fromInclusiveMs: number;
  toExclusiveMs: number;
  stage: SleepStage;
}

export interface SleepSession {
  id: string;
  source: WearableSource;
  fromInclusiveMs: number;
  toExclusiveMs: number;
  utcOffsetMinutes: number;
  stages: SleepStageInterval[];
  // Missing measurements remain undefined, rather than being fabricated as zero.
  asleepMinutes?: number;
  isNap?: boolean;
}

export interface ActivityDay {
  id: string;
  source: WearableSource;
  localDate: string; // YYYY-MM-DD at the supplied offset, not UTC truncation.
  utcOffsetMinutes: number;
  steps?: number;
  distanceMeters?: number;
  activeMinutes?: number;
  activeEnergyKcal?: number;
}

export interface WorkoutSession {
  id: string;
  source: WearableSource;
  fromInclusiveMs: number;
  toExclusiveMs: number;
  // Adapter may retain an unknown sport code without mislabelling it.
  sport: string;
  distanceMeters?: number;
  activeEnergyKcal?: number;
}

export enum WearableDataErrorCode {
  UNSUPPORTED = 'unsupported',
  AUTHORIZATION_REQUIRED = 'authorization_required',
  DISCONNECTED = 'disconnected',
  CANCELLED = 'cancelled',
  INVALID_RANGE = 'invalid_range',
  INVALID_DATA = 'invalid_data',
  STORAGE_UNAVAILABLE = 'storage_unavailable'
}

export class WearableDataError extends Error {
  code: WearableDataErrorCode;

  constructor(code: WearableDataErrorCode) {
    super(code);
    this.code = code;
  }
}

// A device adapter owns protocol-specific field mapping. Views consume these contracts.
export interface WearableDataProvider {
  capabilities(): Promise<WearableCapability[]>;
  readSleep(query: WearableDataQuery): Promise<WearableDataPage<SleepSession>>;
  readActivity(query: WearableDataQuery): Promise<WearableDataPage<ActivityDay>>;
  readWorkouts(query: WearableDataQuery): Promise<WearableDataPage<WorkoutSession>>;
  cancelPendingReads(): void;
}

// Separate from credentials and notification counters; implementation will follow explicit feature activation.
export interface WearableDataRepository {
  upsertSleep(items: SleepSession[]): Promise<void>;
  upsertActivity(items: ActivityDay[]): Promise<void>;
  upsertWorkouts(items: WorkoutSession[]): Promise<void>;
  readSleep(deviceId: string, query: WearableDataQuery): Promise<WearableDataPage<SleepSession>>;
  readActivity(deviceId: string, query: WearableDataQuery): Promise<WearableDataPage<ActivityDay>>;
  readWorkouts(deviceId: string, query: WearableDataQuery): Promise<WearableDataPage<WorkoutSession>>;
  deleteDeviceData(deviceId: string): Promise<void>;
}
