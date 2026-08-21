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
  String get inbox => '收件箱';

  @override
  String get inboxDescription => '共享内容和 Work 回执会显示在这里。';

  @override
  String get works => 'Work';

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
  String get attachmentRetentionDescription => '默认保留 7 天；收件箱消息会一直保留，直到手动删除。';

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
  String get exportConfigurationDescription => '仅包含 Work 和设备端点，不包含凭据或历史记录。';

  @override
  String get importConfiguration => '导入配置';

  @override
  String get importConfigurationDescription => '合并导出的 Work 和设备端点。';

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
  String get chooseWork => '选择 Work';

  @override
  String get chooseWorkDescription => '选择要处理这条共享内容的 Work。';

  @override
  String get thisDevice => '本设备';

  @override
  String get remoteDevice => '远程设备';

  @override
  String get nullWork => 'Null — 保存在本地';

  @override
  String get discard => '丢弃';

  @override
  String get close => '关闭';

  @override
  String get runAgain => '再次运行';

  @override
  String get cancelPendingRequests => '取消待处理请求';

  @override
  String get deleteMessage => '删除消息';

  @override
  String get pairDevice => '配对设备';

  @override
  String get addWork => '新增 Work';

  @override
  String get edit => '编辑';

  @override
  String get enable => '启用';

  @override
  String get disable => '停用';

  @override
  String get delete => '删除';

  @override
  String get addJavaScriptWork => '新增 JavaScript Work';

  @override
  String get editJavaScriptWork => '编辑 JavaScript Work';

  @override
  String get addScriptWork => '新增脚本 Work';

  @override
  String get editScriptWork => '编辑脚本 Work';

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
  String get deleteWorkTitle => '删除 Work？';

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
    return '移除 $name 及其远程 Work 目录？现有收件箱历史会保留。';
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
}
