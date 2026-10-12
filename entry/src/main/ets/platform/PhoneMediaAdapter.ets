import { avSession } from '@kit.AVSessionKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WearablePlayerState, WearableMusicControl, WearableMusicCommand, PhoneMediaAdapter } from '../core/WearableServices';
import { chooseMediaSession, MediaSessionCandidate, mediaVolumePercent, musicVolumeLevel } from '../core/PhoneMedia';
import { WatchChannelError } from './WatchChannelProbe';
import { MusicVolumeBridge } from './MusicVolumeBridge';

async function mediaDeadline<T>(operation: Promise<T>): Promise<T> {
  let timer = -1;
  try {
    return await Promise.race([operation, new Promise<T>((resolve, reject) => {
      timer = setTimeout(() => { reject(new WatchChannelError('媒体服务响应超时', -64)); }, 3000);
    })]);
  } finally { clearTimeout(timer); }
}

// Third-party AVSession controller, never a fake audio player. Metadata lives only in memory.
export class HarmonyPhoneMediaAdapter implements PhoneMediaAdapter {
  private controller: avSession.AVSessionController | undefined = undefined;
  private sessionId: string = '';
  private playerName: string = '';
  private volume: audio.AudioVolumeManager = audio.getAudioManager().getVolumeManager();
  private listener: ((state: WearablePlayerState) => void) | undefined = undefined;
  private closed: boolean = false;
  private invalidated: boolean = true;
  private selectionDirty: boolean = true;
  private lastSelectionMs: number = 0;
  private selectionWork: Promise<void> | undefined = undefined;
  private controllerDead: boolean = false;
  private metadata: avSession.AVMetadata = { assetId: '' };
  private playback: avSession.AVPlaybackState = {};
  private commands: avSession.AVControlCommandType[] = [];
  private changed: (descriptor: avSession.AVSessionDescriptor) => void = () => { this.invalidated = true; this.selectionDirty = true; };
  private metadataChanged: (data: avSession.AVMetadata) => void = () => { this.invalidated = true; };
  private playbackChanged: (state: avSession.AVPlaybackState) => void = () => { this.invalidated = true; };
  private commandsChanged: (commands: avSession.AVControlCommandType[]) => void = (commands) => { this.commands = commands.slice(); };
  private destroyed: () => void = () => { this.invalidated = true; this.selectionDirty = true; this.controllerDead = true; };
  private activeChanged: () => void = () => { this.invalidated = true; this.selectionDirty = true; };

  start(): void {
    avSession.onSessionCreate(this.changed);
    avSession.onSessionDestroy(this.changed);
    avSession.onTopSessionChange(this.changed);
  }
  async close(): Promise<void> {
    this.closed = true; this.listener = undefined;
    try { avSession.offSessionCreate(this.changed); } catch (_) { }
    try { avSession.offSessionDestroy(this.changed); } catch (_) { }
    try { avSession.offTopSessionChange(this.changed); } catch (_) { }
    await this.releaseController();
  }
  private async releaseController(): Promise<void> {
    const old = this.controller; this.controller = undefined; this.sessionId = ''; this.playerName = '';
    this.metadata = { assetId: '' }; this.playback = {}; this.commands = []; this.invalidated = true;
    if (!old) return;
    try { old.off('metadataChange', this.metadataChanged); } catch (_) { }
    try { old.off('playbackStateChange', this.playbackChanged); } catch (_) { }
    try { old.off('sessionDestroy', this.destroyed); } catch (_) { }
    try { old.off('validCommandChange', this.commandsChanged); } catch (_) { }
    try { old.off('activeStateChange', this.activeChanged); } catch (_) { }
    try { await mediaDeadline(old.destroy()); } catch (_) { }
  }
  private async select(): Promise<void> {
    if (this.selectionWork) return await this.selectionWork;
    if (this.controller && !this.controllerDead && !this.selectionDirty && Date.now() - this.lastSelectionMs < 5000) return;
    const work = this.refreshSelection(); this.selectionWork = work;
    try { await work; } finally { if (this.selectionWork === work) this.selectionWork = undefined; }
  }
  private async refreshSelection(): Promise<void> {
    const descriptors = await mediaDeadline(avSession.getAllSessionDescriptors());
    if (this.closed) throw new WatchChannelError('音乐控制已关闭', -21);
    this.lastSelectionMs = Date.now(); this.selectionDirty = false;
    const candidates: MediaSessionCandidate[] = [];
    // The system top active session is authoritative. Historical inactive entries are excluded.
    for (let i = 0; i < Math.min(32, descriptors.length); i++) {
      const item = descriptors[i];
      if (item.elementName.bundleName === 'com.xlennart.wristnotifications' || item.type !== 'audio' && item.type !== 'video') continue;
      candidates.push({ id: item.sessionId, active: item.isActive, top: item.isTopSession, playing: false });
    }
    const selected = chooseMediaSession(candidates);
    if (selected === this.sessionId && this.controller && !this.controllerDead) return;
    await this.releaseController();
    if (!selected || this.closed) return;
    let abandoned = false;
    const creating = avSession.createController(selected);
    creating.then((late: avSession.AVSessionController) => {
      if (abandoned) late.destroy().catch(() => {});
    }).catch(() => {});
    let controller: avSession.AVSessionController;
    try { controller = await mediaDeadline(creating); } catch (error) { abandoned = true; throw new WatchChannelError('创建媒体控制器', (error as BusinessError).code || -64); }
    if (this.closed) { await controller.destroy(); return; }
    this.controller = controller; this.sessionId = selected; this.controllerDead = false;
    this.playerName = descriptors.find(item => item.sessionId === selected)?.sessionTag?.slice(0, 80) || '当前播放器';
    controller.on('metadataChange', 'all', this.metadataChanged);
    controller.on('playbackStateChange', 'all', this.playbackChanged);
    controller.on('sessionDestroy', this.destroyed);
    controller.on('activeStateChange', this.activeChanged);
    controller.on('validCommandChange', this.commandsChanged);
    this.commands = await mediaDeadline(controller.getValidCommands());
  }
  async currentPlayer(): Promise<WearablePlayerState> {
    const result: WearablePlayerState = { state: 'none', playerName: '', title: '', artist: '', volumePercent: 0, positionMs: 0, durationMs: 0 };
    try {
      await this.select();
      const usage = audio.StreamUsage.STREAM_USAGE_MUSIC;
      result.volumePercent = mediaVolumePercent(this.volume.getVolumeByStream(usage),
        this.volume.getMinVolumeByStream(usage), this.volume.getMaxVolumeByStream(usage));
      if (!this.controller || this.closed) return result;
      const controller = this.controller;
      if (this.invalidated) {
        this.playback = await mediaDeadline(controller.getAVPlaybackState());
        this.metadata = await mediaDeadline(controller.getAVMetadata());
      }
      const state = this.playback; const metadata = this.metadata;
      if (this.closed || controller !== this.controller) return result;
      result.state = state.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY ? 'playing' :
        state.state === avSession.PlaybackState.PLAYBACK_STATE_PAUSE ? 'paused' : 'none';
      if (result.state !== 'none') {
        result.title = (metadata.title || '').slice(0, 160); result.artist = (metadata.artist || '').slice(0, 120);
        result.playerName = this.playerName;
        result.durationMs = Math.max(0, Math.min(86400000, metadata.duration || 0));
        result.positionMs = Math.max(0, Math.min(result.durationMs || 86400000, controller.getRealPlaybackPositionSync()));
      }
      if (this.invalidated) { this.invalidated = false; this.listener?.(result); }
      return result;
    } catch (error) {
      if ((error as BusinessError).code === 201) result.state = 'permission_required';
      else throw new WatchChannelError('读取手机媒体会话', (error as BusinessError).code || -64);
      return result;
    }
  }
  async control(request: WearableMusicControl): Promise<void> {
    if (this.closed) throw new WatchChannelError('音乐控制已关闭', -21);
    await this.select();
    if (this.closed) throw new WatchChannelError('音乐控制已关闭', -21);
    if (!this.controller) throw new WatchChannelError('尚无活动媒体会话', -61);
    if (request.command === WearableMusicCommand.SET_VOLUME) {
      const usage = audio.StreamUsage.STREAM_USAGE_MUSIC;
      const current = this.volume.getVolumeByStream(usage);
      const level = musicVolumeLevel(request.volumePercent ?? -1, current,
        this.volume.getMinVolumeByStream(usage), this.volume.getMaxVolumeByStream(usage));
      if (level === current) return;
      MusicVolumeBridge.request(level);
      const until = Date.now() + 600;
      while (!this.closed && Date.now() < until) {
        if (this.volume.getVolumeByStream(usage) === level) { this.invalidated = true; return; }
        await new Promise<void>(resolve => { setTimeout(resolve, 20); });
      }
      throw new WatchChannelError('系统音量未变化', this.closed ? -21 : -67);
    }
    const command: avSession.AVControlCommandType = request.command === WearableMusicCommand.PLAY ? 'play' :
      request.command === WearableMusicCommand.PAUSE ? 'pause' : request.command === WearableMusicCommand.NEXT ? 'playNext' :
      request.command === WearableMusicCommand.PREVIOUS ? 'playPrevious' : 'stop';
    const controller = this.controller;
    const supported = this.commands;
    if (!supported.includes(command)) throw new WatchChannelError('当前播放器未开放此控制', -62);
    if (this.closed || controller !== this.controller) throw new WatchChannelError('音乐控制已关闭', -21);
    await mediaDeadline(controller.sendControlCommand({ command: command }));
    this.invalidated = true;
  }
  onPlayerChanged(listener: (state: WearablePlayerState) => void): () => void {
    this.listener = listener;
    return () => { if (this.listener === listener) this.listener = undefined; };
  }
}
