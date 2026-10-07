# 第一轮：本地编译、签名和真机验证

这一轮交付的是手机端诊断工程。目标是尽快确认“应用可安装 → 系统可识别手表 → 通知权限可用 → 锁屏后回调可达”。手表消息协议还没有实现，不以手表震动作为这一轮的验收标准。

## 1. 取得云端分支

在项目父目录打开 PowerShell：

```powershell
git clone https://github.com/xlennart/Redmi-watch-5-HMOS-notification.git
cd Redmi-watch-5-HMOS-notification
git fetch origin
git switch --track origin/codex/round1-notification-probe
git rev-parse HEAD
```

已有仓库则进入该仓库，从 `git fetch origin` 开始；若本地已有同名分支，运行 `git switch codex/round1-notification-probe`。切换前先保存已有修改。无须合并 PR，也无须重新“发布云环境”。

## 2. 检查本地工具

| 工具 | 本轮配置与建议 |
| --- | --- |
| 系统与 SDK | 目标 API 26.0.0；`targetSdkVersion` 与 `compatibleSdkVersion` 均为 `26.0.0` |
| IDE | 建议 DevEco Studio 26.0.0 Release（26.0.0.821），或实际支持 API 26 的较新版本 |
| Java | JDK 21；优先使用与本地 DevEco/Command Line Tools 配套的版本 |
| Node | 22 或以上；CI 使用 22，本次云端运行使用 24.19.0 |
| DevEco CLI | 可使用已有 `devecocli`；本轮参照官方 npm 包 `@deveco/deveco-cli@1.3.0-stable` |
| Hvigor 工程模型 | 两个 `modelVersion` 暂沿用官方模板 `6.0.2`，**它不是设备 API 版本**。如本地同步要求迁移，用 IDE 支持的模型同时更新 `oh-package.json5` 和 `hvigor/hvigor-config.json5`，回传差异 |
| TLI | 本机已有，但这一轮不依赖未经核对的 TLI 参数；先记录 `tli --help` 所显示的版本与用途 |

```powershell
node --version
npm --version
java -version
devecocli --version
devecocli build --help
hdc list targets
```

缺少 PATH 中的 `hdc` 不代表 SDK 缺失；可以先使用 IDE 的设备管理。记录 DevEco 的“关于”版本及 SDK 管理中的 26.0.0 组件版本。

官方 CLI 1.3.0 的模板仍默认 API 22，创建命令的内置版本映射止于 API 24。本工程已直接配置 API 26，不需要重新执行 `create`；CLI 能否使用本机的新工具链，仍以本机构建结果为准。

## 3. 运行云端同款检查

在仓库根目录：

```powershell
npm ci --ignore-scripts
npm run check
npm test
```

预期核心/配置测试共 11 项通过，0 失败、0 跳过。`check` 检查 JSON/JSON5、资源引用、入口文件及模式一致性；`test` 将实际 `.ets` 核心机械映射为 `.ts` 编译后测试。这些检查不编译 ArkUI、不验证系统 API 或签名。

`npm` 安装的是云测试依赖；鸿蒙依赖由 IDE/OHPM 管理。不要把 npm 测试成功当成 HAP 构建成功。

## 4. 先运行基础诊断模式

默认仓库就是基础诊断模式，可显式恢复：

```powershell
npm run configure:baseline
npm run check
```

1. DevEco Studio → 打开工程，选择含 `build-profile.json5` 的仓库根目录。
2. SDK 管理中安装 HarmonyOS API 26 的编译组件，等待工程同步。工程不附带 `hvigorw` 包装器，使用本地 DevEco/CLI 配套工具。
3. 工程签名设置中选择本机开发者账号与手机，配置自动调试签名。包名为 `com.xlennart.wristnotifications`；基础模式不要求通知 ACL。
4. 手机开启开发者模式、USB 调试，连接电脑并接受设备调试授权。
5. 用 IDE 的运行按钮编译、安装并启动 `EntryAbility`。

也可在配置好本地 CLI 工具链与签名后，从根目录执行：

```powershell
devecocli build --product default --modules entry --build-mode debug
```

CLI 使用 `DEVECO_CLI_STUDIO_PATH` 或 `DEVECO_CLI_CLT_PATH` 定位本地工具；如尚未配置，按本机 CLI 帮助指向实际安装目录，不复制他人的绝对路径。若 CLI 和 IDE 版本不兼容，先以 IDE 构建为准。

使用 Command Line Tools 时，在相应工具已加入 PATH 后，官方底层命令为：

```powershell
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

若这些命令不在 PATH，使用配套工具的完整路径；不要安装一个不匹配的 npm Hvigor 来替代。

构建后检查真正的产物名：

```powershell
Get-ChildItem .\entry\build\default\outputs\default\*.hap
hdc list targets
```

通常签名包为 `entry-default-signed.hap`。确认文件存在且连接了目标手机，再安装：

```powershell
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.xlennart.wristnotifications
```

多个设备时使用 `hdc -t <设备ID>` 选择目标。不要安装 `unsigned.hap` 期待跳过签名。

### 基础模式验收

- 打开“腕间通知”：首页显示基础诊断模式；设备、授权、接收三卡正常，状态栏和底部内容不被遮挡。
- “查找已配对设备”应弹出蓝牙授权。拒绝时显示说明，允许后可重试。
- 蓝牙关闭时应显示失败提示。蓝牙打开、手表已在系统配对时，应列出设备；没有配对则显示引导。
- 选择正确的 Redmi Watch 5；检查通话连接状态。此处只读取 HFP 连接状态，不会主动切换电话音频。
- “查看验证详情 → 运行本地核心自检”应显示合成数据自检通过，接收统计保持不变。
- 试验系统字体放大、深色系统设置和返回页面。本轮为固定浅色主题，深色主题单独记录待完善；不宣称已有完整无障碍适配。

## 5. 获得权限后运行通知模式

`ohos.permission.SUBSCRIBE_NOTIFICATION` 是 **system_basic 级别的受限权限**。需要按华为智能手表配套应用的资格与当前账号流程申请，并让本地调试 Profile 包含对应 ACL；仅在清单写入权限、普通自动签名或用户点击同意都不能替代这一环节。

先确认本地可用 Profile，随后：

```powershell
npm run configure:notifications
npm run check
```

这会同时写入通知权限、`notificationSubscriber` 扩展与页面模式标记。重新同步工程，配置具备 ACL 的签名，重新构建和安装。切换命令不会申请权限、修改系统或更新签名。

1. 确保系统中手表仍已配对，支持 HFP 的设备保持 HFP 连接。不要为这个实验先解绑/重置手表；找不到合适配对状态时先回传现状。
2. 在应用查找并选择手表，点击“关联选中的手表”。地址由系统动态返回，不填截图中的实际 MAC。
3. 点击“打开通知授权”，启用“允许获取本机通知”，并选择一个用于测试的其他应用。请只授权必要应用。
4. 让该应用产生**系统通知**，回到“腕间通知”点“刷新接收记录”，检查累计回调、最近来源和时间是否变化。
5. 手机锁屏、应用退到后台，再产生一条通知。等待后解锁、刷新记录，对照之前的计数判断后台回调是否到达。
6. 取消来源应用的通知，观察取消条目；系统若合并通知或批量取消，回调次数可以不同于条目数。
7. 关闭来源应用授权、停止订阅，再产生通知，核对撤销和停止后的行为。允许正在处理的回调完成，不只凭瞬时刷新判断。
8. 放置一段时间观察日志中扩展销毁；再产生通知，检查计数仍可继续。计数保存在应用沙箱，不依赖一个永不退出的进程。

此模式仅把回调元数据写到应用文件，没有手表协议、认证或消息发送。若计数不变化，应先调查权限/连接/平台回调条件，不把它归因于手表通知功能。

### 常见结果

| 表现 | 先检查 |
| --- | --- |
| 安装时权限或签名错误 | Profile 是否允许受限权限，签名包与包名是否对应 |
| 201 | 蓝牙权限、通知 ACL、设备系统能力；该错误不单独证明是哪一种原因 |
| 1600023 | 是否安装了通知模式，清单中的扩展类型和入口是否正确 |
| 用户授权开启但计数为 0 | 是否真的产生系统通知、对应应用开关、设备关联/HFP、扩展回调日志 |
| `Receive callback persistence failed` | 回调已经进入扩展，接着检查文件访问和上下文；它不代表没有通知 |
| 页面能选设备，但手表无提醒 | 本轮的预期限制，下一轮才实现认证和通知发送 |

可用 IDE 日志或 `devecocli log --bundle-name com.xlennart.wristnotifications --keyword WristProbe --tail 100` 查看本应用事件。代码不打印通知正文、通知哈希或设备地址。发回日志前仍检查其他组件是否含个人数据。

## 6. 回传并取得下一轮更新

使用 [本地验证模板](local-validation-template.zh-CN.md)，附：

- `git rev-parse HEAD`、运行的模式、IDE/SDK/CLI/Hvigor/Java 版本。
- 第一个完整编译错误及上下文；若能运行，说明页面、蓝牙配对和通知测试分别到哪一步。
- 是否取得 ACL、是否弹出用户授权、关联设备数、通知接收/取消计数变化；必要时给脱敏截图。
- 锁屏、授权撤销、停止订阅和扩展重新启动的结果。
- 如本地修改了平台代码/工程模型，提交不含签名配置的源码差异，同步到同一分支。

**不要提交**证书、私钥、Profile、签名密码、AuthKey、账号凭据或完整设备 ID。证书文件已忽略，但 DevEco 可能把路径和密码写进已跟踪的 `build-profile.json5`；`.gitignore` 无法保护已跟踪文件，提交前必须查看该文件的差异。

更新前先恢复生成配置并查看本地改动：

```powershell
npm run configure:baseline
git status --short
```

没有待保存修改时：

```powershell
git pull --ff-only
npm ci --ignore-scripts
npm run check
npm test
```

若本地只改了签名配置，可将这些改动保存在**本地 stash**，再更新并恢复。例如仅改了根构建配置时：

```powershell
git stash push -m "local signing config" -- build-profile.json5
git pull --ff-only
git stash pop
```

如发生冲突，保留本机签名材料并核对云端工程变更，不要盲目覆盖。平台源码修改应先提交并同步，签名材料不能跟随这些提交。更新后需要通知测试时，重新切换 `configure:notifications`，再本地编译和签名。
