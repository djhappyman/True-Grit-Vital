import '../fixtures/single_user.dart';

import 'package:flutter/foundation.dart' show Key, ValueKey;
import 'package:flutter/widgets.dart' show FocusManager;
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
    'failed data-management write preserves records and logs a redacted code',
    (tester) async {
      final f = await launch(tester, privacyActions: _FailingPrivacyActions());
      final a = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: 'failure-adult',
          name: 'Alex Example',
          adultConfirmed: true,
        ),
      ))!;
      await tap(tester, 'Settings');
      await tap(tester, 'Privacy');
      await tapKey(tester, const ValueKey('privacy-delete-me'));
      await tap(tester, 'Delete');

      expect(
        find.text(
          'Could not confirm the change. Review your records before trying again.',
        ),
        findsOneWidget,
      );
      final current = (await runIo(tester, () => f.store.profileById(a.id)))!;
      expect(current.isArchived, false);
      final diagnostics = await runIo(
        tester,
        () => f.store.readSetting('privacy_diagnostics_v1'),
      );
      expect(diagnostics, contains('profile_delete'));
      expect(diagnostics, isNot(contains('Alex Example')));
    },
  );

  appTest('cancelling the confirmation writes nothing', (tester) async {
    final actions = _RecordingPrivacyActions();
    final f = await launch(tester, privacyActions: actions);
    final before = (await runIo(tester, () => f.store.profileById(meId)))!;
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, const ValueKey('privacy-delete-me'));
    await tap(tester, 'Cancel');

    expect(actions.calls, isEmpty);
    final after = (await runIo(tester, () => f.store.profileById(meId)))!;
    expect(after.revision, before.revision);
    expect(after.remindersStopped, before.remindersStopped);
  });

  appTest('the confirmation starts on the safe action', (tester) async {
    final actions = _RecordingPrivacyActions();
    await launch(tester, privacyActions: actions);
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, const ValueKey('privacy-delete-me'));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'privacy-delete-cancel',
    );
    await tap(tester, 'Cancel');
    expect(actions.calls, isEmpty);
  });

  appTest('confirmation passes the captured dataset and owner revision', (
    tester,
  ) async {
    final actions = _RecordingPrivacyActions();
    final f = await launch(tester, privacyActions: actions);
    final before = (await runIo(tester, () => f.store.profileById(meId)))!;
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, const ValueKey('privacy-delete-me'));
    await tap(tester, 'Delete');

    expect(actions.calls, hasLength(1));
    expect(actions.calls.single.personId, meId);
    expect(actions.calls.single.expectedRevision, before.revision);
    expect(actions.calls.single.expectedGeneration, f.store.generation);
    expect(
      find.text('Records deleted. Your profile is still available.'),
      findsOneWidget,
    );

    // A repeated activation after the confirmed result is a new payload and
    // receives a new command identity.
    await tapKey(tester, const ValueKey('privacy-delete-me'));
    await tap(tester, 'Delete');
    expect(actions.calls, hasLength(2));
    expect(actions.calls.last.commandId, isNot(actions.calls.first.commandId));
  });

  appTest('an interrupted write retries with the same command identity', (
    tester,
  ) async {
    final actions = _FailOncePrivacyActions();
    final f = await launch(tester, privacyActions: actions);
    final before = (await runIo(tester, () => f.store.profileById(meId)))!;
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, const ValueKey('privacy-delete-me'));
    await tap(tester, 'Delete');

    expect(
      find.text(
        'Could not confirm the change. Review your records before trying again.',
      ),
      findsOneWidget,
    );
    expect(actions.calls, hasLength(1));
    expect(
      (await runIo(tester, () => f.store.profileById(meId)))!.revision,
      before.revision,
    );

    await tapKey(tester, const ValueKey('privacy-delete-me'));
    await tap(tester, 'Delete');

    expect(actions.calls, hasLength(2));
    expect(actions.calls.last.commandId, actions.calls.first.commandId);
    expect(
      actions.calls.last.expectedRevision,
      actions.calls.first.expectedRevision,
    );
    expect(
      actions.calls.last.expectedGeneration,
      actions.calls.first.expectedGeneration,
    );
  });

  appTest('a profile revision change while confirming writes nothing', (
    tester,
  ) async {
    final actions = _RecordingPrivacyActions();
    final f = await launch(tester, privacyActions: actions);
    final before = (await runIo(tester, () => f.store.profileById(meId)))!;
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    await tapKey(tester, const ValueKey('privacy-delete-me'));

    await runIo(
      tester,
      () => f.store.configureOwnProfile(
        commandId: 'revision-change',
        name: 'Me',
        adultConfirmed: true,
      ),
    );
    await settle(tester);
    await tap(tester, 'Delete');

    expect(actions.calls, isEmpty);
    expect(
      find.text(
        'Records changed. Review the latest records before trying again.',
      ),
      findsOneWidget,
    );
    final after = (await runIo(tester, () => f.store.profileById(meId)))!;
    expect(after.revision, before.revision + 1);
    expect(after.remindersStopped, before.remindersStopped);
  });
}

typedef _DeleteCall = ({
  String commandId,
  String personId,
  int expectedRevision,
  String expectedGeneration,
});

final class _FailingPrivacyActions implements ProfilePrivacyActions {
  Never _fail() => throw StateError('synthetic_privacy_failure');

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String expectedGeneration,
    bool Function()? actionCurrent,
  }) async => _fail();
}

final class _RecordingPrivacyActions implements ProfilePrivacyActions {
  final calls = <_DeleteCall>[];

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String expectedGeneration,
    bool Function()? actionCurrent,
  }) async {
    calls.add((
      commandId: commandId,
      personId: personId,
      expectedRevision: expectedRevision,
      expectedGeneration: expectedGeneration,
    ));
  }
}

/// Fails before committing once, then allows the exact same retry through.
final class _FailOncePrivacyActions implements ProfilePrivacyActions {
  final calls = <_DeleteCall>[];
  var _fail = true;

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String expectedGeneration,
    bool Function()? actionCurrent,
  }) async {
    calls.add((
      commandId: commandId,
      personId: personId,
      expectedRevision: expectedRevision,
      expectedGeneration: expectedGeneration,
    ));
    if (_fail) {
      _fail = false;
      throw StateError('synthetic_interrupted_delete');
    }
  }
}
