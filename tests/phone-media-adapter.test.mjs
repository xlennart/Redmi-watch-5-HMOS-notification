import test from 'node:test';
import assert from 'node:assert/strict';
import { loadMediaAdapter } from './helpers/load-media-adapter.mjs';
import { WearableMusicCommand } from '../.cloud-build/out/WearableServices.js';

function fixture() {
  const calls = [], controllers = new Map();
  const descriptor = (id, top = false, active = true) => ({ sessionId: id, type: 'audio', isTopSession: top,
    isActive: active, elementName: { bundleName: `test.${id}` }, sessionTag: id });
  const create = id => {
    const handlers = new Map();
    const controller = { state: 2, destroyed: 0, commands: ['play','pause','playNext','playPrevious'],
      on(type,filter,callback) { handlers.set(type,callback||filter); }, off(type) { handlers.delete(type); },
      emit(type,arg){handlers.get(type)?.(arg);}, async destroy() { this.destroyed++; },
      async getAVPlaybackState() { return { state: this.state }; },
      async getAVMetadata() { return { title: 'Synthetic song', artist: 'Synthetic artist', duration: 100000 }; },
      getRealPlaybackPositionSync() { return 10000; }, async getValidCommands() { return this.commands; },
      async sendControlCommand(request) { calls.push([id,request.command]); } };
    controllers.set(id, controller); return controller;
  };
  const sessionEvents = new Map();
  const avSession = { descriptors: [descriptor('first'),descriptor('top',true)],
    PlaybackState: { PLAYBACK_STATE_PLAY: 2, PLAYBACK_STATE_PAUSE: 3 },
    onSessionCreate(cb) {sessionEvents.set('create',cb);}, offSessionCreate() {},
    onSessionDestroy(cb) {sessionEvents.set('destroy',cb);}, offSessionDestroy() {},
    onTopSessionChange(cb) {sessionEvents.set('top',cb);}, offTopSessionChange() {}, emit(type,data){sessionEvents.get(type)?.(data);},
    async getAllSessionDescriptors() { return this.descriptors; }, async createController(id) { return controllers.get(id) || create(id); } };
  const manager = { level:5, getVolumeManager() { return { getVolumeByStream: () => manager.level, getMinVolumeByStream: () => 0, getMaxVolumeByStream: () => 10 }; },
    async setVolume(type,level) { calls.push(['volume',level]); } };
  const audio = { StreamUsage: { STREAM_USAGE_MUSIC: 0 }, AudioVolumeType: { MEDIA: 0 }, getAudioManager: () => manager };
  const MusicVolumeBridge={request(level){manager.level=level;calls.push(['volume',level]);}};
  return { avSession,audio,MusicVolumeBridge,manager,calls,controllers,descriptor,create };
}

test('real native adapter controls the top active player with supported transport commands', async () => {
  const f = fixture(); const Adapter = await loadMediaAdapter(f); const adapter = new Adapter(); adapter.start();
  for (const command of [WearableMusicCommand.PLAY,WearableMusicCommand.PAUSE,WearableMusicCommand.NEXT,WearableMusicCommand.PREVIOUS]) {
    await adapter.control({command});
  }
  assert.deepEqual(f.calls, [['top','play'],['top','pause'],['top','playNext'],['top','playPrevious']]);
  f.controllers.get('top').commands = ['play'];
  f.controllers.get('top').emit('validCommandChange',['play']);
  await assert.rejects(adapter.control({command: WearableMusicCommand.NEXT}), error => error.code === -62);
  assert.equal(f.calls.length, 4); await adapter.close();
});

test('no active player rejects controls and clears previous track metadata', async () => {
  const f = fixture(); const Adapter = await loadMediaAdapter(f); const adapter = new Adapter(); adapter.start();
  assert.equal((await adapter.currentPlayer()).title, 'Synthetic song');
  f.avSession.descriptors = [f.descriptor('top',true,false)];
  f.avSession.emit('top',f.avSession.descriptors[0]);
  const result = await adapter.currentPlayer();
  assert.equal(result.state, 'none'); assert.equal(result.title, ''); assert.equal(result.artist, '');
  assert.equal(result.playerName, ''); assert.equal(result.positionMs, 0); assert.equal(result.durationMs, 0);
  await assert.rejects(adapter.control({command: WearableMusicCommand.PLAY}), error => error.code === -61);
  assert.deepEqual(f.calls, []); assert.ok(f.controllers.get('top').destroyed >= 1); await adapter.close();
});

test('stopped media state emits no old metadata; volume target changes one native level', async () => {
  const f = fixture(); const Adapter = await loadMediaAdapter(f); const adapter = new Adapter();
  await adapter.currentPlayer(); f.controllers.get('top').state = 0;
  f.controllers.get('top').emit('playbackStateChange',{state:0});
  const none = await adapter.currentPlayer(); assert.equal(none.state, 'none'); assert.equal(none.title, '');
  await adapter.control({command: WearableMusicCommand.SET_VOLUME,volumePercent: 100});
  await adapter.control({command: WearableMusicCommand.SET_VOLUME,volumePercent: 0});
  assert.deepEqual(f.calls, [['volume',6],['volume',5]]); await adapter.close();
});

test('a controller created after close is destroyed and cannot execute a command', async () => {
  const f = fixture(); let resolveController; let creationStarted;
  const started = new Promise(resolve => { creationStarted = resolve; });
  f.avSession.createController = () => { creationStarted(); return new Promise(resolve => { resolveController = resolve; }); };
  const Adapter = await loadMediaAdapter(f); const adapter = new Adapter();
  const operation = adapter.control({command: WearableMusicCommand.PLAY}); await started;
  await adapter.close(); const late = f.create('top'); resolveController(late);
  await assert.rejects(operation, error => error.code === -21);
  assert.equal(late.destroyed, 1); assert.deepEqual(f.calls, []);
});

test('an unchanged system volume cannot be counted as a successful volume command',async()=>{
  const f=fixture();f.MusicVolumeBridge.request=()=>{};
  const Adapter=await loadMediaAdapter(f);const adapter=new Adapter();
  await assert.rejects(adapter.control({command:WearableMusicCommand.SET_VOLUME,volumePercent:100}),error=>error.code===-67);
  assert.deepEqual(f.calls,[]);await adapter.close();
});
test('playback controls reuse a valid controller instead of reenumerating sessions for each tap',async()=>{
  const f=fixture();let enumerations=0;const original=f.avSession.getAllSessionDescriptors.bind(f.avSession);
  f.avSession.getAllSessionDescriptors=async()=>{enumerations++;return await original();};
  const Adapter=await loadMediaAdapter(f);const adapter=new Adapter();adapter.start();
  await adapter.currentPlayer();
  await adapter.control({command:WearableMusicCommand.PAUSE});
  await adapter.control({command:WearableMusicCommand.PLAY});
  assert.equal(enumerations,1);
  assert.deepEqual(f.calls,[['top','pause'],['top','play']]);await adapter.close();
});
