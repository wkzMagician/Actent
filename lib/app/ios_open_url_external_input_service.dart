import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';

/// Receives URLs and files used to open the iOS application itself.
///
/// This is intentionally independent of the Share Extension inbox. In
/// particular, LiveContainer forwards its Share Extension selection to the
/// guest application's normal open-URL lifecycle, so it arrives here just as
/// it would from any other iOS opener.
final class IosOpenUrlExternalInputService implements ExternalInputService {
  IosOpenUrlExternalInputService({EventChannel? events, MethodChannel? methods})
    : _events = events ?? const EventChannel(_eventChannelName),
      _methods = methods ?? const MethodChannel(_methodChannelName);

  static const _eventChannelName = 'actent/ios_open_url/events';
  static const _methodChannelName = 'actent/ios_open_url/methods';

  final EventChannel _events;
  final MethodChannel _methods;
  Stream<ExternalInputBatch>? _inputs;

  @override
  Stream<ExternalInputBatch> get inputs => _inputs ??= _events
      .receiveBroadcastStream()
      .map(ExternalInputBatch.fromJson);

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    final values = await _methods.invokeMethod<List<Object?>>('takePending');
    return [
      for (final value in values ?? const <Object?>[])
        ExternalInputBatch.fromJson(value),
    ];
  }
}
