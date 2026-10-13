# 华为实况窗到小米手表焦点通知：华为侧可行性研究

2026-10-13。本轮只检查华为官方文档、本机 API 26 SDK 与现有项目源码，没有继续执行 REA、命令行反编译或修改手机。小米焦点协议的二进制核验由用户指定的其他工具完成。用户提供的《小米超级岛推送到RedmiWatch5-分析报告》作为静态线索，不视为本轮独立验证的协议或真机结论。

## 结论

2026-10-14 后续实测：[API 26 模拟器跨应用实验](liveview-emulator-cross-app.zh-CN.md)。发布端成功创建/更新可见实况，自身查询成功，腕间通知以相同准确 ID 查询返回活动不存在；两应用同 ID 共存时，各自仅读到自身对象。该公开查询方法在本次环境下不能用作跨应用主动读取入口。下文早期负对照保留为实验历史。

2026-10-14 已收到目标格式补充分析，见[协议规格核对](super-island-protocol-review.zh-CN.md)。其中 field 14/15 与 V2 通用模板提供了更具体的线索；样例编码错误、内容块嵌套类型、进度归属、能力与移除指令仍需补证。目标格式线索不会自动解决下文的数据读取入口。

华为实况窗和小米超级岛在语义上相似：都围绕有生命周期的活动，用结构化内容、模板和版本更新展示服务进展。格式并不相同，但在获得合法来源数据和可靠目标协议的前提下，可以转换适配。

当前主要缺口是普通第三方应用取得其他应用完整实况数据的入口。项目正在使用的鸿蒙通知订阅回调提供标题、正文、来源和通知标识，没有完整 `LiveView`、进度、模板、图片、操作按钮或分享链接。不能因手机屏幕已显示这些元素，就假定本应用也能读取。

因此可推进的路线是：系统授权的通知文字 → 内部活动摘要 → 已核验的小米手表焦点载荷；在协议或能力尚未确认时继续普通通知。若未来来源应用明确提供完整活动对象，则增加结构化适配器，不必推倒文字路线。当前尚未实现或验收焦点载荷转换。

## 华为实况窗的工作原理

业务应用使用 `LiveViewKit` 构造 `LiveView`。对象中 `id` 标识活动，`event` 标识业务场景（外卖为 `DELIVERY`），可选 `sequence` 标识版本，`liveViewData` 描述内容。创建、更新、结束分别调用 `startLiveView`、`updateLiveView`、`stopLiveView`。设置版本时，更新和结束的新版本必须大于当前版本；未设置版本时不应虚构源端序列。

系统按 `liveViewData.primary` 渲染卡片，按可选 `capsule` 渲染状态栏胶囊；卡片包含主内容、辅助区和扩展模板。扩展区可以展示进度、强调文本、左右文本、比分、导航等。源应用或其业务服务掌握实时订单状态，不是显示胶囊本身产生订单数据。

本地更新依赖应用进程；来源应用也可通过 Push Kit 推送活动更新或结束。官方流程把活动 ID、pushToken、场景和业务状态关联到该应用的业务服务端。这是源应用的推送链路，不是向任意伴侣应用广播完整实况对象。[通过 Push Kit 更新实况窗](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/liveview-update-by-push)

API 26 支持 `LiveViewCardExtensionAbility` 的自定义扩展区：源应用返回页面路径和 `LocalStorage`，系统加载其页面。此类自定义 UI 不一定具有可通用转换的进度/文本模板语义，不能承诺所有实况窗逐元素复制到手表。

## 数据可映射性与实际可读性

以下是语义映射设计，目标 protobuf 字段编号及模板限制尚待外部分析核验；不能直接据此发送生产载荷。

| 华为来源字段/事件 | 内部表示 | 目标手表可能的表示 | 本应用当前通知回调可取得吗 |
| --- | --- | --- | --- |
| `NotificationInfo.bundleName/appIndex/hashCode` | 来源及活动关联键 | 来源标识、通知 ID/key | 可以；但 hashCode 尚未证明等于 LiveView.id |
| `NotificationInfo.content.title/text` | 标题、阶段摘要 | 基础内容、提示文字 | 可以，具体外卖是否投递有用文字待验证 |
| `LiveView.event` | 活动业务场景 | 目标模板选择 | 不在通知回调中；不得只凭 LIVE_VIEW 类别断定外卖 |
| `LiveView.id/sequence` | 源活动 ID、源版本 | 更新身份、目标更新顺序 | 不在通知回调中；本地递增序号须与源版本分开 |
| `primary.title/content`、`capsule` 文本 | 完整主内容/胶囊摘要 | 焦点标题、内容、ticker 等候选 | 没有通用完整读取入口；不能假定回调文字完全相同 |
| `ProgressLayout.progress`，范围 0–100 | 来源明确提供的进度 | 已核验模板中的进度字段 | 不在通知回调中；不能从“配送中”虚构百分比 |
| `ProgressCapsule.max/progress` | 进度数值及最大值 | 适配目标范围后的数值 | 不在通知回调中；不能与 ProgressLayout 直接混用 |
| `timer`、`TimerCapsule.time/isCountdown/isPaused` | 计时状态 | 目标支持的计时或文字降级 | 不在通知回调中；不能保证预计送达时间可推导 |
| 图片资源、颜色、节点图标 | 可选展示资源 | 目标支持的图片/颜色 | 不在通知回调中；现有离线应用图标不是活动图片 |
| `clickAction: WantAgent`、服务按钮 | 手机侧动作 | 经核验的手机动作代理 | 不在通知回调中；HarmonyOS WantAgent 不能序列化为 Android PendingIntent |
| `onCancelMessages(hashCodes)` | 通知移除事件 | 已核验的通知/焦点移除命令 | 有取消回调；但通知取消不能直接认定订单已完成 |
| `shareUrl` | 用户主动分享入口 | 链接或专门来源适配 | 不在通知回调中；没有通用 JSON 数据契约 |

## 已排查的替代入口

- `liveViewManager.getActiveLiveView(id)` 是按已知 ID 查询，不提供枚举或跨应用订阅 API。公开声明未足以证明可读取另一应用对象；本轮没有做跨应用运行验证，也没有把通知 hashCode 转成 LiveView.id 猜测调用。
- `notificationManager.getActiveNotifications()` 的 SDK 明确说明查询“当前应用”的通知，不能替代外卖应用通知/实况的全量读取。
- `SUBSCRIBE_NOTIFICATION` 管理系统授权的伴侣通知订阅。增加 LiveView 创建权益并不会让 `NotificationExtensionContent` 自动出现进度、图片或订单对象；没有证据表明再申请此发布权益即可解决完整数据读取。
- `LiveViewCardExtensionAbility.onRender` 是源应用向系统提供自定义页面，不是第三方实况监听器。
- API 26 `shareUrl` 是源应用提供的 HTTPS 进度页面链接：鸿蒙 7 接收者可从分享卡片打开，其他接收者可从消息链接打开。SDK 没有承诺该链接返回通用进度 JSON，也没有把用户分享转换成后台订阅。只能作为特定来源主动合作/分享路线继续研究。
- 官方白皮书中的实况分享、服务动态跨端流转，属于其规定的发布和分享链路，不能据此认为我们的应用可获取所有实况，或直接接入小米手表蓝牙协议。[官方实况分享说明](https://developer.huawei.com/consumer/cn/doc/guidebook/solution-0000002784570841)

## 后续应实现的接口边界

数据输入应分为系统通知摘要和来源明确提供的结构化活动；共同进入独立的活动模型，再交给小米手表编码器。保留来源、关联键、文字、接收时间、是否仅有摘要、可选源版本/进度/计时及移除状态。模型应明确字段缺失，目标编码器按实际能力降级，不能拿目标模板反向补造源数据。

通知摘要入口优先验证外卖应用的实况类别回调、文字变化及 hashCode 稳定性。实况更新须避免乱序、重复、过期积压；同一订单 ID 不能仅靠应用包名确定，多订单无法可靠关联时继续普通通知。进程重启后不能假装仍保存了可更新的表端卡片身份。具体限流、缓存和结束规则需结合目标协议验证后确定。

项目已有“实况类回调 / 含文字”计数，只保存数量，未增加订单正文日志。真实外卖回调、同活动更新、取消对应表端移除及锁屏接收仍未验收。文字入口和结构化入口的设计不要求用户为测试专门下单、提供账号会话或上传订单资料。

## 本轮证据与边界

本机 SDK：API 26，直接阅读以下声明，没有逆向二进制：

- `@hms.core.liveview.liveViewManager.d.ts`：`LiveView`、`LiveViewData`、`PrimaryData`、`ProgressLayout`、`ProgressCapsule`、`getActiveLiveView`、`shareUrl`。
- `@hms.core.liveview.LiveViewCardExtensionAbility.d.ts`：`CardInfo`、`onRender`。
- `notification/NotificationInfo.d.ts`、`notification/NotificationExtensionContent.d.ts`：伴侣通知回调边界。
- `@ohos.application.NotificationSubscriberExtensionAbility.d.ts`：接收与取消回调。
- `@ohos.notificationExtensionSubscription.d.ts`：授权与蓝牙订阅。
- `@ohos.notificationManager.d.ts`：当前应用通知查询。

SDK 证明接口形状与文档语义，不证明某家外卖应用会投递实况文字。用户报告中“小米载荷可随通知发送”提供了值得推进的静态线索，但成员 q/r 不等于已知线上的字段号，报告中的 Redmi Watch 5 V2 能力仍包含推断。本轮没有执行该报告中的命令，也没有验证手表焦点渲染。

## 2026-10-14 主动读取的真机负对照

用户要求尝试主动获取，且明确当前手机没有实况窗。使用本机临时诊断 HAP，仅调用只读公开 API，不创建、更新或结束活动、不轮询未知 ID：

| 查询 | 实际结果 | 能证明的范围 |
| --- | --- | --- |
| `liveViewManager.isLiveViewEnabled()` | 返回 true | 当前应用的实况开关查询可调用；不证明拥有全部场景发布权益或跨应用读取权限 |
| `notificationManager.getActiveNotifications()` | 成功，当前应用通知 0 条、实况类 0 条 | 与“当前应用”的查询语义一致，不是全手机活动枚举 |
| `liveViewManager.getActiveLiveView(0)` | 错误码 1003500009，活动不存在；调用耗时 63 ms | 活动不存在的负对照可正常返回，不是获取到了实况数据，也不是外卖端到端同步耗时 |

ID 0 只作为无活动时的负对照，未从 hashCode 推导，也未宣称属于其他应用。API 在负对照中未报权限错误，不能因此推定真实跨应用查询必然允许；此时返回不存在也不能据此推定跨应用一定拒绝。需取得一个经确认的源活动 ID，再在其有效期内读取、比较更新与结束，并明确验证调用者与源应用不同。

临时诊断 API 26 clean 编译与本机签名成功，实际覆盖安装、运行并读取只含状态/计数的诊断文件。首次连接掉线，重启电脑上的 HDC 服务后恢复；正式 0.1.2 HAP 随后重新覆盖安装并启动。源文件、模式和无签名构建配置已恢复，正式源码未接入主动轮询。没有实况正文、订单、账号会话或全手机通知清单落盘。诊断包和运行文件留本机忽略目录。
