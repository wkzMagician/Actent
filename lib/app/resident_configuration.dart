import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Configures the resident service through its Dartloom capability contract.
Future<void> configureResidentMenu({
  required ResidentService? resident,
  ResidentExitRequest? onExitRequested,
}) async {
  if (resident == null) return;

  final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final locale = AppLocalizations.supportedLocales.firstWhere(
    (candidate) => candidate.languageCode == platformLocale.languageCode,
    orElse: () => AppLocalizations.supportedLocales.first,
  );
  final localizations = await AppLocalizations.delegate.load(locale);

  await resident.configure(
    ResidentConfiguration(
      menu: [
        ResidentMenuItem.action(id: 'quit', label: localizations.trayQuit),
      ],
      rightClick: ResidentClickAction.showMenu,
      exitMenuItemId: 'quit',
      onExitRequested: onExitRequested,
    ),
  );
}
