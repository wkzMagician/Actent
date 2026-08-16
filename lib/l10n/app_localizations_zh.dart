// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Pengion';

  @override
  String get startupLoading => '正在启动 Pengion…';

  @override
  String get startupPreparing => '正在准备本地数据和设备身份';

  @override
  String get startupFailed => 'Pengion 启动失败';

  @override
  String get trayQuit => '退出 Pengion';

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
  String get languageDescription => '选择 Pengion 使用的语言。';

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
  String get relaySettingsSaved => 'Relay 设置已保存；重启 Pengion 后重新连接。';

  @override
  String get restartToReconnect => '重启 Pengion 后重新连接。';

  @override
  String saveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get lanDiscoveryUnavailable =>
      '局域网发现不可用。VPN/TUN 网卡或 Windows 网络配置可能阻止了多播。';

  @override
  String get lanNoDevices => '没有发现可配对的设备。';
}
