import 'package:flutter/services.dart';

import '../pigeon_core/pigeon_models.dart';
import '../work/android/android_work_runner.dart';

const _channelName = 'pengion/android_share';

class AndroidShareBridge {
  AndroidShareBridge({EventChannel? events, MethodChannel? methods})
    : _events = events ?? const EventChannel(_channelName),
      _methods = methods ?? const MethodChannel(_channelName);

  final EventChannel _events;
  final MethodChannel _methods;

  Stream<PigeonMessage> get messages =>
      _events.receiveBroadcastStream().map(PigeonMessage.fromJson);

  Future<String> createContentUri(PigeonAttachment attachment) async {
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
}

class _AndroidBridgeUriProvider implements AndroidContentUriProvider {
  _AndroidBridgeUriProvider(this.bridge);

  final AndroidShareBridge bridge;

  @override
  Future<String> uriFor(PigeonAttachment attachment) =>
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
