import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

/// Event-end terminal receipt monotonicity under real protected SQLite.
///
/// The ordinary repair lane treats consumed, postUncertain and cancelled
/// states as terminal and only lets postUncertain advance to consumed. The
/// event lane must hold the same monotonicity: a later accepted, failed or
/// unknown receipt may never regress a terminal row, and an adapter-evidenced
/// cancellation is acknowledged once so the obsolete native-cancel work never
/// churns. The terminal row keeps holding its slot as the no-rearm fence for
/// the same event revision, because preparation only recognises active rows.
void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final now = DateTime.utc(2026, 10, 19, 12);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-t15-event-end-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic course item',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  EventMembership membership() => EventMembership(
    id: 'membership',
    itemId: item.id,
    personId: meId,
    effectiveFrom: DateTime.utc(2026, 10, 10),
    effectiveUntil: null,
    revision: 1,
  );

  EventRecord event() => EventRecord(
    id: 'event',
    personId: meId,
    name: 'Synthetic course',
    eventType: 'course',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
    plannedEnd: EventDate.exact(now.add(const Duration(minutes: 20))),
    memberships: [membership()],
  );

  Future<EventRecord> save(
    EventRecord e, {
    String commandId = 'event-save',
    int? expected,
  }) async {
    final c = SaveEventCommand(
      commandId: commandId,
      generation: store.generation,
      expectedRevision: expected,
      event: e,
    );
    final review = await store.previewEventMembership(c);
    return store.saveEvent(c, membershipReview: review);
  }

  Future<ReminderProjection> prepare() => store.prepareReminders(
    now: now,
    observedZone: 'Europe/London',
    clockSample: null,
    adapterFingerprint: 'test-adapter',
  );

  /// The production route for event-end receipts: acknowledgeEventEnd hands
  /// the adapter receipt to acknowledgeReminder at the event revision as the
  /// durable intent-revision fence.
  Future<bool> acknowledge(
    EventEndReminder request,
    ReminderReceipt receipt, {
    int? intentRevision,
    String? reason,
  }) async {
    final observation = await prepare();
    return store.acknowledgeReminder(
      generation: store.generation,
      requestToken: request.requestToken,
      intentRevision: intentRevision ?? request.eventRevision,
      sequence: observation.sequence,
      receipt: receipt,
      reason: reason,
      adapterFingerprint: 'test-adapter',
    );
  }

  Database rawStore() {
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    return raw;
  }

  Map<String, Object?>? eventTokenRow(String token) {
    final raw = rawStore();
    try {
      final rows = raw.select(
        'SELECT state,active,cancel_ack,intent_revision FROM event_end_request WHERE token=?',
        [token],
      );
      return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
    } finally {
      raw.close();
    }
  }

  int eventRequestCount() {
    final raw = rawStore();
    try {
      return raw
              .select(
                "SELECT COUNT(*) AS n FROM event_end_request WHERE event='event'",
              )
              .first
              .values
              .single
          as int;
    } finally {
      raw.close();
    }
  }

  group('event-end terminal receipts', () {
    test(
      'accepted, failed and unknown receipts cannot resurrect a terminal row',
      () async {
        await save(event());
        final r = (await prepare()).eventEnds.single;
        expect(await acknowledge(r, ReminderReceipt.postUncertain), isTrue);
        expect(eventTokenRow(r.requestToken), {
          'state': 'postUncertain',
          'active': 1,
          'cancel_ack': 0,
          'intent_revision': 1,
        });
        // A later accepted receipt must not regress the uncertain terminal
        // state to prepared; failed and unknown are equally barred.
        for (final receipt in [
          ReminderReceipt.accepted,
          ReminderReceipt.failed,
          ReminderReceipt.unknown,
          ReminderReceipt.cancelled,
        ]) {
          final settledRow = eventTokenRow(r.requestToken);
          expect(await acknowledge(r, receipt), isFalse);
          expect(
            eventTokenRow(r.requestToken),
            settledRow,
            reason:
                'a later ${receipt.name} receipt cannot regress postUncertain',
          );
        }
        // The only allowed advancement is postUncertain to consumed.
        expect(await acknowledge(r, ReminderReceipt.consumed), isTrue);
        expect(eventTokenRow(r.requestToken)?['state'], 'consumed');
        expect(eventTokenRow(r.requestToken)?['active'], 1);
        for (final receipt in [
          ReminderReceipt.accepted,
          ReminderReceipt.postUncertain,
          ReminderReceipt.failed,
          ReminderReceipt.unknown,
          ReminderReceipt.cancelled,
        ]) {
          expect(await acknowledge(r, receipt), isFalse);
          expect(eventTokenRow(r.requestToken)?['state'], 'consumed');
        }
        // A repeated consumed receipt stays accepted without mutating the row.
        expect(await acknowledge(r, ReminderReceipt.consumed), isTrue);
        expect(eventTokenRow(r.requestToken)?['state'], 'consumed');
        // The terminal fence keeps blocking a replacement token, and no
        // administration or membership record appeared.
        expect((await prepare()).eventEnds, isEmpty);
        expect(await store.records(), isEmpty);
        expect((await store.eventById('event'))!.revision, 1);
      },
    );
    test('a cancelled receipt settles the live row once without a replacement alert', () async {
      await save(event());
      final r = (await prepare()).eventEnds.single;
      expect(await acknowledge(r, ReminderReceipt.cancelled), isTrue);
      final settled = eventTokenRow(r.requestToken)!;
      expect(settled['state'], 'cancelled');
      expect(
        settled['cancel_ack'],
        1,
        reason: 'the adapter evidenced the end of this token',
      );
      expect(
        settled['active'],
        1,
        reason: 'the row stays the no-rearm fence for this event revision',
      );
      // Repeated repair passes never mint a replacement token for the same
      // revision and never re-list the settled token for a native cancel.
      final first = await prepare();
      final second = await prepare();
      expect(first.obsoleteTokens, isNot(contains(r.requestToken)));
      expect(second.obsoleteTokens, isNot(contains(r.requestToken)));
      expect(first.eventEnds, isEmpty);
      expect(second.eventEnds, isEmpty);
      expect(first.exclusions.where((e) => e.scope == 'event:event'), isEmpty);
      expect(second.exclusions.where((e) => e.scope == 'event:event'), isEmpty);
      expect(eventRequestCount(), 1);
      expect(await store.records(), isEmpty);
      expect((await store.eventById('event'))!.revision, 1);
    });
    test('a stale receipt for an invalidated token is rejected while its cancellation settles once', () async {
      await save(event());
      final r = (await prepare()).eventEnds.single;
      // A deliberate later event revision retires the old native request.
      await save(
        event().copyWith(revision: 2, name: 'Extended course'),
        commandId: 'bump',
        expected: 1,
      );
      final retired = eventTokenRow(r.requestToken)!;
      expect(
        retired['active'],
        0,
        reason: 'the superseded token is retired, not silently replaced',
      );
      expect(retired['cancel_ack'], 0);
      expect(retired['intent_revision'], 1);
      // Stale receipts cannot resurrect a retired row, even at the matching
      // durable intent revision.
      for (final receipt in [
        ReminderReceipt.accepted,
        ReminderReceipt.failed,
        ReminderReceipt.unknown,
        ReminderReceipt.postUncertain,
        ReminderReceipt.consumed,
      ]) {
        expect(await acknowledge(r, receipt), isFalse);
      }
      // A wrong intent fence is rejected outright.
      expect(
        await acknowledge(r, ReminderReceipt.accepted, intentRevision: 2),
        isFalse,
      );
      // The adapter later evidences the cancellation of the retired token.
      expect(await acknowledge(r, ReminderReceipt.cancelled), isTrue);
      final settled = eventTokenRow(r.requestToken)!;
      expect(settled['state'], 'cancelled');
      expect(settled['cancel_ack'], 1);
      // A bounded repair pass prunes the settled row without churn and the
      // legitimate revision-2 notice arms under a fresh token.
      final next = await prepare();
      expect(
        eventTokenRow(r.requestToken),
        isNull,
        reason: 'the settled token prunes instead of looping in obsolete work',
      );
      expect(next.obsoleteTokens, isNot(contains(r.requestToken)));
      expect(next.eventEnds.single.eventId, 'event');
      expect(next.eventEnds.single.eventRevision, 2);
      expect(next.eventEnds.single.requestToken, isNot(r.requestToken));
      final later = await prepare();
      expect(
        later.eventEnds.single.requestToken,
        next.eventEnds.single.requestToken,
        reason: 'repeated repair passes converge on the revision-2 token',
      );
      expect(await store.records(), isEmpty);
    });
    test('a fake adapter that ends the event request converges without re-arming it', () async {
      await save(event());
      final gateway = _EventEndFlightGateway();
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: _EventEndStoreRepair(store),
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      worker.dispose();
      expect(reports.last.convergence, ReminderConvergence.converged);
      expect(reports.last.pendingCancellations, 0);
      final token = gateway.eventEndToken;
      expect(token, isNotNull);
      final settled = eventTokenRow(token!)!;
      expect(settled['state'], 'cancelled');
      expect(settled['cancel_ack'], 1);
      expect(settled['active'], 1);
      final recheck = await prepare();
      expect(
        recheck.eventEnds,
        isEmpty,
        reason: 'a cancelled notice never re-arms for the same revision',
      );
      expect(recheck.obsoleteTokens, isNot(contains(token)));
      expect(await store.records(), isEmpty);
    });
  });
}

Future<ReminderProjection> _prepareStore(
  RecordStore store, {
  required DateTime now,
  required String? observedZone,
  required ReminderClockSample? clockSample,
  required String adapterFingerprint,
}) => store.prepareReminders(
  now: now,
  observedZone: observedZone,
  clockSample: clockSample,
  adapterFingerprint: adapterFingerprint,
);

/// Store-bound repair repository over the existing 07 adapter contract.
final class _EventEndStoreRepair
    implements ReminderRepairRepository, EventEndReminderRepairRepository {
  _EventEndStoreRepair(this.store);
  final RecordStore store;

  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) => _prepareStore(
    store,
    now: now,
    observedZone: observedZone,
    clockSample: clockSample,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<bool> acknowledge({
    required int sequence,
    required DesiredReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.intentRevision,
    sequence: sequence,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<bool> acknowledgeEventEnd({
    required int sequence,
    required EventEndReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.eventRevision,
    sequence: sequence,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeObsoleteReminder(
    generation: generation,
    sequence: sequence,
    requestToken: requestToken,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );
}

/// Fake adapter over the existing adapter boundary: it accepts the flight but
/// reports the single event-end request as cancelled instead of registered.
final class _EventEndFlightGateway implements ReminderGateway {
  String? eventEndToken;

  @override
  Future<ReminderCapabilities> capabilities() async =>
      const ReminderCapabilities(
        supported: true,
        notificationPermission: true,
        appEnabled: true,
        channelEnabled: true,
        exactAlarm: true,
        protectedStorageAvailable: true,
        bootIdentityAvailable: true,
        fingerprint: 'test-adapter',
      );

  @override
  Future<ReminderClockSample> sampleClock() async => ReminderClockSample(
    utcMilliseconds: DateTime.utc(2026, 10, 19, 12, 5).millisecondsSinceEpoch,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );

  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    final eventRequests = desired
        .where((r) => r.purpose == NativeReminderPurpose.eventEnd)
        .toList();
    if (eventRequests.isNotEmpty) {
      eventEndToken = eventRequests.single.requestToken;
    }
    return NativeReminderSnapshot(
      accepted: true,
      epoch: epoch,
      sequence: sequence,
      receipts: [
        for (final request in desired)
          NativeReminderReceipt(
            requestToken: request.requestToken,
            state: request.purpose == NativeReminderPurpose.eventEnd
                ? NativeReminderState.cancelled
                : NativeReminderState.accepted,
          ),
        for (final token in obsoleteTokens)
          NativeReminderReceipt(
            requestToken: token,
            state: NativeReminderState.cancelled,
          ),
      ],
      fingerprint: 'test-adapter',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
