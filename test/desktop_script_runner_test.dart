import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/work/desktop/desktop_script_runner.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  test('writes one JSON document to stdin and bounds stderr', () async {
    final process = _FakeScriptProcess(
      onClose: (process) {
        process.stdoutController.add(utf8.encode('ignored stdout'));
        process.stderrController.add(
          utf8.encode(List.filled(9000, 'x').join()),
        );
        process.complete(7);
      },
    );
    final runner = DesktopScriptRunner(
      config: DesktopScriptConfig(
        executable: 'script',
        timeout: const Duration(seconds: 1),
      ),
      launcher: _FakeLauncher(process),
    );

    final result = await runner.run(
      _work(),
      _message(),
      requestId: 'request-1',
      cancellation: CancellationToken(),
    );

    final decoded = jsonDecode(utf8.decode(process.stdinBytes));
    expect(decoded, containsPair('type', 'text'));
    expect(decoded['data'], containsPair('text', 'hello'));
    expect(decoded, isNot(contains('payload')));
    expect(result.status, WorkReceiptStatus.failed);
    expect(result.errorCode, 'exit_code_7');
    expect(result.summary!.length, 9000);
    expect(result.diagnostics!.stderr!.length, 9000);
    expect(process.terminated, isFalse);
  });

  test('terminates the full process tree on timeout', () async {
    final process = _FakeScriptProcess();
    final runner = DesktopScriptRunner(
      config: DesktopScriptConfig(
        executable: 'script',
        timeout: const Duration(milliseconds: 20),
      ),
      launcher: _FakeLauncher(process),
    );

    final result = await runner.run(
      _work(),
      _message(),
      requestId: 'request-1',
      cancellation: CancellationToken(),
    );

    expect(result.errorCode, 'timeout');
    expect(process.terminated, isTrue);
  });

  test('resolves secret environment values only at process launch', () async {
    final process = _FakeScriptProcess(
      onClose: (process) => process.complete(0),
    );
    final launcher = _FakeLauncher(process);
    final runner = DesktopScriptRunner(
      config: DesktopScriptConfig(
        executable: 'script',
        environment: const {'MODE': 'safe'},
        secretEnvironment: const {'API_KEY': 'api-key'},
      ),
      launcher: launcher,
      secrets: _FakeSecretResolver(),
    );

    final result = await runner.run(
      _work(),
      _message(),
      requestId: 'request-secret',
      cancellation: CancellationToken(),
    );

    expect(result.status, WorkReceiptStatus.succeeded);
    expect(launcher.lastConfig!.environment, {
      'MODE': 'safe',
      'API_KEY': 'resolved-secret',
    });
    expect(launcher.lastConfig!.secretEnvironment, {'API_KEY': 'api-key'});
  });
}

Work _work() => Work(
  id: 'work-1',
  revision: 1,
  name: 'script',
  ownerDeviceId: 'desktop',
  acceptedContentTypes: const {ActentContentType.text},
);

ActentMessage _message() => ActentMessage(
  id: 'message-1',
  traceId: 'trace-1',
  createdAt: DateTime.utc(2026),
  source: const ActentSource(kind: 'test'),
  content: ActentContent(
    type: ActentContentType.text,
    data: const {'text': 'hello'},
  ),
);

class _FakeLauncher implements ScriptProcessLauncher {
  _FakeLauncher(this.process);

  final _FakeScriptProcess process;
  DesktopScriptConfig? lastConfig;

  @override
  Future<ScriptProcess> start(DesktopScriptConfig config) async {
    lastConfig = config;
    return process;
  }
}

class _FakeSecretResolver implements DesktopSecretResolver {
  @override
  Future<String?> resolve(String name) async =>
      name == 'api-key' ? 'resolved-secret' : null;
}

class _FakeScriptProcess implements ScriptProcess {
  _FakeScriptProcess({this.onClose});

  final void Function(_FakeScriptProcess process)? onClose;
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final List<int> stdinBytes = [];
  var terminated = false;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<void> writeStdin(List<int> bytes) async => stdinBytes.addAll(bytes);

  @override
  Future<void> closeStdin() async => onClose?.call(this);

  @override
  Future<void> terminateTree() async {
    terminated = true;
    complete(-9);
  }

  void complete(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (!stdoutController.isClosed) stdoutController.close();
    if (!stderrController.isClosed) stderrController.close();
  }
}
