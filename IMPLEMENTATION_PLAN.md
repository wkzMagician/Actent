# Actent 实现计划

## 1. 目标与边界

Actent 是跨设备的可编程内容路由器。下面是一个使用用例

```text
Share 到 Actent → 选择 Work → 本机执行或加密发送至远端
→ 远端执行/保存 → WorkReceipt 返回 → 手机上的 Share Work 转发
```

第一版支持 Android、Windows、Linux；iOS 是明确的后续目标。所有平台
相关实现必须隔离，Core 不得 import Android、Windows、Linux 或 iOS API。

## 2. 包与职责

### 2.1 Dartloom 新包

创建两个 Dartloom 包。它们是通用能力，不含 Actent 的 `Work`、
`ActentMessage`、Inbox 或 UI 领域逻辑。

| 包 | 职责 | 不负责 |
| --- | --- | --- |
| `dartloom_messaging` | 设备间 Packet、LAN/ntfy 连接、加密、重试、去重、附件分块与重组 | Actent 协议种类、Work、脚本、Inbox |
| `dartloom_pairing` | 设备身份、临时邀请、QR 展示/扫描、复制/粘贴邀请码、双向确认、LAN 配对发现 | 业务消息投递、Work Catalog |

`dartloom_messaging` 是一个发布包，内部可按 `core`、`ntfy`、`lan` 模块
组织，但不拆成多个独立发布包。Actent 通过 Dartloom capability 使用它：
`messaging.default`。`dartloom_pairing` 同样提供独立 capability/契约。

二维码第三方依赖封装在 `dartloom_pairing`：显示使用 `qr_flutter`，Android
扫码使用 `mobile_scanner`。Windows/Linux 不要求摄像头扫码，使用显示 QR 或
粘贴邀请码。Actent 只处理配对结果，不直接依赖这两个库。

### 2.2 Actent 代码边界

```text
lib/features/actent_core/       领域模型、Schema、状态库、路由、队列、Work 服务
lib/features/work/              WorkRunner 契约和共用执行调度
lib/features/work/desktop/      DesktopScriptRunner
lib/features/work/android/      Android Intent/Share/HTTP Runner
lib/features/work/ios/          未来 iOS Runner（第一版仅接口/占位，不注册）
lib/features/actent_platform/   Android Share 输入、FileProvider、各平台胶水
lib/app/                        Dartloom 工厂注册、页面与依赖组合
```

业务代码只依赖 capability 契约并通过 `Dartloom.get<T>(name: ...)` 获得实现。
可选平台能力使用 `Dartloom.maybeGet<T>()`。应用自有实现通过
`bootstrapDartloom(customFactories: ...)` 注册；不得编辑 Dartloom 生成文件。

## 3. dartloom 历史bug 解决

`createJsonReplicaStore` 的应用数据目录 TODO 必须解决，且 metadata 目录
必须位于业务数据根目录之外。桌面 resident 所需的图标 Dart define 也必须在
运行/打包配置中提供。

## 4. 数据、存储与 Schema

### 4.1 本地存储

消息和附件平时以正常文件形式保存在应用私有数据目录；**不做额外静态加密**。
仅在实际跨设备发送时，`dartloom_messaging` 加密 Packet 与附件。接收端解密后
再写入自己的普通 Actent 存储。

建议目录：

```text
actent/
  settings.json
  devices/<device-id>.json
  works/<work-id>.json
  messages/<message-id>.json
  runs/<run-id>.json
  attachments/<attachment-id>/<file>
```

私钥、relay token/password、被标为 secret 的 Work 环境变量不得写入这些 JSON，
只写入 Secure Settings。

消息和历史默认永久保留，用户手动删除。附件保留期可选 1 天、7 天、1 个月、
永久，默认 7 天。删除 Inbox 消息会删除其 runs 与无引用附件，但不删除 Work、
设备或配对配置。导出/导入 Work 与设备 endpoint 配置时，不导出私钥、token、
secret 或历史；重装是新设备，必须重新配对。

### 4.2 ActentMessage

定义并发布版本化 JSON Schema（首版 `schemaVersion: 1`）。每次不兼容变化
递增版本。一个系统 Share 产生一个 `ActentMessage`：一个主内容和零个或多个
附件。

```text
ActentMessage
  id, traceId, schemaVersion, createdAt
  source { kind, deviceId?, appName?, platform? }
  content { type: text | url | image | file | json, ... }
  attachments[] { id, name, mimeType, byteLength, handle }
  metadata
```

脚本可收到非敏感来源元数据。附件在跨平台 Schema 中为抽象 handle：桌面脚本
解析为只读本地路径；Android 外发给第三方应用时解析为临时 `content://` URI，
绝不暴露原始文件路径。

所有接收 Packet 先由 Dartloom 校验版本、接收者、认证标签与 Packet ID，解密后
再由 Actent 按 JSON Schema 校验。任何失败均不进入 Inbox、队列或脚本。

## 5. 设备身份与配对

每台设备自动生成稳定 device ID 与密钥对，用户可改显示名。每个设备有高熵、
随机的 ntfy inbox topic；端点、公开密钥与设备信息由配对建立。私钥只在 Secure
Settings 中。

### 5.1 两种同一协议的引导方式

1. **LAN 配对优先**：仅在用户进入“添加设备/允许配对”页面时，设备通过
   mDNS/DNS-SD 发布 `pairingAvailable`。另一设备选择发现项后建立临时 TLS
   直连，执行临时密钥握手；双方展示相同短验证码，双方确认后才成为已配对设备。
   mDNS 仅提供位置，不是信任依据。
2. **QR/粘贴 relay 回退**：任意设备可创建一次性邀请，同时显示 QR 和可复制的
   `actent://pair/v1/...` 字符串。另一设备可扫码或粘贴，适用于两台电脑、两台
   手机及无摄像头设备。邀请默认有效 10 分钟，含版本、临时 nonce、发起方公钥、
   relay URL 与临时 topic；不含长期私钥或密码。创建方确认加入方设备名与短指纹。

同一 LAN 时优先方式 1；发现/直连失败或跨网络时回退方式 2。没有“主设备”，
任意设备都能发起邀请。自定义 ntfy Server 的认证凭据由每台设备单独填写，绝不
放入 QR 或邀请码。

配对成功后，远端发送完整 Work Catalog；以后发送 Catalog delta。取消配对会
删除 endpoint、公开密钥和 Work 授权，取消未开始的远端请求，保留历史。

## 6. 传输与可靠性

### 6.1 契约

`dartloom_messaging` 对 Actent 暴露通用、不理解业务的加密 Packet：

```text
Packet { packetId, recipientId, ciphertext, createdAt }
```

Actent 在密文内部定义 `workRequest`、`workReceipt`、`catalogSnapshot`、
`catalogDelta` 等协议内容。Adapter 永远只接触 Packet。

实现：

- LAN：mDNS/DNS-SD 发现、TLS/TCP 直连；
- relay：ntfy HTTP POST 发布与 WebSocket 订阅；默认 `ntfy.sh`，每个设备可改
  server URL 并单独保存认证凭据；
- 路由：LAN 优先，3 秒连接/发送窗口失败立即转 ntfy。

每条消息使用一次性会话材料，采用既定的 X25519 + HKDF-SHA-256 + AES-256-GCM
端到端加密。Dartloom 管理密钥、加密、解密与通用 `SeenPacketStore`；Actent 不
维护协议去重清单。

### 6.2 失败、重试与去重

- ntfy 请求最多 3 次，单次超时 10 秒，间隔 2 秒、4 秒；
- 网络错误、超时、5xx 重试；429 遵从 `Retry-After`；其它 4xx 立即失败；
- HTTP 2xx 只代表 relay `accepted`，不代表远端已执行；
- 失败后本次发送确定为失败，不创建永久 Outbox；Inbox 可手动“重试”，重试是
  新发送尝试；应用重启时未完成发送标为失败；
- 通用 Packet 去重默认保存 7 天，并允许在设置中调整；
- relay 或附件限制导致失败时记录具体错误，不为服务端限制额外创建同步协议。

### 6.3 附件

单消息传输上限默认 20 MB，可设置。发送时先加密 manifest，再发送带 message ID、
序号和认证信息的加密块；只有全部块验证、重组成功后才写入 Inbox 或进入 Work
队列。未完成块 24 小时后删除并记录 `attachment_incomplete`。LAN 可传较大文件，
而 relay 失败照常返回明确错误。

Work 请求默认 24 小时过期，Work 可覆盖；过期请求回传 `expired` 而不执行。

## 7. Work 通用抽象

`Work` 是 Actent Core 的通用领域实体，而不是某个平台的模型。通用字段包括：

```text
id, revision, name, ownerDeviceId, allowedSourceDeviceIds
acceptedContentTypes, timeout, queueLimit, enabled
platformBindings, catalogVisibility
```

Work 由目标设备所有。手机只能查看远端发布的非秘密 Work 配置；桌面可编辑自己
拥有的 Work。所有非敏感字段可在 Catalog 中显示，环境变量值、token 与 secret
永远掩码。

`platformBindings` 让 Work 的身份、权限、队列、历史保持通用，而平台配置独立：

```text
desktop -> ScriptWorkConfig
android -> AndroidIntentWorkConfig | AndroidHttpWorkConfig
ios     -> IOSIntentWorkConfig | IOSHttpWorkConfig   (未来)
```

选择 Work 时：本机 Work 直接执行；远端 Work 发送加密 WorkRequest，并在远端
同一 Work 队列执行。请求携带 Work ID 与 revision；目标没有该 Work 或 revision
已变更则返回 `work_unavailable` / `work_changed`，绝不携带或接受源端下发的命令。
不在允许设备列表的请求返回 `authorization_denied`。

每个 Work 自己串行；不同 Work 可并行，但设备全局默认最多并行 2 个、可设置。
每个 Work 默认队列上限 10、可设置；溢出返回 `queue_full`。目标先持久化请求再
入队，桌面重启后恢复未完成队列。一个失败不会阻塞后续项。

仅发起设备可以取消自己的请求；目标设备总可本地取消。排队项取消后不执行，运行
中的脚本终止完整进程树。失败项目可从 Inbox 重新运行，产生新的请求和历史。

### 7.1 Null Work

Null 是唯一跨平台的无执行器例外。它可作为任何设备的目标：目标持久化原消息，
不调用脚本或平台 API，并回传 `WorkReceipt.status = stored`。

### 7.2 Desktop Script Work

桌面所有有副作用的 Work 都通过脚本。配置为绝对可执行路径、固定参数数组、工作
目录、Work timeout 与临时环境变量 map；不拼接 shell command。Python、PowerShell(Windows)/Bash(linux)
与通用可执行文件为内置模板。保存时验证可执行文件存在，但绝不自动安装运行时或
依赖。

协议固定：向 stdin 写入一个 UTF-8、版本化 `ActentMessage` JSON 文档后关闭 stdin；
退出码 0 成功，非 0 失败。stdout 始终读取以免阻塞但丢弃；stderr 仅保留最多 8 KB
本地失败摘要。环境变量仅注入子进程，不改系统环境；普通值存配置，secret 值存
Secure Settings。

### 7.3 Mobile Intent/HTTP Work

手机端不支持任意 shell。Android（以及未来 iOS）Runner 提供 Null、Intent 与 HTTP
API Work。不同平台提供不同的 Work 模板：桌面为 Script/Python/PowerShell，手机
为 Share、目标 App、Deep Link 和 HTTP API。

Android 使用统一 `AndroidIntentSpec`，

```text
action, dataUriTemplate, mimeType, categories,
extras, packageName?, componentName?, chooser,
attachmentPlacement
```

显式配置 package/component 时调用目标 App；无目标配置时是隐式 Intent；`chooser:
true` 与 `ACTION_SEND`/`ACTION_SEND_MULTIPLE` 即为 Share Work。Share 是手机
Intent Work 模板，可在 Work Picker 中选择。用户可配置 action 和字段；extras
支持字符串、数字、布尔、字符串列表、URI/附件引用、JSON 字符串，未知 Parcelable
明确报不支持。附件通过 FileProvider 的临时 `content://` URI 与读权限交付。

HTTP Work 支持 URL、方法、headers、JSON body 模板、timeout、Secure Settings
secret 引用；仅回传 HTTP 状态和安全摘要。模板只允许安全占位符，不运行 Dart/JS
表达式。

本机点击手机 Work 时立即执行。远端手机的请求在 Actent 前台可立即尝试执行；应用
后台时不常驻连接、不开 FCM，下一次打开 Actent 后再执行。Android 后台 Activity
启动受系统限制，因此 Intent 回执只能是 `launch_attempted`，绝不声称目标 App
业务完成。

## 8. Inbox、UI 与系统输入

页面：Inbox（主页面）、Works、Devices、Settings。

Android Share 输入由 Actent 自己在 Manifest 声明 `ACTION_SEND` 与
`ACTION_SEND_MULTIPLE`。收到 `content://` 附件后，先复制到 Actent 私有附件目录，
再创建消息；不得长期保存来源应用的 URI。Text/URL/Image/JSON 映射相应内容类型，
未知 MIME 一律作为 File，保留名称与 MIME。

一次 Share 创建草稿并打开 Work Picker：选择本机 Work 直接执行，选择远端 Work
发送请求，选择 Null Work 则按其目标仅保存；取消 Picker 时丢弃草稿。Work 状态显示
在原 Inbox 消息下，并按既定规则自动回传给发起设备。手机后台期间收到的状态在下次
打开 Actent 时显示。

Share Work 是手机的普通 Intent Work；其 `chooser: true` 模板把原内容和全部附件
交给 Android 系统分享面板。桌面第一版不提供系统 Share Work，桌面有副作用 Work
均为 Script Work。

## 9. 实施顺序：接口 → 测试 → 实现

每个阶段都必须先定义公开契约和 fake，再写测试，最后写真实实现。不得先写 Adapter
或 UI 来倒推协议。

### Phase 0 — Dartloom 基础迁移

1. 解决 dartloom 原有包中所有的 todo。
2. 在 Dartloom 上游创建 `dartloom_messaging` 与 `dartloom_pairing` 的 package skeleton、
   capability contracts 与 fake 实现。
3. 为 Packet、连接策略、去重、配对邀请、确认状态定义 Schema/API；先编写包级测试。
4. 实现 ntfy、LAN、crypto、chunk、QR、Android scanner 适配；保持 Actent 领域无依赖。
5. 更新 Dartloom 配置/生成器以注册 `messaging.default`、`pairing.default`，从 Actent 执行生成升级，绝不手改 `lib/capabilities/`。

### Phase 1 — Actent Core

1. 定义 ActentMessage、Device、Work、WorkRequest、WorkReceipt 和 JSON Schema。
2. 为状态库、Schema 校验、Catalog revision、授权、消息删除/附件清理写单元测试。
3. 实现 JSON-per-entity Repository 和 Secure Settings secret repository。
4. 定义 `WorkRunner`、队列、取消、恢复与结果路由；用 fake runner 完成测试。
5. 通过 fake `MessageConnection` 完成本机/远端路由、重试、去重与状态回传测试。

### Phase 2 — Work Runner

1. 先测试 DesktopScriptRunner 的 stdin JSON、参数非 shell、timeout、树终止、stdout
   丢弃、stderr 上限、exit code 与队列恢复。
2. 实现 DesktopScriptRunner，并增加可执行路径验证与模板。
3. 先为 AndroidIntentRunner 写映射测试：显式/隐式/chooser、typed extras、FileProvider
   URI、缺少目标 App、`launch_attempted`。
4. 实现 Android Intent、Share、HTTP Runner；未来 iOS 只实现同一契约的 fake/占位。

### Phase 3 — Pairing、输入与 UI

1. 测试 LAN 临时发现/确认、QR/粘贴邀请、到期、错误的短验证码与取消配对。
2. 接入 `dartloom_pairing`，实现 Devices UI。
3. Android 原生集成测试 Share 接收、附件私有化、FileProvider、Intent chooser；再实现
   Actent 输入 Activity 与 Work Picker。
4. 实现 Inbox、Works、Devices、Settings；桌面可编辑 Work，手机只读远端 Work Catalog。

### Phase 4 — 端到端验收与稳定性

1. 用 fake LAN/ntfy 测试完整流：手机 Share → 远端 Script Work → receipt → 手机 Share
   Work；覆盖 Null、取消、过期、重复 Packet、断网重试、队列溢出和附件不完整。
2. LAN 使用本地 loopback 集成测试；ntfy 使用 fake HTTP/WebSocket 适配器。真实 ntfy 或
   自建 ntfy 仅作为可选人工 smoke test，不进入 CI。
3. Android 真机/模拟器验证 Share 输入、相机配对权限、后台 Intent 限制和 FileProvider。
4. 每个阶段结束运行 `dart format .`、`flutter analyze`、`flutter test`；Dartloom 新包也
   分别运行其格式化、分析和测试命令。

## 10. MVP 验收标准

```text
Android 阅读 App Share
  → Actent 生成 ActentMessage 并选择远端 Script Work
  → LAN 直连优先、ntfy 回退的端到端加密投递
  → 桌面持久化、排队并执行用户脚本
  → 手机收到 WorkReceipt（成功、失败、stored、expired 等）
  → 用户选择手机 Share Intent Work，交由系统 chooser 转发原内容/附件
```

同时必须演示：手动/QR/LAN 配对、远端 Null Work、用户脚本、消息去重、断网后的有限
重试、Work 授权、取消、附件分块和所有核心测试通过。
