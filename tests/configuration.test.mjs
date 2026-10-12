import test from 'node:test';
import assert from 'node:assert/strict';
import { configuration } from '../scripts/configure-probe.mjs';

test('baseline does not request the restricted notification permission or register an extension', () => {
  const { manifest, modeSource } = configuration('baseline');
  const module = JSON.parse(manifest).module;
  assert.deepEqual(module.requestPermissions.map(p => p.name), ['ohos.permission.INTERNET', 'ohos.permission.ACCESS_BLUETOOTH']);
  assert.equal(module.extensionAbilities, undefined);
  assert.match(modeSource, /= false;/);
});

test('notification mode registers the public notification subscriber and ACL permission together', () => {
  const { manifest, modeSource } = configuration('notifications');
  const module = JSON.parse(manifest).module;
  assert.equal(module.requestPermissions.filter(p => p.name === 'ohos.permission.SUBSCRIBE_NOTIFICATION').length, 1);
  assert.equal(module.requestPermissions.filter(p => p.name === 'ohos.permission.GET_BUNDLE_INFO').length, 1);
  assert.equal(module.extensionAbilities.length, 1);
  assert.equal(module.extensionAbilities[0].type, 'notificationSubscriber');
  assert.equal(module.extensionAbilities[0].exported, true);
  assert.match(modeSource, /= true;/);
});

test('switching modes is deterministic and rejects a typo before producing configuration', () => {
  const original = configuration('baseline');
  configuration('notifications');
  assert.deepEqual(configuration('baseline'), original);
  assert.throws(() => configuration('notification'), /Mode must be/);
});

test('music mode explicitly opts into the ACL media controller and Bluetooth continuous task', () => {
  const { manifest, modeSource } = configuration('notifications-music');
  const module = JSON.parse(manifest).module;
  assert.ok(module.requestPermissions.some(p => p.name === 'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC'));
  assert.ok(module.requestPermissions.some(p => p.name === 'ohos.permission.ACCESS_NOTIFICATION_POLICY'));
  assert.ok(module.requestPermissions.some(p => p.name === 'ohos.permission.KEEP_BACKGROUND_RUNNING'));
  assert.deepEqual(module.abilities[0].backgroundModes, ['bluetoothInteraction']);
  assert.match(modeSource, /MUSIC_CONTROL_ENABLED: boolean = true;/);
  assert.ok(!JSON.parse(configuration('notifications').manifest).module.requestPermissions.some(p => p.name === 'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC'));
});
