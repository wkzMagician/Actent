import '../actent_core/actent_models.dart';
import '../actent_core/actent_store.dart';

abstract interface class WorkRunner {
  String get id;

  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  });
}

class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class WorkRunResult {
  const WorkRunResult.success({this.summary})
    : status = WorkReceiptStatus.succeeded,
      errorCode = null;

  const WorkRunResult.stored({this.summary})
    : status = WorkReceiptStatus.stored,
      errorCode = null;

  const WorkRunResult.failure({required this.errorCode, this.summary})
    : status = WorkReceiptStatus.failed;

  final WorkReceiptStatus status;
  final String? errorCode;
  final String? summary;
}

class NullWorkRunner implements WorkRunner {
  const NullWorkRunner();

  @override
  String get id => 'null';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async =>
      const WorkRunResult.stored(summary: 'Message stored by Null Work.');
}

class FakeWorkRunner implements WorkRunner {
  FakeWorkRunner({this.result = const WorkRunResult.success()});

  final WorkRunResult result;
  final List<String> requests = [];

  @override
  String get id => 'fake';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async {
    requests.add(requestId);
    return result;
  }
}

class WorkQueueFullException implements Exception {
  const WorkQueueFullException(this.workId);

  final String workId;

  @override
  String toString() => 'Work queue is full: $workId';
}

class WorkUnavailableException implements Exception {
  const WorkUnavailableException(this.workId, this.reason);

  final String workId;
  final String reason;

  @override
  String toString() => 'Work unavailable ($workId): $reason';
}

class WorkAuthorizationException implements Exception {
  const WorkAuthorizationException(this.workId);

  final String workId;

  @override
  String toString() => 'Source is not authorized for Work $workId';
}

typedef WorkReceiptHandler = Future<void> Function(WorkReceipt receipt);

class WorkQueueCoordinator {
  WorkQueueCoordinator({
    required this.repository,
    this.maxParallel = 2,
    this.onReceipt,
  }) : assert(maxParallel > 0);

  final ActentRepository repository;
  final int maxParallel;
  final WorkReceiptHandler? onReceipt;
  final Map<String, WorkRunner> _runners = {};
  final List<WorkReceiptHandler> _receiptListeners = [];
  final Map<String, _WorkQueue> _queues = {};
  final Map<String, CancellationToken> _running = {};
  int _runningCount = 0;
  bool _draining = false;

  void register(String workId, WorkRunner runner) => _runners[workId] = runner;

  void addReceiptListener(WorkReceiptHandler listener) =>
      _receiptListeners.add(listener);

  Future<void> enqueue(Work work, WorkRequest request) async {
    if (await repository.getReceipt(request.requestId) != null ||
        _running.containsKey(request.requestId) ||
        _queues.values.any(
          (queue) => queue.pending.any(
            (item) => item.request.requestId == request.requestId,
          ),
        )) {
      return;
    }
    if (!work.enabled) {
      throw WorkUnavailableException(work.id, 'disabled');
    }
    if (request.workRevision != work.revision) {
      throw WorkUnavailableException(work.id, 'revision changed');
    }
    if (!work.isAuthorized(request.sourceDeviceId)) {
      throw WorkAuthorizationException(work.id);
    }
    if (!work.accepts(request.message)) {
      throw WorkUnavailableException(work.id, 'content type is not accepted');
    }
    final runner = _runners[work.id];
    if (runner == null) {
      throw WorkUnavailableException(work.id, 'no runner registered');
    }
    final queue = _queues.putIfAbsent(work.id, () => _WorkQueue(work.id));
    if (queue.pending.length + (queue.running ? 1 : 0) >= work.queueLimit) {
      throw WorkQueueFullException(work.id);
    }
    await repository.saveRequest(request);
    queue.pending.add(
      _QueuedWork(work: work, request: request, runner: runner),
    );
    await _drain();
  }

  /// Re-queues requests that were durably saved before an application
  /// shutdown. A request with a receipt is already terminal and is ignored.
  Future<void> restorePending(Iterable<Work> works) async {
    final byId = {for (final work in works) work.id: work};
    for (final request in await repository.listRequests()) {
      if (await repository.getReceipt(request.requestId) != null) continue;
      final work = byId[request.workId];
      if (work == null) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'work_unavailable',
            summary: 'Work no longer exists after restart.',
          ),
        );
        continue;
      }
      final queue = _queues.putIfAbsent(work.id, () => _WorkQueue(work.id));
      if (queue.pending.any(
        (item) => item.request.requestId == request.requestId,
      )) {
        continue;
      }
      if (request.isExpired) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.expired,
            summary: 'Work request expired while the app was stopped.',
          ),
        );
        continue;
      }
      if (!work.enabled) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'work_unavailable',
            summary: 'Work is disabled.',
          ),
        );
        continue;
      }
      if (request.workRevision != work.revision) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'work_changed',
            summary: 'Work revision changed while the app was stopped.',
          ),
        );
        continue;
      }
      if (!work.isAuthorized(request.sourceDeviceId)) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'authorization_denied',
            summary: 'Source device is no longer authorized.',
          ),
        );
        continue;
      }
      if (!work.accepts(request.message)) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'content_type_rejected',
            summary: 'Work no longer accepts this content type.',
          ),
        );
        continue;
      }
      final runner = _runners[request.workId];
      if (runner == null) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'runner_unavailable',
            summary: 'No runner is registered after restart.',
          ),
        );
        continue;
      }
      if (queue.pending.length + (queue.running ? 1 : 0) >= work.queueLimit) {
        await _complete(
          _receipt(
            request,
            WorkReceiptStatus.failed,
            errorCode: 'queue_full',
            summary: 'Work queue is full after application restart.',
          ),
        );
      } else {
        queue.pending.add(
          _QueuedWork(work: work, request: request, runner: runner),
        );
      }
    }
    await _drain();
  }

  Future<bool> cancel(String requestId) async {
    for (final queue in _queues.values) {
      final pendingIndex = queue.pending.indexWhere(
        (item) => item.request.requestId == requestId,
      );
      if (pendingIndex >= 0) {
        queue.pending.removeAt(pendingIndex);
        await _complete(
          WorkReceipt(
            requestId: requestId,
            workId: queue.workId,
            status: WorkReceiptStatus.cancelled,
            createdAt: DateTime.now().toUtc(),
            completedAt: DateTime.now().toUtc(),
          ),
        );
        return true;
      }
    }
    final token = _running[requestId];
    if (token != null) {
      token.cancel();
      return true;
    }
    return false;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_runningCount < maxParallel) {
        final next = _nextPending();
        if (next == null) break;
        next.queue.running = true;
        _runningCount++;
        _run(next.queue, next.item);
      }
    } finally {
      _draining = false;
    }
  }

  _NextWork? _nextPending() {
    for (final entry in _queues.entries) {
      final queue = entry.value;
      if (!queue.running && queue.pending.isNotEmpty) {
        return _NextWork(queue, queue.pending.removeAt(0));
      }
    }
    return null;
  }

  Future<void> _run(_WorkQueue queue, _QueuedWork item) async {
    final token = CancellationToken();
    _running[item.request.requestId] = token;
    WorkReceipt receipt;
    try {
      await _complete(
        _receipt(
          item.request,
          WorkReceiptStatus.processing,
          summary: 'Work execution started.',
        ),
      );
      if (item.request.isExpired) {
        receipt = _receipt(
          item.request,
          WorkReceiptStatus.expired,
          summary: 'Work request expired before execution.',
        );
      } else {
        final result = await item.runner.run(
          item.work,
          item.request.message,
          requestId: item.request.requestId,
          cancellation: token,
        );
        final status = token.isCancelled
            ? WorkReceiptStatus.cancelled
            : result.status;
        receipt = _receipt(
          item.request,
          status,
          errorCode: token.isCancelled ? 'cancelled' : result.errorCode,
          summary: result.summary,
        );
      }
    } catch (error) {
      receipt = _receipt(
        item.request,
        WorkReceiptStatus.failed,
        errorCode: 'runner_error',
        summary: error.toString(),
      );
    } finally {
      _running.remove(item.request.requestId);
      queue.running = false;
      _runningCount--;
    }
    await _complete(receipt);
    await _drain();
  }

  WorkReceipt _receipt(
    WorkRequest request,
    WorkReceiptStatus status, {
    String? errorCode,
    String? summary,
  }) => WorkReceipt(
    requestId: request.requestId,
    workId: request.workId,
    status: status,
    createdAt: DateTime.now().toUtc(),
    completedAt: DateTime.now().toUtc(),
    errorCode: errorCode,
    summary: summary,
  );

  Future<void> _complete(WorkReceipt receipt) async {
    await repository.saveReceipt(receipt);
    await onReceipt?.call(receipt);
    for (final listener in List<WorkReceiptHandler>.of(_receiptListeners)) {
      await listener(receipt);
    }
  }
}

class _WorkQueue {
  _WorkQueue(this.workId);

  final List<_QueuedWork> pending = [];
  bool running = false;
  final String workId;
}

class _QueuedWork {
  const _QueuedWork({
    required this.work,
    required this.request,
    required this.runner,
  });

  final Work work;
  final WorkRequest request;
  final WorkRunner runner;
}

class _NextWork {
  const _NextWork(this.queue, this.item);

  final _WorkQueue queue;
  final _QueuedWork item;
}
