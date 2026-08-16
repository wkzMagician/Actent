import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_resident_tray/dartloom_resident_tray.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
import 'package:flutter/foundation.dart';

Future<ResidentService?> createResidentService() async {
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return null;
  }
  final service = TrayResidentService(
    tooltip: 'Pengion',
    linuxIconPath: 'linux/runner/resources/app_icon.png',
    macosIconPath:
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    windowsIconPath: 'windows/runner/resources/app_icon.ico',
  );
  final icon = switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'windows/runner/resources/app_icon.ico',
    TargetPlatform.macOS =>
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    _ => 'linux/runner/resources/app_icon.png',
  };
  try {
    await service.initialize(iconPath: icon);
    return service;
  } on Object {
    await service.dispose();
    return null;
  }
}

SingleInstanceService? createSingleInstanceService() {
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return null;
  }
  return SocketSingleInstanceService(identity: 'com.example.pengion');
}
