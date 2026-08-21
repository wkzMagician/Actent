import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';

Future<void> showActentPairingQr(
  BuildContext context,
  String invitation,
) async {
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.pairDevice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(data: invitation, size: 240),
          const SizedBox(height: 12),
          Text(l10n.scanPairingQrDescription),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invitation));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(SnackBar(content: Text(l10n.invitationLinkCopied)));
          },
          icon: const Icon(Icons.content_copy_outlined),
          label: Text(l10n.copyInvitationLink),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
