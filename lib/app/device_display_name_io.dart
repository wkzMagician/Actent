import 'dart:io';

import 'package:flutter/services.dart';

Future<String> resolveDeviceDisplayName() async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final name = await const MethodChannel('actent/device')
          .invokeMethod<String>('displayName');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } on PlatformException {
      // Use the hostname fallback on older app installations without the
      // platform channel.
    }
  }
  final hostname = Platform.localHostname.trim();
  if (hostname.isEmpty || hostname == 'localhost') return 'Actent device';
  return hostname;
}
