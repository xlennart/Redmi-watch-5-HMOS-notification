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
    case 'com.amap.hmapp': return 'Amap.png';
    case 'com.atomicservice.5765880207856344205': return 'LuckinCoffee.png';
    case 'com.atomicservice.6917584437461147371': return 'MeituanTakeaway.png';
    case 'com.baidu.netdisk.hmos': return 'BaiduNetDisk.png';
    case 'com.cainiao.cainiao4hmos': return 'CaiNiao.png';
    case 'com.chinamobile.cmcc': return 'ChinaMobile.png';
    case 'com.chinarailway.ticketingHM': return 'Railway12306.png';
    case 'com.ctrip.harmonynext': return 'CtripTravel.png';
    case 'com.hos.moonshot.kimichat': return 'Kimi.png';
    case 'com.jd.hm.mall': return 'JingDong.png';
    case 'com.netease.cloudmusic.hm': return 'NeteaseMusic.png';
    case 'com.quark.ohosbrowser': return 'QuarkBrowser.png';
    case 'com.sankuai.dianping': return 'DianPing.png';
    case 'com.sina.weibo.stage': return 'WeiBo.png';
    case 'com.taobao.idlefish4ohos': return 'Goofish.png';
    case 'com.tongcheng.hmos': return 'TongchengTravel.png';
    case 'com.wudaokou.hippo_hmos': return 'Freshippo.png';
    case 'com.ximalaya.ting.xmharmony': return 'HimalayaFM.png';
    case 'com.xingin.xhs_hos': return 'RedNote.png';
    case 'com.xunmeng.pinduoduo.hos': return 'PinDuoDuo.png';
    case 'yylx.danmaku.bili': return 'BilibiliPink.png';
    case 'cn.wps.mobileoffice.hap': return 'WPS_Office.png';
    case 'com.cbn.chinaradio': return 'ChinaBroadnet.png';
    case 'com.coolapk.hmclient': return 'CoolApk.png';
    case 'com.mubu.ohapp': return 'MuBu.png';
    case 'com.sdu.didi.hmos.psnger': return 'DiDi.png';
    case 'com.umetrip.hm.app': return 'Umetrip.png';
    case 'com.huawei.hmos.wallet': return 'huawei/HuaweiWallet.png';
    case 'com.huawei.hms.payment': return 'huawei/HuaweiPay.png';
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
