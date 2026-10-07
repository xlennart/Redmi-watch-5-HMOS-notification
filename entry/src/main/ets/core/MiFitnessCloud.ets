// RC4-drop1024 is required by the existing Xiaomi Fitness service protocol.
// It is not used for local credential storage.
export class FitnessRc4 {
  private state: number[] = [];
  private x: number = 0;
  private y: number = 0;

  constructor(key: Uint8Array, drop: number = 1024) {
    if (key.length === 0 || key.length > 256) throw new Error('INVALID_SESSION_KEY');
    for (let i = 0; i < 256; i++) this.state.push(i);
    let j = 0;
    for (let i = 0; i < 256; i++) {
      j = (j + this.state[i] + key[i % key.length]) & 255;
      const saved = this.state[i];
      this.state[i] = this.state[j];
      this.state[j] = saved;
    }
    for (let i = 0; i < drop; i++) this.next();
  }

  private next(): number {
    this.x = (this.x + 1) & 255;
    this.y = (this.y + this.state[this.x]) & 255;
    const saved = this.state[this.x];
    this.state[this.x] = this.state[this.y];
    this.state[this.y] = saved;
    return this.state[(this.state[this.x] + this.state[this.y]) & 255];
  }

  crypt(bytes: Uint8Array): Uint8Array {
    const output = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) output[i] = bytes[i] ^ this.next();
    return output;
  }

  clear(): void {
    this.state.fill(0);
    this.x = 0;
    this.y = 0;
  }
}

export function fitnessSignatureInput(path: string, signedNonce: string, params: Map<string, string>): string {
  const names = Array.from(params.keys()).sort();
  const pieces: string[] = ['POST', path];
  for (let i = 0; i < names.length; i++) pieces.push(`${names[i]}=${params.get(names[i])!}`);
  pieces.push(signedNonce);
  return pieces.join('&');
}

export function fitnessNonce(random: Uint8Array, milliseconds: number): Uint8Array {
  if (random.length !== 8) throw new Error('INVALID_NONCE');
  const nonce = new Uint8Array(12);
  nonce.set(random);
  new DataView(nonce.buffer).setUint32(8, Math.floor(milliseconds / 60000), false);
  return nonce;
}

export function xiaomiLoginUrlAllowed(value: string): boolean {
  return /^https:\/\/(?:[a-z0-9-]+\.)?account\.xiaomi\.com(?::443)?(?:\/|$)/i.test(value) ||
    /^https:\/\/sts-hlth\.io\.mi\.com(?::443)?\/healthapp\/sts(?:\?|$)/i.test(value);
}

export const FITNESS_LOGIN_URL: string = 'https://account.xiaomi.com/pass/serviceLogin?sid=miothealth';

// Only send the minimum account-session cookies back to the exact official account host.
export function fitnessAccountCookieHeader(cookies: string, fallbackDeviceId: string): string {
  if (cookies.length > 32768 || /[\r\n]/.test(cookies) || !/^[a-zA-Z0-9_-]{8,128}$/.test(fallbackDeviceId)) {
    throw new Error('INVALID_SESSION');
  }
  const values = new Map<string, string>();
  const allowed = ['passToken', 'userId', 'cUserId', 'deviceId'];
  const parts = cookies.split(';');
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i].trim(); const separator = part.indexOf('=');
    if (separator <= 0) continue;
    const name = part.slice(0, separator); const value = part.slice(separator + 1);
    if (allowed.includes(name) && value.length > 0 && value.length <= 8192) values.set(name, value);
  }
  if (!values.has('passToken') || !values.has('userId')) throw new Error('LOGIN_ACCOUNT_COOKIE_MISSING');
  if (!values.has('deviceId')) values.set('deviceId', fallbackDeviceId);
  values.set('sdkVersion', 'accountsdk-18.8.15');
  const result: string[] = [];
  values.forEach((value: string, name: string) => { result.push(`${name}=${value}`); });
  return result.join('; ');
}

export interface FitnessLoginCapture {
  status: number;
  body: string;
  extensionPragma: string;
}

export interface FitnessLoginSession {
  code?: number;
  _sign?: string;
  ssecurity?: string;
  cUserId?: string;
  location?: string;
  notificationUrl?: string;
}

// A successful web login can put service security in Extension-Pragma rather than its body.
export function readFitnessLoginSession(capture: FitnessLoginCapture): FitnessLoginSession {
  if (capture.status !== 200) throw new Error('LOGIN_HTTP_FAILED');
  if (capture.body.length > 2 * 1024 * 1024 || capture.extensionPragma.length > 16384) {
    throw new Error('INVALID_SESSION');
  }
  const session = JSON.parse(capture.body.trim().replace(/^&&&START&&&/, '')) as FitnessLoginSession;
  if (session.notificationUrl) throw new Error('VERIFICATION_REQUIRED');
  if (session._sign) throw new Error('LOGIN_REQUIRED');
  if (session.code !== 0) throw new Error('LOGIN_REJECTED');
  if (!session.ssecurity && capture.extensionPragma) {
    try {
      const extension = JSON.parse(capture.extensionPragma) as FitnessLoginSession;
      if (typeof extension.ssecurity === 'string') session.ssecurity = extension.ssecurity;
    } catch (_) {
      // An invalid optional header must not discard a valid body session.
    }
  }
  if (typeof session.ssecurity !== 'string' || session.ssecurity.length === 0) throw new Error('LOGIN_SECURITY_MISSING');
  if (typeof session.location !== 'string' || !xiaomiLoginUrlAllowed(session.location)) throw new Error('LOGIN_REDIRECT_MISSING');
  return session;
}
