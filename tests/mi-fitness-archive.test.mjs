import test from 'node:test';
import assert from 'node:assert/strict';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { fitnessArchiveEntries, logCrc32 } from '../.cloud-build/out/MiFitnessArchive.js';

function archive(name, content, method = 8, declaredSize = content.length) {
  const filename = Buffer.from(name);
  const packed = method === 8 ? deflateRawSync(content) : content;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(method, 8);
  local.writeUInt32LE(logCrc32(content), 14);
  local.writeUInt32LE(packed.length, 18);
  local.writeUInt32LE(declaredSize, 22);
  local.writeUInt16LE(filename.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(method, 10);
  central.writeUInt32LE(logCrc32(content), 16);
  central.writeUInt32LE(packed.length, 20);
  central.writeUInt32LE(declaredSize, 24);
  central.writeUInt16LE(filename.length, 28);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + filename.length, 12);
  end.writeUInt32LE(local.length + filename.length + packed.length, 16);
  return Buffer.concat([local, filename, packed, central, filename, end]);
}

test('reads stored and deflated Xiaomi log records with CRC integrity', () => {
  const content = Buffer.from('synthetic log 123');
  for (const method of [0, 8]) {
    const [entry] = fitnessArchiveEntries(archive('wearable/XiaomiFit.device.log', content, method));
    const decoded = method === 8 ? inflateRawSync(entry.bytes, { maxOutputLength: entry.size + 1 }) : entry.bytes;
    assert.deepEqual(Buffer.from(decoded), content);
    assert.equal(entry.crc, logCrc32(decoded));
  }
});

test('ignores unrelated logs and rejects oversized and malformed archives', () => {
  const content = Buffer.from('test');
  assert.equal(fitnessArchiveEntries(archive('account.log', content)).length, 0);
  assert.throws(() => fitnessArchiveEntries(archive('XiaomiFit.main.log', content, 8, 17 * 1024 * 1024)), /UNSUPPORTED_ARCHIVE/);
  const broken = archive('XiaomiFit.main.log', content);
  broken.writeUInt32LE(0xffffffff, broken.length - 6);
  assert.throws(() => fitnessArchiveEntries(broken), /INVALID_ARCHIVE/);
});
