import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';

import 'actent_models.dart';

abstract interface class ActentJsonStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
  Future<void> delete(String key);
  Future<List<String>> list({String prefix = ''});
}

class MemoryActentJsonStore implements ActentJsonStore {
  final Map<String, Object?> _values = {};

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Object? value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      (_values.keys.where((key) => key.startsWith(prefix)).toList()..sort());
}

/// Bridges the Dartloom storage capability to the Core's small JSON contract.
/// The Core only sees this contract and can therefore use a fake in tests.
class ReplicaActentJsonStore implements ActentJsonStore {
  ReplicaActentJsonStore(this.replica);

  final ObjectStore replica;

  @override
  Future<Object?> read(String key) async {
    final bytes = await replica.read(key);
    if (bytes == null) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw ActentValidationException(
        key,
        'stored value is not valid JSON: $error',
      );
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    await replica.write(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
    );
  }

  @override
  Future<void> delete(String key) => replica.delete(key);

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      (await replica.scan())
          .where((item) => item.key.startsWith(prefix))
          .map((item) => item.key)
          .toList()
        ..sort();
}

class ActentRepository {
  ActentRepository(this.store);

  final ActentJsonStore store;

  Future<void> saveMessage(ActentMessage message) =>
      store.write(_key('messages', message.id), message.toJson());

  Future<ActentMessage?> getMessage(String id) async =>
      _read(_key('messages', id), ActentMessage.fromJson);

  Future<List<ActentMessage>> listMessages() =>
      _list('messages/', ActentMessage.fromJson);

  Future<void> deleteMessage(String id) async {
    await store.delete(_key('messages', id));
    for (final request in await listRequests()) {
      if (request.message.id != id) continue;
      await deleteRequest(request.requestId);
      await deleteReceipt(request.requestId);
    }
  }

  Future<void> saveWork(Work work) async {
    final normalizedName = _normalizeWorkName(work.name);
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        work.name,
        'name',
        'Work names cannot be empty.',
      );
    }
    for (final existing in await listWorks()) {
      if (existing.id == work.id ||
          existing.ownerDeviceId != work.ownerDeviceId) {
        continue;
      }
      if (_normalizeWorkName(existing.name) == normalizedName) {
        throw StateError(
          'A Work named "${work.name}" already exists on device '
          '${work.ownerDeviceId}.',
        );
      }
    }
    await store.write(_key('works', work.id), work.toJson());
  }

  Future<Work?> getWork(String id) => _read(_key('works', id), Work.fromJson);

  Future<List<Work>> listWorks() => _list('works/', Work.fromJson);

  Future<void> deleteWork(String id) => store.delete(_key('works', id));

  Future<void> saveWorkflow(Workflow workflow) =>
      store.write(_key('workflows', workflow.id), workflow.toJson());

  Future<Workflow?> getWorkflow(String id) =>
      _read(_key('workflows', id), Workflow.fromJson);

  Future<List<Workflow>> listWorkflows() =>
      _list('workflows/', Workflow.fromJson);

  Future<void> deleteWorkflow(String id) => store.delete(_key('workflows', id));

  Future<void> saveWorkflowExecution(WorkflowExecution execution) =>
      store.write(_key('workflowExecutions', execution.id), execution.toJson());

  Future<WorkflowExecution?> getWorkflowExecution(String id) =>
      _read(_key('workflowExecutions', id), WorkflowExecution.fromJson);

  Future<List<WorkflowExecution>> listWorkflowExecutions() =>
      _list('workflowExecutions/', WorkflowExecution.fromJson);

  Future<void> saveDevice(Device device) =>
      store.write(_key('devices', device.id), device.toJson());

  Future<Device?> getDevice(String id) =>
      _read(_key('devices', id), Device.fromJson);

  Future<List<Device>> listDevices() => _list('devices/', Device.fromJson);

  Future<void> deleteDevice(String id) => store.delete(_key('devices', id));

  Future<void> saveRequest(WorkRequest request) =>
      store.write(_key('requests', request.requestId), request.toJson());

  Future<WorkRequest?> getRequest(String id) =>
      _read(_key('requests', id), WorkRequest.fromJson);

  Future<List<WorkRequest>> listRequests() =>
      _list('requests/', WorkRequest.fromJson);

  Future<void> deleteRequest(String id) => store.delete(_key('requests', id));

  Future<void> saveReceipt(WorkReceipt receipt) =>
      store.write(_key('receipts', receipt.requestId), receipt.toJson());

  Future<WorkReceipt?> getReceipt(String requestId) =>
      _read(_key('receipts', requestId), WorkReceipt.fromJson);

  Future<List<WorkReceipt>> listReceipts() =>
      _list('receipts/', WorkReceipt.fromJson);

  Future<void> deleteReceipt(String requestId) =>
      store.delete(_key('receipts', requestId));

  Future<T?> _read<T>(String key, T Function(Object?) decode) async {
    final value = await store.read(key);
    return value == null ? null : decode(value);
  }

  Future<List<T>> _list<T>(String prefix, T Function(Object?) decode) async {
    final keys = await store.list(prefix: prefix);
    final values = <T>[];
    for (final key in keys) {
      final value = await store.read(key);
      if (value != null) values.add(decode(value));
    }
    return values;
  }

  String _key(String collection, String id) {
    if (id.isEmpty ||
        id.contains('/') ||
        id.contains('\\') ||
        id == '.' ||
        id == '..') {
      throw ArgumentError.value(
        id,
        'id',
        'IDs must be safe single path components.',
      );
    }
    return '$collection/$id.json';
  }

  String _normalizeWorkName(String name) => name.trim().toLowerCase();
}
