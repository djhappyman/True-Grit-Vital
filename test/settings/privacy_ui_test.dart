import 'package:flutter/foundation.dart' show Key, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/data/record_store.dart';

import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

Future<void> tapKey(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  appTest(
    'archive keeps history, stops reminders and reactivation stays stopped',
    (tester) async {
      final f = await launch(tester);
      final a = (await runIo(
        tester,
        () => f.store.createProfile(
          commandId: 'privacy-adult',
          name: 'Alex Example',
          adultConfirmed: true,
        ),
      ))!;
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'privacy-item',
          personId: a.id,
          expectedPersonRevision: a.revision,
          name: 'Synthetic tablet',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        ),
      ))!;
      final record = (await runIo(
        tester,
        () => f.store.record(
          commandId: 'privacy-record',
          personId: a.id,
          expectedPersonRevision: a.revision,
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19, 9),
        ),
      ))!;

      await tap(tester, 'Settings');
      await tap(tester, 'Privacy');
      expect(
        find.textContaining('Archive keeps history and stops reminders.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Anyone who can unlock this device can see every local profile. Adult profiles are not separate accounts.',
        ),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Archive Alex Example'), findsOneWidget);
      expect(find.text('Delete Alex Example'), findsNothing);
      await tapKey(tester, ValueKey('privacy-archive-${a.id}'));
      await tap(tester, 'Archive');
      semantics.dispose();

      final archived = (await runIo(tester, () => f.store.profileById(a.id)))!;
      expect(archived.isArchived, true);
      expect(archived.remindersStopped, true);
      expect(
        (await runIo(tester, () => f.store.records(personId: a.id)))!.single.id,
        record.id,
      );
      expect(
        (await runIo(tester, f.store.reminderStopIntents))![a.id],
        isNotNull,
      );
      expect(
        find.text(
          'Alex Example archived. History is kept and reminders are stopped.',
        ),
        findsOneWidget,
      );
      expect(find.text('Archived people'), findsOneWidget);

      await tapKey(tester, ValueKey('privacy-reactivate-${a.id}'));
      await tap(tester, 'Reactivate');

      final resumed = (await runIo(tester, () => f.store.profileById(a.id)))!;
      expect(resumed.isArchived, false);
      expect(resumed.remindersStopped, true);
      expect(
        (await runIo(tester, f.store.reminderStopIntents))![a.id],
        resumed.revision,
      );
      expect(
        (await runIo(tester, () => f.store.records(personId: a.id))),
        hasLength(1),
      );
      expect(
        find.text(
          'Alex Example reactivated. Reminders stay stopped until you set them again.',
        ),
        findsOneWidget,
      );
    },
  );

  appTest('deletion removes only the selected adult and Me stays available', (
    tester,
  ) async {
    final f = await launch(tester);
    final a = (await runIo(
      tester,
      () => f.store.createProfile(
        commandId: 'delete-a',
        name: 'Alex Example',
        adultConfirmed: true,
      ),
    ))!;
    final b = (await runIo(
      tester,
      () => f.store.createProfile(
        commandId: 'delete-b',
        name: 'Blair Example',
        adultConfirmed: true,
      ),
    ))!;
    final ai = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'delete-ai',
        personId: a.id,
        expectedPersonRevision: a.revision,
        name: 'Synthetic A',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    final bi = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'delete-bi',
        personId: b.id,
        expectedPersonRevision: b.revision,
        name: 'Synthetic B',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    final me = (await runIo(tester, () => f.store.profileById(meId)))!;
    final mi = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'delete-mi',
        personId: meId,
        expectedPersonRevision: me.revision,
        name: 'Synthetic Me',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    for (final (person, item, command) in [
      (a, ai, 'delete-ar'),
      (b, bi, 'delete-br'),
      (me, mi, 'delete-mr'),
    ]) {
      await runIo(
        tester,
        () => f.store.record(
          commandId: command,
          personId: person.id,
          expectedPersonRevision: person.revision,
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19, 9),
        ),
      );
    }

    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, ValueKey('privacy-delete-${a.id}'));
    expect(
      find.textContaining('Delete all saved records for Alex Example?'),
      findsOneWidget,
    );
    await tap(tester, 'Delete');

    expect(await runIo(tester, () => f.store.profileById(a.id)), isNull);
    expect(
      (await runIo(tester, () => f.store.records(personId: b.id))),
      hasLength(1),
    );
    expect(
      (await runIo(tester, () => f.store.records(personId: meId))),
      hasLength(1),
    );
    expect(find.text('Alex Example deleted.'), findsOneWidget);

    await tapKey(tester, const ValueKey('privacy-delete-me'));
    expect(
      find.textContaining(
        'Me stays available and other people are not changed.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Delete');

    expect(await runIo(tester, () => f.store.profileById(meId)), isNotNull);
    expect(await runIo(tester, () => f.store.records(personId: meId)), isEmpty);
    expect(
      await runIo(tester, () => f.store.items(scope: const FeedScope.me())),
      isEmpty,
    );
    expect(
      (await runIo(tester, () => f.store.records(personId: b.id))),
      hasLength(1),
    );
    expect(
      find.text('Records deleted. Me is still available.'),
      findsOneWidget,
    );
  });

  appTest(
    'failed data-management write preserves records and logs a redacted code',
    (tester) async {
      final f = await launch(tester, privacyActions: _FailingPrivacyActions());
      final a = (await runIo(
        tester,
        () => f.store.createProfile(
          commandId: 'failure-adult',
          name: 'Alex Example',
          adultConfirmed: true,
        ),
      ))!;
      await tap(tester, 'Settings');
      await tap(tester, 'Privacy');
      await tapKey(tester, ValueKey('privacy-archive-${a.id}'));
      await tap(tester, 'Archive');

      expect(
        find.text(
          'Could not confirm the change. Review the people shown here before trying again.',
        ),
        findsOneWidget,
      );
      final current = (await runIo(tester, () => f.store.profileById(a.id)))!;
      expect(current.isArchived, false);
      final diagnostics = await runIo(
        tester,
        () => f.store.readSetting('privacy_diagnostics_v1'),
      );
      expect(diagnostics, contains('profile_archive'));
      expect(diagnostics, isNot(contains('Alex Example')));
    },
  );
}

final class _FailingPrivacyActions implements ProfilePrivacyActions {
  Never _fail() => throw StateError('synthetic_privacy_failure');

  @override
  Future<void> archive({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async => _fail();

  @override
  Future<void> reactivate({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async => _fail();

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async => _fail();
}
