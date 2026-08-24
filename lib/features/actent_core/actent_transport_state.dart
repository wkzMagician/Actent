import 'dart:convert';

import 'actent_store.dart';

const _outgoingPrefix = 'transport/v2/outgoing/';
const _incomingPrefix = 'transport/v2/incoming/';
const _completedPrefix = 'transport/v2/completed/';
const _seenPrefix = 'transport/v2/seen/';

class OutgoingTransportState {
  const OutgoingTransportState({
    required this.requestId,
    required this.recipientId,
    required this.control,
    required this.transfers,
    required this.createdAt,
  });

  final String requestId;
  final String recipientId;
  final Map<String, Object?> control;
  final List<Map<String, Object?>> transfers;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
    'requestId': requestId,
    'recipientId': recipientId,
    'control': control,
    'transfers': transfers,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory OutgoingTransportState.fromJson(Object? value) {
    final json = _object(value, 'outgoing transport state');
    if (json['version'] != 2) {
      throw const FormatException('unsupported outgoing transport state');
    }
    final rawTransfers = json['transfers'];
    if (rawTransfers is! List) {
      throw const FormatException('outgoing transfers must be a list');
    }
    return OutgoingTransportState(
      requestId: _string(json['requestId'], 'requestId'),
      recipientId: _string(json['recipientId'], 'recipientId'),
      control: _object(json['control'], 'control'),
      transfers: rawTransfers
          .map((value) => _object(value, 'outgoing transfer'))
          .toList(growable: false),
      createdAt: _date(json['createdAt'], 'createdAt'),
    );
  }
}

class IncomingTransportState {
  const IncomingTransportState({
    required this.requestId,
    required this.senderId,
    required this.payload,
    required this.createdAt,
  });

  final String requestId;
  final String senderId;
  final Map<String, Object?> payload;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
    'requestId': requestId,
    'senderId': senderId,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory IncomingTransportState.fromJson(Object? value) {
    final json = _object(value, 'incoming transport state');
    if (json['version'] != 2) {
      throw const FormatException('unsupported incoming transport state');
    }
    return IncomingTransportState(
      requestId: _string(json['requestId'], 'requestId'),
      senderId: _string(json['senderId'], 'senderId'),
      payload: _object(json['payload'], 'payload'),
      createdAt: _date(json['createdAt'], 'createdAt'),
    );
  }
}

/// Application-owned durable state for restart-safe delivery.
class ActentTransportStateStore {
  ActentTransportStateStore(
    this.store, {
    this.retention = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _clock = clock ?? _now;

  final ActentJsonStore store;
  final Duration retention;
  final DateTime Function() _clock;

  Future<void> saveOutgoing(OutgoingTransportState state) =>
      store.write('$_outgoingPrefix${_key(state.requestId)}', state.toJson());

  Future<List<OutgoingTransportState>> listOutgoing() =>
      _list(_outgoingPrefix, OutgoingTransportState.fromJson);

  Future<void> deleteOutgoing(String requestId) =>
      store.delete('$_outgoingPrefix${_key(requestId)}');

  Future<void> saveIncoming(IncomingTransportState state) =>
      store.write('$_incomingPrefix${_key(state.requestId)}', state.toJson());

  Future<List<IncomingTransportState>> listIncoming() =>
      _list(_incomingPrefix, IncomingTransportState.fromJson);

  Future<void> deleteIncoming(String requestId) =>
      store.delete('$_incomingPrefix${_key(requestId)}');

  Future<void> markCompleted(String requestId) => store.write(
    '$_completedPrefix${_key(requestId)}',
    _clock().toUtc().toIso8601String(),
  );

  Future<bool> isCompleted(String requestId) async =>
      await store.read('$_completedPrefix${_key(requestId)}') != null;

  Future<void> rememberPacket(String packetId) =>
      store.write('$_seenPrefix${_key(packetId)}', <String, Object?>{
        'packetId': packetId,
        'seenAt': _clock().toUtc().toIso8601String(),
      });

  Future<Map<String, DateTime>> loadSeenPackets() async {
    final result = <String, DateTime>{};
    final cutoff = _clock().toUtc().subtract(retention);
    for (final key in await store.list(prefix: _seenPrefix)) {
      final value = await store.read(key);
      if (value is! Map) continue;
      final json = Map<String, Object?>.from(value);
      final packetId = json['packetId'];
      final seenAt = DateTime.tryParse('${json['seenAt']}')?.toUtc();
      if (packetId is String && packetId.isNotEmpty && seenAt != null) {
        if (!seenAt.isBefore(cutoff)) result[packetId] = seenAt;
      }
    }
    return result;
  }

  Future<List<IncomingTransportState>> purgeExpired() async {
    final cutoff = _clock().toUtc().subtract(retention);
    final expiredIncoming = <IncomingTransportState>[];
    for (final state in await listOutgoing()) {
      if (state.createdAt.isBefore(cutoff)) {
        await deleteOutgoing(state.requestId);
      }
    }
    for (final state in await listIncoming()) {
      if (state.createdAt.isBefore(cutoff)) {
        expiredIncoming.add(state);
        await deleteIncoming(state.requestId);
      }
    }
    for (final prefix in const [_completedPrefix, _seenPrefix]) {
      for (final key in await store.list(prefix: prefix)) {
        final value = await store.read(key);
        final timestamp = value is String
            ? DateTime.tryParse(value)?.toUtc()
            : value is Map
            ? DateTime.tryParse('${value['seenAt']}')?.toUtc()
            : null;
        if (timestamp == null || timestamp.isBefore(cutoff)) {
          await store.delete(key);
        }
      }
    }
    return expiredIncoming;
  }

  Future<List<T>> _list<T>(String prefix, T Function(Object?) decode) async {
    final result = <T>[];
    for (final key in await store.list(prefix: prefix)) {
      final value = await store.read(key);
      if (value == null) continue;
      try {
        result.add(decode(value));
      } on FormatException {
        // Corrupt volatile transfer state is isolated from business records.
        await store.delete(key);
      }
    }
    return result;
  }
}

String _key(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, Object?>.from(value);
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

DateTime _date(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value)?.toUtc() : null;
  if (parsed == null) throw FormatException('$field must be an ISO-8601 time');
  return parsed;
}

DateTime _now() => DateTime.now().toUtc();
