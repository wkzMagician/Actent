import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';

/// Reads iOS pasteboard item providers, including files copied in Files.
final class ActentIosClipboardExternalInputReader
    implements ClipboardExternalInputReader {
  ActentIosClipboardExternalInputReader({MethodChannel? methods})
    : _methods = methods ?? const MethodChannel(_channelName);

  static const _channelName = 'actent/ios_clipboard';
  final MethodChannel _methods;

  @override
  Future<ClipboardReadResult> read({String? afterChangeToken}) async {
    final value = await _methods.invokeMethod<Object?>('read', {
      'afterChangeToken': ?afterChangeToken,
    });
    return ClipboardReadResult.fromJson(value);
  }
}
