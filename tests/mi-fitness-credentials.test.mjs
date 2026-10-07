import test from 'node:test';
import assert from 'node:assert/strict';
import { readMiFitnessLog } from '../.cloud-build/out/MiFitnessCredentials.js';

const key = '0123456789abcdef0123456789abcdef';
const record = (overrides = {}) => ({ name: 'REDMI Watch 5', model: 'test.watch',
  detail: { mac: 'AA:BB:CC:DD:EE:FF', encrypt_key: key }, ...overrides });

test('reads nested and multiline device snapshots without confusing account cookies', () => {
  const source = `prefix ${JSON.stringify({ data: { devices: [record()] } }, null, 2)}\n` +
    JSON.stringify({ name: 'account', detail: { auth_key: key, mac: 'AA:BB:CC:DD:EE:FF' } });
  const found = readMiFitnessLog(source);
  assert.equal(found.length, 1);
  assert.equal(found[0].authKey, key);
  assert.equal(found[0].address, 'AA:BB:CC:DD:EE:FF');
});

test('requires target device identity, address and valid device key', () => {
  const inputs = [record({ name: 'REDMI Watch 5 Active' }), record({ name: 'Xiaomi Watch 5' }),
    record({ detail: { encrypt_key: key } }), record({ detail: { mac: 'EE:FF', encrypt_key: 'bad' } }),
    record({ detail: { mac: 'EE:FF', auth_key: key } })];
  assert.equal(readMiFitnessLog(inputs.map(value => JSON.stringify(value)).join('\n')).length, 0);
});

test('retains a redacted address without guessing and uses later key for the same address', () => {
  const newer = 'abcdef0123456789abcdef0123456789';
  const found = readMiFitnessLog(JSON.stringify(record({ detail: { mac: 'ee-ff', encryptKey: key } })) + '\n' +
    JSON.stringify(record({ name: 'REDMI Watch 5 A1B2', detail: { mac: 'EE:FF', encrypt_key: newer } })));
  assert.equal(found.length, 1);
  assert.equal(found[0].address, 'EE:FF');
  assert.equal(found[0].authKey, newer);
});

test('handles escaped braces in names and rejects excessive nesting', () => {
  assert.equal(readMiFitnessLog(`unrelated {garbage} ${JSON.stringify(record({ extra: '\\"{ }' }))}`).length, 1);
  assert.throws(() => readMiFitnessLog('{'.repeat(65)), /LOG_TOO_DEEP/);
});
