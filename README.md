# Redmi Watch 5 鸿蒙通知桥接

为 Mate 70 Pro 优享版（HarmonyOS 7、API 26）与 Redmi Watch 5（M2427W1、固件 3.100.105）开发鸿蒙原生通知桥接应用，暂定名称「腕间通知」。

当前阶段：通知转发、来源图标修复与手机音乐控制。默认构建保留不申请受限权限的基础模式；通知及音乐模式需对应 ACL 调试签名。

页面保留通知单页入口，音乐控制位于“设置 → 手机音乐控制”，不扩展健康、运动或歌曲文件管理。最新流程见[通知界面设计](docs/frontend/notification-focused.zh-CN.md)及[音乐控制与本轮验收](docs/phone-music-control.zh-CN.md)。

2026-10-12：核对官方 APK 后修复图标格式 0 的 protobuf 缺省处理、格式 8 字节序及格式 4 兼容；新增 Xiaomi 18/1 状态同步、18/2 播放控制、鸿蒙媒体会话适配及共享认证连接。原生编译、包含媒体 ACL 的调试签名与覆盖安装通过，**本轮图标实际显示、音乐控制和后台持续性尚未真机验收**。

**固定提醒和自有测试源自动转发已在 Redmi Watch 5 通知中心显示，其他应用及后台稳定性仍待验收。** 本机已完成 API 26 鸿蒙编译、调试签名、安装、通知授权与真实通知回调检查。手机日志认证材料已保存，SPP 协议版本 3、密钥认证及加密通知配置读写已通过真机验证。账号同步此前缺少安全参数，新增官方账号 Cookie 交换回退，仍待验证；日志路线已可用。见 [手机初始化与认证](docs/phone-onboarding.zh-CN.md)和[本机验证记录](docs/phone-watch-validation.zh-CN.md)。

长期目标是鸿蒙原生手表管理应用，逐步接替小米运动健康。通知优先；本轮实现手机音乐控制链路，其余健康、设置与资源管理仍保留独立接口，见 [功能扩展设计](docs/wearable-companion.zh-CN.md)与 [AstroBox 源码对照](docs/astrobox-research.zh-CN.md)。未验收的功能不对外标记为真机可用。

## 本地开始

要求：Node.js 22 或以上；本机验证使用 DevEco Studio / Command Line Tools 26.0.0.851、SDK 26.0.0.105（API 26）及 Studio 自带 JBR。签名在本地设置。

```powershell
npm ci --ignore-scripts
npm run check
npm test
```

在 DevEco Studio 中打开仓库根目录，先编译、签名并运行默认基础诊断模式。申请到 `ohos.permission.SUBSCRIBE_NOTIFICATION` 的 ACL 签名权限后，再执行 `npm run configure:notifications`，重新编译、签名和安装通知模式。

音乐模式另需 `ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC` 的 ACL；获准后执行 `npm run configure:music`，重新生成包含两项 ACL 的本地调试签名。它是 system_grant 权限，不能通过用户授权弹窗取得。基础与普通通知包保留原有权限范围。

完整的拉取分支、CLI 构建、签名、安装、测试与回传步骤见 [本地构建指南](docs/local-build.zh-CN.md)。

## 文档与协作

详细设计见 [实施方案](docs/implementation-plan.zh-CN.md)，包括权限与签名、协议研究、后台生命周期、模块架构、开发里程碑、测试矩阵、云端部署性价比及风险处理。

[原生前端接入](docs/frontend/integration.zh-CN.md)记录本轮“今日 / 设备 / 通知”、初始化与诊断页面和真实服务的连接；[页面设计](docs/ui-design.zh-CN.md)保留第一轮信息层级；[云端验证记录](docs/round1-validation.zh-CN.md)列出第一轮检查与未验证部分。

协作方式：云端负责源码与可运行核心测试，本地负责 DevEco 编译、签名和真机调试。本地每轮结果按 [验证报告模板](docs/local-validation-template.zh-CN.md) 回传，绑定同一代码版本。

继续开发前读取[本地至云端交接](docs/cloud-handoff.zh-CN.md)，其中区分已经验证的结果、最新安装的范围与尚未验收的功能。

推荐路线：手机端原生应用，将用户授权的通知发送至手表原有通知中心。先验证平台权限和手表协议，首版不开发手表应用。

## 当前工程

| 目录 | 用途 |
| --- | --- |
| `entry/src/main/ets/pages` | ArkUI 配置与接收诊断页面 |
| `entry/src/main/ets/extensionability` | 真正的通知订阅扩展，不输出正文 |
| `entry/src/main/ets/core` | 应用和云端测试共用的受约束源码 |
| `entry/src/main/ets/platform` | 应用沙箱中的元数据持久化 |
| `config`、`scripts` | 两种模式生成、核心编译和工程检查 |
| `tests`、`.github/workflows` | Node 测试与 GitHub Actions |

“接收次数”统计系统回调，不去重，不等同于独立消息数或手表送达数。通知元数据保存在应用沙箱，认证材料保存在手机系统安全存储中，不同步。日志导入在本机离线处理；账号同步使用联网权限。最终使用流程完全由手机完成，电脑仅用于开发。
