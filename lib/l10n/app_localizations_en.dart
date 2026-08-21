// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Actent';

  @override
  String get startupLoading => 'Starting Actent…';

  @override
  String get startupPreparing => 'Preparing local data and device identity';

  @override
  String get startupFailed => 'Actent failed to start';

  @override
  String get trayQuit => 'Quit Actent';

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
  String get languageDescription => 'Choose the language used by Actent.';

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
      'Relay settings saved; restart Actent to reconnect.';

  @override
  String get restartToReconnect => 'Restart Actent to reconnect.';

  @override
  String saveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get lanDiscoveryUnavailable =>
      'LAN discovery is unavailable. A VPN/TUN adapter or Windows network configuration may be blocking multicast.';

  @override
  String get lanNoDevices => 'No pairing-enabled devices were found.';

  @override
  String get chooseWork => 'Choose Work';

  @override
  String get chooseWorkDescription =>
      'Select where this shared content should go.';

  @override
  String get thisDevice => 'This device';

  @override
  String get remoteDevice => 'Remote device';

  @override
  String get nullWork => 'Null — store locally';

  @override
  String get discard => 'Discard';

  @override
  String get close => 'Close';

  @override
  String get runAgain => 'Run again';

  @override
  String get cancelPendingRequests => 'Cancel pending requests';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get pairDevice => 'Pair device';

  @override
  String get addWork => 'Add Work';

  @override
  String get edit => 'Edit';

  @override
  String get enable => 'Enable';

  @override
  String get disable => 'Disable';

  @override
  String get delete => 'Delete';

  @override
  String get addJavaScriptWork => 'Add JavaScript Work';

  @override
  String get editJavaScriptWork => 'Edit JavaScript Work';

  @override
  String get addScriptWork => 'Add Script Work';

  @override
  String get editScriptWork => 'Edit Script Work';

  @override
  String get name => 'Name';

  @override
  String get javaScriptBody => 'JavaScript body';

  @override
  String get allowedNetworkHosts => 'Allowed network hosts (one per line)';

  @override
  String get absoluteExecutablePath => 'Absolute executable path';

  @override
  String get argumentsOnePerLine => 'Arguments (one per line)';

  @override
  String get deleteWorkTitle => 'Delete Work?';

  @override
  String deleteWorkMessage(Object name) {
    return 'Delete “$name” and cancel pending requests?';
  }

  @override
  String get relaySettingsTitle => 'Relay settings';

  @override
  String saveFailedWithError(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get attachmentRetentionTitle => 'Attachment retention';

  @override
  String removedExpiredMessages(Object count) {
    return 'Removed $count expired message(s).';
  }

  @override
  String get packetDeduplicationRetentionTitle =>
      'Packet deduplication retention';

  @override
  String get deduplicationRetentionSaved =>
      'Deduplication retention saved; restart to apply.';

  @override
  String get exportConfigurationTitle => 'Export configuration';

  @override
  String get importConfigurationTitle => 'Import configuration';

  @override
  String get import => 'Import';

  @override
  String importFailedWithError(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get removePairedDeviceTitle => 'Remove paired device?';

  @override
  String removePairedDeviceMessage(Object name) {
    return 'Remove $name and its remote Work catalog? Existing Inbox history is kept.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get discoverOnLan => 'Discover on LAN';

  @override
  String get pasteInvitation => 'Paste invitation';

  @override
  String get scanQrInvitation => 'Scan QR invitation';

  @override
  String get nearbyDevices => 'Nearby Actent devices';

  @override
  String get confirmLanPairingCode => 'Confirm LAN pairing code';

  @override
  String get confirmPairingCode => 'Confirm pairing code';

  @override
  String get sixDigitCode => '6-digit code';

  @override
  String get confirm => 'Confirm';

  @override
  String get addPairedDevice => 'Add paired device';

  @override
  String get invitationUri => 'Invitation URI';

  @override
  String pairingFailedWithError(Object error) {
    return 'Pairing failed: $error';
  }

  @override
  String get confirmNewPairedDevice => 'Confirm new paired device';

  @override
  String deviceName(Object name) {
    return 'Name: $name';
  }

  @override
  String deviceId(Object id) {
    return 'Device ID: $id';
  }

  @override
  String platform(Object platform) {
    return 'Platform: $platform';
  }

  @override
  String get publicKeyFingerprint => 'Public-key fingerprint:';

  @override
  String get reject => 'Reject';

  @override
  String get retentionOneDay => '1 day';

  @override
  String get retentionSevenDays => '7 days';

  @override
  String get retentionOneMonth => '1 month';

  @override
  String get retentionForever => 'Forever';

  @override
  String packetRetentionDays(Object days) {
    return '$days day(s)';
  }

  @override
  String get scanPairingQrDescription =>
      'Scan this QR code to pair the device.';

  @override
  String get copyInvitationLink => 'Copy invitation link';

  @override
  String get invitationLinkCopied => 'Invitation link copied.';
}
