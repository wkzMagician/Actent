// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Actent';

  @override
  String get startupLoading => '正在启动 Actent…';

  @override
  String get startupPreparing => '正在准备本地数据和设备身份';

  @override
  String get startupFailed => 'Actent 启动失败';

  @override
  String get trayQuit => '退出 Actent';

  @override
  String get activity => '活动';

  @override
  String get activityDescription => '输入内容及任务执行记录会显示在这里。';

  @override
  String get works => '任务';

  @override
  String get worksDescription => '创建和管理此设备上可用的操作。';

  @override
  String get devices => '设备';

  @override
  String get devicesDescription => '通过局域网或邀请码配对设备。';

  @override
  String get settings => '设置';

  @override
  String get settingsDescription => '传输、存储和保留策略设置会显示在这里。';

  @override
  String get secrets => '安全凭据';

  @override
  String get secretsDescription => '私钥和 relay 凭据使用安全设置存储。';

  @override
  String get transport => '传输';

  @override
  String get transportDescription => '优先使用局域网；ntfy relay 仅作为有限回退。';

  @override
  String get relayServer => 'Relay 服务器';

  @override
  String get authorizationConfigured => '已配置授权';

  @override
  String get attachmentRetention => '附件保留';

  @override
  String get attachmentRetentionDescription => '默认保留 7 天；活动记录会一直保留，直到手动删除。';

  @override
  String get purgeExpiredAttachments => '清理过期附件';

  @override
  String currentRetention(Object value) {
    return '当前保留时间：$value';
  }

  @override
  String get packetDeduplicationRetention => '数据包去重保留';

  @override
  String get exportConfiguration => '导出配置';

  @override
  String get exportConfigurationDescription => '仅包含任务和设备端点，不包含凭据或历史记录。';

  @override
  String get importConfiguration => '导入配置';

  @override
  String get importConfigurationDescription => '合并导出的任务和设备端点。';

  @override
  String get language => '语言';

  @override
  String get languageDescription => '选择 Actent 使用的语言。';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get relaySettings => 'Relay 设置';

  @override
  String get ntfyServerUrl => 'ntfy 服务器 URL';

  @override
  String get authorizationEmptyToClear => '授权（留空可清除）';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get invalidRelayUrl => 'Relay URL 无效。';

  @override
  String get relaySettingsSaved => 'Relay 设置已保存；重启 Actent 后重新连接。';

  @override
  String get restartToReconnect => '重启 Actent 后重新连接。';

  @override
  String saveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get lanDiscoveryUnavailable =>
      '局域网发现不可用。VPN/TUN 网卡或 Windows 网络配置可能阻止了多播。';

  @override
  String get lanNoDevices => '没有发现可配对的设备。';

  @override
  String get chooseWork => '选择任务';

  @override
  String get chooseWorkDescription => '选择要处理这条共享内容的任务。';

  @override
  String get thisDevice => '本设备';

  @override
  String get remoteDevice => '远程设备';

  @override
  String get nullWork => '空任务 — 保存在本地';

  @override
  String get discard => '丢弃';

  @override
  String get close => '关闭';

  @override
  String get runAgain => '再次运行';

  @override
  String get resend => '重发';

  @override
  String get activitySending => '正在发送中';

  @override
  String get activitySendFailed => '发送失败';

  @override
  String get activityReceived => '已接收';

  @override
  String get activityProcessing => '正在处理中';

  @override
  String get activityFailed => '处理失败';

  @override
  String get activitySucceeded => '已处理成功';

  @override
  String get cancelPendingRequests => '取消待处理请求';

  @override
  String get deleteMessage => '删除消息';

  @override
  String get pairDevice => '配对设备';

  @override
  String get addWork => '新增任务';

  @override
  String get chooseWorkType => '选择任务类型';

  @override
  String get nullWorkType => '空任务';

  @override
  String get scriptWorkType => '脚本任务';

  @override
  String get javaScriptWorkType => 'JavaScript 任务';

  @override
  String get applicationWorkType => '应用程序任务';

  @override
  String get networkWorkType => '网络任务';

  @override
  String get addApplicationWork => '新增应用程序任务';

  @override
  String get addNetworkWork => '新增网络任务';

  @override
  String get androidPackageName => '应用包名（可选）';

  @override
  String get networkUrl => '网络 URL';

  @override
  String get applicationUrl => '应用程序 URL 或 URL Scheme';

  @override
  String get edit => '编辑';

  @override
  String get enable => '启用';

  @override
  String get disable => '停用';

  @override
  String get delete => '删除';

  @override
  String get addJavaScriptWork => '新增 JavaScript 任务';

  @override
  String get editJavaScriptWork => '编辑 JavaScript 任务';

  @override
  String get addScriptWork => '新增脚本任务';

  @override
  String get editScriptWork => '编辑脚本任务';

  @override
  String get name => '名称';

  @override
  String get javaScriptBody => 'JavaScript 内容';

  @override
  String get allowedNetworkHosts => '允许的网络主机（每行一个）';

  @override
  String get absoluteExecutablePath => '可执行文件绝对路径';

  @override
  String get argumentsOnePerLine => '参数（每行一个）';

  @override
  String get deleteWorkTitle => '删除任务？';

  @override
  String deleteWorkMessage(Object name) {
    return '删除“$name”并取消待处理请求？';
  }

  @override
  String get relaySettingsTitle => 'Relay 设置';

  @override
  String saveFailedWithError(Object error) {
    return '保存失败：$error';
  }

  @override
  String get attachmentRetentionTitle => '附件保留';

  @override
  String removedExpiredMessages(Object count) {
    return '已删除 $count 条过期消息。';
  }

  @override
  String get packetDeduplicationRetentionTitle => '数据包去重保留';

  @override
  String get deduplicationRetentionSaved => '数据包去重保留已保存；重启后生效。';

  @override
  String get exportConfigurationTitle => '导出配置';

  @override
  String get importConfigurationTitle => '导入配置';

  @override
  String get import => '导入';

  @override
  String importFailedWithError(Object error) {
    return '导入失败：$error';
  }

  @override
  String get removePairedDeviceTitle => '移除已配对设备？';

  @override
  String removePairedDeviceMessage(Object name) {
    return '移除 $name 及其远程任务目录？现有活动记录会保留。';
  }

  @override
  String get remove => '移除';

  @override
  String get discoverOnLan => '发现局域网设备';

  @override
  String get pasteInvitation => '粘贴邀请';

  @override
  String get scanQrInvitation => '扫描二维码邀请';

  @override
  String get nearbyDevices => '附近的 Actent 设备';

  @override
  String get confirmLanPairingCode => '确认局域网配对码';

  @override
  String get confirmPairingCode => '确认配对码';

  @override
  String get sixDigitCode => '6 位数字配对码';

  @override
  String get confirm => '确认';

  @override
  String get addPairedDevice => '添加已配对设备';

  @override
  String get invitationUri => '邀请 URI';

  @override
  String pairingFailedWithError(Object error) {
    return '配对失败：$error';
  }

  @override
  String get confirmNewPairedDevice => '确认新配对设备';

  @override
  String deviceName(Object name) {
    return '名称：$name';
  }

  @override
  String deviceId(Object id) {
    return '设备 ID：$id';
  }

  @override
  String get unnamedDevice => '未命名设备';

  @override
  String platform(Object platform) {
    return '平台：$platform';
  }

  @override
  String get publicKeyFingerprint => '公钥指纹：';

  @override
  String get reject => '拒绝';

  @override
  String get retentionOneDay => '1 天';

  @override
  String get retentionSevenDays => '7 天';

  @override
  String get retentionOneMonth => '1 个月';

  @override
  String get retentionForever => '永久';

  @override
  String packetRetentionDays(Object days) {
    return '$days 天';
  }

  @override
  String get scanPairingQrDescription => '扫描此二维码以配对设备。';

  @override
  String get copyInvitationLink => '复制邀请链接';

  @override
  String get invitationLinkCopied => '邀请链接已复制。';

  @override
  String get runWork => '运行任务';

  @override
  String get chooseWorkInput => '选择输入内容';

  @override
  String get chooseWorkInputDescription => '选择要发送到此任务的兼容活动内容。';

  @override
  String get noMessagesAvailable => '没有可供此任务运行的兼容活动内容。';

  @override
  String workRequestFailed(Object error) {
    return '任务请求失败：$error';
  }

  @override
  String pairingCode(Object code) {
    return '配对码：$code';
  }

  @override
  String get pairingCodeDescription => '请在另一台设备输入此代码，以确认两台设备正在互相配对。';

  @override
  String fileSelectionFailed(Object error) {
    return '无法选择文件：$error';
  }

  @override
  String get chooseInputType => '选择输入类型';

  @override
  String get chooseInputTypeDescription => '选择要发送到此任务的内容类型。';

  @override
  String get inputTypeNotAccepted => '所选任务不接受此文件类型。';

  @override
  String get inputText => '文本';

  @override
  String get inputUrl => '链接';

  @override
  String get inputImage => '图片';

  @override
  String get inputFile => '文件';

  @override
  String get inputJson => 'JSON';

  @override
  String get inputValueHint => '输入内容';

  @override
  String get urlInputHint => 'https://example.com';

  @override
  String get continueLabel => '继续';
}
