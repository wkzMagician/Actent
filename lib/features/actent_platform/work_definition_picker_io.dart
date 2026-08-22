import 'package:file_selector/file_selector.dart';

Future<String?> pickWorkDefinitionFile() async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Programs and scripts',
        extensions: [
          'exe',
          'py',
          'ps1',
          'sh',
          'bash',
          'zsh',
          'js',
          'mjs',
          'cmd',
          'bat',
        ],
      ),
    ],
  );
  return file?.path;
}
