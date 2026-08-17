import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/work/android/android_work_runner.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  test(
    'maps explicit and chooser intents without exposing file paths',
    () async {
      final launcher = _FakeLauncher();
      final runner = AndroidIntentRunner(
        spec: AndroidIntentSpec(
          action: 'android.intent.action.SEND',
          chooser: true,
          mimeType: 'text/plain',
          extras: <String, AndroidExtra>{
            'subject': AndroidExtra.template('{{content.text}}'),
            'attachment': AndroidExtra.attachmentUri(0),
          },
          attachmentPlacement: AndroidAttachmentPlacement.stream,
          packageName: 'com.example.target',
        ),
        uriProvider: MemoryAndroidUriProvider(),
        launcher: launcher,
      );

      final result = await runner.run(
        _work(),
        _message(),
        requestId: 'request-1',
        cancellation: CancellationToken(),
      );

      expect(result.summary, 'launch_attempted');
      expect(launcher.request!.chooser, isTrue);
      expect(launcher.request!.packageName, 'com.example.target');
      expect(launcher.request!.extras['subject'], 'hello');
      expect(launcher.request!.extras['android.intent.extra.TEXT'], 'hello');
      expect(launcher.request!.extras['attachment'], startsWith('content://'));
      expect(
        launcher.request!.extras['attachment'],
        isNot(contains('/private/')),
      );
    },
  );

  test(
    'rejects unknown placeholders and supports typed HTTP secrets',
    () async {
      final launcher = _FakeLauncher();
      final intentRunner = AndroidIntentRunner(
        spec: const AndroidIntentSpec(
          dataUriTemplate: '{{unsupported.value}}',
          action: 'VIEW',
        ),
        uriProvider: MemoryAndroidUriProvider(),
        launcher: launcher,
      );
      final failed = await intentRunner.run(
        _work(),
        _message(),
        requestId: 'request-1',
        cancellation: CancellationToken(),
      );
      expect(failed.errorCode, 'invalid_intent');

      final client = _FakeHttpClient();
      final httpRunner = AndroidHttpRunner(
        spec: const AndroidHttpSpec(
          urlTemplate: 'https://example.test/{{message.id}}',
          headers: <String, String>{'Authorization': '{{secret:token}}'},
          bodyTemplate: '{"text":"{{content.text}}"}',
        ),
        client: client,
        secrets: _FakeSecrets(),
      );
      final result = await httpRunner.run(
        _work(),
        _message(),
        requestId: 'request-1',
        cancellation: CancellationToken(),
      );
      expect(result.status, WorkReceiptStatus.succeeded);
      expect(client.headers['Authorization'], 'Bearer test-token');
      expect(client.body, '{"text":"hello"}');
    },
  );
}

Work _work() => Work(
  id: 'work-1',
  revision: 1,
  name: 'android',
  ownerDeviceId: 'phone',
  acceptedContentTypes: const {ActentContentType.text},
);

ActentMessage _message() => ActentMessage(
  id: 'message-1',
  traceId: 'trace-1',
  createdAt: DateTime.utc(2026),
  source: const ActentSource(kind: 'share'),
  content: ActentContent(
    type: ActentContentType.text,
    data: const {'text': 'hello'},
  ),
  attachments: const [
    ActentAttachment(
      id: 'attachment-1',
      name: 'note.txt',
      mimeType: 'text/plain',
      byteLength: 5,
      handle: '/private/note.txt',
    ),
  ],
);

class _FakeLauncher implements AndroidIntentLauncher {
  AndroidIntentRequest? request;

  @override
  Future<void> launch(AndroidIntentRequest request) async =>
      this.request = request;
}

class _FakeHttpClient implements AndroidHttpClient {
  Map<String, String> headers = {};
  String? body;

  @override
  Future<HttpExecutionResult> execute({
    required Uri url,
    required String method,
    required Map<String, String> headers,
    required String? body,
    required Duration timeout,
  }) async {
    this.headers = headers;
    this.body = body;
    return const HttpExecutionResult(statusCode: 200, safeSummary: 'ok');
  }
}

class _FakeSecrets implements SecretResolver {
  @override
  Future<String?> resolve(String name) async => 'Bearer test-token';
}
