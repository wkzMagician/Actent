import 'dart:io';

import 'pigeon_store.dart';
import 'secret_repository.dart';

enum AttachmentRetention { oneDay, sevenDays, oneMonth, forever }

class AttachmentRetentionPreferences {
  const AttachmentRetentionPreferences(this.secrets);

  final PigeonSecretRepository secrets;

  Future<AttachmentRetention> load() async {
    final value = await secrets.read('retention.attachments');
    return AttachmentRetention.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AttachmentRetention.sevenDays,
    );
  }

  Future<void> save(AttachmentRetention value) =>
      secrets.write('retention.attachments', value.name);
}

class PacketDedupRetentionPreferences {
  const PacketDedupRetentionPreferences(this.secrets);

  final PigeonSecretRepository secrets;

  Future<Duration> load() async {
    final days = int.tryParse(
      await secrets.read('retention.packetDedup') ?? '',
    );
    return Duration(days: days != null && days > 0 ? days : 7);
  }

  Future<void> save(Duration value) {
    if (value <= Duration.zero) throw ArgumentError.value(value, 'value');
    return secrets.write('retention.packetDedup', '${value.inDays}');
  }
}

extension AttachmentRetentionDuration on AttachmentRetention {
  Duration? get duration => switch (this) {
    AttachmentRetention.oneDay => const Duration(days: 1),
    AttachmentRetention.sevenDays => const Duration(days: 7),
    AttachmentRetention.oneMonth => const Duration(days: 30),
    AttachmentRetention.forever => null,
  };
}

/// Deletes only Pigeon-owned attachment files and only after their message
/// reference has disappeared. Handles outside [root] are ignored.
class AttachmentRetentionManager {
  AttachmentRetentionManager({
    required this.repository,
    required this.root,
    this.clock = _now,
  });

  final PigeonRepository repository;
  final Directory root;
  final DateTime Function() clock;

  Future<void> deleteMessage(String messageId) async {
    final message = await repository.getMessage(messageId);
    if (message == null) return;
    final handles = message.attachments.map((attachment) => attachment.handle);
    await repository.deleteMessage(messageId);
    final remaining = await repository.listMessages();
    final referenced = {
      for (final item in remaining)
        for (final attachment in item.attachments) attachment.handle,
    };
    for (final handle in handles) {
      if (!referenced.contains(handle)) await _deleteOwned(handle);
    }
  }

  Future<int> purgeExpired({
    AttachmentRetention retention = AttachmentRetention.sevenDays,
  }) async {
    final duration = retention.duration;
    if (duration == null) return 0;
    final cutoff = clock().toUtc().subtract(duration);
    var deleted = 0;
    for (final message in await repository.listMessages()) {
      if (message.createdAt.isBefore(cutoff)) {
        await deleteMessage(message.id);
        deleted++;
      }
    }
    return deleted;
  }

  Future<void> _deleteOwned(String handle) async {
    final file = File(handle).absolute;
    final rootPath = root.absolute.path;
    final filePath = file.path;
    if (!filePath.startsWith('$rootPath${Platform.pathSeparator}')) return;
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (parent.path != rootPath && await parent.exists()) {
      try {
        await parent.delete();
      } on FileSystemException {
        // The directory is non-empty or concurrently in use.
      }
    }
  }
}

DateTime _now() => DateTime.now().toUtc();
