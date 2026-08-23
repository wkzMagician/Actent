import 'dart:convert';

import 'android/android_work_runner.dart';
import 'desktop/desktop_script_runner.dart';
import 'ios/ios_work_runner.dart';
import 'web_js_work.dart';
import '../actent_core/actent_models.dart';

class WorkBindingException implements Exception {
  const WorkBindingException(this.message);

  final String message;

  @override
  String toString() => 'Invalid Work binding: $message';
}

class DesktopScriptBinding {
  const DesktopScriptBinding({
    required this.executable,
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
    this.secretEnvironment = const {},
    this.timeout,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Map<String, String> secretEnvironment;
  final Duration? timeout;

  factory DesktopScriptBinding.fromWork(Work work) {
    final binding = _binding(work, 'desktop-script');
    return DesktopScriptBinding(
      executable: _string(binding, 'executable'),
      arguments: _stringList(binding['arguments'], 'arguments'),
      workingDirectory: _optionalString(binding, 'workingDirectory'),
      environment: _stringMap(binding['environment'], 'environment'),
      secretEnvironment: _stringMap(
        binding['secretEnvironment'],
        'secretEnvironment',
      ),
      timeout: _duration(binding['timeoutSeconds'], 'timeoutSeconds'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'desktop-script',
    'executable': executable,
    'arguments': arguments,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    'environment': environment,
    'secretEnvironment': secretEnvironment,
    if (timeout != null) 'timeoutSeconds': timeout!.inSeconds,
  };

  DesktopScriptConfig toConfig(Work work) => DesktopScriptConfig(
    executable: executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    secretEnvironment: secretEnvironment,
    timeout: timeout ?? work.timeout,
  );
}

class DesktopShellBinding {
  const DesktopShellBinding({required this.source, required this.shell});

  final String source;
  final String shell;

  factory DesktopShellBinding.fromWork(Work work) {
    final binding = _binding(work, 'desktop-shell');
    return DesktopShellBinding(
      source: _string(binding, 'source'),
      shell: _optionalString(binding, 'shell') ?? 'bash',
    );
  }

  DesktopScriptConfig toConfig(Work work) => DesktopScriptConfig(
    executable: shell,
    arguments: _isPowerShell(shell)
        ? <String>[
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-EncodedCommand',
            base64Encode(_utf16Le(_powerShellBootstrap(source))),
          ]
        : <String>['-c', source],
    timeout: work.timeout,
    validateExecutable: false,
  );
}

bool _isPowerShell(String value) {
  final name = value.replaceAll('\\', '/').split('/').last.toLowerCase();
  return name == 'powershell' ||
      name == 'powershell.exe' ||
      name == 'pwsh' ||
      name == 'pwsh.exe';
}

String _powerShellBootstrap(String source) =>
    '''
\$actentUtf8 = New-Object System.Text.UTF8Encoding(\$false)
[Console]::InputEncoding = \$actentUtf8
[Console]::OutputEncoding = \$actentUtf8
\$OutputEncoding = \$actentUtf8
$source
''';

List<int> _utf16Le(String value) {
  final bytes = <int>[];
  for (final codeUnit in value.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add(codeUnit >> 8);
  }
  return bytes;
}

class DesktopFileBinding {
  const DesktopFileBinding({required this.path});

  final String path;

  factory DesktopFileBinding.fromWork(Work work) {
    final binding = _binding(work, 'desktop-file');
    return DesktopFileBinding(path: _string(binding, 'path'));
  }
}

class AndroidIntentBinding {
  const AndroidIntentBinding(this.spec);

  final AndroidIntentSpec spec;

  factory AndroidIntentBinding.fromWork(Work work) {
    final binding = _binding(work, 'android-intent');
    final rawExtras = binding['extras'];
    if (rawExtras is! Map) {
      throw const WorkBindingException('extras must be an object');
    }
    return AndroidIntentBinding(
      AndroidIntentSpec(
        action: _string(binding, 'action'),
        dataUriTemplate: _optionalString(binding, 'dataUriTemplate'),
        mimeType: _optionalString(binding, 'mimeType'),
        categories: _stringList(binding['categories'], 'categories'),
        extras: {
          for (final entry in rawExtras.entries)
            _mapKey(entry.key): _androidExtra(entry.value),
        },
        packageName: _optionalString(binding, 'packageName'),
        componentName: _optionalString(binding, 'componentName'),
        chooser: binding['chooser'] == true,
        attachmentPlacement: _attachmentPlacement(
          binding['attachmentPlacement'],
        ),
      ),
    );
  }
}

class AndroidHttpBinding {
  const AndroidHttpBinding(this.spec);

  final AndroidHttpSpec spec;

  factory AndroidHttpBinding.fromWork(Work work) {
    final binding = Map<String, Object?>.from(work.platformBindings);
    if (binding['kind'] != 'android-http' && binding['kind'] != 'http') {
      throw WorkBindingException(
        'Work ${work.id} requires http binding, got ${binding['kind']}',
      );
    }
    return AndroidHttpBinding(
      AndroidHttpSpec(
        urlTemplate: _string(binding, 'urlTemplate'),
        method: _optionalString(binding, 'method') ?? 'POST',
        headers: _stringMap(binding['headers'], 'headers'),
        bodyTemplate: _optionalString(binding, 'bodyTemplate'),
        timeout:
            _duration(binding['timeoutSeconds'], 'timeoutSeconds') ??
            const Duration(seconds: 30),
      ),
    );
  }
}

class IosUrlBinding {
  const IosUrlBinding({required this.urlTemplate});

  final String urlTemplate;

  factory IosUrlBinding.fromWork(Work work) {
    final binding = _binding(work, 'ios-url');
    return IosUrlBinding(urlTemplate: _string(binding, 'urlTemplate'));
  }

  IosUrlWorkRunner toRunner() => IosUrlWorkRunner(urlTemplate: urlTemplate);
}

class WebJsBinding {
  const WebJsBinding({required this.source, this.allowedHosts = const []});

  final String source;
  final List<String> allowedHosts;

  factory WebJsBinding.fromWork(Work work) {
    final binding = _binding(work, 'web-js');
    return WebJsBinding(
      source: _string(binding, 'source'),
      allowedHosts: _stringList(binding['allowedHosts'], 'allowedHosts'),
    );
  }

  WebJsWorkConfig toConfig() =>
      WebJsWorkConfig(source: source, allowedHosts: allowedHosts);
}

Map<String, Object?> _binding(Work work, String kind) {
  final binding = Map<String, Object?>.from(work.platformBindings);
  if (binding['kind'] != kind) {
    throw WorkBindingException(
      'Work ${work.id} requires $kind binding, got ${binding['kind']}',
    );
  }
  return binding;
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw WorkBindingException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) throw WorkBindingException('$key must be a string');
  return value;
}

List<String> _stringList(Object? value, String key) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw WorkBindingException('$key must be an array of strings');
  }
  return List<String>.from(value);
}

Map<String, String> _stringMap(Object? value, String key) {
  if (value == null) return const {};
  if (value is! Map ||
      value.keys.any((item) => item is! String) ||
      value.values.any((item) => item is! String)) {
    throw WorkBindingException('$key must be a string map');
  }
  return Map<String, String>.from(value);
}

Duration? _duration(Object? value, String key) {
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw WorkBindingException('$key must be a positive integer');
  }
  return Duration(seconds: value);
}

String _mapKey(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const WorkBindingException('extra keys must be non-empty strings');
  }
  return value;
}

AndroidExtra _androidExtra(Object? value) {
  if (value is String) return AndroidExtra.text(value);
  if (value is bool) return AndroidExtra.boolean(value);
  if (value is num) return AndroidExtra.number(value);
  if (value is List && value.every((item) => item is String)) {
    return AndroidExtra.stringList(List<String>.from(value));
  }
  throw const WorkBindingException('unsupported Android extra type');
}

AndroidAttachmentPlacement _attachmentPlacement(Object? value) =>
    switch (value) {
      null || 'none' => AndroidAttachmentPlacement.none,
      'stream' => AndroidAttachmentPlacement.stream,
      'streams' => AndroidAttachmentPlacement.streams,
      _ => throw const WorkBindingException('unsupported attachment placement'),
    };
