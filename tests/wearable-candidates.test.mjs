import test from 'node:test';
import assert from 'node:assert/strict';
import { isWristWearableCandidate } from '../.cloud-build/out/WearableCandidates.js';

test('watch and band candidates are not limited to Redmi Watch 5', () => {
  for (const name of ['REDMI Watch 5 A1B2', 'Redmi Watch 5 Lite', 'Xiaomi Smart Band 9',
    'MiBand 8', 'HUAWEI WATCH GT 5', 'HONOR Band 9', '小米手环 9', '华为手表',
    'Amazfit GTR 4', 'Fitbit Charge 6', 'Polar Vantage V3']) {
    assert.equal(isWristWearableCandidate(name), true, name);
  }
});

test('ordinary paired devices and head wearables are excluded', () => {
  for (const name of ['HUAWEI FreeBuds 6i', 'Galaxy Buds', 'Mi AirDots', 'My laptop',
    'HUAWEI Mate 70', 'Car Audio', '蓝牙耳机', 'Smart Glasses', 'Amazfit PowerBuds', 'Polar H10']) {
    assert.equal(isWristWearableCandidate(name), false, name);
  }
  assert.equal(isWristWearableCandidate('Unknown', 0x0714), false);
});

test('a wrist-watch device class covers unknown names and audio-class watches use names', () => {
  assert.equal(isWristWearableCandidate('', 0x0704), true);
  assert.equal(isWristWearableCandidate('Wearable', 0x0704), true);
  assert.equal(isWristWearableCandidate('REDMI Watch 5 A1B2', 0x0408), true);
  assert.equal(isWristWearableCandidate('Unknown', 0x0408), false);
});
