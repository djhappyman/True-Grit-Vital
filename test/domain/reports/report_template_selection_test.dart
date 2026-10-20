import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';

ReportSelection selection({
  ReportTemplateId template = ReportTemplateId.r02DetailedHistory,
  String? eventId,
  bool includeSkipped = true,
  bool includeUnrecorded = true,
}) => ReportSelection(
  template: template,
  personId: 'me',
  fromDate: CivilDate(2026, 10, 18),
  beforeDate: CivilDate(2026, 10, 22),
  displayZone: 'Europe/London',
  eventId: eventId,
  includeSkipped: includeSkipped,
  includeUnrecorded: includeUnrecorded,
);

void main() {
  group('ReportSelection template fields', () {
    test('round-trips the event and ledger choices through identity', () {
      final original = selection(
        template: ReportTemplateId.r03EventReview,
        eventId: 'event-1',
        includeSkipped: false,
        includeUnrecorded: false,
      );
      final restored = ReportSelection.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(original.toJson())) as Map,
        ),
      );
      expect(restored.identity, original.identity);
      expect(restored.template, ReportTemplateId.r03EventReview);
      expect(restored.eventId, 'event-1');
      expect(restored.includeSkipped, isFalse);
      expect(restored.includeUnrecorded, isFalse);
      expect(restored.template.requiresEvent, isTrue);
    });

    test('changing a ledger choice invalidates the captured identity', () {
      expect(
        selection().identity,
        isNot(selection(includeSkipped: false).identity),
      );
      expect(
        selection().identity,
        isNot(selection(includeUnrecorded: false).identity),
      );
      expect(
        selection().identity,
        isNot(selection(eventId: 'event-1').identity),
      );
    });

    test('rejects an unsafe event identity', () {
      expect(
        () => selection(eventId: 'event 1'),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_event',
          ),
        ),
      );
    });

    test('only R03 requires an event selection', () {
      expect(selection().template.requiresEvent, isFalse);
      expect(
        selection(template: ReportTemplateId.r01SubstanceSummary)
            .template
            .requiresEvent,
        isFalse,
      );
    });
  });
}
