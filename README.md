# Redmi Watch 5 鸿蒙通知桥接

为 Mate 70 Pro 优享版（HarmonyOS 7、API 26）与 Redmi Watch 5（M2427W1、固件 3.100.105）开发鸿蒙原生通知桥接应用，暂定名称「腕间通知」。

当前阶段：**第一轮手机端诊断工程**。已提供 ArkUI 页面、系统配对设备选择、通知授权/订阅入口、通知扩展回调计数，以及与应用共用源码的云端核心测试。默认构建不申请受限通知权限，便于先在本地编译并安装。

**当前还不能向手表发送通知。** 完整鸿蒙编译、签名、通知权限、后台回调及目标手表协议均待本地验证。Node/TypeScript 测试通过不代表 ArkTS 或真机验证通过。

## 本地开始

要求：Node.js 22 或以上；建议 DevEco Studio 26.0.0 Release（26.0.0.821）、HarmonyOS SDK 26.0.0、JDK 21。签名在本地设置。

```powershell
npm ci --ignore-scripts
npm run check
npm test
```

在 DevEco Studio 中打开仓库根目录，先编译、签名并运行默认基础诊断模式。申请到 `ohos.permission.SUBSCRIBE_NOTIFICATION` 的 ACL 签名权限后，再执行 `npm run configure:notifications`，重新编译、签名和安装通知模式。

完整的拉取分支、CLI 构建、签名、安装、测试与回传步骤见 [本地构建指南](docs/local-build.zh-CN.md)。

## 文档与协作

详细设计见 [实施方案](docs/implementation-plan.zh-CN.md)，包括权限与签名、协议研究、后台生命周期、模块架构、开发里程碑、测试矩阵、云端部署性价比及风险处理。

[页面设计](docs/ui-design.zh-CN.md)定义第一轮信息层级、状态与后续扩展；[云端验证记录](docs/round1-validation.zh-CN.md)列出已执行检查与未验证部分。

协作方式：云端负责源码与可运行核心测试，本地负责 DevEco 编译、签名和真机调试。本地每轮结果按 [验证报告模板](docs/local-validation-template.zh-CN.md) 回传，绑定同一代码版本。

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

第一轮的“接收次数”统计系统回调，不去重，不等同于独立消息数或手表送达数。元数据只保存在应用沙箱，卸载应用后清除；本项目不申请联网权限。
