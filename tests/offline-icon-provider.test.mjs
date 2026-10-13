import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadIconProvider } from './helpers/load-icon-provider.mjs';

async function fixture(valid = true) {
  const stored = new Uint8Array(valid ? readFileSync(new URL('../entry/src/main/resources/rawfile/notification-icons/WeChat.png', import.meta.url)) : [1, 2, 3]);
  const calls = { bundle: 0, decode: 0, pixelReleased: 0, sourceReleased: 0, files: [] };
  const resources = { async getRawFileContent(file) { calls.files.push(file); return stored; },
    getDrawableDescriptor() { throw new Error('unexpected native resource lookup'); } };
  const pixel = { getImageInfoSync() { return {size: {width: 1, height: 1}, pixelFormat: 4, alphaType: 2}; },
    readPixelsToAreaSync(area) { new Uint8Array(area.pixels).set([20, 40, 80, 255]); },
    async release() { calls.pixelReleased++; } };
  const image = { PixelMapFormat: {BGRA_8888: 4}, AlphaType: {PREMUL: 1, UNPREMUL: 2},
    createImageSource() { calls.decode++; return { async createPixelMap() { return pixel; }, async release() { calls.sourceReleased++; } }; } };
  const Provider = await loadIconProvider({image, bundleManager: {BundleFlag: {GET_BUNDLE_INFO_WITH_APPLICATION: 1},
    getBundleInfoSync() { calls.bundle++; throw Object.assign(new Error('denied'), {code: 201}); } }});
  return {Provider, resources, stored, calls};
}

test('known native package loads the bundled icon despite denied cross-app permissions and clears decoded buffers', async () => {
  const f = await fixture(); const provider = new f.Provider(f.resources, 'com.tencent.wechat');
  const bytes = await provider.load(176, 2);
  assert.equal(bytes.length, 123904); assert.deepEqual([...bytes.subarray(0, 4)], [20, 40, 80, 255]);
  assert.equal(provider.reason, 'encoded_offline'); assert.equal(f.calls.bundle, 0);
  assert.deepEqual(f.calls.files, ['notification-icons/WeChat.png']);
  assert.equal(f.calls.pixelReleased, 1); assert.equal(f.calls.sourceReleased, 1);
  assert.ok(f.stored.every(value => value === 0));
});

test('bad bundled PNG is rejected before native decoding and preserves a bounded failure reason', async () => {
  const f = await fixture(false); const provider = new f.Provider(f.resources, 'com.tencent.wechat');
  assert.equal(await provider.load(176, 2), undefined);
  assert.equal(provider.reason, 'offline_png_failed'); assert.equal(f.calls.decode, 0); assert.equal(f.calls.bundle, 0);
  assert.ok(f.stored.every(value => value === 0));
});

test('native Huawei Pay source uses its own official artwork without querying another application', async () => {
  const f = await fixture(); const provider = new f.Provider(f.resources, 'com.huawei.hms.payment');
  const bytes = await provider.load(176, 2);
  assert.equal(bytes.length, 123904);
  assert.equal(provider.reason, 'encoded_offline'); assert.equal(f.calls.bundle, 0);
  assert.deepEqual(f.calls.files, ['notification-icons/huawei/HuaweiPay.png']);
});

test('unmapped source never borrows another app icon or interprets the package as a rawfile path', async () => {
  const f = await fixture(); const provider = new f.Provider(f.resources, '../WeChat.png');
  assert.equal(await provider.load(176, 2), undefined);
  assert.equal(provider.reason, 'bundle_201'); assert.deepEqual(f.calls.files, []);
});
