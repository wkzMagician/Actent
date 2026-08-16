// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pengion';

  @override
  String get startupLoading => 'Starting Pengion…';

  @override
  String get startupPreparing => 'Preparing local data and device identity';

  @override
  String get startupFailed => 'Pengion failed to start';

  @override
  String get trayQuit => 'Quit Pengion';

  @override
  String get inbox => 'Inbox';

  @override
  String get inboxDescription =>
      'Shared content and Work receipts will appear here.';

  @override
  String get works => 'Works';

  @override
  String get worksDescription =>
      'Create and manage the actions available on this device.';

  @override
  String get devices => 'Devices';

  @override
  String get devicesDescription =>
      'Pair devices over LAN or with an invitation code.';

  @override
  String get settings => 'Settings';

  @override
  String get settingsDescription =>
      'Transport, storage and retention settings will appear here.';

  @override
  String get secrets => 'Secrets';

  @override
  String get secretsDescription =>
      'Private keys and relay credentials use Secure Settings.';

  @override
  String get transport => 'Transport';

  @override
  String get transportDescription =>
      'LAN is preferred; ntfy relay is used as a bounded fallback.';

  @override
  String get relayServer => 'Relay server';

  @override
  String get authorizationConfigured => 'authorization configured';

  @override
  String get attachmentRetention => 'Attachment retention';

  @override
  String get attachmentRetentionDescription =>
      'Default: 7 days. Inbox messages remain until manually deleted.';

  @override
  String get purgeExpiredAttachments => 'Purge expired attachments';

  @override
  String currentRetention(Object value) {
    return 'Current retention: $value';
  }

  @override
  String get packetDeduplicationRetention => 'Packet deduplication retention';

  @override
  String get exportConfiguration => 'Export configuration';

  @override
  String get exportConfigurationDescription =>
      'Works and device endpoints only; no secrets or history.';

  @override
  String get importConfiguration => 'Import configuration';

  @override
  String get importConfigurationDescription =>
      'Merge exported Works and device endpoints.';

  @override
  String get language => 'Language';

  @override
  String get languageDescription => 'Choose the language used by Pengion.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get relaySettings => 'Relay settings';

  @override
  String get ntfyServerUrl => 'ntfy server URL';

  @override
  String get authorizationEmptyToClear => 'Authorization (empty to clear)';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get invalidRelayUrl => 'Relay URL is invalid.';

  @override
  String get relaySettingsSaved =>
      'Relay settings saved; restart Pengion to reconnect.';

  @override
  String get restartToReconnect => 'Restart Pengion to reconnect.';

  @override
  String saveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get lanDiscoveryUnavailable =>
      'LAN discovery is unavailable. A VPN/TUN adapter or Windows network configuration may be blocking multicast.';

  @override
  String get lanNoDevices => 'No pairing-enabled devices were found.';
}
