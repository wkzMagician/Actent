import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../pigeon_core/pigeon_models.dart';
import '../work_runner.dart';

class DesktopScriptConfig {
  DesktopScriptConfig({
    required this.executable,
    List<String> arguments = const [],
    this.workingDirectory,
    Map<String, String> environment = const {},
    Map<String, String> secretEnvironment = const {},
    this.timeout = const Duration(hours: 24),
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment),
       secretEnvironment = Map.unmodifiable(secretEnvironment);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Map<String, String> secretEnvironment;
  final Duration timeout;

  Future<void> validate() async {
    if (executable.trim().isEmpty) {
      throw ArgumentError.value(executable, 'executable');
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (!await File(executable).exists()) {
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
    this.maxStderrBytes = 8 * 1024,
  }) : _launcher = launcher ?? const IoScriptProcessLauncher();

  final DesktopScriptConfig config;
  final ScriptProcessLauncher _launcher;
  final DesktopSecretResolver? secrets;
  final int maxStderrBytes;

  @override
  String get id => 'desktop-script';

  @override
  Future<WorkRunResult> run(
    Work work,
    PigeonMessage message, {
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
    final process = await _launcher.start(runtimeConfig);
    final stderr = BytesBuilder(copy: false);
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.listen((chunk) {
      if (stderr.length < maxStderrBytes) {
        final remaining = maxStderrBytes - stderr.length;
        stderr.add(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
      }
    }).asFuture<void>();
    try {
      await process.writeStdin(utf8.encode(jsonEncode(message.toJson())));
      await process.closeStdin();
      final exitCode = await _waitForExit(process, cancellation);
      await Future.wait<void>([stdoutDone, stderrDone]);
      if (cancellation.isCancelled) {
        return const WorkRunResult.failure(errorCode: 'cancelled');
      }
      if (exitCode == -2) {
        return const WorkRunResult.failure(errorCode: 'timeout');
      }
      if (exitCode == 0) return const WorkRunResult.success();
      final summary = utf8
          .decode(stderr.takeBytes(), allowMalformed: true)
          .trim();
      return WorkRunResult.failure(
        errorCode: 'exit_code_$exitCode',
        summary: summary.isEmpty
            ? 'Script exited with code $exitCode.'
            : summary,
      );
    } catch (error) {
      await process.terminateTree();
      return WorkRunResult.failure(
        errorCode: 'script_error',
        summary: error.toString(),
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
