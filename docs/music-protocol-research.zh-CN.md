# Redmi Watch 5 音频控制协议核对

本轮目标是手机正在播放的媒体状态同步与手表遥控，不涉及歌曲文件安装、手表独立播放器、健康数据或账号登录。协议事实和运行效果必须分别判断：已核对静态协议并实现有边界的编码/解析；真机媒体会话权限、锁屏持续连接和手表实际显示仍需验证。

## 证据与报告修正

用户提供的小米运动健康分析报告已经补充小米新协议路径。同一个 APK 包含华米老协议和小米 protobuf 协议，报告里的 `syncHuami()` 和整数控制码不是本项目的实现依据。`MediaSyncManager.exeSync()` 根据 `isHuaMi()` 分流，另一分支为 `syncDefaultDevice()`。现有项目的 Xiaomi SPP v3 通道以及 [Gadgetbridge 的 Xiaomi protobuf 设备名单](https://freeyourgadget.codeberg.page/gadgetbridge_org/basics/topics/xiaomi-protobuf/) 支持将本块表按 Xiaomi protobuf 路线接入；本次没有通过运行小米运动健康来观察实际分支。

核对对象为用户给出的 APK：版本 `3.59.1`，版本代码 `359001`，SHA-256 `46100649d47000e8886d94cfbb34c18706e492a5d3aaa7f34cd4785841ffc254`。使用现有 REA CLI、调用者提供的 JADX JAR、JDK 21 作只读静态分析，没有运行 APK。原始 Evidence 与反编译内容仅保存在忽略目录 `.local/research/music/`。

| 证据 | 静态结果 | 边界 |
| --- | --- | --- |
| `ev_72dfacb2ef2069360fc6368c29aa5ca0087b8ba5cb993b5232396f123d9c8cdd` | APK 身份与清单 | 未验签、未执行 |
| `ev_496fcc9582107c780cb764ddf2fd0758b0b56b07f9ac68967bd2bf037700c730` | `MediaSyncManager` 有 `onControl(int)`、`onControl(x5h)` 两个重载 | 混淆名不是稳定接口 |
| `ev_8e3a139ed0374639f305d881dea7aa99920866aedded6fc76b338b76027cec0c` | `exeSync()` 对华米与其余设备分流 | 没有逐项展开型号名单 |
| `ev_f39b3f32a8d9240167a1b67c6e69ef5c5ec7ad73c50e08a616d129b9f0a3b6b7` | `syncDefaultDevice()` 使用 18/1；计算播放进度时检查 `b6h.c == 1`；无播放态而有标题时改为 2 | 表侧渲染没有运行证据 |
| `ev_57b92ed4db3cce2a5d6a246a28a278c32f9923956deda599b4c60ef7eaf3d023` | `onControl(x5h)` 对 0/1/3/4 调用对应 TransportControls；5 将手表目标百分比与当前百分比比较，每次只调一级音量，相等不调 | Android API 需改用 HarmonyOS 原生接口 |

**更新报告 3.2.2 把小米播放态写成 3，应修正为 1。** Android 媒体框架的播放状态 3、华米状态映射和小米 `b6h` 字段值不能混用。直接读取上述 APK 的 `syncDefaultDevice()` 可见，只有 `b6h.c == 1` 才增加经过的播放时间；其发送的就是包含该 `mPlayerInfo` 的 18/1 消息。它没有在发送处将 3 映射为 1。本项目继续发送 0=无会话、1=播放、2=暂停，与 Gadgetbridge 的 Xiaomi schema/实现一致。

本次未独立恢复 `b6h.writeTo()` 的全部字段编号。以下 protobuf 编号来自 Gadgetbridge 的公开协议定义；APK 的业务调用用于交叉核对类型、状态和控制语义。两种证据的范围分别记录，不把第三方协议定义冒称为 APK 中直接恢复的全部 schema。

## Wire contract

核对日期：2026-10-12。Gadgetbridge 以 Codeberg 为当前上游，本次读取 `master` 提交 `069af8dbb0e64b7fc41c61a1ae59313ac2f07215` 的 [顶层 Command](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/commit/069af8dbb0e64b7fc41c61a1ae59313ac2f07215/GBProtobufGenerator/src/main/proto/xiaomi.proto)、[wear_media.proto](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/commit/069af8dbb0e64b7fc41c61a1ae59313ac2f07215/GBProtobufGenerator/src/main/proto/xiaomi/wear_media.proto) 与 [XiaomiMusicService](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/commit/069af8dbb0e64b7fc41c61a1ae59313ac2f07215/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/xiaomi/services/XiaomiMusicService.java)。只提取互操作事实，编解码器由本项目独立编写，没有复制 AGPL 实现或生成类。

| 层级 | 字段与动作 |
| --- | --- |
| Command | 1=type，2=subtype，20=Music；type 固定 18 |
| subtype | 0=请求当前状态，1=手机发送状态，2=手表发控制键 |
| Music | 1=MusicInfo，2=MediaKey |
| MusicInfo | 1=state，2=volume，4=track，5=artist，6=position，7=duration |
| state / 单位 | 0=无会话、1=播放、2=暂停；进度、时长为秒；音量为 0..100 整数百分比 |
| MediaKey | 1=key，2=目标音量百分比（音量键必须携带） |
| key | 0=播放、1=暂停、3=上一首、4=下一首、5=音量；2 和其他未知值拒绝执行 |

报告的华米整数码 2=下一首、4=加音量、5=减音量不能用在这条链路。Xiaomi key 5 中的 100/0 常用来表示增/减目标；中间百分比同样按与当前值的大小比较只调一级，不直接跳到目标百分比。边界相等时不调音量，避免 100% 上的增加命令反而减音量。

公开 schema 和已查方法没有确认单独的“音乐页面关闭”通知。收到 18/0 可以请求立即同步，但不能把未知 subtype 猜成打开/关闭页面或据此触发播放操作。

AstroBox-NG 的 [当前主仓库](https://github.com/AstralSightStudios/AstroBox-NG/tree/d243cadb37eca679b56044e31b8790597ef31077) 是模块入口，本次公开递归树的 `src-tauri/modules` 只有占位文件，没有可用的音乐 schema。未把“没找到”扩张为整个项目不支持音乐，也没有从不完整入口猜测协议。

## 独立实现与验证

`entry/src/main/ets/core/WatchMusic.ets` 提供：

- `watchMusicStateCommand(input)`：接受 UTF-8 标题/艺术家字节、播放态、秒数和音量百分比。字符串最大各 512 字节，拒绝非法 UTF-8、NUL、非整数/负数/溢出。已知时长时把位置限定在时长内。无会话只发送 state=0 和音量，不残留上一首标题。
- `parseWatchMusicCommand(fields)`：仅解析已通过连接认证的 18/0、18/2；关键字段缺失、重复、类型不符、超长、畸形嵌套、未知键都返回 `unsupported`，不推断操作。解析时只清除内部副本，不改调用者持有的消息。
- `watchMusicVolumeDirection(requestedPercent, currentPercent)`：按百分比返回增加一级、减少一级或不变，适配平台音乐流音量档位。

`tests/watch-music.test.mjs` 的 6 项测试通过：核对独立 wire 字段、播放/暂停/无会话、时间边界、UTF-8 与整数边界、已知控制映射、未知/恶意消息拒绝以及音量边界。测试不会替代手机系统对其他应用媒体会话的访问权限，也不能证明手表已经显示或执行。HarmonyOS 媒体适配器、授权配置、公共蓝牙连接和前端状态由对应平台层实现，协议层不持有账号、密钥、通知正文或跨应用控制器。
