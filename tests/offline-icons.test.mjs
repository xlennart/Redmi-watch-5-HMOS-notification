import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { offlineIconFileForPackage, validateOfflineIconPng } from '../.cloud-build/out/OfflineNotificationIcons.js';

const base = new URL('../entry/src/main/resources/rawfile/notification-icons/', import.meta.url);
const catalog = JSON.parse(readFileSync(new URL('catalog.json', base), 'utf8'));
const huaweiCatalog = JSON.parse(readFileSync(new URL('huawei/catalog.json', base), 'utf8'));
const artwork = [...catalog.entries, ...huaweiCatalog.entries];

test('offline catalog is complete, bounded and matches pinned artwork digests', () => {
  function walk(url, prefix = '') {
    return readdirSync(url, { withFileTypes: true }).flatMap(item => item.isDirectory() ?
      walk(new URL(item.name + '/', url), prefix + item.name + '/') : [prefix + item.name]);
  }
  const files = walk(base).filter(file => file.endsWith('.png')).sort();
  assert.deepEqual(artwork.map(item => item.file).sort(), files);
  assert.equal(new Set(files).size, files.length);
  let total = 0;
  for (const item of artwork) {
    assert.ok(!item.file.includes('..') && !item.file.startsWith('/'));
    const bytes = readFileSync(new URL(item.file, base));
    assert.equal(bytes.length, item.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
    // The upstream catalog has one 2048px desktop icon; it is kept as source artwork,
    // but the mobile decoder must reject it until a smaller reviewed version is added.
    if (item.file === 'Tampermonkey.png') assert.throws(() => validateOfflineIconPng(bytes), /OFFLINE_ICON_SIZE/);
    else validateOfflineIconPng(bytes);
    total += bytes.length;
  }
  assert.ok(total < 16 * 1024 * 1024);
  assert.match(readFileSync(new URL('LICENSE.txt', base), 'utf8'), /Copyright \(c\) 2025 sooyaaabo/);
  assert.equal(huaweiCatalog.entries.length, 2);
  for (const item of huaweiCatalog.entries) {
    assert.equal(new URL(item.source).hostname.endsWith('.huawei.com'), true);
    assert.match(item.rights, /Huawei/);
  }
});

test('exact package mapping never guesses from a lookalike name or treats a package as a path', () => {
  const packages = ['com.tencent.wechat', 'com.tencent.mm', 'com.tencent.mqq', 'com.alipay.mobile.client',
    'com.dingtalk.hmos', 'com.taobao.taobao4hmos', 'com.sankuai.hmeituan', 'com.tencent.hm.qqmusic',
    'com.huawei.hmos.wallet', 'com.huawei.hms.payment', 'com.amap.hmapp', 'com.netease.cloudmusic.hm',
    'cn.wps.mobileoffice.hap', 'com.xingin.xhs_hos', 'yylx.danmaku.bili'];
  for (const pkg of packages) assert.ok(artwork.some(item => item.file === offlineIconFileForPackage(pkg)));
  assert.equal(offlineIconFileForPackage('com.tencent.wechat.fake'), '');
  assert.equal(offlineIconFileForPackage('../WeChat.png'), '');
  assert.equal(offlineIconFileForPackage('WeChat'), '');
  assert.equal(offlineIconFileForPackage('com.huawei.hms.payment.fake'), '');
  assert.equal(offlineIconFileForPackage('钱包'), '');
});

test('PNG validation refuses HTML, excessive dimensions, truncated headers and oversized files', () => {
  const bytes = readFileSync(new URL('WeChat.png', base));
  assert.throws(() => validateOfflineIconPng(Buffer.from('<html>upstream error</html>')), /OFFLINE_ICON_PNG/);
  assert.throws(() => validateOfflineIconPng(bytes.subarray(0, 32)), /OFFLINE_ICON_PNG/);
  assert.throws(() => validateOfflineIconPng(new Uint8Array(524289)), /OFFLINE_ICON_PNG/);
  const large = Buffer.from(bytes); large.writeUInt32BE(1025, 16);
  assert.throws(() => validateOfflineIconPng(large), /OFFLINE_ICON_SIZE/);
});
