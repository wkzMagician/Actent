import 'package:flutter/services.dart';

import '../actent_core/actent_models.dart';
import '../work/android/android_work_runner.dart';

const _channelName = 'actent/android_share';

class AndroidShareBridge {
  AndroidShareBridge({EventChannel? events, MethodChannel? methods})
    : _events = events ?? const EventChannel(_channelName),
      _methods = methods ?? const MethodChannel(_channelName);

  final EventChannel _events;
  final MethodChannel _methods;

  Stream<ActentMessage> get messages =>
      _events.receiveBroadcastStream().map(ActentMessage.fromJson);

  Future<String> createContentUri(ActentAttachment attachment) async {
    final value = await _methods.invokeMethod<String>(
      'createContentUri',
      <String, Object?>{'handle': attachment.handle},
    );
    if (value == null || value.isEmpty) {
      throw const AndroidWorkException('Android FileProvider returned no URI');
    }
    return value;
  }

  AndroidContentUriProvider get contentUriProvider =>
      _AndroidBridgeUriProvider(this);

  AndroidIntentLauncher get intentLauncher =>
      _AndroidBridgeIntentLauncher(_methods);

  Future<List<AndroidIntentTarget>> findIntentTargets({
    required String action,
    String? mimeType,
  }) async {
    final values = await _methods.invokeMethod<List<Object?>>(
      'queryIntentHandlers',
      <String, Object?>{'action': action, 'mimeType': mimeType},
    );
    return [
      for (final value in values ?? const <Object?>[])
        AndroidIntentTarget.fromJson(value),
    ];
  }
}

class AndroidIntentTarget {
  const AndroidIntentTarget({
    required this.label,
    required this.packageName,
    required this.componentName,
  });

  final String label;
  final String packageName;
  final String componentName;

  factory AndroidIntentTarget.fromJson(Object? value) {
    final json = Map<String, Object?>.from(value as Map);
    return AndroidIntentTarget(
      label: json['label'] as String? ?? json['packageName'] as String,
      packageName: json['packageName'] as String,
      componentName: json['componentName'] as String,
    );
  }
}

class _AndroidBridgeUriProvider implements AndroidContentUriProvider {
  _AndroidBridgeUriProvider(this.bridge);

  final AndroidShareBridge bridge;

  @override
  Future<String> uriFor(ActentAttachment attachment) =>
      bridge.createContentUri(attachment);
}

class _AndroidBridgeIntentLauncher implements AndroidIntentLauncher {
  _AndroidBridgeIntentLauncher(this.channel);

  final MethodChannel channel;

  @override
  Future<void> launch(AndroidIntentRequest request) async {
    await channel.invokeMethod<void>('launchIntent', <String, Object?>{
      'action': request.action,
      'dataUri': request.dataUri,
      'mimeType': request.mimeType,
      'categories': request.categories,
      'extras': request.extras,
      'chooser': request.chooser,
      'packageName': request.packageName,
      'componentName': request.componentName,
      'grantReadPermission': request.grantReadPermission,
    });
  }
}
