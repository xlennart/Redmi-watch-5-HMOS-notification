import test from 'node:test';
import assert from 'node:assert/strict';
import { AppCommand } from '../.cloud-build/out/AppState.js';
import { loadViewModel } from './helpers/load-view-model.mjs';

const flush = () => new Promise(resolve => setImmediate(resolve));
async function fixture({ material = true, active = false } = {}) {
  let resolveSession; let rejectSession;
  const session = new Promise((resolve, reject) => { resolveSession = resolve; rejectSession = reject; });
  const calls = { runs: 0, cancellations: 0, channel: 0 };
  class RelayStore {
    config() { return { enabled: false, musicEnabled: false }; }
    active() { return active; }
    setTestIcon() {}
  }
  class WatchCredentialStore { async present() { return material; } }
  class WatchTestSession {
    iconStatus = 'uploaded'; iconReason = 'transport_ack';
    async run() { calls.runs++; return session; }
    cancel() { calls.cancellations++; }
  }
  class WatchChannelProbe { async check() { calls.channel++; return 3; } cancel() {} }
  class WatchChannelError extends Error {}
  const ViewModel = await loadViewModel({ RelayStore, WatchCredentialStore, WatchTestSession, WatchChannelProbe, WatchChannelError,
    AppNotificationIcon: class {}, clearMiFitnessAccountSession() {}, MusicVolumeBridge: {setPanelVisible() {}},
    NOTIFICATION_PROBE_ENABLED: true, MUSIC_CONTROL_ENABLED: true,
    audio: { getAudioManager() { return { getVolumeManager() { return {}; } }; } } });
  const history = [];
  const model = new ViewModel({filesDir: '/synthetic'}, {}, state => history.push(state));
  model.selectedId = 'synthetic'; model.current.supported = true;
  model.current.testState = 'confirmed'; model.current.confirmationRequired = true;
  model.current.diagnosticIconStatus = 'cached'; model.current.diagnosticIconReason = 'old_result';
  return { model, history, calls, resolveSession, rejectSession };
}

test('direct vibration starts a fresh test, waits for the watch receipt and requires independent human confirmation', async () => {
  const f = await fixture(); f.model.dispatch(AppCommand.TEST_VIBRATION); await flush();
  assert.equal(f.model.snapshot().testState, 'running'); assert.equal(f.model.snapshot().testKind, 'vibration');
  assert.equal(f.model.snapshot().confirmationRequired, false);
  assert.equal(f.model.snapshot().diagnosticIconReason, '');
  f.resolveSession(); await flush();
  assert.equal(f.model.snapshot().testState, 'awaiting'); assert.equal(f.model.snapshot().confirmationRequired, true);
  f.model.dispatch(AppCommand.CONFIRM_VISIBLE);
  assert.equal(f.model.snapshot().testState, 'confirmed');
});

test('direct category test failure clears the previous visible result and confirmation', async () => {
  const f = await fixture(); f.model.dispatch(AppCommand.ENABLE_CATEGORIES); await flush();
  f.rejectSession(Object.assign(new Error('synthetic failure'), {code: -39, stage: 'synthetic'})); await flush();
  assert.equal(f.model.snapshot().testState, 'failed'); assert.equal(f.model.snapshot().testKind, 'notification');
  assert.equal(f.model.snapshot().confirmationRequired, false); assert.equal(f.model.snapshot().pendingKind, '');
  assert.equal(f.model.snapshot().noticeFailed, true);
});

test('navigation cancels a direct diagnostic and a late receipt cannot reintroduce its confirmation', async () => {
  const f = await fixture(); f.model.dispatch(AppCommand.TEST_VIBRATION); await flush();
  f.model.dispatch(AppCommand.HOME);
  assert.equal(f.model.snapshot().testState, 'cancelled'); assert.equal(f.calls.cancellations, 1);
  f.resolveSession(); await flush();
  assert.equal(f.model.snapshot().testState, 'cancelled'); assert.equal(f.model.snapshot().confirmationRequired, false);
});

test('channel-only checks clear old test and icon evidence without claiming a visible notification', async () => {
  const f = await fixture(); f.model.dispatch(AppCommand.CHECK_CHANNEL); await flush();
  assert.equal(f.calls.channel, 1); assert.equal(f.calls.runs, 0);
  assert.equal(f.model.snapshot().testState, 'idle'); assert.equal(f.model.snapshot().confirmationRequired, false);
  assert.equal(f.model.snapshot().diagnosticIconStatus, 'notRequested');
});

test('missing credentials and active shared sessions do not leave direct tests running', async () => {
  for (const options of [{material: false}, {active: true}]) {
    const f = await fixture(options); f.model.dispatch(AppCommand.TEST_VIBRATION); await flush();
    assert.equal(f.calls.runs, 0); assert.equal(f.model.snapshot().testState, 'failed');
    assert.equal(f.model.snapshot().confirmationRequired, false);
  }
});
