import 'dart:io';

Future<String> resolveDeviceDisplayName() async {
  final hostname = Platform.localHostname.trim();
  if (hostname.isEmpty || hostname == 'localhost') return 'Actent device';
  return hostname;
}
