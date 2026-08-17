import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/work/web_js_work.dart';
import 'package:actent/features/work/work_bindings.dart';

void main() {
  test('parses a Web JavaScript Work binding with explicit hosts', () {
    final work = Work(
      id: 'web-script',
      revision: 1,
      name: 'Web script',
      ownerDeviceId: 'device',
      platformBindings: const {
        'kind': 'web-js',
        'source': 'return input.content;',
        'allowedHosts': ['api.example.com'],
      },
    );

    final config = WebJsBinding.fromWork(work).toConfig();

    expect(config.source, 'return input.content;');
    expect(config.allowedHosts, ['api.example.com']);
    expect(WebJsWorkRunner(config).id, 'web-js');
  });
}
