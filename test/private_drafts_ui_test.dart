import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

import 'vital_app_test.dart' show appTest, settle, tap, runIo;

class FakeAuth implements AppAuthGateway {
  AppAuthAvailability capability = AppAuthAvailability.available;
  AppAuthResult result = AppAuthResult.authenticated;
  Completer<AppAuthResult>? pending;
  final privacy = <bool>[];
  @override
  Future<AppAuthAvailability> availability() async => capability;
  @override
  Future<AppAuthResult> authenticate() =>
      pending?.future ?? Future.value(result);
  @override
  Future<void> setPrivacyEnabled(bool enabled) async {
    privacy.add(enabled);
  }
}

Future<
  ({
    RecordStore store,
    ProviderContainer container,
    String path,
    List<int> key,
    FakeAuth auth,
  })
>
fixture(
  WidgetTester tester, {
  bool enabled = false,
  FakeAuth? auth,
  Future<UseRecord> Function(RecordStore, RecordInput)? writer,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-lock-ui-'),
  ))!;
  final path = '${dir.path}/records.db', key = List.generate(32, (i) => i + 1);
  final store = (await runIo(tester, () async {
    final s = await RecordStore.open(path: path, key: key, isNew: true);
    await s.editProfile(
      commandId: 'setup',
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await s.saveBrowsingScope(const FeedScope.me());
    await s.writeSetting('app_lock', enabled.toString());
    return s;
  }))!;
  final gateway = auth ?? FakeAuth();
  final container = ProviderContainer(
    overrides: [
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(gateway),
      if (writer != null)
        recordWriterProvider.overrideWithValue((input) => writer(store, input)),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (
    store: store,
    container: container,
    path: path,
    key: key,
    auth: gateway,
  );
}

void main() {
  appTest(
    'cancelled lock setup changes no preference and unsupported capability keeps recording usable',
    (tester) async {
      final auth = FakeAuth()..result = AppAuthResult.cancelled;
      final f = await fixture(tester, auth: auth);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      await settle(tester);
      expect(f.container.read(appLockProvider).enabled, false);
      expect(
        await runIo(tester, () => f.store.readSetting('app_lock')),
        'false',
      );
      expect(auth.privacy, [false]);
      auth.capability = AppAuthAvailability.unsupported;
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      await settle(tester);
      await tap(tester, 'Appearance');
      expect(
        find.text(
          'Device authentication is unavailable on this platform. You can still record doses.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Back');
      await tap(tester, 'Substances');
      await tap(tester, 'Create');
      expect(find.byType(TextField), findsNWidgets(3));
    },
  );
  appTest(
    'startup lock hides content; cancel remains locked; valid unlock resumes original draft without hidden focus',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final f = await fixture(tester, enabled: true);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Unlock'), findsNWidgets(2));
      f.auth.result = AppAuthResult.cancelled;
      await tap(tester, 'Unlock');
      expect(find.text('Today'), findsNothing);
      f.auth.result = AppAuthResult.authenticated;
      await tap(tester, 'Unlock');
      await tap(tester, 'Substances');
      await tap(tester, 'Create');
      await tester.enterText(
        find.byType(TextField).first,
        'Private unfinished substance',
      );
      await settle(tester);
      final command = (await runIo(tester, f.store.drafts))!.single.operationId;
      await tester.enterText(
        find.byType(TextField).first,
        'Private unfinished substance latest',
      );
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('Private unfinished substance'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      for (final input in tester.widgetList<EditableText>(
        find.byType(EditableText, skipOffstage: false),
      )) {
        expect(input.focusNode.hasFocus, false);
      }
      expect(find.bySemanticsLabel('Full name'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(find.byType(TextField), findsNothing);
      expect(f.store.writesSuspended, true);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      expect(find.text('Private unfinished substance latest'), findsOneWidget);
      expect(
        (await runIo(tester, f.store.drafts))!.single.operationId,
        command,
      );
      await tester.enterText(find.byType(TextField).at(1), 'tablet');
      await tap(tester, 'mg');
      await tester.enterText(find.byType(TextField).at(2), 'medicine');
      await tap(tester, 'Create');
      expect(
        (await runIo(tester, f.store.items))!.single.name,
        'Private unfinished substance latest',
      );
      expect(await runIo(tester, f.store.drafts), isEmpty);
      semantics.dispose();
    },
  );
  appTest(
    'authentication completing in background never reveals content or permits writes',
    (tester) async {
      final f = await fixture(tester, enabled: true);
      f.auth.pending = Completer<AppAuthResult>();
      final unlock = f.container.read(appLockProvider.notifier).unlock();
      await tester.pump();
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.paused);
      f.auth.pending!.complete(AppAuthResult.authenticated);
      await unlock;
      await settle(tester);
      expect(f.container.read(appLockProvider).locked, true);
      expect(find.text('Today'), findsNothing);
      expect(f.store.writesSuspended, true);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.text('Today'), findsNothing);
    },
  );
  appTest(
    'ordinary entries resume after router restart and explicit discard clears them',
    (tester) async {
      final f = await fixture(tester);
      await tap(tester, 'Substances');
      await tap(tester, 'Create');
      await tester.enterText(
        find.byType(TextField).first,
        'Survives router restart',
      );
      await settle(tester);
      final draft = (await runIo(tester, f.store.drafts))!.single;
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      final container = ProviderContainer(
        overrides: [
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
          storeLoaderProvider.overrideWithValue(() async => f.store),
          appAuthGatewayProvider.overrideWithValue(f.auth),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const VitalApp(),
        ),
      );
      await settle(tester);
      expect(find.text('Unfinished entries'), findsOneWidget);
      await tap(tester, 'Resume');
      expect(find.text('Survives router restart'), findsOneWidget);
      expect(
        (await runIo(tester, f.store.drafts))!.single.operationId,
        draft.operationId,
      );
      await tap(tester, 'Back');
      await tap(tester, 'Discard');
      expect(await runIo(tester, f.store.drafts), isEmpty);
      await tap(tester, 'People');
      await tap(tester, 'Add');
      await tester.enterText(find.byType(TextField).first, 'Unfinished adult');
      await tap(tester, 'Adult confirmed');
      final profile = (await runIo(tester, f.store.drafts))!.single;
      expect(profile.kind, DraftKind.profile);
      expect(profile.fields['adult'], 'true');
    },
  );
  appTest(
    'scoped deletion invalidates an open dose draft and hides its fields',
    (tester) async {
      final f = await fixture(tester);
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'delete-item',
          name: 'Synthetic deletion item',
          form: 'tablet',
          unit: 'mg',
          type: 'medicine',
          expectedPersonRevision: 2,
        ),
      ))!;
      f.container.read(routerProvider).push('/record/${item.id}');
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '2');
      await settle(tester);
      expect((await runIo(tester, f.store.drafts))!.single.personId, meId);
      await runIo(
        tester,
        () => f.store.deleteProfile(
          commandId: 'delete-records',
          personId: meId,
          expectedRevision: 2,
        ),
      );
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(await runIo(tester, f.store.drafts), isEmpty);
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest(
    'Me deletion invalidates a targetless substance draft without showing old fields',
    (tester) async {
      final f = await fixture(tester);
      await tap(tester, 'Substances');
      await tap(tester, 'Create');
      await tester.enterText(
        find.byType(TextField).first,
        'Deleted private draft',
      );
      await settle(tester);
      await runIo(
        tester,
        () => f.store.deleteProfile(
          commandId: 'delete-me-draft',
          personId: meId,
          expectedRevision: 2,
        ),
      );
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Deleted private draft'), findsNothing);
      expect(await runIo(tester, f.store.drafts), isEmpty);
    },
  );
}
