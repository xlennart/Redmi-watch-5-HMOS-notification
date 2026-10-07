# ViewModel / 命令 / 事件契约说明 v0.1

本文件与 viewmodel-contract.d.ts 共同定义拟议的 UI 边界。它们是可评审的设计协议，当前尚未接入服务。TypeScript 声明不代表已经通过 ArkTS 编译。

## 数据流与职责

页面 → WristViewModel.dispatch(Command) → 应用 façade → 平台 / 功能服务。
服务 → 安全 Event / Snapshot → ViewModel 派生显示状态 → ArkUI V1 页面。

页面负责导航、读取安全快照、提交用户动作、展示确认与结果。ViewModel 负责只读派生状态、操作关联、快照版本、过期事件过滤和安全文案。后台负责权限与配对重校验、文件解析、安全存储、账号会话、蓝牙拥有权、协议报文、取消、重试策略与生命周期。

UI 模型中不允许出现 DeviceCredential、AuthKey、Cookie、passToken、userId、cUserId、原始日志、ZIP 字节、蓝牙报文、通知标题/正文。ImportCandidateView 只含后台候选引用与安全标签；账号完成命令不携带会话字符串。后台可以在自己的适配层拥有这些数据，但不能透传进页面、Toast、异常详情或诊断日志。

原 Index.ets 当前 private importedCredentials 与 clearImportedCredentials 会直接管理 authKey。后续移到 import façade 内部，页面改持 CandidateRef；这只是拟议边界，本轮没有编辑 Index 或存储实现。

## 快照不变量

| 事实 | 不变量 |
| --- | --- |
| RelayConfig.enabled | 表示持久转发意图；不是常驻连接 |
| RelayView.operational | 由后台事件或实际权限快照派生；事件未接入时为 unknown |
| HFP callConnection | 不代表消息 SPP 连接或认证状态 |
| CredentialView.storage | present 表示安全存储有材料；仍需验证与当前设备匹配 |
| ConnectionView.stage = ready | 仅代表尚未关闭的本次会话；关闭后不能维持“在线” |
| recentOutcome = transport_acknowledged | 传输收包证据；不得变成已显示或已送达 |
| delivery = device_accepted | 只在协议确实返回语义接受状态时使用；当前没有证据应保持未提供 |
| visibility = user_confirmed | 本次人工可见结果；不修改 ACK stage，不自动验证全部来源 |
| permission query 失败 | unknown/stale，保留上次已确认快照；不能以 false 或空数组覆盖 |
| 账号失败 / 导入取消 | 保留已存材料、现有授权与设备绑定，清理本次未保存暂存数据 |
| 未实现扩展 | implemented=false，页面不给可用操作；未知电量和健康值不补零 |

## 操作协议

1. 页面发出 requestId、expectedRevision、deviceGeneration 与动作 payload。
2. façade 返回 CommandReceipt，accepted 只表示接受处理，并给 operationId；页面进入 pending。
3. 服务完成真实查询/持久化/取消或业务错误后，发 OperationChanged 和对应快照事件。
4. ViewModel 只消费匹配当前目标代次、有效操作且 revision 不倒退的事件。失败保留用户选择和已提交的安全状态，提供明确恢复行动。
5. 操作过期、取消或页面销毁后，后台仍负责清理候选和敏感内存；页面忽略旧结果不会代替后台清理。

重复 requestId 不执行两次。读操作可以合并；写操作不能仅靠按钮 disabled 防重复。停止转发优先级高于普通刷新、发送和诊断排队。旧事件不得重新打开已停止的开关。

StatsChanged 的全局累计计数与特定设备的 connection/evidence 分开作用域；切换设备不能错误地把旧连接当新连接。计数事件仍使用后台有序 revision，不用客户端 Date.now() 决定覆盖顺序。

## 命令与当前实现映射

| 拟议动作 | 当前来源 | 状态 / 结果映射与欠缺 |
| --- | --- | --- |
| RefreshSnapshot | Index.readStats / refreshResults / refreshAuthorization；ProbeStore.read；RelayStore.config / stats；WatchCredentialStore.present | 组合安全快照；三项通知查询全部成功才提交授权快照 |
| DiscoverPairedDevices | Index.loadDevices；ACCESS_BLUETOOTH 请求；connection.getPairedDevices / getRemoteDeviceName / getRemoteDeviceClass；hfp 查询 | 临时 DeviceRef、候选与适配状态；扫描不能沿用旧选择 ID |
| SelectDevice | Index 设备选择事件中的 selectedId / selectedName | 只接收当前扫描的后台引用；选择后后台验证配对与材料绑定，不按名称当身份 |
| OpenNotificationSettings | Index.subscribeSelected / openAuthorization；notificationExtensionSubscription.subscribe / openSubscriptionSettingsWithResult | 关联目标与系统页面；系统返回再完整刷新，取消不假称授权成功 |
| StartRelay | Index.startRelay；isUserGranted；subscribeSelected；RelayStore.setConfig | 严格区分 configEnabled 与 armed/processing；当前配置写成功并未建立连接 |
| StopRelay | Index.stopRelay；RelayStore.setConfig(new RelayConfig())；WatchNotificationRelay 每 500ms 检查取消 | 当前先确认开关已停止；会话关闭确认另需事件，不能仅写文件就报告拥有权已释放 |
| UnsubscribeNotifications | Index.stopSubscription；unsubscribe | 先停转发，再停止系统订阅；不能把 unsubscribe 失败当成功 |
| ImportCredentialFromPicker | MiFitnessImportJob.pick / cancel；Index.importCredentials | 服务拥有文件与 DeviceCredential；事件只返回候选引用、模型与遮蔽标签 |
| SaveCredentialCandidate | Index.saveCredential；WatchCredentialStore.save | 校验引用有效、材料匹配再保存；安全存储成功后 present；禁止先显示已保存 |
| DiscardImportCandidates | Index.clearImportedCredentials | façade 清理 authKey 与候选；页面清掉标签引用 |
| OpenOfficialAccountLogin / CompleteAccountLogin | Index.openAccountLogin / browserLoginResponse / syncAccount；MiFitnessAccount.syncMiFitnessAccount / clearMiFitnessAccountSession | 官方视图与服务由平台协调；页面不返回登录响应字符串或 Cookie |
| DeleteCredential | Index.removeCredential；stopRelay；WatchCredentialStore.remove | 先停转发，再清理；删失败仍标 present/unknown 并解释可恢复错误 |
| RunDiagnostics(channel) | WatchChannelProbe.check / cancel | 协议版本结果；此检查不代表 AuthKey 认证成功 |
| RunDiagnostics(fixed_notification / vibration) | WatchTestSession.run / cancel | 通道传输结果与人为可见确认分开；不称实际执行已成功 |
| EnableNotificationCategoriesAndTest | WatchTestSession.run(..., enableNotifications=true) | 明确修改总开关与其他应用类别；经独占仲裁和单独确认后运行 |
| ConfirmVisibleResult | 当前无独立结构化 UI 契约 | 新增设计动作，记录诊断 operationId 的人工结果，不能自动变成长期能力验收 |
| CancelOperation | MiFitnessImportJob.cancel / WatchChannelProbe.cancel / WatchTestSession.cancel | 按具体操作取消；后台仍清理内存；没有系统 API 支持时不能声称可撤销文件选择器 |
| dispose | Index.aboutToDisappear 中前台取消与会话清理 | 取消导入/诊断、清理账号暂存与监听；不关闭已开启的通知转发 |

当前 RelayStore 只持久化 enabled / deviceId 与 acknowledged / failed / dropped / lastCode。它没有当前连接 stage、owner、最后 ACK 时刻、正文、密钥或人工确认结果。设计中的新字段必须由真实服务事件补齐；接入前保持 unknown/undefined，不能用已有 received 时间推断 lastAck。

## 与 WearableServices.ets 的对应

| UI 契约 | 既有服务契约 | 接入规则 |
| --- | --- | --- |
| FeatureEvidence | WearableFeatureEvidence | 显式把 undefined 映射 unknown；implemented 与 deviceVerified 各自独立 |
| ConnectionView | WearableSession.stage / onStage；WearableConnectionStage | UI 增加 unknown；当前临时 relay 尚未统一接到此 session 接口 |
| DeviceView | WearableDeviceInfo | batteryPercent / firmwareVersion 未提供就不显示虚构值 |
| DeliveryStage / receipt | WearableNotificationReceipt；WearableDeliveryStage | 当前运行实现只支持传输 ACK；不能消费未实现的 DEVICE_ACCEPTED |
| 只读来源摘要 | WearableNotification.sourceId / id | 页面不接收 WearableNotification 的 title/body；后台身份包括应用分身 |
| 截止时间与取消 | WearableOperation / WearableCancellation | 服务传入 deadlineMs 与 cancellation；页面发操作 ID，不自己构造蓝牙操作 |
| 通知类别诊断 | WearableSettingsService.readNotificationEnabled / setNotificationEnabled | 当前实际路径是 WatchTestSession；能力接口存在不代表已完成通用适配器 |
| 音乐计划页 | WearablePhoneMusicService / PhoneMediaAdapter | 没有实现和手机媒体授权之前只展示“尚未实现” |
| 健康计划页 | WearableDataProvider | 不查询、不补零，分页与单位转换待后续实现 |
| 资源计划页 | WearableResourceService | acknowledgedBytes 只是真实确认进度；未来支持取消与容量校验后才提供安装 |

既有 WearableDeviceAdapter 中 notifications / phoneMusic / settings / health / resources 是可选服务。只有实际存在服务、手机授权、目标支持与对应运行证据满足策略后才解锁操作。不能仅根据接口声明或协议定义显示可用。

## 诊断与转发的仲裁

当前源码通过读取 RelayConfig.enabled 拒绝诊断。这是已有防护，应保留正在进行的冲突修复。本设计不新增蓝牙连接，也不替换那项修复。

拟议 façade 维护同一通道 owner = none / relay / diagnostics。诊断的 preflight 必须同时满足：开关已停止、当前 relay 会话已关闭、没有另一个诊断拥有者。UI 停止后等待 owner=none，再执行诊断；“停止开关成功”与“拥有权释放”是两次不同确认。

StopRelay：先禁止新入队，清空待发条目，取消当前会话，等资源释放，再发已停止的 operational 状态。当前配置文件实现仅确认前半部；在后台补齐关闭事件前，UI 说明已发帧可能到表，不能伪造资源释放。诊断取消和 timeout 都要释放 owner。诊断结束不自动开启 relay。

页级 V1 busy 不能充当后台跨扩展/页面互斥锁。停止请求不能被普通 pending 刷新永久拒绝。后续单一连接拥有者复用 WearableSession，不为音乐或健康各建一条 SPP。

## 典型事件序列

开启：StartRelay → accepted/pending → 权限、配对与材料重校验 → 系统关联成功 → 配置写入成功 → RelayConfigChanged(true) → operational=armed → confirmed。没有新通知时不发布 ready。

收到通知：扩展过滤来源与自身 → 队列 → connecting → authenticating → queued/transport_acknowledged 或 failed → 会话清理 → currentSession=false，stage 回 unknown/disconnected。页面只收到安全统计与阶段，不收到正文。

停止：StopRelay → accepted → 配置禁用 / 新通知拒绝 → 清理队列 → 取消会话 → owner 释放 → operational=stopped。已经发出的帧可能执行，取消不是撤销设备提醒。

权限撤销：系统返回或发送前重查 → PermissionSnapshotChanged(denied) → configEnabled 保留原意图，operational=blocked。停止仍可用。单个来源被禁用仅更新来源，不误阻断所有来源。

导入取消：ImportCredentialFromPicker → pending → CancelOperation → cancelled → 清理后台候选 → 原存储 present 状态保持。晚到的解析事件不能重新把 cancelled 改成 confirmed。

账号失败：官方登录完成 → 服务交换 failed(-12/-16/-17 等受控代码) → 清理暂存会话 → 用户选择重试或日志路线；已有日志材料和 relay 配置不被清除。

## 安全错误映射

| 当前错误 / 条件 | 日常文案与恢复 | 技术详情 |
| --- | --- | --- |
| 201 | 当前操作未获允许；检查相关权限或设备支持 | 原生业务码 201；保持具体能力未确定 |
| 1600023 | 当前构建未启用通知订阅 | 模式与错误码；不要求普通用户理解 ACL 技术细节 |
| 全局 isUserGranted=false | 系统通知权限待恢复 | 不从单次 -41 推断 |
| -41，global=true，来源不在清单 | 该应用已不再获准 | 来源作用域；正文不提供 |
| IMPORT_CANCELLED | 导入已取消，原有材料保留 | phase=cancelled，不标 error |
| IMPORT_TIMEOUT | 日志处理超时，可重新导出再试 | 受控 timeout 分类 |
| 无效 / 过大日志 | 日志未能读取；解释 64 MB / 16 MB 限额 | 文件内容和 raw reason 不进页面 |
| 账号 -12 | 登录完成，但设备同步未完成；可用日志路线 | 服务会话阶段；官方回退待验证 |
| 账号 -16 / -17 | 同步未完成，可重试或导入日志 | 捕获/超时阶段；不显示 Cookie 细节 |
| 通道未知码 | 连接未完成，可查看诊断重试 | 仅安全 stage / code，不展示报文或原始异常 |
| 存储失败 | 尚未确认保存，请重试 | 页面保持旧快照，重新读取实际存储状态 |

错误文本走受控字典。Native BusinessError 与任意 Error.message 可能含数据，必须分类、脱敏后才输出，不能直接把 JSON.stringify(error) 放入状态。

## ArkUI V1 接入建议

使用显式 class 保存快照与 UI 操作，不直接复制 TypeScript union 的实现语法。页面已有 @Entry / @Component / @State，应沿用 V1。根状态所有者收到新 revision 时整体替换安全模型；子页面由只读对象或明确参数读取，再发 action，不直接创建平台服务。

生命周期独立于后台 relay。页面订阅先返回完整快照，再返回按序事件；重连监听后用 revision 重新同步。导航返回与窗口变化保留选择和滚动，不重复启动服务。进度、成功、失败与取消由操作事件控制，不能使用 animation.onFinish 或 UI 固定定时器决定真实操作结果。

本轮 HTML 与 native-preview 内的定时器仅用于明确标注的本地模拟。原生 PreviewViewModel 是可编译的 V1 演示实现，尚未实现本契约的真实适配器。生产 façade 成功路径必须以实际服务回执取代这些定时器。原生项目已实现快照替换、取消 epoch、返回处理、未保存候选清理与模拟通道互斥；真实后台释放、权限快照与材料绑定仍须按本契约接入。
