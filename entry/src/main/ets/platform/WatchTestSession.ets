import { socket, connection } from '@kit.ConnectivityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { WatchCredentialStore } from './WatchCredentialStore';
import { DeviceCredential } from '../core/MiFitnessCredentials';
import { WatchChannelError } from './WatchChannelProbe';
import { WatchVersionDecoder, watchVersionRequest } from '../core/WatchWire';
import { NotificationIconExchange, NotificationIconProvider, NotificationIconTransport, NotificationIconStatus } from '../core/WatchIcon';
import { WatchV2Frame, WatchV2Decoder, encodeWatchV2, watchSessionConfig, joinBytes,
  authCommand, protoBytes, protoInt, protoFloat, readProto, ProtoField, fieldBytes, fieldInt, clearProto,
  watchHmac, watchSessionKeys, equalBytes, watchNotificationCommand, WatchNotificationContent, watchVibrationTestCommand } from '../core/WatchProtocol';

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const digest = cryptoFramework.createMd('SHA256'); await digest.update({ data: data }); return (await digest.digest()).data;
}
function utf8(value: string): Uint8Array { return new util.TextEncoder().encodeInto(value); }
async function aes(key: Uint8Array, iv: Uint8Array, payload: Uint8Array, ccm: boolean, encrypt: boolean): Promise<Uint8Array> {
  const material = await cryptoFramework.createSymKeyGenerator('AES128').convertKey({ data: key });
  try {
    const cipher = cryptoFramework.createCipher(ccm ? 'AES128|CCM|NoPadding' : 'AES128|CTR|NoPadding');
    const ccmParams: cryptoFramework.AeadParamsSpec = { algName: 'AeadParamsSpec', nonce: iv, tagLen: 4 };
    const ctrParams: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
    await cipher.init(encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE,
      material, ccm ? ccmParams : ctrParams);
    return (await cipher.doFinal({ data: payload })).data;
  } finally { material.clearMem(); }
}

function fixedTestNotification(): Uint8Array {
  const timestamp = Date.now();
  const id = timestamp % 0x7fffffff;
  return watchNotificationCommand({ packageName: utf8('com.xlennart.wristnotifications'), appName: utf8('腕间通知'),
    title: utf8('腕间通知测试'), body: utf8('手机与手表消息通道已连通。'), date: utf8(timestamp.toString()),
    group: utf8('com.xlennart.wristnotifications'),
    key: utf8(`0|com.xlennart.wristnotifications|${id}|null|10000`), id: id });
}

// One explicit, foreground-only test. Every operation has a deadline; closing destroys session keys.
export class WatchTestSession {
  iconStatus: NotificationIconStatus = 'notRequested';
  private id: number = -1;
  private closed: boolean = false;
  private v2: boolean = false;
  private sequence: number = 0;
  private version: number = 0;
  private queue: WatchV2Frame[] = [];
  private decoder: WatchV2Decoder = new WatchV2Decoder();
  private versionDecoder: WatchVersionDecoder = new WatchVersionDecoder();
  private writeQueue: Promise<void> = Promise.resolve();
  private wake: (() => void) | undefined = undefined;
  private failure: WatchChannelError | undefined = undefined;
  private listener: ((data: ArrayBuffer) => void) = (data: ArrayBuffer) => { this.receive(data); };
  private keyMaterial: Uint8Array = new Uint8Array();
  private deadline: number = 0;

  cancel(): void {
    this.closed = true; this.failure = new WatchChannelError('认证测试已取消', -21); this.wake?.();
    if (this.id >= 0) { try { socket.sppCloseClientSocket(this.id); } catch (_) { } }
  }
  private send(data: Uint8Array): Promise<void> {
    const bytes = data.slice();
    const next = this.writeQueue.then(async () => {
      let timer = -1;
      try {
        if (this.closed) throw new Error('WATCH_CLOSED');
        await Promise.race([socket.sppWriteAsync(this.id, bytes.buffer), new Promise<void>((resolve, reject) => {
          timer = setTimeout(() => { reject(new WatchChannelError('发送手表协议数据超时', -30)); }, 5000);
        })]);
      } finally { clearTimeout(timer); bytes.fill(0); }
    });
    this.writeQueue = next.catch(() => { this.failure = new WatchChannelError('发送手表协议数据', -30); this.wake?.(); });
    return next;
  }
  private receive(data: ArrayBuffer): void {
    if (this.closed) return;
    try {
      if (!this.v2) {
        const frames = this.versionDecoder.feed(new Uint8Array(data));
        for (let i = 0; i < frames.length; i++) {
          if (frames[i].channel === 0 && frames[i].payload.length > 0) this.version = frames[i].payload[0];
          frames[i].payload.fill(0);
        }
      } else {
        const frames = this.decoder.feed(new Uint8Array(data));
        for (let i = 0; i < frames.length; i++) {
          const frame = frames[i];
          if (frame.type === 3) this.send(encodeWatchV2(1, frame.sequence, new Uint8Array())).catch(() => { });
          if (this.queue.length >= 32) throw new Error('WATCH_QUEUE_LIMIT');
          this.queue.push(frame);
        }
      }
      this.wake?.();
    } catch (_) { this.failure = new WatchChannelError('读取手表协议数据', -24); this.wake?.(); }
  }
  private async waitUntil(predicate: () => boolean, stage: string, timeout: number = 8000): Promise<void> {
    if (this.failure) throw this.failure;
    if (predicate()) return;
    await new Promise<void>((resolve, reject) => {
      const duration = Math.max(1, Math.min(timeout, this.deadline - Date.now()));
      const timer = setTimeout(() => { this.wake = undefined; reject(new WatchChannelError(stage, -23)); }, duration);
      this.wake = () => {
        if (!this.failure && !predicate()) return;
        clearTimeout(timer); this.wake = undefined;
        if (this.failure) reject(this.failure); else resolve();
      };
      this.wake();
    });
  }
  private async nextFrame(type: number, stage: string, sequence: number = -1, timeout: number = 8000): Promise<WatchV2Frame> {
    const matches = (frame: WatchV2Frame): boolean => frame.type === type && (sequence < 0 || frame.sequence === sequence);
    const rejects = (frame: WatchV2Frame): boolean => frame.type === 0 && (sequence < 0 || frame.sequence === sequence);
    await this.waitUntil(() => this.queue.some(matches) || this.queue.some(rejects), stage, timeout);
    const rejected = this.queue.findIndex(rejects);
    if (rejected >= 0) { this.queue.splice(rejected, 1)[0].payload.fill(0); throw new WatchChannelError('手表拒绝协议数据', -32); }
    const index = this.queue.findIndex(matches);
    if (index < 0) throw new WatchChannelError(stage, -23);
    return this.queue.splice(index, 1)[0];
  }
  private async sendCommand(command: Uint8Array, encrypted: boolean): Promise<number> {
    const sequence = this.sequence++ & 255;
    const key = this.keyMaterial.slice(16, 32);
    let payload = new Uint8Array();
    try {
      payload = encrypted ? await aes(key, key, command, false, true) : command.slice();
      await this.send(encodeWatchV2(3, sequence, joinBytes([new Uint8Array([1, encrypted ? 2 : 1]), payload])));
      return sequence;
    } finally { key.fill(0); payload.fill(0); command.fill(0); }
  }
  private async authResponse(subtype: number): Promise<Uint8Array> {
    for (let attempts = 0; attempts < 16; attempts++) {
      const frame = await this.nextFrame(3, '等待手表认证回应');
      let payload = new Uint8Array();
      const key = this.keyMaterial.slice(0, 16);
      try {
        if (frame.payload.length < 2 || frame.payload[0] !== 1) continue;
        const ciphertext = frame.payload.slice(2);
        payload = frame.payload[1] === 2 ? await aes(key, key, ciphertext, false, false) : ciphertext;
        const fields = readProto(payload);
        try {
          if (fieldInt(fields, 1) !== 1 || fieldInt(fields, 2) !== subtype) continue;
          const status = fieldInt(fields, 100);
          if (status > 0) throw new WatchChannelError('手表认证被拒绝', -34);
          return fieldBytes(fields, 3).slice();
        } finally { clearProto(fields); }
      } finally { frame.payload.fill(0); payload.fill(0); key.fill(0); }
    }
    throw new WatchChannelError('未收到有效认证回应', -34);
  }

  private async applicationReply(frame: WatchV2Frame): Promise<ProtoField[]> {
    if (frame.payload.length < 2 || frame.payload[0] !== 1 || (frame.payload[1] !== 1 && frame.payload[1] !== 2)) {
      frame.payload.fill(0); return [];
    }
    const key = this.keyMaterial.slice(0, 16); const ciphertext = frame.payload.slice(2); let plain: Uint8Array = new Uint8Array();
    try {
      plain = frame.payload[1] === 2 ? await aes(key, key, ciphertext, false, false) : ciphertext.slice();
      return readProto(plain);
    } finally { key.fill(0); ciphertext.fill(0); plain.fill(0); frame.payload.fill(0); }
  }

  private async sendIconCommand(command: Uint8Array): Promise<void> {
    const sequence = await this.sendCommand(command, true);
    const ack = await this.nextFrame(1, '等待图标指令收包', sequence, 2000); ack.payload.fill(0);
  }
  private async iconMassReply(timeoutMs: number): Promise<Uint8Array> {
    const until = Date.now() + Math.min(3000, timeoutMs);
    while (Date.now() < until) {
      const fields = await this.applicationReply(await this.nextFrame(3, '等待图标上传准备', -1, until - Date.now()));
      try {
        if (fieldInt(fields, 1) === 7 && fieldInt(fields, 2) === 0 && fieldInt(fields, 100) > 0) {
          this.failure = new WatchChannelError('手表应用拒绝通知', -38); throw this.failure;
        }
        if (fieldInt(fields, 1) !== 22 || fieldInt(fields, 2) !== 0) continue;
        if (fieldInt(fields, 100) > 0) throw new Error('ICON_MASS_REJECTED');
        const mass = readProto(fieldBytes(fields, 24));
        try { return fieldBytes(mass, 2).slice(); } finally { clearProto(mass); }
      } finally { clearProto(fields); }
    }
    throw new Error('ICON_MASS_TIMEOUT');
  }
  private async sendIconChunk(chunk: Uint8Array): Promise<void> {
    const sequence = this.sequence++ & 255;
    const body = joinBytes([new Uint8Array([2, 1]), chunk]);
    try {
      await this.send(encodeWatchV2(3, sequence, body));
      const ack = await this.nextFrame(1, '等待图标分片收包', sequence, 2000); ack.payload.fill(0);
    } finally { body.fill(0); }
  }
  private iconExchange(source: Uint8Array, provider: NotificationIconProvider): NotificationIconExchange {
    const transport: NotificationIconTransport = {
      sendCommand: (command: Uint8Array): Promise<void> => this.sendIconCommand(command),
      massReply: (timeoutMs: number): Promise<Uint8Array> => this.iconMassReply(timeoutMs),
      sendChunk: (chunk: Uint8Array): Promise<void> => this.sendIconChunk(chunk),
      md5: async (bytes: Uint8Array): Promise<Uint8Array> => {
        const digest = cryptoFramework.createMd('MD5'); await digest.update({ data: bytes }); return (await digest.digest()).data;
      }
    };
    return new NotificationIconExchange(source, provider, transport);
  }

  private async checkNotificationSettings(): Promise<string> {
    await this.sendCommand(joinBytes([protoInt(1, 7), protoInt(2, 6)]), true);
    const until = Date.now() + 8000;
    while (Date.now() < until) {
      const fields = await this.applicationReply(await this.nextFrame(3, '验证加密通知配置回应', -1, until - Date.now()));
      try {
        if (fieldInt(fields, 1) !== 7 || fieldInt(fields, 2) !== 6) continue;
        if (fieldInt(fields, 100) > 0) throw new WatchChannelError('手表拒绝通知配置查询', -37);
        const notification = readProto(fieldBytes(fields, 9));
        try {
          const screen = fieldInt(notification, 7) === 1 ? '通知亮屏开启' : '通知亮屏关闭或未报告';
          return `${screen}；${await this.readNotificationAppPolicy()}`;
        }
        finally { clearProto(notification); }
      } finally { clearProto(fields); }
    }
    throw new WatchChannelError('未验证加密通知配置回应', -37);
  }

  private async readNotificationAppPolicy(): Promise<string> {
    await this.sendCommand(joinBytes([protoInt(1, 7), protoInt(2, 3)]), true);
    const until = Date.now() + 8000;
    while (Date.now() < until) {
      let frame: WatchV2Frame;
      try { frame = await this.nextFrame(3, '读取手表通知应用策略', -1, until - Date.now()); }
      catch (error) { if ((error as WatchChannelError).code === -23 && !this.failure) return '应用过滤策略未报告'; throw error as WatchChannelError; }
      const fields = await this.applicationReply(frame);
      try {
        if (fieldInt(fields, 1) !== 7 || fieldInt(fields, 2) !== 3) continue;
        const status = fieldInt(fields, 100);
        if (status > 0) return `应用策略查询被拒绝（${status}）`;
        const notification = readProto(fieldBytes(fields, 9));
        const list = readProto(fieldBytes(notification, 6));
        let global = -1; let other = -1;
        try {
          for (let i = 0; i < list.length; i++) {
            if (list[i].id !== 1) continue;
            const app = readProto(list[i].bytes);
            try {
              const type = fieldInt(app, 1); const enable = fieldInt(app, 2);
              if (type === 0) global = enable;
              if (type === 5) other = enable;
            } finally { clearProto(app); }
          }
          if (global === 0) throw new WatchChannelError('手表通知总开关关闭，请点“开启手表通知并测试”', -39);
          if (other === 0) throw new WatchChannelError('手表过滤了其他应用，请点“开启手表通知并测试”', -40);
          return `通知总开关${global === 1 ? '开启' : '未报告'}，其他应用${other === 1 ? '允许' : '未报告'}`;
        } finally { clearProto(notification); clearProto(list); }
      } finally { clearProto(fields); }
    }
    return '应用过滤策略未报告';
  }

  private async observeTestResponses(progress: (message: string) => void, settings: string,
    icon: NotificationIconExchange | undefined = undefined, duration: number = 20000): Promise<void> {
    const until = Date.now() + duration; let summary = '暂未收到应用层回应';
    progress(`认证及加密通道通过；${settings}。通知数据已收包，正在等待后续回应。`);
    while (Date.now() < until && !this.closed) {
      let frame: WatchV2Frame;
      try { frame = await this.nextFrame(3, '等待测试提醒后续回应', -1, until - Date.now()); }
      catch (error) { if ((error as WatchChannelError).code === -23 && !this.failure) break; throw error as WatchChannelError; }
      const fields = await this.applicationReply(frame);
      try {
        const type = fieldInt(fields, 1); const subtype = fieldInt(fields, 2); const status = fieldInt(fields, 100);
        if (type === 7 && subtype === 0 && status > 0) throw new WatchChannelError('手表应用拒绝测试提醒', -38);
        if (type === 7 && icon && (subtype === 15 || subtype === 16)) {
          try { await icon.handle(subtype, fieldBytes(fields, 9)); }
          catch (_) { icon.status = 'failed'; }
          this.iconStatus = icon.status;
          if (this.failure) throw this.failure;
          if (this.closed) throw new WatchChannelError('通知会话已取消', -21);
          summary = icon.status === 'uploaded' ? '图标分片已收包，图标显示待验证' :
            (icon.status === 'unavailable' || icon.status === 'unsupported' || icon.status === 'failed' ? '图标不可用，保留默认图标' : '正在响应手表图标请求');
          progress(`认证及加密通道通过；${settings}。${summary}。`);
          if (icon.status !== 'notRequested' && duration < 20000) break;
          continue;
        }
        if (type === 7) summary = subtype === 16 || subtype === 15 ? `手表请求通知图标（7/${subtype}）` :
          `通知应用回应 7/${subtype}，状态 ${status < 0 ? '未报告' : status}`;
        progress(`认证及加密通道通过；${settings}。${summary}；保持连接中，请查看手表。`);
      } finally { clearProto(fields); }
    }
    progress(`认证及加密通道通过；${settings}。${summary}；测试会话已关闭，显示结果待确认。`);
  }

  async run(deviceId: string, progress: (message: string) => void, enableNotifications: boolean = false,
    vibrationOnly: boolean = false, notification: WatchNotificationContent | undefined = undefined,
    iconProvider: NotificationIconProvider | undefined = undefined): Promise<void> {
    this.deadline = Date.now() + 60000;
    let credential: DeviceCredential | undefined = undefined;
    let secret = new Uint8Array(); let phone = new Uint8Array(); let stage = '读取本机认证材料';
    let connectTimer = -1;
    try {
      credential = await new WatchCredentialStore().readForHandshake();
      secret = new Uint8Array(16);
      for (let i = 0; i < 16; i++) secret[i] = parseInt(credential.authKey.slice(i * 2, i * 2 + 2), 16);
      credential.authKey = '';
      if (!connection.getPairedDevices().includes(deviceId)) throw new WatchChannelError('重新选择配对手表', -20);
      stage = '连接手表消息通道'; progress('正在连接手表消息通道…');
      this.id = await new Promise<number>((resolve, reject) => {
        let finished = false;
        connectTimer = setTimeout(() => { finished = true; reject(new WatchChannelError(stage, -22)); }, 12000);
        socket.sppConnect(deviceId, { uuid: '00001101-0000-1000-8000-00805f9b34fb', secure: true, type: socket.SppType.SPP_RFCOMM },
          (error: BusinessError, id: number) => {
            if (finished || this.closed) { if (!error) { try { socket.sppCloseClientSocket(id); } catch (_) { } } return; }
            finished = true;
            if (error) reject(new WatchChannelError(stage, error.code)); else resolve(id);
          });
      });
      clearTimeout(connectTimer);
      socket.on('sppRead', this.id, this.listener);
      stage = '查询手表协议版本'; await this.send(watchVersionRequest());
      await this.waitUntil(() => this.version > 0, stage);
      if (this.version < 2 || this.version > 3) throw new WatchChannelError('当前认证暂不支持此协议版本', -35);
      this.v2 = true; this.versionDecoder.clear();
      stage = '建立手表协议会话'; progress('消息通道已连接，正在建立认证会话…');
      await this.send(encodeWatchV2(2, 0, watchSessionConfig()));
      const config = await this.nextFrame(2, stage);
      if (config.payload[0] !== 2) throw new WatchChannelError(stage, -36); config.payload.fill(0);
      stage = '发送认证随机数'; phone = (await cryptoFramework.createRandom().generateRandom(16)).data;
      await this.sendCommand(authCommand(26, 30, protoBytes(1, phone)), false);
      const verify = await this.authResponse(26);
      const account = readProto(verify); const remote = readProto(fieldBytes(account, 31));
      let confirmation = new Uint8Array(); let nonces = new Uint8Array();
      try {
        const watch = fieldBytes(remote, 1); const hmac = fieldBytes(remote, 2);
        stage = '校验手表与认证密钥'; progress('正在校验手表与认证密钥…');
        this.keyMaterial = await watchSessionKeys(secret, phone, watch, sha256);
        const decryptKey = this.keyMaterial.slice(0, 16);
        nonces = joinBytes([watch, phone]);
        try { confirmation = await watchHmac(decryptKey, nonces, sha256); } finally { decryptKey.fill(0); }
        if (hmac.length !== 32 || !equalBytes(confirmation, hmac)) throw new WatchChannelError('认证密钥与手表不匹配', -31);
        const encryptKey = this.keyMaterial.slice(16, 32); const nonce = new Uint8Array(12); nonce.set(this.keyMaterial.slice(36, 40));
        let info = new Uint8Array(); let sealed = new Uint8Array(); let proof = new Uint8Array();
        try {
          nonces.fill(0); nonces = joinBytes([phone, watch]); proof = await watchHmac(encryptKey, nonces, sha256);
          info = joinBytes([protoInt(1, 0), protoFloat(2, 26), protoBytes(3, utf8('HarmonyOS phone')), protoInt(4, 224), protoBytes(5, utf8('CN'))]);
          stage = '加密手机认证确认'; sealed = await aes(encryptKey, nonce, info, true, true);
          await this.sendCommand(authCommand(27, 32, joinBytes([protoBytes(1, proof), protoBytes(2, sealed)])), false);
        } finally { encryptKey.fill(0); nonce.fill(0); info.fill(0); sealed.fill(0); proof.fill(0); }
      } finally { verify.fill(0); clearProto(account); clearProto(remote); confirmation.fill(0); nonces.fill(0); secret.fill(0); phone.fill(0); }
      stage = '确认手表认证结果';
      const result = await this.authResponse(27); const auth = readProto(result); const device = readProto(fieldBytes(auth, 33));
      try {
        if (fieldInt(device, 1) !== 1 && fieldInt(auth, 8) !== 1) throw new WatchChannelError('手表未确认认证成功', -34);
      } finally { result.fill(0); clearProto(auth); clearProto(device); }
      if (vibrationOnly) {
        stage = '发送两次短震动测试';
        const sequence = await this.sendCommand(watchVibrationTestCommand(), true);
        const ack = await this.nextFrame(1, '等待手表确认震动指令', sequence); ack.payload.fill(0);
        progress('认证通过，震动指令已收包。请确认手表是否短震两次；收包确认不代表实际震动。');
        await new Promise<void>((resolve) => { setTimeout(resolve, 2000); });
        return;
      }
      if (enableNotifications) {
        stage = '开启手表通知及其他应用类别'; progress('正在开启手表通知及其他应用类别，并读取回确认…');
        for (let i = 0; i < 2; i++) {
          const app = joinBytes([protoInt(1, i === 0 ? 0 : 5), protoInt(2, 1)]);
          const command = joinBytes([protoInt(1, 7), protoInt(2, 4), protoBytes(9, protoBytes(5, app))]);
          const sequence = await this.sendCommand(command, true);
          const ack = await this.nextFrame(1, stage, sequence); ack.payload.fill(0); app.fill(0);
        }
      }
      stage = '验证加密通知通道'; progress('密钥认证通过，正在读取通知配置以验证加密通道…');
      const settings = await this.checkNotificationSettings();
      stage = '发送固定测试提醒'; progress('密钥认证通过，正在发送固定测试提醒…');
      const sequence = await this.sendCommand(notification ? watchNotificationCommand(notification) : fixedTestNotification(), true);
      const ack = await this.nextFrame(1, '等待手表确认测试数据', sequence); ack.payload.fill(0);
      const iconSource = notification ? notification.packageName : utf8('com.xlennart.wristnotifications');
      const icon = iconProvider ? this.iconExchange(iconSource, iconProvider) : undefined;
      if (notification) {
        // Process late icon queries instead of closing after a blind one-second delay.
        await this.observeTestResponses(progress, settings, icon, icon ? 4000 : 1000);
        return;
      }
      stage = '读取测试提醒后续回应'; await this.observeTestResponses(progress, settings, icon);
    } catch (error) {
      const code = (error as WatchChannelError).code || (error as BusinessError).code || -3;
      throw new WatchChannelError((error as WatchChannelError).stage || stage, code);
    } finally {
      clearTimeout(connectTimer); this.closed = true; this.wake = undefined;
      if (this.id >= 0) {
        try { socket.off('sppRead', this.id, this.listener); } catch (_) { }
        try { socket.sppCloseClientSocket(this.id); } catch (_) { }
      }
      this.id = -1; this.keyMaterial.fill(0); secret.fill(0); phone.fill(0);
      if (credential) credential.authKey = '';
      this.decoder.clear(); this.versionDecoder.clear();
      for (let i = 0; i < this.queue.length; i++) this.queue[i].payload.fill(0); this.queue = [];
    }
  }
}
