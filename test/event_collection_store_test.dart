import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  final now = DateTime.utc(2026, 10, 24, 11, 55);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-event-collection-');
    store = await RecordStore.open(
      path: '${dir.path}/collection.db',
      key: key,
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  EventDate day(int month, int day) =>
      EventDate.day(CivilDate(2026, month, day));

  Future<EventRecord> save(
    String id, {
    EventDate? start,
    EventDate? end,
    bool completed = false,
  }) async {
    final command = SaveEventCommand(
      commandId: 'save-$id',
      generation: store.generation,
      expectedRevision: null,
      event: EventRecord(
        id: id,
        personId: meId,
        name: 'Event $id',
        eventType: 'course',
        zoneId: 'Europe/London',
        revision: 1,
        plannedStart: start,
        plannedEnd: end,
        completed: completed,
      ),
    );
    return store.saveEvent(
      command,
      membershipReview: await store.previewEventMembership(command),
    );
  }

  test(
    'whole-collection counts use the canonical phase for every event',
    () async {
      await save('active-open', start: day(10, 1));
      await save('active-bounded', start: day(10, 1), end: day(10, 30));
      await save('upcoming', start: day(11, 2));
      await save('completed', start: day(10, 1), completed: true);
      await save(
        'review-partial',
        start: EventDate(precision: EventDatePrecision.month, value: '2026-10'),
      );
      await save('review-end-only', end: day(11, 30));

      final all = await store.eventCollection(
        filter: EventCollectionFilter.all,
        now: now,
      );
      expect(all.counts.all, 6);
      expect(all.counts.active, 2);
      expect(all.counts.upcoming, 1);
      expect(all.counts.completed, 1);
      expect(all.counts.review, 2);
      expect(
        all.counts.active +
            all.counts.upcoming +
            all.counts.completed +
            all.counts.review,
        all.counts.all,
      );
      expect(all.filteredTotal, 6);
      expect(all.total, 6);
      expect(all.events.map((event) => event.id), [
        'active-bounded',
        'active-open',
        'completed',
        'review-end-only',
        'review-partial',
        'upcoming',
      ]);

      final review = await store.eventCollection(
        filter: EventCollectionFilter.review,
        now: now,
      );
      expect(review.events.map((event) => event.id), [
        'review-end-only',
        'review-partial',
      ]);
      expect(review.counts, sameCounts(all.counts));
    },
  );

  test(
    'filters the whole collection before slicing a deterministic page',
    () async {
      for (var index = 0; index < 55; index++) {
        await save(
          'active-${index.toString().padLeft(3, '0')}',
          start: day(10, 1),
        );
      }
      for (var index = 0; index < 10; index++) {
        await save(
          'upcoming-${index.toString().padLeft(3, '0')}',
          start: day(12, 1),
        );
      }

      final first = await store.eventCollection(
        filter: EventCollectionFilter.all,
        now: now,
      );
      expect(first.counts.all, 65);
      expect(first.counts.active, 55);
      expect(first.counts.upcoming, 10);
      expect(first.events, hasLength(eventCollectionPageSize));
      expect(first.hasNext, isTrue);
      expect(first.hasPrevious, isFalse);

      final second = await store.eventCollection(
        filter: EventCollectionFilter.all,
        now: now,
        offset: eventCollectionPageSize,
      );
      expect(second.events, hasLength(15));
      expect(second.events.first.id, 'active-050');
      expect(second.events.last.id, 'upcoming-009');
      expect(
        {...first.events.map((event) => event.id)}
            .intersection({...second.events.map((event) => event.id)}),
        isEmpty,
      );

      // A filter on values only present after the first raw page must still
      // return that status instead of an empty page.
      final upcoming = await store.eventCollection(
        filter: EventCollectionFilter.upcoming,
        now: now,
      );
      expect(upcoming.events, hasLength(10));
      expect(upcoming.filteredTotal, 10);
      expect(upcoming.total, 65);
      expect(upcoming.hasNext, isFalse);
      expect(
        upcoming.events.every((event) => event.id.startsWith('upcoming-')),
        isTrue,
      );

      final active = await store.eventCollection(
        filter: EventCollectionFilter.active,
        now: now,
      );
      expect(active.events, hasLength(eventCollectionPageSize));
      expect(active.filteredTotal, 55);
      expect(active.hasNext, isTrue);
    },
  );

  test('clamps a stale offset to the last filtered page', () async {
    for (var index = 0; index < 3; index++) {
      await save(
        'small-${index.toString().padLeft(3, '0')}',
        start: day(10, 1),
      );
    }
    final empty = await store.eventCollection(
      filter: EventCollectionFilter.completed,
      now: now,
      offset: 150,
    );
    expect(empty.filteredTotal, 0);
    expect(empty.offset, 0);
    expect(empty.events, isEmpty);
    expect(empty.hasPrevious, isFalse);
    expect(empty.hasNext, isFalse);

    final clamped = await store.eventCollection(
      filter: EventCollectionFilter.all,
      now: now,
      offset: 150,
    );
    expect(clamped.offset, 0);
    expect(clamped.events, hasLength(3));

    for (var index = 3; index < 60; index++) {
      await save(
        'small-${index.toString().padLeft(3, '0')}',
        start: day(10, 1),
      );
    }
    final late = await store.eventCollection(
      filter: EventCollectionFilter.all,
      now: now,
      offset: 150,
    );
    expect(late.offset, 50);
    expect(late.events, hasLength(10));
    expect(late.events.first.id, 'small-050');
    expect(late.hasPrevious, isTrue);
    expect(late.hasNext, isFalse);
  });

  test(
    'clamps a late page against the filtered total, not all events',
    () async {
      for (var index = 0; index < 60; index++) {
        await save(
          'done-${index.toString().padLeft(3, '0')}',
          start: day(10, 1),
          completed: true,
        );
      }
      for (var index = 0; index < 3; index++) {
        await save(
          'open-${index.toString().padLeft(3, '0')}',
          start: day(10, 1),
        );
      }

      final stale = await store.eventCollection(
        filter: EventCollectionFilter.active,
        now: now,
        offset: 50,
      );
      expect(stale.counts.all, 63);
      expect(stale.filteredTotal, 3);
      expect(stale.offset, 0);
      expect(stale.events.map((event) => event.id), [
        'open-000',
        'open-001',
        'open-002',
      ]);
      expect(stale.hasPrevious, isFalse);
      expect(stale.hasNext, isFalse);

      // The same offset is valid for the larger unrelated status, proving the
      // clamp follows the chosen filter rather than the whole collection.
      final completed = await store.eventCollection(
        filter: EventCollectionFilter.completed,
        now: now,
        offset: 50,
      );
      expect(completed.filteredTotal, 60);
      expect(completed.offset, 50);
      expect(completed.events, hasLength(10));
      expect(completed.events.first.id, 'done-050');
    },
  );

  test('refuses to read the collection while writes are suspended', () async {
    await save('locked', start: day(10, 1));
    store.suspendWrites(true);
    await expectLater(
      store.eventCollection(filter: EventCollectionFilter.all, now: now),
      throwsA(
        isA<CommandConflict>().having(
          (error) => error.code,
          'code',
          'app_locked',
        ),
      ),
    );
    store.suspendWrites(false);
    expect(
      (await store.eventCollection(
        filter: EventCollectionFilter.all,
        now: now,
      )).counts.all,
      1,
    );
  });

  test(
    'the watch exposes fresh whole counts and the current generation',
    () async {
      await save('first', start: day(10, 1));
      final iterator = StreamIterator(
        store.watchEventCollection(filter: EventCollectionFilter.all, now: now),
      );
      addTearDown(iterator.cancel);
      Future<EventCollectionSnapshot> nextWhere(
        bool Function(EventCollectionSnapshot) test,
      ) async {
        while (await iterator.moveNext().timeout(const Duration(seconds: 10))) {
          if (test(iterator.current)) return iterator.current;
        }
        fail('collection watch closed before the expected snapshot');
      }

      final first = await nextWhere((snapshot) => snapshot.counts.all == 1);
      expect(first.generation, store.generation);
      expect(first.counts.active, 1);

      await save('second', start: day(12, 1));
      final second = await nextWhere((snapshot) => snapshot.counts.all == 2);
      expect(second.generation, store.generation);
      expect(second.counts.active, 1);
      expect(second.counts.upcoming, 1);
      expect(second.events.map((event) => event.id), ['first', 'second']);

      await save('third', start: day(10, 1), completed: true);
      final third = await nextWhere((snapshot) => snapshot.counts.all == 3);
      expect(third.counts.completed, 1);
      final completed = await store.eventCollection(
        filter: EventCollectionFilter.completed,
        now: now,
      );
      expect(completed.events.single.id, 'third');
    },
  );
}

Matcher sameCounts(EventCollectionCounts counts) => isA<EventCollectionCounts>()
    .having((value) => value.all, 'all', counts.all)
    .having((value) => value.active, 'active', counts.active)
    .having((value) => value.upcoming, 'upcoming', counts.upcoming)
    .having((value) => value.completed, 'completed', counts.completed)
    .having((value) => value.review, 'review', counts.review);
