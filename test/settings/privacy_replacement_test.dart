import 'dart:io';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/settings/privacy_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import '../fixtures/single_user.dart';
import '../vital_app_test.dart' show runIo, settle;

typedef _DeleteCall = ({
  String commandId,
  String personId,
  int expectedRevision,
  String expectedGeneration,
});

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

/// A ready, open lock whose state the test can change without native auth.
final class _TestAppLock extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(ready: true, enabled: false, locked: false);

  void setLocked(bool value) => state = state.copy(locked: value);
}

class _PrivacyHost extends StatelessWidget {
  const _PrivacyHost();

  @override
  Widget build(BuildContext context) => Center(
    child: Builder(
      builder: (context) => TextButton(
        key: const ValueKey('open-privacy'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
        child: const Text('Open'),
      ),
    ),
  );
}

Future<RecordStore> _openStore(WidgetTester tester, Directory directory) async {
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/dataset-${_storeSequence++}.db',
      key: List<int>.generate(32, (index) => index + 1),
      isNew: true,
    ),
  ))!;
  return store;
}

var _storeSequence = 0;

OrdinaryDraft _draft(RecordStore store, int revision) => OrdinaryDraft(
  id: 'draft-1',
  generation: store.generation,
  operationId: 'draft-operation-1',
  kind: DraftKind.profile,
  personId: meId,
  personRevision: revision,
  targetId: meId,
  targetRevision: null,
  fields: const {'name': 'Draft'},
);

Future<ProviderContainer> _pumpPrivacy(
  WidgetTester tester, {
  required RecordStore Function() active,
  required ProfilePrivacyActions actions,
  AppLockController Function()? lock,
}) async {
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => active()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      profilePrivacyActionsProvider.overrideWithValue(actions),
      appLockProvider.overrideWith(lock ?? _TestAppLock.new),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        theme: vitalTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: const _PrivacyHost(),
      ),
    ),
  );
  await settle(tester);
  return container;
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-privacy')));
  await settle(tester);
  final trigger = find.byKey(const ValueKey('privacy-delete-me'));
  await tester.ensureVisible(trigger);
  await settle(tester);
  await tester.tap(trigger);
  await settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Future<void> _tearDown(
  WidgetTester tester,
  ProviderContainer container,
  Directory directory,
  List<RecordStore> stores,
) async {
  container.dispose();
  await runIo(tester, () async {
    for (final store in stores) {
      await store.close();
    }
    await directory.delete(recursive: true);
  });
}

void main() {
  testWidgets(
    'a confirmation opened against an older dataset cannot delete its replacement',
    (tester) async {
      final directory = (await runIo(
        tester,
        () => Directory.systemTemp.createTemp('vital-privacy-replacement-'),
      ))!;
      final first = await _openStore(tester, directory);
      final replacement = await _openStore(tester, directory);
      final firstProfile = (await runIo(
        tester,
        () => first.configureOwnProfile(
          commandId: 'first-adult',
          name: 'Me',
          adultConfirmed: true,
        ),
      ))!;
      final replacementProfile = (await runIo(
        tester,
        () => replacement.configureOwnProfile(
          commandId: 'replacement-adult',
          name: 'Me',
          adultConfirmed: true,
        ),
      ))!;
      // A replacement can reuse the person ID and revision exactly.
      expect(replacementProfile.revision, firstProfile.revision);
      await runIo(
        tester,
        () => replacement.saveDraft(
          _draft(replacement, replacementProfile.revision),
        ),
      );
      var active = first;
      final actions = _RecordingPrivacyActions();
      final container = await _pumpPrivacy(
        tester,
        active: () => active,
        actions: actions,
      );
      addTearDown(
        () => _tearDown(tester, container, directory, [first, replacement]),
      );

      await _openConfirmation(tester);
      expect(
        find.text(
          'Delete all your saved records, files and drafts? This cannot be undone. Saved or shared copies outside Vital remain.',
        ),
        findsOneWidget,
      );

      // Replace the live dataset while the confirmation is still open. Unlike
      // a full restore, this leaves a page mounted so the confirmation itself
      // has to notice the replacement.
      active = replacement;
      container.invalidate(recordStoreProvider);
      await settle(tester);

      await _tapText(tester, 'Delete');

      expect(actions.calls, isEmpty);
      expect(
        find.text(
          'Records changed. Review the latest records before trying again.',
        ),
        findsOneWidget,
      );
      final after = (await runIo(tester, () => replacement.profileById(meId)))!;
      expect(after.revision, replacementProfile.revision);
      expect(after.remindersStopped, replacementProfile.remindersStopped);
      expect(
        await runIo(tester, () => replacement.draftById('draft-1')),
        isNotNull,
      );
    },
  );

  testWidgets('a revision change while confirming writes nothing', (
    tester,
  ) async {
    final directory = (await runIo(
      tester,
      () => Directory.systemTemp.createTemp('vital-privacy-revision-'),
    ))!;
    final store = await _openStore(tester, directory);
    final profile = (await runIo(
      tester,
      () => store.configureOwnProfile(
        commandId: 'profile',
        name: 'Me',
        adultConfirmed: true,
      ),
    ))!;
    await runIo(tester, () => store.saveDraft(_draft(store, profile.revision)));
    final actions = _RecordingPrivacyActions();
    final container = await _pumpPrivacy(
      tester,
      active: () => store,
      actions: actions,
    );
    addTearDown(() => _tearDown(tester, container, directory, [store]));

    await _openConfirmation(tester);
    await runIo(
      tester,
      () => store.configureOwnProfile(
        commandId: 'revision-change',
        name: 'Me',
        adultConfirmed: true,
      ),
    );
    await settle(tester);
    await _tapText(tester, 'Delete');

    expect(actions.calls, isEmpty);
    expect(
      find.text(
        'Records changed. Review the latest records before trying again.',
      ),
      findsOneWidget,
    );
    final after = (await runIo(tester, () => store.profileById(meId)))!;
    expect(after.revision, profile.revision + 1);
    expect(await runIo(tester, () => store.draftById('draft-1')), isNotNull);
  });

  testWidgets('a lock and unlock while confirming writes nothing', (
    tester,
  ) async {
    final directory = (await runIo(
      tester,
      () => Directory.systemTemp.createTemp('vital-privacy-lock-'),
    ))!;
    final store = await _openStore(tester, directory);
    final profile = (await runIo(
      tester,
      () => store.configureOwnProfile(
        commandId: 'profile',
        name: 'Me',
        adultConfirmed: true,
      ),
    ))!;
    final actions = _RecordingPrivacyActions();
    final container = await _pumpPrivacy(
      tester,
      active: () => store,
      actions: actions,
    );
    addTearDown(() => _tearDown(tester, container, directory, [store]));

    await _openConfirmation(tester);
    final lock = container.read(appLockProvider.notifier) as _TestAppLock;
    lock.setLocked(true);
    await settle(tester);
    lock.setLocked(false);
    await settle(tester);
    await _tapText(tester, 'Delete');

    expect(actions.calls, isEmpty);
    expect(
      find.text('Vital locked before the change. Nothing was deleted.'),
      findsOneWidget,
    );
    final after = (await runIo(tester, () => store.profileById(meId)))!;
    expect(after.revision, profile.revision);
    expect(after.remindersStopped, false);
  });

  testWidgets('leaving the page while confirming writes nothing', (
    tester,
  ) async {
    final directory = (await runIo(
      tester,
      () => Directory.systemTemp.createTemp('vital-privacy-route-'),
    ))!;
    final store = await _openStore(tester, directory);
    final profile = (await runIo(
      tester,
      () => store.configureOwnProfile(
        commandId: 'profile',
        name: 'Me',
        adultConfirmed: true,
      ),
    ))!;
    final actions = _RecordingPrivacyActions();
    final container = await _pumpPrivacy(
      tester,
      active: () => store,
      actions: actions,
    );
    addTearDown(() => _tearDown(tester, container, directory, [store]));

    await _openConfirmation(tester);
    final pageContext = tester.element(find.byType(PrivacyPage));
    final route = ModalRoute.of(pageContext)!;
    Navigator.of(pageContext).removeRoute(route);
    await settle(tester);

    // The decision route still owns Delete, but its originating page is gone.
    expect(find.text('Delete'), findsOneWidget);
    await _tapText(tester, 'Delete');

    expect(actions.calls, isEmpty);
    final after = (await runIo(tester, () => store.profileById(meId)))!;
    expect(after.revision, profile.revision);
    expect(after.remindersStopped, false);
  });
}
