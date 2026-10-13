import { ProtoField, joinBytes, protoInt, protoBytes, readProto, clearProto } from './WatchProtocol';

// Xiaomi protobuf music facts; independently implemented. See docs/music-protocol-research.zh-CN.md.
export type WatchMusicPlayback = 'none' | 'playing' | 'paused';
export interface WatchMusicState {
  state: WatchMusicPlayback;
  track: Uint8Array;
  artist: Uint8Array;
  positionSeconds: number;
  durationSeconds: number;
  volumePercent: number;
}
export type WatchMusicAction = 'request' | 'play' | 'pause' | 'previous' | 'next' | 'volume' | 'unsupported';
export class WatchMusicCommand {
  action: WatchMusicAction;
  volumePercent: number;
  reason: string;
  constructor(action: WatchMusicAction, volumePercent: number = -1, reason: string = '') {
    this.action = action; this.volumePercent = volumePercent; this.reason = reason;
  }
}

function uint(value: number, maximum: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= maximum;
}

// Require bounded, well-formed UTF-8. Inputs stay bytes so no platform codec is required by the shared core.
function validText(data: Uint8Array): boolean {
  if (data.length > 512) return false;
  for (let i = 0; i < data.length;) {
    const first = data[i++];
    if (first === 0) return false;
    if (first < 0x80) continue;
    let remaining = 0; let value = 0; let minimum = 0;
    if (first >= 0xc2 && first <= 0xdf) { remaining = 1; value = first & 31; minimum = 0x80; }
    else if (first >= 0xe0 && first <= 0xef) { remaining = 2; value = first & 15; minimum = 0x800; }
    else if (first >= 0xf0 && first <= 0xf4) { remaining = 3; value = first & 7; minimum = 0x10000; }
    else return false;
    if (i + remaining > data.length) return false;
    for (let j = 0; j < remaining; j++) {
      const next = data[i++];
      if ((next & 0xc0) !== 0x80) return false;
      value = value * 64 + (next & 63);
    }
    if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return false;
  }
  return true;
}

export function watchMusicStateCommand(input: WatchMusicState): Uint8Array {
  if (!uint(input.volumePercent, 100) || !uint(input.positionSeconds, 0xffffffff) ||
    !uint(input.durationSeconds, 0xffffffff)) throw new Error('WATCH_MUSIC_INTEGER');
  if (!validText(input.track) || !validText(input.artist)) throw new Error('WATCH_MUSIC_TEXT');
  let state = 0;
  if (input.state === 'playing') state = 1;
  else if (input.state === 'paused') state = 2;
  else if (input.state !== 'none') throw new Error('WATCH_MUSIC_STATE');
  const pieces: Uint8Array[] = [protoInt(1, state), protoInt(2, input.volumePercent)];
  if (state !== 0) {
    const position = input.durationSeconds > 0 ? Math.min(input.positionSeconds, input.durationSeconds) : input.positionSeconds;
    pieces.push(protoBytes(4, input.track), protoBytes(5, input.artist), protoInt(6, position), protoInt(7, input.durationSeconds));
  }
  const info = joinBytes(pieces);
  const music = protoBytes(1, info);
  try { return joinBytes([protoInt(1, 18), protoInt(2, 1), protoBytes(20, music)]); }
  finally { info.fill(0); music.fill(0); for (let i = 0; i < pieces.length; i++) pieces[i].fill(0); }
}

function one(fields: ProtoField[], id: number): ProtoField | undefined {
  const matches = fields.filter(item => item.id === id);
  if (matches.length > 1) throw new Error('duplicate');
  return matches[0];
}
function integer(fields: ProtoField[], id: number): number {
  const field = one(fields, id);
  if (!field || field.bytes.length !== 0 || !uint(field.integer, 0xffffffff)) throw new Error('integer');
  return field.integer;
}
function nested(fields: ProtoField[], id: number, required: boolean, maximum: number): ProtoField[] {
  const field = one(fields, id);
  if (!field) { if (required) throw new Error('missing'); return []; }
  if (field.integer !== -1 || field.bytes.length > maximum) throw new Error('body');
  return readProto(field.bytes);
}

// Called only after authenticated transport decoding. Never dispatch an unknown or malformed key.
export function parseWatchMusicCommand(fields: ProtoField[]): WatchMusicCommand {
  let music: ProtoField[] = []; let key: ProtoField[] = [];
  try {
    if (fields.length > 128) throw new Error('fields');
    if (integer(fields, 1) !== 18) return new WatchMusicCommand('unsupported', -1, 'domain');
    const subtype = integer(fields, 2);
    if (subtype !== 0 && subtype !== 2) return new WatchMusicCommand('unsupported', -1, 'subtype');
    music = nested(fields, 20, subtype === 2, 1024);
    if (subtype === 0) {
      if (one(music, 2)) return new WatchMusicCommand('unsupported', -1, 'request_key');
      return new WatchMusicCommand('request');
    }
    key = nested(music, 2, true, 128);
    const code = integer(key, 1);
    const volumeField = one(key, 2);
    if (volumeField && integer(key, 2) > 100) throw new Error('volume');
    if (code === 0) return new WatchMusicCommand('play');
    if (code === 1) return new WatchMusicCommand('pause');
    if (code === 3) return new WatchMusicCommand('previous');
    if (code === 4) return new WatchMusicCommand('next');
    if (code === 5) {
      const volume = integer(key, 2);
      if (volume > 100) throw new Error('volume');
      return new WatchMusicCommand('volume', volume);
    }
    return new WatchMusicCommand('unsupported', -1, 'key');
  } catch (_) { return new WatchMusicCommand('unsupported', -1, 'malformed'); }
  finally { clearProto(key); clearProto(music); }
}

// The Xiaomi volume key carries a target percentage, not separate Huami +/- command codes.
// Avoid lowering volume when an increase arrives at 100%, or raising it at 0%.
export function watchMusicVolumeDirection(requestedPercent: number, currentPercent: number): number {
  if (!uint(requestedPercent, 100) || !uint(currentPercent, 100)) throw new Error('WATCH_MUSIC_VOLUME');
  if (requestedPercent === currentPercent) return 0;
  return requestedPercent > currentPercent ? 1 : -1;
}
