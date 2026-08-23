import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../actent_core/actent_models.dart';
import '../work_runner.dart';
import '../work_output.dart';

class DesktopScriptConfig {
  DesktopScriptConfig({
    required this.executable,
    List<String> arguments = const [],
    this.workingDirectory,
    Map<String, String> environment = const {},
    Map<String, String> secretEnvironment = const {},
    this.timeout = const Duration(hours: 24),
    this.validateExecutable = true,
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment),
       secretEnvironment = Map.unmodifiable(secretEnvironment);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Map<String, String> secretEnvironment;
  final Duration timeout;
  final bool validateExecutable;

  Future<void> validate() async {
    if (executable.trim().isEmpty) {
      throw ArgumentError.value(executable, 'executable');
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (validateExecutable && !await File(executable).exists()) {
      throw FileSystemException('script executable does not exist', executable);
    }
    if (workingDirectory != null &&
        !await Directory(workingDirectory!).exists()) {
      throw FileSystemException(
        'script working directory does not exist',
        workingDirectory,
      );
    }
    if (secretEnvironment.keys.any((key) => key.isEmpty) ||
        secretEnvironment.values.any((key) => key.isEmpty)) {
      throw ArgumentError.value(
        secretEnvironment,
        'secretEnvironment',
        'environment and secret names must not be empty',
      );
    }
  }
}

abstract interface class ScriptProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  Future<void> writeStdin(List<int> bytes);
  Future<void> closeStdin();
  Future<void> terminateTree();
}

abstract interface class ScriptProcessLauncher {
  Future<ScriptProcess> start(DesktopScriptConfig config);
}

abstract interface class DesktopSecretResolver {
  Future<String?> resolve(String name);
}

class IoScriptProcessLauncher implements ScriptProcessLauncher {
  const IoScriptProcessLauncher();

  @override
  Future<ScriptProcess> start(DesktopScriptConfig config) async {
    final process = await Process.start(
      config.executable,
      config.arguments,
      workingDirectory: config.workingDirectory,
      environment: config.environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    return _IoScriptProcess(process);
  }
}

class _IoScriptProcess implements ScriptProcess {
  _IoScriptProcess(this.process);

  final Process process;

  @override
  Stream<List<int>> get stdout => process.stdout;

  @override
  Stream<List<int>> get stderr => process.stderr;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  Future<void> writeStdin(List<int> bytes) async {
    process.stdin.add(bytes);
    await process.stdin.flush();
  }

  @override
  Future<void> closeStdin() => process.stdin.close();

  @override
  Future<void> terminateTree() async {
    if (Platform.isWindows) {
      await Process.run('taskkill', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]);
    } else {
      process.kill(ProcessSignal.sigterm);
    }
  }
}

class DesktopScriptRunner implements WorkRunner {
  DesktopScriptRunner({
    required this.config,
    ScriptProcessLauncher? launcher,
    this.secrets,
    this.maxStderrBytes = 64 * 1024,
    this.maxStdoutBytes = 1024 * 1024,
  }) : _launcher = launcher ?? const IoScriptProcessLauncher();

  final DesktopScriptConfig config;
  final ScriptProcessLauncher _launcher;
  final DesktopSecretResolver? secrets;
  final int maxStderrBytes;
  final int maxStdoutBytes;

  @override
  String get id => 'desktop-script';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return const WorkRunResult.failure(errorCode: 'cancelled');
    }
    final runtimeConfig = await _resolveConfig();
    if (runtimeConfig == null) {
      return const WorkRunResult.failure(errorCode: 'secret_unavailable');
    }
    final startedAt = DateTime.now().toUtc();
    final process = await _launcher.start(runtimeConfig);
    final stderr = BytesBuilder(copy: false);
    final stdout = BytesBuilder(copy: false);
    var stdoutTruncated = false;
    var stderrTruncated = false;
    final stdoutDone = process.stdout.listen((chunk) {
      if (stdout.length < maxStdoutBytes) {
        final remaining = maxStdoutBytes - stdout.length;
        stdout.add(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
        if (chunk.length > remaining) stdoutTruncated = true;
      } else {
        stdoutTruncated = true;
      }
    }).asFuture<void>();
    final stderrDone = process.stderr.listen((chunk) {
      if (stderr.length < maxStderrBytes) {
        final remaining = maxStderrBytes - stderr.length;
        stderr.add(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
        if (chunk.length > remaining) stderrTruncated = true;
      } else {
        stderrTruncated = true;
      }
    }).asFuture<void>();
    try {
      await process.writeStdin(
        utf8.encode(jsonEncode(message.payload.toJson())),
      );
      await process.closeStdin();
      final exitCode = await _waitForExit(process, cancellation);
      await Future.wait<void>([stdoutDone, stderrDone]);
      final completedAt = DateTime.now().toUtc();
      final stdoutText = utf8.decode(stdout.takeBytes(), allowMalformed: true);
      final stderrText = utf8.decode(stderr.takeBytes(), allowMalformed: true);
      final diagnostics = WorkExecutionDiagnostics(
        stage: exitCode == -2
            ? 'timeout'
            : cancellation.isCancelled
            ? 'cancelled'
            : exitCode == 0
            ? 'completed'
            : 'exited',
        startedAt: startedAt,
        completedAt: completedAt,
        exitCode: exitCode < 0 ? null : exitCode,
        stdout: stdoutText.isEmpty ? null : stdoutText,
        stderr: stderrText.isEmpty ? null : stderrText,
        stdoutTruncated: stdoutTruncated,
        stderrTruncated: stderrTruncated,
      );
      if (cancellation.isCancelled) {
        return WorkRunResult.failure(
          errorCode: 'cancelled',
          diagnostics: diagnostics,
        );
      }
      if (exitCode == -2) {
        return WorkRunResult.failure(
          errorCode: 'timeout',
          diagnostics: diagnostics,
        );
      }
      if (exitCode == 0) {
        try {
          return WorkRunResult.success(
            output: parseTextWorkOutput(
              work,
              stdoutText,
              maxTextBytes: maxStdoutBytes,
            ),
            diagnostics: diagnostics,
          );
        } on Object catch (error) {
          return WorkRunResult.failure(
            errorCode: 'output_contract_violated',
            summary: error.toString(),
            diagnostics: diagnostics,
          );
        }
      }
      final summary = stderrText.trim();
      return WorkRunResult.failure(
        errorCode: 'exit_code_$exitCode',
        summary: summary.isEmpty
            ? 'Script exited with code $exitCode.'
            : summary,
        diagnostics: diagnostics,
      );
    } catch (error) {
      await process.terminateTree();
      return WorkRunResult.failure(
        errorCode: 'script_error',
        summary: error.toString(),
        diagnostics: WorkExecutionDiagnostics(
          stage: 'launch',
          startedAt: startedAt,
          completedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<DesktopScriptConfig?> _resolveConfig() async {
    if (config.secretEnvironment.isEmpty) return config;
    final resolver = secrets;
    if (resolver == null) return null;
    final environment = <String, String>{...config.environment};
    for (final entry in config.secretEnvironment.entries) {
      final value = await resolver.resolve(entry.value);
      if (value == null) return null;
      environment[entry.key] = value;
    }
    return DesktopScriptConfig(
      executable: config.executable,
      arguments: config.arguments,
      workingDirectory: config.workingDirectory,
      environment: environment,
      secretEnvironment: config.secretEnvironment,
      timeout: config.timeout,
      validateExecutable: config.validateExecutable,
    );
  }

  Future<int> _waitForExit(
    ScriptProcess process,
    CancellationToken cancellation,
  ) async {
    final deadline = DateTime.now().add(config.timeout);
    while (!cancellation.isCancelled) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        await process.terminateTree();
        return -2;
      }
      try {
        return await process.exitCode.timeout(
          remaining < const Duration(milliseconds: 100)
              ? remaining
              : const Duration(milliseconds: 100),
        );
      } on TimeoutException {
        // Polling makes cancellation responsive while still using the process
        // exit code as the source of truth.
      }
    }
    await process.terminateTree();
    return -1;
  }
}

/// Runs a user-selected program or script through a fixed argument list.
class DesktopFileRunner extends DesktopScriptRunner {
  DesktopFileRunner({required String path, super.secrets})
    : super(config: _configForPath(path));
}

DesktopScriptConfig _configForPath(String path) {
  final extension = path.contains('.')
      ? path.substring(path.lastIndexOf('.') + 1).toLowerCase()
      : '';
  final interpreter = switch (extension) {
    'py' => Platform.isWindows ? 'python.exe' : 'python3',
    'ps1' => Platform.isWindows ? 'powershell.exe' : 'pwsh',
    'sh' || 'bash' => 'bash',
    'zsh' => 'zsh',
    'js' || 'mjs' => Platform.isWindows ? 'node.exe' : 'node',
    'cmd' || 'bat' => 'cmd.exe',
    _ => null,
  };
  if (interpreter == null) {
    return DesktopScriptConfig(executable: path);
  }
  final arguments = switch (extension) {
    'ps1' => ['-NoProfile', '-NonInteractive', '-File', path],
    'cmd' || 'bat' => ['/d', '/s', '/c', path],
    _ => [path],
  };
  return DesktopScriptConfig(
    executable: interpreter,
    arguments: arguments,
    validateExecutable: false,
  );
}
