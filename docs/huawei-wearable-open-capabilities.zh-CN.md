# 华为穿戴开放能力：能否提供跨应用实况数据

2026-10-14。根据用户要求继续排查公开开放能力。检查当前官方网页、DevEco CLI 官方本地知识库与 API 26 SDK；没有使用 REA，没有修改手机配对、申请新服务权益或安装实验包。

## 结论

本轮未找到公开的“第三方穿戴伴侣读取其他应用完整实况窗”的入口。Wear Engine 是面向华为穿戴设备的通信和设备能力接口，不是全手机通知/实况读取器；不能把 Wear Engine 的 NOTIFY 权限当成跨应用实况订阅权限。

对 Redmi Watch 5，目前可适用的第三方穿戴系统通知入口仍是项目已经接入的 `NotificationSubscriberExtensionAbility` / `notificationExtensionSubscription`。这个入口提供获准通知的标题、正文、来源和取消标识，没有完整 LiveView 模板数据。某家外卖来源的文字是否随实况更新投递，仍需验证。

本轮做了文档和 SDK 接口核对，没有进行 Wear Engine 调用：公开 SDK 没有与目标匹配的跨应用实况读取函数；现有目标手表也不是其华为穿戴目标。向不匹配的接口传入虚构 Client ID 或设备 ID，得到未申请服务/无绑定设备等错误，不能验证实况读取可行性。

## 三类能力的区别

| 能力 | 公开用途 | 对本项目的意义 | 能否提供完整跨应用实况 |
| --- | --- | --- | --- |
| Wear Engine Kit | 华为穿戴设备列表、状态、应用 P2P 消息/文件、模板化通知、传感器 | 目标设备与 Redmi 不匹配；消息通知是应用向设备发送自己提供的内容 | API 26 SDK 没有此读取/订阅方法 |
| ConnectivityKit 伙伴代理 | 配对设备注册，检测 BR 连接/BLE 广播，拉起 PartnerAgentExtensionAbility | 可作为未来通知传输生命周期研究；不应为了读取实况而改动现有配对注册 | 没有实况对象/通知内容回调 |
| NotificationKit 通知订阅扩展 | 已授权来源的系统通知接收、取消，适配第三方穿戴的数据传输 | 已有接入并具备本机 SUBSCRIBE_NOTIFICATION 签名权限 | 当前回调仅 title/text 与通知元数据 |

## Wear Engine 核对结果

官方业务简介及产品页明确以华为穿戴设备为开放对象。公开开放能力涵盖设备信息和状态、应用通信、模板通知、穿戴用户状态及传感器。[Wear Engine Kit](https://developer.huawei.com/consumer/cn/sdk/wear-engine-kit/)、[官方业务简介与支持设备](https://developer.huawei.com/consumer/cn/doc/connectivity-guides/service-introduction-0000000000018585)

本机 `@hms.health.wearEngine.d.ts` 提供 `DeviceClient`、`P2pClient`、`MonitorClient`、`NotifyClient`、`SensorClient`、`AuthClient` 等对象：

- `NotifyClient.notify(deviceRandomId, options)` 的输入由调用应用提供，包括标题、正文和可选按钮；输出是送往设备的模板通知。它不返回或订阅手机其他应用的活动内容。
- Monitor 订阅的是设备状态，P2P 订阅的是另一端应用明确发送的消息，均不能据此读取外卖应用的实况对象。
- 系统能力为 `SystemCapability.Health.WearEngine`；接入需要服务权益、Client ID 等条件。当前官方本地知识库说明该 Kit 不支持模拟器，不能把实况窗模拟器试验环境当成 Wear Engine 的可用目标。

上述范围足以排除该公开接口作为当前 Redmi 项目的实况数据入口，不代表华为内部或专门合作伙伴一定没有其他能力。

## 伙伴代理核对结果

`@ohos.FusionConnectivity.partnerAgent.d.ts` 的接口为支持性查询、绑定/解绑、设备是否绑定、设备控制是否开启等。`PartnerAgentExtensionAbility` 在发现已注册设备时由系统启动。`BusinessCapability` 声明媒体控制与电话控制，没有实况数据订阅字段。

官方本地开发指南明确其用途是让伴侣进程保持可唤醒，在业务需要时实现自己的数据传输；并有基础访问模式功能约束。它不是持久在线的万能保活或后台音量权限，也不增加读取其他应用活动的权限。本轮未调用 bindDevice，未改变手表原配对状态。

## 向官方确认时应问的具体问题

以下是技术问题草稿，未对外发送：

> 我们开发 HarmonyOS 原生第三方穿戴伴侣应用，通过系统授权的 NotificationSubscriberExtensionAbility 接收通知，目标设备是非华为品牌的 Redmi Watch 5。希望同步其他原生应用的外卖实况进展。API 26 模拟器测试显示 getActiveLiveView(id) 按调用应用隔离活动，现有通知回调仅提供 title/text。请问是否存在面向第三方穿戴伙伴的跨应用 LiveView 更新/结束订阅接口或合作权益？若存在，请提供接口、权限或权益名称、接入条件、数据范围，以及是否适用于非华为品牌穿戴设备。若只支持通知摘要，请确认源应用通过 LiveViewKit 更新实况时，是否会同步投递通知订阅回调及对应取消回调。

在取得具体接口规格前，不为“可能存在的合作接口”伪造 SDK 调用，不把 Wear Engine 服务开通或本应用 LiveView 发布权益的申请成功当成取得跨应用数据。
