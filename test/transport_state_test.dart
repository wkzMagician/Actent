import 'dart:typed_data';

import 'package:actent/features/actent_core/actent_attachment_transfer.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/actent_transport_state.dart';
import 'package:actent/features/messaging/attachment_chunks.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'durable transport state round-trips and expires after seven days',
    () async {
      var now = DateTime.utc(2026, 8, 24);
      final store = MemoryActentJsonStore();
      final states = ActentTransportStateStore(store, clock: () => now);
      await states.saveOutgoing(
        OutgoingTransportState(
          requestId: 'request-1',
          recipientId: 'device-2',
          control: const <String, Object?>{'type': 'workRequest'},
          transfers: const <Map<String, Object?>>[],
          createdAt: now,
        ),
      );
      await states.saveIncoming(
        IncomingTransportState(
          requestId: 'request-2',
          senderId: 'device-2',
          payload: const <String, Object?>{'type': 'workRequest'},
          createdAt: now,
        ),
      );
      await states.rememberPacket('packet-1');
      await states.markCompleted('request-0');

      expect((await states.listOutgoing()).single.requestId, 'request-1');
      expect((await states.listIncoming()).single.senderId, 'device-2');
      expect(await states.isCompleted('request-0'), isTrue);
      expect(await states.loadSeenPackets(), contains('packet-1'));

      now = now.add(const Duration(days: 8));
      await states.purgeExpired();
      expect(await states.listOutgoing(), isEmpty);
      expect(await states.listIncoming(), isEmpty);
      expect(await states.isCompleted('request-0'), isFalse);
      expect(await states.loadSeenPackets(), isEmpty);
    },
  );

  test(
    'ObjectStore attachment sink resumes chunks after reconstruction',
    () async {
      final objectStore = MemoryObjectStore();
      final manifest = AttachmentManifest(
        messageId: 'message-1',
        attachmentId: 'attachment-1',
        name: 'note.txt',
        mimeType: 'text/plain',
        byteLength: 6,
        chunkSize: 3,
        sha256:
            'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721',
      );
      final first = ActentObjectStoreAttachmentSink(objectStore);
      await first.begin(manifest);
      await first.writeChunk(
        manifest,
        0,
        Uint8List.fromList(<int>[97, 98, 99]),
      );

      final restored = ActentObjectStoreAttachmentSink(objectStore);
      await restored.begin(manifest);
      expect(await restored.receivedChunkIndexes(manifest), <int>{0});
      await restored.writeChunk(
        manifest,
        1,
        Uint8List.fromList(<int>[100, 101, 102]),
      );
      await restored.commit(manifest);

      expect(restored.completedHandle, startsWith('actent-indexeddb://'));
      final key = restored.completedHandle!.substring(
        'actent-indexeddb://'.length,
      );
      expect(await objectStore.read(key), <int>[97, 98, 99, 100, 101, 102]);
    },
  );
}
