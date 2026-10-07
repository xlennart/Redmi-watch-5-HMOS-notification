import test from 'node:test';
import assert from 'node:assert/strict';
import { FitnessRc4, fitnessSignatureInput, fitnessNonce, xiaomiLoginUrlAllowed, readFitnessLoginSession, fitnessAccountCookieHeader } from '../.cloud-build/out/MiFitnessCloud.js';

test('native account exchange limits cookies and keeps the existing login device identity', () => {
  const header = fitnessAccountCookieHeader('passToken=synthetic==; userId=123; deviceId=existing-device; tracking=omit', 'fallback-device');
  assert.match(header, /passToken=synthetic==/);
  assert.match(header, /deviceId=existing-device/);
  assert.match(header, /sdkVersion=accountsdk-18.8.15/);
  assert.equal(header.includes('tracking'), false);
  assert.equal(header.includes('fallback-device'), false);
  assert.throws(() => fitnessAccountCookieHeader('userId=123', 'fallback-device'), /LOGIN_ACCOUNT_COOKIE_MISSING/);
  assert.throws(() => fitnessAccountCookieHeader('passToken=x\r\nInjected=value; userId=123', 'fallback-device'), /INVALID_SESSION/);
});

test('RC4 drop1024 matches RFC 6229 published test vector and retains stream position', () => {
  const cipher = new FitnessRc4(new Uint8Array([1, 2, 3, 4, 5]));
  const output = Buffer.concat([cipher.crypt(new Uint8Array(7)), cipher.crypt(new Uint8Array(9))]);
  assert.equal(output.toString('hex'), '30abbcc7c20b01609f23ee2d5f6bb7df');
  cipher.clear();
});

test('service session accepts security from response header and distinguishes incomplete login', () => {
  const location = 'https://sts-hlth.io.mi.com/healthapp/sts?ticket=synthetic';
  const capture = { status: 200, body: '&&&START&&&' + JSON.stringify({code: 0, location}),
    extensionPragma: JSON.stringify({ssecurity: 'synthetic-security'}) };
  assert.equal(readFitnessLoginSession(capture).ssecurity, 'synthetic-security');
  assert.throws(() => readFitnessLoginSession({...capture, extensionPragma: ''}), /LOGIN_SECURITY_MISSING/);
  assert.throws(() => readFitnessLoginSession({...capture, body: '{"code":0,"_sign":"synthetic"}'}), /LOGIN_REQUIRED/);
  assert.throws(() => readFitnessLoginSession({...capture, body: '{"code":0,"notificationUrl":"synthetic"}'}), /VERIFICATION_REQUIRED/);
  assert.throws(() => readFitnessLoginSession({...capture, status: 403}), /LOGIN_HTTP_FAILED/);
  assert.throws(() => readFitnessLoginSession({...capture, body: JSON.stringify({code: 0, ssecurity: 'synthetic', location: 'https://attacker.test/'})}), /LOGIN_REDIRECT_MISSING/);
});

test('fitness request signatures order parameter names and nonce uses network byte order', () => {
  assert.equal(fitnessSignatureInput('/path', 'signed', new Map([['z', 'two'], ['a', 'one']])),
    'POST&/path&a=one&z=two&signed');
  assert.equal(Buffer.from(fitnessNonce(new Uint8Array([1,2,3,4,5,6,7,8]), 0x01020304 * 60000)).toString('hex'),
    '010203040506070801020304');
});

test('official account pages and health exchange are accepted while lookalike redirects are blocked', () => {
  for (const url of ['https://account.xiaomi.com/pass/login', 'https://sgp.account.xiaomi.com/pass/login',
    'https://sts-hlth.io.mi.com/healthapp/sts?ticket=synthetic']) assert.equal(xiaomiLoginUrlAllowed(url), true);
  for (const url of ['http://account.xiaomi.com/pass/login', 'https://account.xiaomi.com.attacker.test/',
    'https://account.xiaomi.com@attacker.test/', 'file:///test', 'https://sts-hlth.io.mi.com/other']) {
    assert.equal(xiaomiLoginUrlAllowed(url), false);
  }
});
