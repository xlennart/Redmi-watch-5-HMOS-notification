import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { DeviceCredential, readMiFitnessLog } from '../core/MiFitnessCredentials';
import { FitnessRc4, fitnessNonce, fitnessSignatureInput, FitnessLoginCapture, FitnessLoginSession,
  readFitnessLoginSession, fitnessAccountCookieHeader, xiaomiLoginUrlAllowed, FITNESS_LOGIN_URL } from '../core/MiFitnessCloud';

interface LoginResult {
  code?: number;
  ssecurity?: string;
  cUserId?: string;
  location?: string;
  notificationUrl?: string;
}

export class MiAccountSyncError extends Error {
  stage: string;
  code: number;
  constructor(stage: string, code: number) {
    super('ACCOUNT_SYNC_FAILED');
    this.stage = stage;
    this.code = code;
  }
}

const DEVICE_PATH: string = '/app/v1/source/get_source_list';
export const MI_LOGIN_USER_AGENT: string = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

// The same-origin request retains HttpOnly cookies and exposes response headers to the app.
// Its bounded result stays in the hidden incognito page until immediately consumed and deleted.
export const MI_LOGIN_CAPTURE_SCRIPT: string = `(() => {
  delete window.__wristLoginCapture;
  if (location.protocol !== 'https:' || !/^(?:[a-z0-9-]+\\.)?account\\.xiaomi\\.com$/i.test(location.hostname)) return;
  const xhr = new XMLHttpRequest();
  xhr.open('GET', location.href, true);
  xhr.withCredentials = true;
  xhr.timeout = 15000;
  xhr.onload = () => {
    window.__wristLoginCapture = JSON.stringify({ status: xhr.status,
      body: xhr.responseText.length <= 2097152 ? xhr.responseText : '',
      extensionPragma: xhr.getResponseHeader('Extension-Pragma') || '' });
  };
  xhr.onerror = xhr.ontimeout = () => { window.__wristLoginCapture = JSON.stringify({status: 0, body: '', extensionPragma: ''}); };
  xhr.send();
})()`;

function cookieValue(cookies: string, name: string): string {
  const match = cookies.match(new RegExp(`(?:^|[;,\\n])\\s*${name}=([^;\\r\\n,]+)`));
  return match ? match[1] : '';
}

function bytes(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

async function digest(name: string, value: Uint8Array): Promise<Uint8Array> {
  const md = cryptoFramework.createMd(name);
  await md.update({ data: value });
  return (await md.digest()).data;
}

async function request(url: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
  const client = http.createHttp();
  try {
    return await client.request(url, options);
  } finally {
    client.destroy();
  }
}

export function clearMiFitnessAccountSession(): void {
  webview.WebCookieManager.clearAllCookiesSync(true);
}

function responseHeader(response: http.HttpResponse, name: string): string {
  const headers = response.header as Record<string, string>;
  const keys = Object.keys(headers);
  for (let i = 0; i < keys.length; i++) if (keys[i].toLowerCase() === name.toLowerCase()) return headers[keys[i]] || '';
  return '';
}

async function accountCookieSession(): Promise<FitnessLoginSession> {
  let cookies = ''; let header = ''; let random = new Uint8Array();
  try {
    cookies = webview.WebCookieManager.fetchCookieSync(FITNESS_LOGIN_URL, true);
    random = (await cryptoFramework.createRandom().generateRandom(16)).data;
    let deviceId = '';
    for (let i = 0; i < random.length; i++) deviceId += random[i].toString(16).padStart(2, '0');
    header = fitnessAccountCookieHeader(cookies, deviceId); cookies = '';
    const response = await request(`${FITNESS_LOGIN_URL}&_json=true`, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': MI_LOGIN_USER_AGENT, 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': header },
      expectDataType: http.HttpDataType.STRING, connectTimeout: 15000, readTimeout: 20000,
      maxLimit: 2 * 1024 * 1024, maxRedirects: 0, usingCache: false
    });
    header = '';
    const capture: FitnessLoginCapture = { status: response.responseCode,
      body: typeof response.result === 'string' ? response.result : '', extensionPragma: responseHeader(response, 'Extension-Pragma') };
    try {
      const session = readFitnessLoginSession(capture);
      if (!session.cUserId) session.cUserId = responseHeader(response, 'cUserId');
      return session;
    } finally { capture.body = ''; capture.extensionPragma = ''; response.result = ''; response.cookies = ''; }
  } finally { cookies = ''; header = ''; random.fill(0); }
}

// Tokens exist only within this operation. Device credentials are returned for explicit selection.
export async function syncMiFitnessAccount(loginPayload: string): Promise<DeviceCredential[]> {
  let accountCookies = '';
  let security = '';
  let serviceToken = '';
  let signedKey = new Uint8Array();
  let cipher: FitnessRc4 | undefined = undefined;
  let stage = '读取登录会话';
  try {
    stage = '获取运动健康会话';
    if (loginPayload.length > 4 * 1024 * 1024) throw new Error('INVALID_SESSION');
    const capture = JSON.parse(loginPayload) as FitnessLoginCapture;
    let response: FitnessLoginSession;
    try {
      try { response = readFitnessLoginSession(capture); }
      catch (error) {
        if ((error as Error).message !== 'LOGIN_SECURITY_MISSING') throw error as Error;
        stage = '通过官方账号会话获取运动健康凭据';
        response = await accountCookieSession();
      }
    } finally { capture.body = ''; capture.extensionPragma = ''; loginPayload = ''; }
    security = response.ssecurity || '';
    // Do not forward account cookies to the service exchange host.
    stage = '交换服务凭据';
    let stsUrl = response.location!;
    for (let hop = 0; hop < 4; hop++) {
      if (!xiaomiLoginUrlAllowed(stsUrl)) throw new Error('INVALID_LOGIN_REDIRECT');
      const sts = await request(stsUrl, {
        method: http.RequestMethod.GET, header: { 'User-Agent': MI_LOGIN_USER_AGENT }, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000, readTimeout: 20000, maxLimit: 2 * 1024 * 1024, maxRedirects: 0, usingCache: false
      });
      serviceToken = cookieValue(sts.cookies, 'serviceToken');
      if (serviceToken.length > 0) break;
      const location = (sts.header as Record<string, string>)['location'];
      if (sts.responseCode < 300 || sts.responseCode >= 400 || !location) break;
      stsUrl = location;
    }
    if (serviceToken.length === 0) throw new Error('LOGIN_REQUIRED');
    stage = '构造设备同步请求';
    const base64 = new util.Base64Helper();
    const random = (await cryptoFramework.createRandom().generateRandom(8)).data;
    const nonce = fitnessNonce(random, Date.now());
    const secretBytes = base64.decodeSync(security);
    const input = new Uint8Array(secretBytes.length + nonce.length);
    input.set(secretBytes);
    input.set(nonce, secretBytes.length);
    signedKey = await digest('SHA256', input);
    input.fill(0);
    secretBytes.fill(0);
    random.fill(0);
    const signedNonce = base64.encodeToStringSync(signedKey);
    const params: Map<string, string> = new Map();
    params.set('data', '{"page_size":50,"status":1}');
    params.set('rc4_hash__', base64.encodeToStringSync(await digest('SHA1', bytes(fitnessSignatureInput(DEVICE_PATH, signedNonce, params)))));
    const encrypted: Map<string, string> = new Map();
    cipher = new FitnessRc4(signedKey);
    const names = Array.from(params.keys()).sort();
    for (let i = 0; i < names.length; i++) encrypted.set(names[i], base64.encodeToStringSync(cipher.crypt(bytes(params.get(names[i])!))));
    encrypted.set('signature', base64.encodeToStringSync(await digest('SHA1', bytes(fitnessSignatureInput(DEVICE_PATH, signedNonce, encrypted)))));
    encrypted.set('_nonce', base64.encodeToStringSync(nonce));
    const form: string[] = [];
    encrypted.forEach((value: string, key: string) => form.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`));
    const cUserId = response.cUserId || cookieValue(accountCookies, 'cUserId');
    if (!cUserId || /[;\r\n]/.test(cUserId + serviceToken)) throw new Error('INVALID_SESSION');
    const devices = await request(`https://hlth.io.mi.com${DEVICE_PATH}`, {
      method: http.RequestMethod.POST, extraData: form.join('&'), expectDataType: http.HttpDataType.STRING,
      header: { 'User-Agent': MI_LOGIN_USER_AGENT, 'Content-Type': 'application/x-www-form-urlencoded',
        'region_tag': 'cn', 'HandleParams': 'true', 'Cookie': `cUserId=${cUserId}; serviceToken=${serviceToken}; locale=en_us` },
      connectTimeout: 15000, readTimeout: 20000, maxLimit: 2 * 1024 * 1024, maxRedirects: 0, usingCache: false
    });
    stage = '读取设备列表';
    if (devices.responseCode !== 200 || typeof devices.result !== 'string') throw new Error('DEVICE_SYNC_FAILED');
    const raw = devices.result.trim();
    const payload = base64.decodeSync(raw.startsWith('"') ? JSON.parse(raw) as string : raw);
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    const decryptor = new FitnessRc4(signedKey);
    const plain = decryptor.crypt(payload);
    try {
      const source = decoder.decodeToString(plain);
      const envelope = JSON.parse(source) as LoginResult;
      if (envelope.code !== 0 && envelope.code !== 200) throw new Error('DEVICE_SYNC_FAILED');
      return readMiFitnessLog(source);
    } finally {
      decryptor.clear();
      payload.fill(0);
      plain.fill(0);
    }
  } catch (error) {
    const reason = (error as Error).message;
    if (reason === 'LOGIN_REQUIRED') throw new MiAccountSyncError(stage, -1);
    if (reason === 'VERIFICATION_REQUIRED') throw new MiAccountSyncError(stage, -2);
    if (reason === 'LOGIN_SECURITY_MISSING') throw new MiAccountSyncError('服务响应缺少安全参数', -12);
    if (reason === 'LOGIN_REDIRECT_MISSING') throw new MiAccountSyncError('服务响应缺少有效交换地址', -13);
    if (reason === 'LOGIN_REJECTED') throw new MiAccountSyncError('小米服务未接受登录会话', -14);
    if (reason === 'LOGIN_HTTP_FAILED') throw new MiAccountSyncError('浏览会话请求未完成', -15);
    if (reason === 'LOGIN_ACCOUNT_COOKIE_MISSING') throw new MiAccountSyncError('网页登录未提供完整账号会话，仍可使用日志认证', -16);
    throw new MiAccountSyncError(stage, (error as BusinessError).code || -3);
  } finally {
    cipher?.clear();
    signedKey.fill(0);
    accountCookies = '';
    security = '';
    serviceToken = '';
    loginPayload = '';
    // Keep an incomplete login session for retry/2FA; completed sync is cleared by its caller.
  }
}
