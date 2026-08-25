import 'dart:async';

import 'package:actent/app/optional_ios_inbox_external_input_service.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'treats a missing side-loaded App Group container as optional',
    () async {
      final service = OptionalIosInboxExternalInputService(
        _ThrowingService(
          PlatformException(
            code: 'external_input_inbox_error',
            message: "The file doesn't exist.",
          ),
        ),
      );

      expect(await service.takePending(), isEmpty);
      expect(await service.inputs.toList(), isEmpty);
    },
  );

  test('preserves unrelated inbox errors', () async {
    final service = OptionalIosInboxExternalInputService(
      _ThrowingService(
        PlatformException(
          code: 'external_input_inbox_error',
          message: 'The data is corrupted.',
        ),
      ),
    );

    await expectLater(service.takePending(), throwsA(isA<PlatformException>()));
    await expectLater(
      service.inputs.toList(),
      throwsA(isA<PlatformException>()),
    );
  });
}

final class _ThrowingService implements ExternalInputService {
  _ThrowingService(this.error);

  final Object error;

  @override
  Stream<ExternalInputBatch> get inputs => Stream.error(error);

  @override
  Future<List<ExternalInputBatch>> takePending() => Future.error(error);
}
