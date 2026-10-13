// Exact, reviewed package aliases only. Never use app display names or a package as a file path.
// Artwork provenance and the complete file manifest live beside the bundled rawfile catalog.
export function offlineIconFileForPackage(bundleName: string): string {
  switch (bundleName) {
    case 'com.tencent.wechat':
    case 'com.tencent.mm': return 'WeChat.png';
    case 'com.tencent.mqq': return 'QQ.png';
    case 'com.alipay.mobile.client': return 'Alipay.png';
    case 'com.dingtalk.hmos': return 'DingTalk.png';
    case 'com.taobao.taobao4hmos': return 'TaoBao.png';
    case 'com.sankuai.hmeituan': return 'MeiTuan.png';
    case 'com.tencent.hm.qqmusic': return 'QQMusic.png';
    default: return '';
  }
}

// Check the encoded dimensions before giving compressed artwork to the native decoder.
export function validateOfflineIconPng(bytes: Uint8Array): void {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 || bytes.length > 524288 || signature.some((value, index) => bytes[index] !== value)) {
    throw new Error('OFFLINE_ICON_PNG');
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(8) !== 13 || view.getUint32(12) !== 0x49484452) throw new Error('OFFLINE_ICON_PNG');
  const width = view.getUint32(16); const height = view.getUint32(20);
  if (width < 1 || height < 1 || width > 1024 || height > 1024) throw new Error('OFFLINE_ICON_SIZE');
}
