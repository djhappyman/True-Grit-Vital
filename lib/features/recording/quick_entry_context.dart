import '../../domain/scheduling/daily_plan.dart';

/// A supplied quick-entry parameter that cannot be applied as given.
///
/// The parser never repairs a route by normalising a date or silently choosing
/// one of two competing tasks. It reports why the parameter was dropped and
/// leaves the screen to explain the recovery.
enum QuickEntryIssue {
  invalidLocation,
  duplicateDay,
  invalidDay,
  duplicateTime,
  invalidTime,
  timeWithoutPlan,
  duplicateItem,
  invalidItem,
  invalidNewFlag,
  invalidPlanFlag,
  newAndItem,
  planAndItem,
}

/// The exact, validated quick-entry route state.
///
/// Both `/unplanned?new=1` and `/unplanned?item=...` arrive on the same route.
/// Parsing is separate from the widgets so impossible calendar dates, malformed
/// clocks and contradictory task flags have one tested interpretation.
final class QuickEntryContext {
  QuickEntryContext._({
    required this.day,
    required this.time,
    required this.itemId,
    required this.createNew,
    required this.plan,
    required this.issues,
  });

  factory QuickEntryContext.parse(String location) {
    final Uri uri;
    try {
      uri = Uri.parse(location);
    } on FormatException {
      return QuickEntryContext._(
        day: null,
        time: null,
        itemId: null,
        createNew: false,
        plan: false,
        issues: const [QuickEntryIssue.invalidLocation],
      );
    }

    final issues = <QuickEntryIssue>[];
    final values = uri.queryParametersAll;

    String? single(String key, QuickEntryIssue duplicate) {
      final found = values[key];
      if (found == null) return null;
      if (found.length != 1) {
        issues.add(duplicate);
        return null;
      }
      return found.single;
    }

    final rawDay = single('day', QuickEntryIssue.duplicateDay);
    CivilDate? day;
    if (rawDay != null) {
      day = parseQuickEntryDay(rawDay);
      if (day == null) issues.add(QuickEntryIssue.invalidDay);
    }

    final rawTime = single('time', QuickEntryIssue.duplicateTime);
    String? time;
    if (rawTime != null) {
      time = parseQuickEntryTime(rawTime);
      if (time == null) issues.add(QuickEntryIssue.invalidTime);
    }

    final rawItem = single('item', QuickEntryIssue.duplicateItem);
    String? itemId;
    if (rawItem != null) {
      if (rawItem.isEmpty || rawItem.trim() != rawItem) {
        issues.add(QuickEntryIssue.invalidItem);
      } else {
        itemId = rawItem;
      }
    }

    final rawNew = single('new', QuickEntryIssue.invalidNewFlag);
    final createNew = rawNew == '1';
    if (rawNew != null && rawNew != '1' && rawNew != '0') {
      issues.add(QuickEntryIssue.invalidNewFlag);
    }

    final rawPlan = single('plan', QuickEntryIssue.invalidPlanFlag);
    final plan = rawPlan == '1';
    if (rawPlan != null && rawPlan != '1' && rawPlan != '0') {
      issues.add(QuickEntryIssue.invalidPlanFlag);
    }

    if (time != null && !plan) {
      // `time` is the optional suggested slot for the planning flow. Recording
      // an existing item uses the actual-time field instead.
      time = null;
      issues.add(QuickEntryIssue.timeWithoutPlan);
    }

    if (itemId != null && createNew) {
      issues.add(QuickEntryIssue.newAndItem);
    }
    if (itemId != null && plan) {
      issues.add(QuickEntryIssue.planAndItem);
    }

    return QuickEntryContext._(
      day: day,
      time: time,
      itemId: itemId,
      createNew: createNew,
      plan: plan,
      issues: List.unmodifiable(issues),
    );
  }

  /// The validated day, or null when it was absent or rejected.
  final CivilDate? day;

  /// A validated suggested plan time, only retained for the planning flow.
  final String? time;

  /// The exact item identity from the route, or null when absent or rejected.
  final String? itemId;

  final bool createNew;
  final bool plan;
  final List<QuickEntryIssue> issues;

  bool get hasIssues => issues.isNotEmpty;

  /// A route that names both an item and a competing task cannot pick one.
  bool get needsChoice => itemId != null && (createNew || plan);
}

/// Parses only the exact `YYYY-MM-DD` civil-date form.
///
/// `DateTime.tryParse` accepts `2026-02-30` and returns 2 March, so it cannot
/// validate a supplied day. `CivilDate` rejects the impossible day, and the
/// round trip keeps the accepted spelling exact.
CivilDate? parseQuickEntryDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  try {
    final day = CivilDate.parse(value);
    return day.toString() == value ? day : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// Parses only a 24-hour `HH:mm` wall time and returns its canonical form.
String? parseQuickEntryTime(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return null;
  try {
    final time = WallTime(int.parse(match[1]!), int.parse(match[2]!));
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  } on ArgumentError {
    return null;
  }
}

/// The retained search and page of the chooser route.
typedef QuickEntryListSeed = ({String query, int offset});

const quickEntryPageSize = 50;

QuickEntryListSeed quickEntryListSeed(Uri uri) {
  final query = uri.queryParameters['q'] ?? '';
  final offset = int.tryParse(uri.queryParameters['offset'] ?? '');
  return (query: query, offset: offset == null || offset < 0 ? 0 : offset);
}

String quickEntryCreateLocation(QuickEntryContext entry) => Uri(
  path: '/unplanned',
  queryParameters: {
    'new': '1',
    if (entry.plan) 'plan': '1',
    if (entry.day != null) 'day': entry.day.toString(),
    if (entry.plan && entry.time != null) 'time': entry.time!,
  },
).toString();

String quickEntryRecordLocation(QuickEntryContext entry, {String? itemId}) =>
    Uri(
      path: '/unplanned',
      queryParameters: {
        'item': itemId ?? entry.itemId!,
        if (entry.day != null) 'day': entry.day.toString(),
      },
    ).toString();

String quickEntryPlanLocation(QuickEntryContext entry, {String? itemId}) => Uri(
  path: '/schedule/${itemId ?? entry.itemId}',
  queryParameters: {
    if (entry.day != null) 'start': entry.day.toString(),
    if (entry.time != null) 'time': entry.time!,
  },
).toString();
