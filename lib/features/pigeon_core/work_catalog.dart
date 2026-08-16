import 'pigeon_models.dart';

class WorkCatalogException implements Exception {
  const WorkCatalogException(this.message);

  final String message;

  @override
  String toString() => 'Invalid Work catalog: $message';
}

class WorkCatalog {
  WorkCatalog({this.revision = 0, Iterable<Work> works = const []})
    : _works = {for (final work in works) work.id: work};

  int revision;
  final Map<String, Work> _works;

  List<Work> get works =>
      _works.values.toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name));

  Work? operator [](String workId) => _works[workId];

  Map<String, Object?> toSnapshotJson() => <String, Object?>{
    'revision': revision,
    'works': works.map((work) => work.toJson()).toList(),
  };

  factory WorkCatalog.fromSnapshotJson(Object? value) {
    if (value is! Map) {
      throw const WorkCatalogException('snapshot must be an object');
    }
    final json = Map<String, Object?>.from(value);
    final rawWorks = json['works'];
    if (rawWorks is! List) {
      throw const WorkCatalogException('works must be an array');
    }
    return WorkCatalog(
      revision: _revision(json['revision']),
      works: rawWorks.map(Work.fromJson),
    );
  }

  void replaceSnapshot({
    required int nextRevision,
    required Iterable<Work> works,
  }) {
    if (nextRevision < revision) {
      throw WorkCatalogException(
        'snapshot revision $nextRevision is older than $revision',
      );
    }
    _works
      ..clear()
      ..addEntries((works.map((work) => MapEntry(work.id, work))));
    revision = nextRevision;
  }

  void applyDelta({
    required int baseRevision,
    required int nextRevision,
    required Iterable<Work> upserts,
    required Iterable<String> removedWorkIds,
  }) {
    if (baseRevision != revision) {
      throw WorkCatalogException(
        'delta base revision $baseRevision does not match local revision $revision',
      );
    }
    if (nextRevision <= baseRevision) {
      throw const WorkCatalogException('delta revision must increase');
    }
    for (final work in upserts) {
      _works[work.id] = work;
    }
    for (final workId in removedWorkIds) {
      _works.remove(workId);
    }
    revision = nextRevision;
  }
}

int _revision(Object? value) {
  if (value is! int || value < 0) {
    throw const WorkCatalogException('revision must be a non-negative integer');
  }
  return value;
}
