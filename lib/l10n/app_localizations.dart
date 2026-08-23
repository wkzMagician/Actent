import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Actent'**
  String get appTitle;

  /// No description provided for @startupLoading.
  ///
  /// In en, this message translates to:
  /// **'Starting Actent…'**
  String get startupLoading;

  /// No description provided for @startupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing local data and device identity'**
  String get startupPreparing;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Actent failed to start'**
  String get startupFailed;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Actent'**
  String get trayQuit;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @activityDescription.
  ///
  /// In en, this message translates to:
  /// **'Inputs and Work execution history will appear here.'**
  String get activityDescription;

  /// No description provided for @works.
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get works;

  /// No description provided for @worksDescription.
  ///
  /// In en, this message translates to:
  /// **'Create and manage the actions available on this device.'**
  String get worksDescription;

  /// No description provided for @workflows.
  ///
  /// In en, this message translates to:
  /// **'Workflows'**
  String get workflows;

  /// No description provided for @workflowsDescription.
  ///
  /// In en, this message translates to:
  /// **'Run a linear sequence of Works across paired devices.'**
  String get workflowsDescription;

  /// No description provided for @addWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Add Workflow'**
  String get addWorkflow;

  /// No description provided for @workflowName.
  ///
  /// In en, this message translates to:
  /// **'Workflow name'**
  String get workflowName;

  /// No description provided for @workflowSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get workflowSteps;

  /// No description provided for @addWorkflowStep.
  ///
  /// In en, this message translates to:
  /// **'Add step'**
  String get addWorkflowStep;

  /// No description provided for @noWorkflowSteps.
  ///
  /// In en, this message translates to:
  /// **'Add at least one Work step.'**
  String get noWorkflowSteps;

  /// No description provided for @workflowInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get workflowInvalid;

  /// No description provided for @workflowReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get workflowReady;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @devicesDescription.
  ///
  /// In en, this message translates to:
  /// **'Pair devices over LAN or with an invitation code.'**
  String get devicesDescription;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Transport, storage and retention settings will appear here.'**
  String get settingsDescription;

  /// No description provided for @secrets.
  ///
  /// In en, this message translates to:
  /// **'Secrets'**
  String get secrets;

  /// No description provided for @secretsDescription.
  ///
  /// In en, this message translates to:
  /// **'Private keys and relay credentials use Secure Settings.'**
  String get secretsDescription;

  /// No description provided for @transport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// No description provided for @transportDescription.
  ///
  /// In en, this message translates to:
  /// **'LAN is preferred; ntfy relay is used as a bounded fallback.'**
  String get transportDescription;

  /// No description provided for @relayServer.
  ///
  /// In en, this message translates to:
  /// **'Relay server'**
  String get relayServer;

  /// No description provided for @authorizationConfigured.
  ///
  /// In en, this message translates to:
  /// **'authorization configured'**
  String get authorizationConfigured;

  /// No description provided for @attachmentRetention.
  ///
  /// In en, this message translates to:
  /// **'Attachment retention'**
  String get attachmentRetention;

  /// No description provided for @attachmentRetentionDescription.
  ///
  /// In en, this message translates to:
  /// **'Default: 7 days. Activity remains until manually deleted.'**
  String get attachmentRetentionDescription;

  /// No description provided for @purgeExpiredAttachments.
  ///
  /// In en, this message translates to:
  /// **'Purge expired attachments'**
  String get purgeExpiredAttachments;

  /// No description provided for @currentRetention.
  ///
  /// In en, this message translates to:
  /// **'Current retention: {value}'**
  String currentRetention(Object value);

  /// No description provided for @packetDeduplicationRetention.
  ///
  /// In en, this message translates to:
  /// **'Packet deduplication retention'**
  String get packetDeduplicationRetention;

  /// No description provided for @exportConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Export configuration'**
  String get exportConfiguration;

  /// No description provided for @exportConfigurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Works and device endpoints only; no secrets or history.'**
  String get exportConfigurationDescription;

  /// No description provided for @importConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Import configuration'**
  String get importConfiguration;

  /// No description provided for @importConfigurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Merge exported Works and device endpoints.'**
  String get importConfigurationDescription;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used by Actent.'**
  String get languageDescription;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @relaySettings.
  ///
  /// In en, this message translates to:
  /// **'Relay settings'**
  String get relaySettings;

  /// No description provided for @ntfyServerUrl.
  ///
  /// In en, this message translates to:
  /// **'ntfy server URL'**
  String get ntfyServerUrl;

  /// No description provided for @authorizationEmptyToClear.
  ///
  /// In en, this message translates to:
  /// **'Authorization (empty to clear)'**
  String get authorizationEmptyToClear;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @invalidRelayUrl.
  ///
  /// In en, this message translates to:
  /// **'Relay URL is invalid.'**
  String get invalidRelayUrl;

  /// No description provided for @relaySettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Relay settings saved; restart Actent to reconnect.'**
  String get relaySettingsSaved;

  /// No description provided for @restartToReconnect.
  ///
  /// In en, this message translates to:
  /// **'Restart Actent to reconnect.'**
  String get restartToReconnect;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(Object error);

  /// No description provided for @workNameAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A Work with this name already exists on this device.'**
  String get workNameAlreadyExists;

  /// No description provided for @lanDiscoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'LAN discovery is unavailable. A VPN/TUN adapter or Windows network configuration may be blocking multicast.'**
  String get lanDiscoveryUnavailable;

  /// No description provided for @lanNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No pairing-enabled devices were found.'**
  String get lanNoDevices;

  /// No description provided for @chooseWork.
  ///
  /// In en, this message translates to:
  /// **'Choose Work'**
  String get chooseWork;

  /// No description provided for @chooseWorkDescription.
  ///
  /// In en, this message translates to:
  /// **'Select where this shared content should go.'**
  String get chooseWorkDescription;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @remoteDevice.
  ///
  /// In en, this message translates to:
  /// **'Remote device'**
  String get remoteDevice;

  /// No description provided for @nullWork.
  ///
  /// In en, this message translates to:
  /// **'Null — store locally'**
  String get nullWork;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @runAgain.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get runAgain;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// No description provided for @activitySending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get activitySending;

  /// No description provided for @activitySendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get activitySendFailed;

  /// No description provided for @activityReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get activityReceived;

  /// No description provided for @activityQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get activityQueued;

  /// No description provided for @activityProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get activityProcessing;

  /// No description provided for @activityCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get activityCancelling;

  /// No description provided for @activityInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get activityInterrupted;

  /// No description provided for @activityFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed'**
  String get activityFailed;

  /// No description provided for @activitySucceeded.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get activitySucceeded;

  /// No description provided for @cancelPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Cancel pending requests'**
  String get cancelPendingRequests;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @pairDevice.
  ///
  /// In en, this message translates to:
  /// **'Pair device'**
  String get pairDevice;

  /// No description provided for @addWork.
  ///
  /// In en, this message translates to:
  /// **'Add Work'**
  String get addWork;

  /// No description provided for @chooseWorkType.
  ///
  /// In en, this message translates to:
  /// **'Choose Work type'**
  String get chooseWorkType;

  /// No description provided for @nullWorkType.
  ///
  /// In en, this message translates to:
  /// **'Null Work'**
  String get nullWorkType;

  /// No description provided for @scriptWorkType.
  ///
  /// In en, this message translates to:
  /// **'Script Work'**
  String get scriptWorkType;

  /// No description provided for @fileWorkType.
  ///
  /// In en, this message translates to:
  /// **'Program or script file'**
  String get fileWorkType;

  /// No description provided for @shellWorkType.
  ///
  /// In en, this message translates to:
  /// **'Shell script'**
  String get shellWorkType;

  /// No description provided for @addShellWork.
  ///
  /// In en, this message translates to:
  /// **'Add shell script task'**
  String get addShellWork;

  /// No description provided for @editShellWork.
  ///
  /// In en, this message translates to:
  /// **'Edit shell script task'**
  String get editShellWork;

  /// No description provided for @addFileWork.
  ///
  /// In en, this message translates to:
  /// **'Add program or script task'**
  String get addFileWork;

  /// No description provided for @editFileWork.
  ///
  /// In en, this message translates to:
  /// **'Edit program or script task'**
  String get editFileWork;

  /// No description provided for @programOrScriptFile.
  ///
  /// In en, this message translates to:
  /// **'Program or script file'**
  String get programOrScriptFile;

  /// No description provided for @shell.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get shell;

  /// No description provided for @shellSource.
  ///
  /// In en, this message translates to:
  /// **'Shell script'**
  String get shellSource;

  /// No description provided for @javaScriptWorkType.
  ///
  /// In en, this message translates to:
  /// **'JavaScript Work'**
  String get javaScriptWorkType;

  /// No description provided for @applicationWorkType.
  ///
  /// In en, this message translates to:
  /// **'Application Work'**
  String get applicationWorkType;

  /// No description provided for @intentAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get intentAction;

  /// No description provided for @chooseApplication.
  ///
  /// In en, this message translates to:
  /// **'Choose application'**
  String get chooseApplication;

  /// No description provided for @noCompatibleApps.
  ///
  /// In en, this message translates to:
  /// **'No compatible applications found'**
  String get noCompatibleApps;

  /// No description provided for @iosApplicationMode.
  ///
  /// In en, this message translates to:
  /// **'Integration'**
  String get iosApplicationMode;

  /// No description provided for @shortcutName.
  ///
  /// In en, this message translates to:
  /// **'Shortcut name'**
  String get shortcutName;

  /// No description provided for @networkWorkType.
  ///
  /// In en, this message translates to:
  /// **'Network Work'**
  String get networkWorkType;

  /// No description provided for @addApplicationWork.
  ///
  /// In en, this message translates to:
  /// **'Add Application Work'**
  String get addApplicationWork;

  /// No description provided for @addNetworkWork.
  ///
  /// In en, this message translates to:
  /// **'Add Network Work'**
  String get addNetworkWork;

  /// No description provided for @androidPackageName.
  ///
  /// In en, this message translates to:
  /// **'Application package name (optional)'**
  String get androidPackageName;

  /// No description provided for @networkUrl.
  ///
  /// In en, this message translates to:
  /// **'Network URL'**
  String get networkUrl;

  /// No description provided for @networkMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get networkMethod;

  /// No description provided for @networkHeaders.
  ///
  /// In en, this message translates to:
  /// **'Headers (one per line)'**
  String get networkHeaders;

  /// No description provided for @networkBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get networkBody;

  /// No description provided for @applicationUrl.
  ///
  /// In en, this message translates to:
  /// **'Application URL or URL scheme'**
  String get applicationUrl;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @addJavaScriptWork.
  ///
  /// In en, this message translates to:
  /// **'Add JavaScript Work'**
  String get addJavaScriptWork;

  /// No description provided for @editJavaScriptWork.
  ///
  /// In en, this message translates to:
  /// **'Edit JavaScript Work'**
  String get editJavaScriptWork;

  /// No description provided for @addScriptWork.
  ///
  /// In en, this message translates to:
  /// **'Add Script Work'**
  String get addScriptWork;

  /// No description provided for @editScriptWork.
  ///
  /// In en, this message translates to:
  /// **'Edit Script Work'**
  String get editScriptWork;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @javaScriptBody.
  ///
  /// In en, this message translates to:
  /// **'JavaScript body'**
  String get javaScriptBody;

  /// No description provided for @allowedNetworkHosts.
  ///
  /// In en, this message translates to:
  /// **'Allowed network hosts (one per line)'**
  String get allowedNetworkHosts;

  /// No description provided for @absoluteExecutablePath.
  ///
  /// In en, this message translates to:
  /// **'Absolute executable path'**
  String get absoluteExecutablePath;

  /// No description provided for @argumentsOnePerLine.
  ///
  /// In en, this message translates to:
  /// **'Arguments (one per line)'**
  String get argumentsOnePerLine;

  /// No description provided for @deleteWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Work?'**
  String get deleteWorkTitle;

  /// No description provided for @deleteWorkMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}” and cancel pending requests?'**
  String deleteWorkMessage(Object name);

  /// No description provided for @relaySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Relay settings'**
  String get relaySettingsTitle;

  /// No description provided for @saveFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedWithError(Object error);

  /// No description provided for @attachmentRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachment retention'**
  String get attachmentRetentionTitle;

  /// No description provided for @removedExpiredMessages.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} expired message(s).'**
  String removedExpiredMessages(Object count);

  /// No description provided for @packetDeduplicationRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Packet deduplication retention'**
  String get packetDeduplicationRetentionTitle;

  /// No description provided for @deduplicationRetentionSaved.
  ///
  /// In en, this message translates to:
  /// **'Deduplication retention saved; restart to apply.'**
  String get deduplicationRetentionSaved;

  /// No description provided for @exportConfigurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Export configuration'**
  String get exportConfigurationTitle;

  /// No description provided for @importConfigurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Import configuration'**
  String get importConfigurationTitle;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @importFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailedWithError(Object error);

  /// No description provided for @removePairedDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove paired device?'**
  String get removePairedDeviceTitle;

  /// No description provided for @removePairedDeviceMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} and its remote Work catalog? Existing Activity history is kept.'**
  String removePairedDeviceMessage(Object name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @discoverOnLan.
  ///
  /// In en, this message translates to:
  /// **'Discover on LAN'**
  String get discoverOnLan;

  /// No description provided for @pasteInvitation.
  ///
  /// In en, this message translates to:
  /// **'Paste invitation'**
  String get pasteInvitation;

  /// No description provided for @scanQrInvitation.
  ///
  /// In en, this message translates to:
  /// **'Scan QR invitation'**
  String get scanQrInvitation;

  /// No description provided for @nearbyDevices.
  ///
  /// In en, this message translates to:
  /// **'Nearby Actent devices'**
  String get nearbyDevices;

  /// No description provided for @confirmLanPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Confirm LAN pairing code'**
  String get confirmLanPairingCode;

  /// No description provided for @confirmPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Confirm pairing code'**
  String get confirmPairingCode;

  /// No description provided for @sixDigitCode.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get sixDigitCode;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @addPairedDevice.
  ///
  /// In en, this message translates to:
  /// **'Add paired device'**
  String get addPairedDevice;

  /// No description provided for @invitationUri.
  ///
  /// In en, this message translates to:
  /// **'Invitation URI'**
  String get invitationUri;

  /// No description provided for @pairingFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: {error}'**
  String pairingFailedWithError(Object error);

  /// No description provided for @confirmNewPairedDevice.
  ///
  /// In en, this message translates to:
  /// **'Confirm new paired device'**
  String get confirmNewPairedDevice;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Name: {name}'**
  String deviceName(Object name);

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID: {id}'**
  String deviceId(Object id);

  /// No description provided for @unnamedDevice.
  ///
  /// In en, this message translates to:
  /// **'Unnamed device'**
  String get unnamedDevice;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}'**
  String platform(Object platform);

  /// No description provided for @publicKeyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Public-key fingerprint:'**
  String get publicKeyFingerprint;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @retentionOneDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get retentionOneDay;

  /// No description provided for @retentionSevenDays.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get retentionSevenDays;

  /// No description provided for @retentionOneMonth.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get retentionOneMonth;

  /// No description provided for @retentionForever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get retentionForever;

  /// No description provided for @packetRetentionDays.
  ///
  /// In en, this message translates to:
  /// **'{days} day(s)'**
  String packetRetentionDays(Object days);

  /// No description provided for @scanPairingQrDescription.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code to pair the device.'**
  String get scanPairingQrDescription;

  /// No description provided for @copyInvitationLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invitation link'**
  String get copyInvitationLink;

  /// No description provided for @invitationLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invitation link copied.'**
  String get invitationLinkCopied;

  /// No description provided for @runWork.
  ///
  /// In en, this message translates to:
  /// **'Run Work'**
  String get runWork;

  /// No description provided for @chooseWorkInput.
  ///
  /// In en, this message translates to:
  /// **'Choose input'**
  String get chooseWorkInput;

  /// No description provided for @chooseWorkInputDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose compatible Activity content to send to this Work.'**
  String get chooseWorkInputDescription;

  /// No description provided for @noMessagesAvailable.
  ///
  /// In en, this message translates to:
  /// **'There is no compatible Activity content to run.'**
  String get noMessagesAvailable;

  /// No description provided for @workRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Work request failed: {error}'**
  String workRequestFailed(Object error);

  /// No description provided for @pairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code: {code}'**
  String pairingCode(Object code);

  /// No description provided for @pairingCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on the other device to confirm that both devices are pairing with each other.'**
  String get pairingCodeDescription;

  /// No description provided for @fileSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not select file: {error}'**
  String fileSelectionFailed(Object error);

  /// No description provided for @chooseInputType.
  ///
  /// In en, this message translates to:
  /// **'Choose input type'**
  String get chooseInputType;

  /// No description provided for @chooseInputTypeDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the kind of content to send to this Work.'**
  String get chooseInputTypeDescription;

  /// No description provided for @inputTypeNotAccepted.
  ///
  /// In en, this message translates to:
  /// **'This file type is not accepted by the selected Work.'**
  String get inputTypeNotAccepted;

  /// No description provided for @inputText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get inputText;

  /// No description provided for @inputUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get inputUrl;

  /// No description provided for @inputImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get inputImage;

  /// No description provided for @inputFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get inputFile;

  /// No description provided for @inputJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get inputJson;

  /// No description provided for @inputValueHint.
  ///
  /// In en, this message translates to:
  /// **'Enter content'**
  String get inputValueHint;

  /// No description provided for @urlInputHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get urlInputHint;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
