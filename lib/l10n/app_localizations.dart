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
  /// **'Pengion'**
  String get appTitle;

  /// No description provided for @startupLoading.
  ///
  /// In en, this message translates to:
  /// **'Starting Pengion…'**
  String get startupLoading;

  /// No description provided for @startupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing local data and device identity'**
  String get startupPreparing;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Pengion failed to start'**
  String get startupFailed;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Pengion'**
  String get trayQuit;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @inboxDescription.
  ///
  /// In en, this message translates to:
  /// **'Shared content and Work receipts will appear here.'**
  String get inboxDescription;

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
  /// **'Default: 7 days. Inbox messages remain until manually deleted.'**
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
  /// **'Choose the language used by Pengion.'**
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
  /// **'Relay settings saved; restart Pengion to reconnect.'**
  String get relaySettingsSaved;

  /// No description provided for @restartToReconnect.
  ///
  /// In en, this message translates to:
  /// **'Restart Pengion to reconnect.'**
  String get restartToReconnect;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(Object error);

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
