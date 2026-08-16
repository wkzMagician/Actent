import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('singleton contract forwards second-instance arguments', () async {
    final service = MemorySingleInstanceService();
    final received = <List<String>>[];
    await service.configure(SingleInstanceConfiguration(onArgs: received.add));

    final subscription = service.onSecondInstance.listen((args) {
      received.add(args);
    });
    service.emit(['--open', 'item']);
    await Future<void>.delayed(Duration.zero);

    expect(received, [
      ['--open', 'item'],
      ['--open', 'item'],
    ]);
    await subscription.cancel();
    await service.dispose();
  });
}
