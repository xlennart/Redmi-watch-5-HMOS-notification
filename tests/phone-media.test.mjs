import test from 'node:test';
import assert from 'node:assert/strict';
import { chooseMediaSession, musicVolumeLevel, mediaVolumePercent } from '../.cloud-build/out/PhoneMedia.js';

test('system top active player wins; inactive historical sessions cannot receive commands', () => {
  const sessions = [
    {id:'stale', active:false, top:true, playing:true},
    {id:'playing', active:true, top:false, playing:true},
    {id:'top', active:true, top:true, playing:false}
  ];
  assert.equal(chooseMediaSession(sessions), 'top');
  assert.equal(chooseMediaSession(sessions.slice(0,2)), 'playing');
  assert.equal(chooseMediaSession(sessions.slice(0,1)), '');
  assert.equal(chooseMediaSession([]), '');
});
test('volume endpoint requests change one step, clamp safely, and never jump to maximum', () => {
  assert.equal(musicVolumeLevel(100, 5, 0, 15), 6);
  assert.equal(musicVolumeLevel(0, 5, 0, 15), 4);
  assert.equal(musicVolumeLevel(100, 15, 0, 15), 15);
  assert.equal(musicVolumeLevel(0, 0, 0, 15), 0);
  assert.equal(musicVolumeLevel(50, 5, 0, 15), 6);
  assert.equal(musicVolumeLevel(50, 8, 0, 16), 8);
  assert.equal(musicVolumeLevel(25, 8, 0, 16), 7);
  assert.equal(mediaVolumePercent(8, 0, 16), 50);
  assert.equal(mediaVolumePercent(-1, 0, 16), 0);
  assert.equal(mediaVolumePercent(50, 0, 16), 100);
  assert.throws(() => musicVolumeLevel(NaN,5,0,15));
  assert.throws(() => musicVolumeLevel(101,5,0,15));
});
