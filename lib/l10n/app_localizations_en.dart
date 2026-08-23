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
  String get activity => 'Activity';

  @override
  String get activityDescription =>
      'Inputs and Work execution history will appear here.';

  @override
  String get works => 'Works';

  @override
  String get worksDescription =>
      'Create and manage the actions available on this device.';

  @override
  String get workflows => 'Workflows';

  @override
  String get workflowsDescription =>
      'Run a linear sequence of Works across paired devices.';

  @override
  String get addWorkflow => 'Add Workflow';

  @override
  String get workflowName => 'Workflow name';

  @override
  String get workflowSteps => 'Steps';

  @override
  String get addWorkflowStep => 'Add step';

  @override
  String get noWorkflowSteps => 'Add at least one Work step.';

  @override
  String get workflowInvalid => 'Invalid';

  @override
  String get workflowReady => 'Ready';

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
      'Default: 7 days. Activity remains until manually deleted.';

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
  String get workNameAlreadyExists =>
      'A Work with this name already exists on this device.';

  @override
  String get lanDiscoveryUnavailable =>
      'LAN discovery is unavailable. A VPN/TUN adapter or Windows network configuration may be blocking multicast.';

  @override
  String get lanNoDevices => 'No pairing-enabled devices were found.';

  @override
  String get chooseWork => 'Choose Work';

  @override
  String get chooseWorkOrWorkflow => 'Choose Work or Workflow';

  @override
  String get chooseWorkDescription =>
      'Select where this shared content should go.';

  @override
  String get deviceConnected => 'Connected';

  @override
  String get deviceDisconnected => 'Not connected';

  @override
  String get deviceConnectionChecking => 'Checking connection';

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
  String get resend => 'Resend';

  @override
  String get activitySending => 'Sending';

  @override
  String get activitySendFailed => 'Send failed';

  @override
  String get activityReceived => 'Received';

  @override
  String get activityQueued => 'Queued';

  @override
  String get activityProcessing => 'Processing';

  @override
  String get activityCancelling => 'Cancelling';

  @override
  String get activityInterrupted => 'Interrupted';

  @override
  String get activityFailed => 'Processing failed';

  @override
  String get activitySucceeded => 'Processed';

  @override
  String get cancelPendingRequests => 'Cancel pending requests';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get pairDevice => 'Pair device';

  @override
  String get addWork => 'Add Work';

  @override
  String get chooseWorkType => 'Choose Work type';

  @override
  String get nullWorkType => 'Null Work';

  @override
  String get scriptWorkType => 'Script Work';

  @override
  String get fileWorkType => 'Program or script file';

  @override
  String get shellWorkType => 'Shell script';

  @override
  String get addShellWork => 'Add shell script task';

  @override
  String get editShellWork => 'Edit shell script task';

  @override
  String get addFileWork => 'Add program or script task';

  @override
  String get editFileWork => 'Edit program or script task';

  @override
  String get programOrScriptFile => 'Program or script file';

  @override
  String get shell => 'Shell';

  @override
  String get shellSource => 'Shell script';

  @override
  String get javaScriptWorkType => 'JavaScript Work';

  @override
  String get applicationWorkType => 'Application Work';

  @override
  String get intentAction => 'Action';

  @override
  String get chooseApplication => 'Choose application';

  @override
  String get noCompatibleApps => 'No compatible applications found';

  @override
  String get iosApplicationMode => 'Integration';

  @override
  String get shortcutName => 'Shortcut name';

  @override
  String get networkWorkType => 'Network Work';

  @override
  String get addApplicationWork => 'Add Application Work';

  @override
  String get addNetworkWork => 'Add Network Work';

  @override
  String get androidPackageName => 'Application package name (optional)';

  @override
  String get networkUrl => 'Network URL';

  @override
  String get networkMethod => 'Method';

  @override
  String get networkHeaders => 'Headers (one per line)';

  @override
  String get networkBody => 'Body';

  @override
  String get applicationUrl => 'Application URL or URL scheme';

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
    return 'Remove $name and its remote Work catalog? Existing Activity history is kept.';
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
  String get unnamedDevice => 'Unnamed device';

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

  @override
  String get runWork => 'Run Work';

  @override
  String get chooseWorkInput => 'Choose input';

  @override
  String get chooseWorkInputDescription =>
      'Choose compatible Activity content to send to this Work.';

  @override
  String get noMessagesAvailable =>
      'There is no compatible Activity content to run.';

  @override
  String workRequestFailed(Object error) {
    return 'Work request failed: $error';
  }

  @override
  String pairingCode(Object code) {
    return 'Pairing code: $code';
  }

  @override
  String get pairingCodeDescription =>
      'Enter this code on the other device to confirm that both devices are pairing with each other.';

  @override
  String fileSelectionFailed(Object error) {
    return 'Could not select file: $error';
  }

  @override
  String get chooseInputType => 'Choose input type';

  @override
  String get chooseInputTypeDescription =>
      'Select the kind of content to send to this Work.';

  @override
  String get inputTypeNotAccepted =>
      'This file type is not accepted by the selected Work.';

  @override
  String get inputText => 'Text';

  @override
  String get inputUrl => 'URL';

  @override
  String get inputImage => 'Image';

  @override
  String get inputFile => 'File';

  @override
  String get inputJson => 'JSON';

  @override
  String get inputValueHint => 'Enter content';

  @override
  String get urlInputHint => 'https://example.com';

  @override
  String get continueLabel => 'Continue';
}
