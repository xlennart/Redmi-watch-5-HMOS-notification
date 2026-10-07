import { connection, socket } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WatchVersionDecoder, watchVersionRequest } from '../core/WatchWire';

export class WatchChannelError extends Error {
  stage: string;
  code: number;
  constructor(stage: string, code: number) {
    super('WATCH_CHANNEL_FAILED'); this.stage = stage; this.code = code;
  }
}

export class WatchChannelProbe {
  private socketId: number = -1;
  private generation: number = 0;
  private cancelPending: (() => void) | undefined = undefined;

  cancel(): void {
    this.generation++;
    this.cancelPending?.();
    // check() releases its listener and socket in finally, including cancellation.
  }

  async check(deviceId: string): Promise<number> {
    if (!connection.getPairedDevices().includes(deviceId)) throw new WatchChannelError('重新选择配对手表', -20);
    const generation = ++this.generation;
    let timer = -1;
    const decoder = new WatchVersionDecoder();
    let listener: ((data: ArrayBuffer) => void) | undefined = undefined;
    try {
      this.socketId = await new Promise<number>((resolve, reject) => {
        let done = false;
        this.cancelPending = () => { if (!done) { done = true; reject(new WatchChannelError('通道连接已取消', -21)); } };
        timer = setTimeout(() => { if (!done) { done = true; reject(new WatchChannelError('连接消息通道超时', -22)); } }, 12000);
        socket.sppConnect(deviceId, { uuid: '00001101-0000-1000-8000-00805f9b34fb', secure: true, type: socket.SppType.SPP_RFCOMM },
          (error: BusinessError, id: number) => {
            if (done || generation !== this.generation) {
              if (!error && id >= 0) { try { socket.sppCloseClientSocket(id); } catch (_) { } }
              return;
            }
            done = true;
            if (error) reject(new WatchChannelError('连接手表消息通道', error.code)); else resolve(id);
          });
      });
      clearTimeout(timer);
      const id = this.socketId;
      return await new Promise<number>((resolve, reject) => {
        this.cancelPending = () => { reject(new WatchChannelError('通道检查已取消', -21)); };
        timer = setTimeout(() => { reject(new WatchChannelError('等待手表协议版本超时', -23)); }, 8000);
        listener = (data: ArrayBuffer) => {
          try {
            const frames = decoder.feed(new Uint8Array(data));
            for (let i = 0; i < frames.length; i++) {
              const frame = frames[i];
              if (frame.channel === 0 && frame.dataType === 0 && frame.payload.length > 0) resolve(frame.payload[0]);
              frame.payload.fill(0);
            }
          } catch (_) { reject(new WatchChannelError('解析手表协议版本', -24)); }
        };
        socket.on('sppRead', id, listener);
        socket.sppWriteAsync(id, watchVersionRequest().buffer).catch((error: BusinessError) => {
          reject(new WatchChannelError('发送协议版本查询', error.code));
        });
      });
    } finally {
      clearTimeout(timer);
      this.cancelPending = undefined;
      if (listener && this.socketId >= 0) { try { socket.off('sppRead', this.socketId, listener); } catch (_) { } }
      if (this.socketId >= 0) { try { socket.sppCloseClientSocket(this.socketId); } catch (_) { } }
      this.socketId = -1;
      decoder.clear();
    }
  }
}
