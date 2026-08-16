import 'package:flutter/widgets.dart';

Route<dynamic> onGenerateRoute(RouteSettings settings) =>
    PageRouteBuilder<void>(pageBuilder: (_, _, _) => const Placeholder());
