# 通知来源应用图标

## 本轮实现与验证边界

### 2026-10-07 后续修订

用户确认手表仍未显示来源应用图标，前一版不能视为图标功能验收成功。本次新增以下待实测修复：

- 在发送当前来源通知前主动发送 `7/15` 协商，避免完全依赖手表重复发出 `7/16`。来源仍限制为本次已授权应用，不枚举其他应用。
- `7/15` 回复若含字段 5 的分片长度，直接使用已协商参数上传；字段缺省时才进行独立 MASS prepare，避免忽略图标专属协商。
- 增加 PNG 格式 6；系统在内存中缩放并编码，检查 PNG 签名、尺寸与 64 KiB 上限。原始像素格式仍保留。
- Drawable 读取失败或没有 PixelMap 时尝试原始媒体资源解码；阶段与数值错误码分别记录，不保存原始异常、包名或图像。测试图标结果与后台最近图标结果分别显示。
- 区分 pending、cached、uploaded、unsupported、unavailable、failed。cached 是手表报告已缓存，uploaded 是分片 ACK，二者均不能替代可见图标。

本轮没有执行手机 UI 或手表显示检查；需要后续真实通知验证这些调整。资源不可访问、卓易通容器图标或固件要求其他格式仍可能保留默认图标。

以下保留初版数据路径，后续修订优先于其中的请求方式和格式限制。

用户报告自动转发通知已显示，但所有来源使用默认图标。源码检查发现两个缺口：收到 `7/15`、`7/16` 时仅记录诊断文字，没有回应或上传；自动转发收包后只等待一秒就关闭连接。本轮补齐图标请求处理，未连接手机、未安装或进行手表显示验证。

当前实现是原生应用图标资源上传，不是从通知正文、头像或网络图片中猜图标。通知扩展的 `NotificationInfo` / `NotificationExtensionContent` 只提供来源名称与文本，不提供图标。

## 数据路径

1. 按原流程认证并发送通知。收到文字数据的传输 ACK 后保留连接，自动转发最多等待 4 秒接收后续请求；固定测试保留原有 20 秒观察窗口。
2. 手表发 `NOTIFICATION / APP_ICON_APPLY (7/16)`，其 `Notification` 字段 16 的包名只能匹配当前已授权来源，允许有至少 8 字节的前缀截断。不会按手表任意给出的包名查询其他应用。
3. 回应 `PREPARE_APP_ICON (7/15)`，字段 14 带手表请求的包名，声明不压缩。手表字段 15 的回应指定状态、像素格式和正方形边长。
4. 通过本机 `bundleManager.getBundleInfoSync` 获取该来源的 `iconResource`，通过 `ResourceManager.getDrawableDescriptor(Resource)` 合成普通或分层应用图标。使用 API 26 的 `PixelMap.readPixelsToAreaSync` 读出 BGRA，按实际 alpha 类型处理预乘，保留宽高比缩放。
5. 上传协商使用 `MASS / PREPARE (22/0)`，数据类型 **50（通知图标）**。携带图标 MD5、原始字节长度，并检查手表回应的 MD5、状态、压缩及分片长度。
6. 数据通道使用 SPP v2/v3 的 `channel=2, opcode=1`，按照公开协议传送 `版本0 + 类型50 + MD5 + 长度LE + 像素 + CRC32LE`。分片有总数与当前序号，逐片等待对应序号的 ACK；未增加重试、解绑或任何固件操作。

收到图标分片 ACK 只记为 `uploaded`（收包），不能据此声称已显示。验证详情显示最近一次图标处理状态，持久化中没有图像、通知正文或密钥。

## 限制与回退

- 支持公开实现已覆盖的原始像素格式：0 / 1 RGB565，2 / 3 32 位颜色，7 / 8 带 alpha 的 8565。PNG、JPEG、EZIP 等尚未实现，收到此类要求时保留默认图标。
- 图标边长限制为 1–128 像素，来源解码图像每边最多 1024；单个上传不超过 64 KiB。分片限制在协议会话协商的 4096 字节之内。
- 图标转换与上传设置 8 秒调度预算，写入/ACK 等待另有超时，整个认证会话仍有 60 秒总期限。每个会话只回应当前来源一次，重复请求不会重复上传。停止转发会取消同一个会话。
- 当前只接受从偏移 0 开始的新上传。非零续传偏移、未知压缩、MD5 不一致、非法分片长度及上传失败都会取消已开始的图标上传，保持文字通知的已有收包结果。不同固件的续传长度定义尚未统一验证。
- 图标资源不可访问、应用已卸载或权限不足时保留默认图标，不改写来源身份。应用分身使用该原生应用的基础图标，不保证含分身角标；卓易通等容器内的 Android 图标未必能由原生包资源接口取得。
- 通知构建新增 `ohos.permission.GET_BUNDLE_INFO`，仅查询正在处理的已授权来源，没有枚举已安装应用。实际授权与跨应用图标读取仍需后续真机验证；基础诊断构建不增加该权限。取不到资源时不会阻断文字转发。
- 没有手机图标缓存或在线下载。手表是否缓存图标、是否即时替换当前提醒中的图标以及多次连接后的行为，均尚未验收。

## 离线证据

核心测试覆盖已知颜色/字节序/透明度、宽高比、大小及格式限制、CRC32 标准向量、MD5 与分片重组、模拟手表的完整请求上传、重复/外来/过短包名、缺失资源和上传拒绝/续传/压缩/NACK 回退。鸿蒙 API 26 的原生编译与本机签名另行执行，不等同于真机效果验证。

## 公开协议来源

本轮独立实现依据 [Gadgetbridge XiaomiNotificationService](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/xiaomi/services/XiaomiNotificationService.java)、其 `XiaomiDataUploadService`、`XiaomiBitmapUtils`、`XiaomiSppPacketV2`，并与 [AstroBox Pb](https://github.com/AstralSightStudios/AstroBox-NG-Module-Pb) 的 `wear_notification.proto`、`wear_mass.proto` 及 [AstroBox Core](https://github.com/AstralSightStudios/AstroBox-NG-Module-Core) 的 mass/install 模块对照。原生 API、字段和权限定义以本机 SDK 26 的声明核对。本轮没有直接复制上游代码，也没有把其他表型号的验证当作 Redmi Watch 5 实测。
