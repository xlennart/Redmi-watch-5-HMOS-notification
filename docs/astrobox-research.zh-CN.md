# AstroBox 项目对照

2026-10-07：从 https://astrobox.online/values/ 中的项目链接进入，读取公开源码；未执行上游安装脚本，也未把用户密钥交给这些工具。

| 项目 | 对本项目的用途 | 边界 |
| --- | --- | --- |
| [AstroBox-NG Core](https://github.com/AstralSightStudios/AstroBox-NG-Module-Core) | 认证、加密、分层通信、通知发送与移除的直接参考 | Rust 核心，需要原生鸿蒙传输适配；上游发送成功也只表示入队，不证明手表显示 |
| [AstroBox-NG Pb](https://github.com/AstralSightStudios/AstroBox-NG-Module-Pb) | 完整通知字段、系统震动指令，以及后续健康协议研究 | 有协议定义不代表 Redmi Watch 5 固件支持某项功能 |
| [TatumRobotics](https://github.com/TatumRobotics/astrobox_miband_watch) | 独立震动指令与实际执行的诊断办法 | 目标为 Smart Band 10、Linux/Raspberry Pi，不能把其验收结果等同于本机手表 |
| [BandBurg](https://github.com/Bandbbs/bandburg) | 手机友好的连接、设备管理流程和 WASM 核心封装 | 公开接口主要为连接、安装、设备信息与快应用消息；快应用消息不等于系统通知。浏览器传输不能直接替代 HarmonyOS SPP |
| [AstroBox-NG Account](https://github.com/AstralSightStudios/AstroBox-NG-Module-Account) | 小米服务会话及设备认证材料获取 | 已用于账号路线研究；当前手机仍缺安全参数 -12，继续以已保存日志材料推进 |

## 本次用于通知诊断的差异

Core 的 `src/device/xiaomi/components/notification.rs` 使用单条 `Notification.data`、毫秒时间戳字符串、非空 `app_group`，且普通提醒不设置 `call_type`。本项目保留单条封装和全部必填字段，将固定测试日期改为 Unix 毫秒、分组改为自身包名、省略通话类型。以上是有来源的兼容性尝试，不是已确认的故障根因。

新增“测试手表震动”：认证成功后发送 `SYSTEM / TEST_VIBRATOR`（2/59），System 字段 41 的 VibratorEffect 包含两次 120 ms 短震，中间间隔 180 ms。仅本次执行，不改震动设置；ACK 仍只表示传输收包，必须由用户确认实际震动。

修改后的固定提醒已由用户明确确认显示在手表通知中心。日期、分组与通话类型一起调整，不能据此归因于某一个字段。

账号模块还实现了官方账号 Cookie 携带、`deviceId` 复用/生成和 `sdkVersion=accountsdk-18.8.15`。本项目在浏览会话缺安全参数时增加一次原生官方服务请求回退，只把 `passToken/userId/cUserId/deviceId/sdkVersion` 传给固定账号域名，不跟随未知重定向，不落盘、不记录。缺少完整 Cookie 时报告 -16 并保留日志路线；账号回退仍待真机验证，不要求通知验收等待账号登录。

Core、OronBox 和 TatumRobotics 在手机认证信息中声明 `app_capability = 0xffffffff`，本项目目前为旧兼容值 224。公开定义没有解释每个位的含义；本次保留它，以便先检验通知内容差异。若仍失败，需要单独对照能力声明，不能把不同改动的结果混作同一证据。

TatumRobotics 的指南涉及从原手机迁往另一台设备时取消配对及“连接新手机”。本项目已在同一手机通过密钥认证与配置读写，尚无证据表明必须重绑。当前没有执行解绑、重置或修改账号绑定；不能因指南采用迁移流程就直接套用到现有连接。

## 后续睡眠与运动接口

Pb 中存在 Fitness、SleepResult、运动与传感器结构，可以作为未来 `WearableDataProvider` 的协议适配参考。当前公开 Core 的通用数据接口主要是 Info、Status、Storage，不能当作已实现健康同步。继续使用本项目已有的睡眠、每日活动与单次运动统一模型；本轮不查询健康数据、不增加相关权限或页面。

## 可复核版本

- Core：`e0a5e7887390135241f75023f60b81ccf88f2fb9`
- Pb：`03a92010056dd41af114f6f46fd612104b27bd7b`
- TatumRobotics：`b2f6e220cdf54be23d85e628c0e851bf76e382bb`
- BandBurg：`a550c61fa48d7185f545614ef724f85ca01027a2`

公开参考检出在忽略目录 `.local/`。源码阅读用于协议事实核对；当前应用未嵌入上游 Rust、C#、WASM 或生成的 protobuf 文件。若以后直接复用代码，需要按对应 AGPL 与附加署名要求处理。
