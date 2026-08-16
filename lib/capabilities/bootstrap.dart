import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:flutter/widgets.dart';

import 'capabilities.dart';

/// Dartloom-owned startup fragment. Call this from the application's main
/// method before creating its widget tree.
Future<void> bootstrapDartloom({
  Map<String, DartloomFactory> customFactories = const {},
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDartloom(customFactories: customFactories);
}
