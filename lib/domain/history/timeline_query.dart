import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../records.dart';

/// Status filter for one timeline query.
enum TimelineStatus { all, recorded, skipped, voided }

/// Bounded History limits. A bound is a typed failure, never a silent cut.
abstract final class TimelineLimits {
  static const defaultPageSize = 25;
  static const maxPageSize = 50;
  static const maxTypeIds = 10;
  static const maxEventIds = 20;
  static const maxEventMembershipClauses = 1000;
  static const maxCombinedComponentsPerPage = 800;
  static const maxCalendarCells = 42;
}

/// Typed query construction failure. Codes are stable for the data/UI boundary.
final class TimelineQueryException implements Exception {
  const TimelineQueryException(this.code);

  final String code;

  @override
  String toString() => 'TimelineQueryException($code)';
}

/// Typed cursor failure.
final class TimelineCursorException implements Exception {
  const TimelineCursorException(this.code);

  final String code;

  @override
  String toString() => 'TimelineCursorException($code)';
}

/// Immutable, bounded History filters.
final class TimelineFilter {
  TimelineFilter({
    this.scope = const FeedScope.everyone(),
    this.fromInstant,
    this.beforeInstant,
    this.itemId,
    Iterable<String> typeIds = const [],
    this.actualUnit,
    Iterable<String> eventIds = const [],
    this.status = TimelineStatus.all,
  }) : typeIds = _boundedIdentityList(typeIds, TimelineLimits.maxTypeIds),
       eventIds = _boundedIdentityList(eventIds, TimelineLimits.maxEventIds) {
    _checkOptionalIdentity(scope.personId, 'invalid_filter');
    _checkRange();
    _checkOptionalIdentity(itemId, 'invalid_filter');
    _checkOptionalIdentity(actualUnit, 'invalid_filter', maxLength: 64);
  }

  final FeedScope scope;

  /// Inclusive UTC instant. Null means no lower bound.
  final DateTime? fromInstant;

  /// Exclusive UTC instant. Null means no upper bound.
  final DateTime? beforeInstant;

  final String? itemId;

  /// Sorted, distinct, unmodifiable. OR within this group.
  final List<String> typeIds;

  final String? actualUnit;

  /// Sorted, distinct, unmodifiable. OR within this group.
  final List<String> eventIds;

  final TimelineStatus status;

  bool get hasDateRange => fromInstant != null || beforeInstant != null;

  bool get hasIdentityFilters =>
      itemId != null ||
      typeIds.isNotEmpty ||
      actualUnit != null ||
      eventIds.isNotEmpty;

  bool get isUnfiltered =>
      !hasDateRange && !hasIdentityFilters && status == TimelineStatus.all;

  TimelineFilter restart({
    FeedScope? scope,
    DateTime? fromInstant,
    DateTime? beforeInstant,
    String? itemId,
    Iterable<String>? typeIds,
    String? actualUnit,
    Iterable<String>? eventIds,
    TimelineStatus? status,
    bool clearFrom = false,
    bool clearBefore = false,
    bool clearItem = false,
    bool clearUnit = false,
  }) => TimelineFilter(
    scope: scope ?? this.scope,
    fromInstant: clearFrom ? null : fromInstant ?? this.fromInstant,
    beforeInstant: clearBefore ? null : beforeInstant ?? this.beforeInstant,
    itemId: clearItem ? null : itemId ?? this.itemId,
    typeIds: typeIds ?? this.typeIds,
    actualUnit: clearUnit ? null : actualUnit ?? this.actualUnit,
    eventIds: eventIds ?? this.eventIds,
    status: status ?? this.status,
  );

  void _checkRange() {
    _checkRangeValue(fromInstant);
    _checkRangeValue(beforeInstant);
    if (fromInstant != null &&
        beforeInstant != null &&
        !beforeInstant!.isAfter(fromInstant!)) {
      throw const TimelineQueryException('invalid_range');
    }
  }
}

/// One immutable bounded timeline read.
final class TimelineQuery {
  TimelineQuery({
    required this.filter,
    required this.displayZone,
    this.limit = TimelineLimits.defaultPageSize,
    this.cursor,
    this.anchorId,
  }) {
    _checkIdentity(displayZone, 'invalid_zone');
    if (limit < 1 || limit > TimelineLimits.maxPageSize) {
      throw const TimelineQueryException('invalid_limit');
    }
    _checkOptionalIdentity(anchorId, 'invalid_filter', maxLength: 512);
    final value = cursor;
    if (value != null && value.queryHash != identity) {
      throw const TimelineCursorException('cursor_expired');
    }
  }

  final TimelineFilter filter;

  /// Requested IANA id. Display fallback to UTC is handled by `DisplayTime`.
  final String displayZone;

  /// Parent rows per page. 25 default, 50 maximum.
  final int limit;

  final TimelineCursor? cursor;

  /// Inspection/back-navigation anchor. Not part of the query identity.
  final String? anchorId;

  /// Stable SHA-256 identity of scope, exact range and filters.
  late final String identity = _queryIdentity(filter, displayZone);

  TimelineQuery get firstPage => restart();

  TimelineQuery withCursor(TimelineCursor value) => TimelineQuery(
    filter: filter,
    displayZone: displayZone,
    limit: limit,
    cursor: value,
    anchorId: anchorId,
  );

  /// Changes view state and always drops the cursor.
  TimelineQuery restart({
    TimelineFilter? filter,
    String? displayZone,
    int? limit,
    String? anchorId,
    bool clearAnchor = false,
  }) => TimelineQuery(
    filter: filter ?? this.filter,
    displayZone: displayZone ?? this.displayZone,
    limit: limit ?? this.limit,
    anchorId: clearAnchor ? null : anchorId ?? this.anchorId,
  );
}

/// Opaque, validated keyset position for `occurredAt DESC, sortKey ASC`.
final class TimelineCursor {
  const TimelineCursor._({
    required this.occurredAt,
    required this.sortKey,
    required this.queryHash,
    required this.schemaVersion,
    required this.datasetGeneration,
  });

  factory TimelineCursor.at({
    required DateTime occurredAt,
    required String sortKey,
    required TimelineQuery query,
    required int schemaVersion,
    required String datasetGeneration,
  }) {
    final utc = occurredAt.toUtc();
    _checkCursorInstant(utc);
    _checkSortKey(sortKey);
    if (schemaVersion < 1) {
      throw const TimelineCursorException('cursor_malformed');
    }
    _checkCursorText(datasetGeneration, 'cursor_malformed');
    return TimelineCursor._(
      occurredAt: utc,
      sortKey: sortKey,
      queryHash: query.identity,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
    );
  }

  /// Decodes the opaque envelope without knowing the current query.
  factory TimelineCursor.decode(String value) {
    if (value.isEmpty || value.length > 4096) {
      throw const TimelineCursorException('cursor_malformed');
    }
    late final List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      throw const TimelineCursorException('cursor_malformed');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const TimelineCursorException('cursor_malformed');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TimelineCursorException('cursor_malformed');
    }
    final version = decoded['v'];
    if (version is! int) {
      throw const TimelineCursorException('cursor_malformed');
    }
    if (version != envelopeVersion) {
      throw const TimelineCursorException('cursor_version');
    }
    final atMicros = decoded['a'];
    final key = decoded['k'];
    final queryHash = decoded['q'];
    final schema = decoded['s'];
    final dataset = decoded['d'];
    if (atMicros is! int ||
        key is! String ||
        queryHash is! String ||
        schema is! int ||
        dataset is! String) {
      throw const TimelineCursorException('cursor_malformed');
    }
    late final DateTime at;
    try {
      at = DateTime.fromMicrosecondsSinceEpoch(atMicros, isUtc: true);
    } catch (_) {
      throw const TimelineCursorException('cursor_malformed');
    }
    _checkCursorInstant(at);
    _checkSortKey(key);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(queryHash) || schema < 1) {
      throw const TimelineCursorException('cursor_malformed');
    }
    _checkCursorText(dataset, 'cursor_malformed');
    return TimelineCursor._(
      occurredAt: at,
      sortKey: key,
      queryHash: queryHash,
      schemaVersion: schema,
      datasetGeneration: dataset,
    );
  }

  static const envelopeVersion = 1;

  final DateTime occurredAt;
  final String sortKey;
  final String queryHash;
  final int schemaVersion;
  final String datasetGeneration;

  String encode() {
    final payload = <String, Object?>{
      'v': envelopeVersion,
      'a': occurredAt.microsecondsSinceEpoch,
      'k': sortKey,
      'q': queryHash,
      's': schemaVersion,
      'd': datasetGeneration,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool isValidFor({
    required TimelineQuery query,
    required int schemaVersion,
    required String datasetGeneration,
  }) =>
      queryHash == query.identity &&
      this.schemaVersion == schemaVersion &&
      this.datasetGeneration == datasetGeneration;

  /// Returns this cursor when it still belongs to the same view and dataset.
  TimelineCursor validateFor({
    required TimelineQuery query,
    required int schemaVersion,
    required String datasetGeneration,
  }) {
    if (!isValidFor(
      query: query,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
    )) {
      throw const TimelineCursorException('cursor_expired');
    }
    return this;
  }

  /// Exact keyset predicate: `at < cursor.at OR (at = cursor.at AND key > cursor.key)`.
  bool isAfterCursor({required DateTime occurredAt, required String sortKey}) {
    final byTime = occurredAt.toUtc().compareTo(this.occurredAt);
    return byTime < 0 || (byTime == 0 && sortKey.compareTo(this.sortKey) > 0);
  }

  static int comparePositions({
    required DateTime aAt,
    required String aKey,
    required DateTime bAt,
    required String bKey,
  }) {
    final byTime = bAt.toUtc().compareTo(aAt.toUtc());
    return byTime != 0 ? byTime : aKey.compareTo(bKey);
  }
}

String _queryIdentity(TimelineFilter filter, String displayZone) {
  final canonical = <String, Object?>{
    'contract': 'vital.timeline.query',
    'version': 1,
    'scope': filter.scope.isEveryone
        ? 'everyone'
        : 'person:${filter.scope.personId}',
    'from': filter.fromInstant?.microsecondsSinceEpoch,
    'before': filter.beforeInstant?.microsecondsSinceEpoch,
    'item': filter.itemId,
    'types': filter.typeIds,
    'unit': filter.actualUnit,
    'events': filter.eventIds,
    'status': filter.status.name,
    'zone': displayZone,
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

List<String> _boundedIdentityList(Iterable<String> values, int maximum) {
  final unique = <String>{};
  for (final value in values) {
    _checkIdentity(value, 'invalid_filter');
    unique.add(value);
  }
  if (unique.length > maximum) {
    throw const TimelineQueryException('query_too_broad');
  }
  final sorted = unique.toList()..sort();
  return List.unmodifiable(sorted);
}

void _checkRangeValue(DateTime? value) {
  if (value != null && (!value.isUtc || value.year < 1 || value.year > 9999)) {
    throw const TimelineQueryException('invalid_range');
  }
}

void _checkIdentity(String value, String code, {int maxLength = 256}) {
  if (value.isEmpty || value.trim().isEmpty || value.length > maxLength) {
    throw TimelineQueryException(code);
  }
}

void _checkOptionalIdentity(String? value, String code, {int maxLength = 256}) {
  if (value != null) _checkIdentity(value, code, maxLength: maxLength);
}

void _checkCursorInstant(DateTime value) {
  if (!value.isUtc || value.year < 1 || value.year > 9999) {
    throw const TimelineCursorException('cursor_malformed');
  }
}

void _checkCursorText(String value, String code) {
  if (value.isEmpty || value.trim().isEmpty || value.length > 256) {
    throw TimelineCursorException(code);
  }
}

void _checkSortKey(String value) {
  if (value.length < 3 ||
      value.length > 258 ||
      (value[0] != 'r' && value[0] != 'c' && value[0] != 's') ||
      value[1] != ':') {
    throw const TimelineCursorException('cursor_malformed');
  }
  final id = value.substring(2);
  if (id.isEmpty || id.trim().isEmpty || id.length > 256) {
    throw const TimelineCursorException('cursor_malformed');
  }
}
