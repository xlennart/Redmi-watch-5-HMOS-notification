// Platform-independent selection and volume policy. Session IDs never enter the page model.
export interface MediaSessionCandidate {
  id: string;
  active: boolean;
  top: boolean;
  playing: boolean;
}
export function chooseMediaSession(candidates: MediaSessionCandidate[]): string {
  const active = candidates.filter(item => item.active);
  return active.find(item => item.top)?.id || active.find(item => item.playing)?.id || active[0]?.id || '';
}
export function mediaVolumePercent(level: number, min: number, max: number): number {
  if (![level, min, max].every(value => Number.isFinite(value)) || max <= min) return 0;
  return Math.round(Math.max(0, Math.min(1, (level - min) / (max - min))) * 100);
}
// Xiaomi sends a target percentage. Match the official client: compare then change just one native step.
export function musicVolumeLevel(request: number, current: number, min: number, max: number): number {
  if (![request, current, min, max].every(value => Number.isFinite(value)) || min > max || request < 0 || request > 100) {
    throw new Error('MEDIA_VOLUME_RANGE');
  }
  const percent = mediaVolumePercent(current, min, max);
  const target = current + (request > percent ? 1 : request < percent ? -1 : 0);
  return Math.round(Math.max(min, Math.min(max, target)));
}
