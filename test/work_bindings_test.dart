import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/work/android/android_work_runner.dart';
import 'package:actent/features/work/work_bindings.dart';

void main() {
  test('round trips a desktop script binding without shell semantics', () {
    final work = Work(
      id: 'script',
      revision: 1,
      name: 'Run script',
      ownerDeviceId: 'desktop',
      platformBindings: const {
        'kind': 'desktop-script',
        'executable': 'C:/tools/worker.exe',
        'arguments': ['--fixed', 'value'],
        'environment': {'MODE': 'safe'},
        'timeoutSeconds': 30,
      },
    );
    final binding = DesktopScriptBinding.fromWork(work);
    expect(binding.arguments, ['--fixed', 'value']);
    expect(binding.toConfig(work).environment['MODE'], 'safe');
  });

  test('maps typed Android Work bindings and rejects unknown extras', () {
    final work = Work(
      id: 'share',
      revision: 1,
      name: 'Share',
      ownerDeviceId: 'phone',
      platformBindings: const {
        'kind': 'android-intent',
        'action': 'android.intent.action.SEND',
        'categories': ['android.intent.category.DEFAULT'],
        'extras': {'priority': 2, 'label': 'Actent'},
        'chooser': true,
        'attachmentPlacement': 'stream',
      },
    );
    final spec = AndroidIntentBinding.fromWork(work).spec;
    expect(spec.chooser, isTrue);
    expect(spec.extras['priority']!.value, 2);
    expect(spec.attachmentPlacement, AndroidAttachmentPlacement.stream);

    final invalid = Work(
      id: 'invalid',
      revision: 1,
      name: 'Invalid',
      ownerDeviceId: 'phone',
      platformBindings: const {
        'kind': 'android-intent',
        'action': 'android.intent.action.SEND',
        'extras': {
          'unknown': {'parcelable': true},
        },
      },
    );
    expect(
      () => AndroidIntentBinding.fromWork(invalid),
      throwsA(isA<WorkBindingException>()),
    );
  });
}
