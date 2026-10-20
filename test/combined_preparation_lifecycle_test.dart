import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/combined_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

import 'product_ui_test.dart' show product, tapFinder;
import 'reminders/reminder_ui_test.dart' show UiGateway;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

class _Auth implements AppAuthGateway {
  AppAuthAvailability capability = AppAuthAvailability.available;
  AppAuthResult result = AppAuthResult.authenticated;
  final privacy = <bool>[];
  @override
  Future<AppAuthAvailability> availability() async => capability;
  @override
  Future<AppAuthResult> authenticate() async => result;
  @override
  Future<void> setPrivacyEnabled(bool enabled) async {
    privacy.add(enabled);
  }
}

/// Holds the interval-clock sample until the test releases it.
class _GatedClock extends UiGateway {
  final requested = Completer<void>();
  Completer<void>? block;
  Object? fail;
  @override
  Future<ReminderClockSample> sampleClock() async {
    if (!requested.isCompleted) requested.complete();
    final wait = block;
    if (wait != null) await wait.future;
    if (fail != null) throw fail!;
    return clock;
  }
}

typedef _StoreLoader = Future<RecordStore> Function();

class _SurfaceLoader extends Notifier<_StoreLoader> {
  @override
  _StoreLoader build() =>
      () async => throw StateError('no surface');
  void set(_StoreLoader loader) => state = loader;
}

final _surfaceLoaderProvider = NotifierProvider<_SurfaceLoader, _StoreLoader>(
  _SurfaceLoader.new,
);

/// A real provider surface, so a replacement retains the retired store exactly
/// as a dataset swap does without synthesising internal AsyncValue state.
final _surfaceProvider = FutureProvider<RecordStore>(
  retry: (_, _) => null,
  (ref) => ref.watch(_surfaceLoaderProvider)(),
);

Future<ProviderContainer> openCombined(
  WidgetTester tester,
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
  f, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: f.container,
      child: ProviderScope(overrides: overrides, child: const VitalApp()),
    ),
  );
  await settle(tester);
  final inner = ProviderScope.containerOf(
    tester.element(find.byType(VitalApp)),
    listen: false,
  );
  inner.read(_surfaceLoaderProvider.notifier).set(() async => f.store);
  inner.read(_surfaceProvider);
  await settle(tester);
  return inner;
}

/// Starts a replacement that has not resolved yet, retaining the old store.
Completer<RecordStore> beginReplacement(ProviderContainer inner) {
  final gate = Completer<RecordStore>();
  inner.read(_surfaceLoaderProvider.notifier).set(() => gate.future);
  inner.invalidate(_surfaceProvider);
  return gate;
}

/// Starts a replacement whose loader fails while the old store is retained.
void failReplacement(ProviderContainer inner) {
  inner
      .read(_surfaceLoaderProvider.notifier)
      .set(() async => throw StateError('failed replacement'));
  inner.invalidate(_surfaceProvider);
}

Future<void> settleReplacement(
  WidgetTester tester,
  ProviderContainer inner,
) async {
  await inner.read(_surfaceProvider.future);
  await settle(tester);
}

Future<void> healReplacement(
  WidgetTester tester,
  ProviderContainer inner,
  RecordStore store,
) async {
  inner.read(_surfaceLoaderProvider.notifier).set(() async => store);
  inner.invalidate(_surfaceProvider);
  await settleReplacement(tester, inner);
}

Future<void> addSource(WidgetTester tester, String id) async {
  await tap(tester, 'Add');
  await tapFinder(tester, find.byKey(ValueKey('combine-add-$id')));
}

Future<void> amountAt(WidgetTester tester, int index, String value) async {
  final field = find.descendant(
    of: find.widgetWithText(LabelledInput, 'Amount').at(index),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settle(tester);
}

Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}

void main() {
  appTest('intentional repeated source keeps two separate entries', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    expect(find.byKey(const ValueKey('combined-source-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('combined-source-1')), findsOneWidget);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await tap(tester, 'Save');
    await waitForText(
      tester,
      'Correct or undo every source together. Each source retains its own history.',
    );
    final records = (await runIo(tester, f.store.records))!;
    expect(records.length, 2);
    expect(records.map((record) => record.combinedActionId).toSet().length, 1);
    expect(tester.takeException(), isNull);
  });

  appTest('a repeated tap joins one pending source read', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gate = Completer<void>();
    var reads = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: ProviderScope(
          overrides: [
            combinedSourceLabelProvider.overrideWithValue((
              store,
              personId,
              itemId,
            ) async {
              reads++;
              await gate.future;
              return store.productLabel(personId: personId, itemId: itemId);
            }),
          ],
          child: const VitalApp(),
        ),
      ),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    await tapFinder(tester, choose);
    gate.complete();
    await settle(tester);
    expect(reads, 1);
    expect(find.byKey(const ValueKey('combined-source-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('combined-source-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('a source read finishing after lock does not join the form', (
    tester,
  ) async {
    final auth = _Auth();
    final f = await launch(tester, auth: auth);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gate = Completer<void>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: ProviderScope(
          overrides: [
            combinedSourceLabelProvider.overrideWithValue((
              store,
              personId,
              itemId,
            ) async {
              await gate.future;
              return store.productLabel(personId: personId, itemId: itemId);
            }),
          ],
          child: const VitalApp(),
        ),
      ),
    );
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    await settle(tester);
    expect(f.container.read(appLockProvider).enabled, isTrue);
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(f.container.read(appLockProvider).locked, isTrue);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    expect(f.container.read(appLockProvider).locked, isFalse);
    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-0')), findsNothing);
    // A deliberate later choice still works once the lock boundary has passed.
    await tapFinder(tester, choose);
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-0')), findsOneWidget);
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('a review finishing after lock freezes no command', (tester) async {
    final auth = _Auth();
    final f = await launch(tester, auth: auth);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gateway = _GatedClock();
    gateway.block = Completer<void>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: ProviderScope(
          overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
          child: const VitalApp(),
        ),
      ),
    );
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await waitUntil(tester, () => gateway.requested.isCompleted);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    gateway.block!.complete();
    await settle(tester);
    expect(find.text('Review entry'), findsNothing);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.fields['frozen'], isEmpty);
    // The reviewed source amounts are still here, so a fresh review succeeds.
    expect(find.byKey(const ValueKey('combined-source-1')), findsOneWidget);
    gateway.block = null;
    await tap(tester, 'Review');
    expect(find.text('Review entry'), findsOneWidget);
    await tap(tester, 'Save');
    await waitForText(
      tester,
      'Correct or undo every source together. Each source retains its own history.',
    );
    expect((await runIo(tester, f.store.records))!.length, 2);
    expect(tester.takeException(), isNull);
  });

  appTest('a genuine source read failure stays visible and can be retried', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    var fail = true;
    await openCombined(
      tester,
      f,
      overrides: [
        combinedSourceLabelProvider.overrideWithValue((
          store,
          personId,
          itemId,
        ) async {
          if (fail) {
            fail = false;
            throw StateError('label read failed');
          }
          return store.productLabel(personId: personId, itemId: itemId);
        }),
      ],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    await settle(tester);
    expect(
      find.text('The source could not be loaded. Choose it again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('combined-source-0')), findsNothing);
    // The item chooser stays open, so the person can deliberately retry.
    await tapFinder(tester, choose);
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-0')), findsOneWidget);
    expect(
      find.text('The source could not be loaded. Choose it again.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    appTest('a source read after disposal stays silent (failure: $fails)', (
      tester,
    ) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      final gate = Completer<ProductLabelSnapshot?>();
      await openCombined(
        tester,
        f,
        overrides: [
          combinedSourceLabelProvider.overrideWithValue(
            (_, _, _) => gate.future,
          ),
        ],
      );
      f.container.read(routerProvider).go('/combined/$meId');
      await settle(tester);
      await tap(tester, 'Add');
      await tapFinder(tester, find.byKey(ValueKey('combine-add-${item.id}')));
      await tester.pumpWidget(const SizedBox.shrink());
      if (fails) {
        gate.completeError(StateError('retired source read failed'));
      } else {
        gate.complete(null);
      }
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(await runIo(tester, f.store.records), isEmpty);
    });
  }

  appTest('a source read failure after lock stays silent', (tester) async {
    final auth = _Auth();
    final f = await launch(tester, auth: auth);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gate = Completer<void>();
    await openCombined(
      tester,
      f,
      overrides: [
        combinedSourceLabelProvider.overrideWithValue((
          store,
          personId,
          itemId,
        ) async {
          await gate.future;
          throw StateError('label read failed');
        }),
      ],
    );
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    gate.complete();
    await settle(tester);
    expect(
      find.text('The source could not be loaded. Choose it again.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('combined-source-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('a current review failure stays visible and can be retried', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gateway = _GatedClock()
      ..block = Completer<void>()
      ..fail = StateError('clock failed');
    await openCombined(
      tester,
      f,
      overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await waitUntil(tester, () => gateway.requested.isCompleted);
    gateway.block!.complete();
    await settle(tester);
    expect(
      find.text('Check each source amount, unit and time, then review again.'),
      findsWidgets,
    );
    expect(find.text('Review entry'), findsNothing);
    gateway
      ..fail = null
      ..block = null;
    await tap(tester, 'Review');
    await settle(tester);
    expect(find.text('Review entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('a review failure after lock stays silent', (tester) async {
    final auth = _Auth();
    final f = await launch(tester, auth: auth);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gateway = _GatedClock()
      ..block = Completer<void>()
      ..fail = StateError('clock failed');
    await openCombined(
      tester,
      f,
      overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
    );
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await waitUntil(tester, () => gateway.requested.isCompleted);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    gateway.block!.complete();
    await settle(tester);
    expect(
      find.text('Check each source amount, unit and time, then review again.'),
      findsNothing,
    );
    expect(find.text('Review entry'), findsNothing);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.fields['frozen'], isEmpty);
    gateway
      ..fail = null
      ..block = null;
    await tap(tester, 'Review');
    await settle(tester);
    expect(find.text('Review entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('a source read finishing during a replacement joins no source', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gate = Completer<void>();
    var gated = false;
    final inner = await openCombined(
      tester,
      f,
      overrides: [
        combinedRecordSurfaceProvider.overrideWith(
          (ref) => ref.watch(_surfaceProvider),
        ),
        combinedSourceLabelProvider.overrideWithValue((
          store,
          personId,
          itemId,
        ) async {
          if (gated) await gate.future;
          return store.productLabel(personId: personId, itemId: itemId);
        }),
      ],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    gated = true;
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    final replacement = beginReplacement(inner);
    await settle(tester);
    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-1')), findsNothing);
    expect(
      find.text('The source could not be loaded. Choose it again.'),
      findsNothing,
    );
    final draft = (await runIo(tester, f.store.drafts))!.single;
    final components = jsonDecode(draft.fields['components']!) as List;
    expect(components.length, 1);
    // A settled replacement allows the deliberate source again.
    replacement.complete(f.store);
    await settleReplacement(tester, inner);
    await tapFinder(tester, choose);
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('a source read error during a replacement shows no banner', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gate = Completer<void>();
    var gated = false;
    final inner = await openCombined(
      tester,
      f,
      overrides: [
        combinedRecordSurfaceProvider.overrideWith(
          (ref) => ref.watch(_surfaceProvider),
        ),
        combinedSourceLabelProvider.overrideWithValue((
          store,
          personId,
          itemId,
        ) async {
          if (gated) {
            await gate.future;
            throw StateError('label read failed');
          }
          return store.productLabel(personId: personId, itemId: itemId);
        }),
      ],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    gated = true;
    await tap(tester, 'Add');
    final choose = find.byKey(ValueKey('combine-add-${item.id}'));
    await tapFinder(tester, choose);
    final replacement = beginReplacement(inner);
    await settle(tester);
    gate.complete();
    await settle(tester);
    expect(
      find.text('The source could not be loaded. Choose it again.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('combined-source-1')), findsNothing);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    final components = jsonDecode(draft.fields['components']!) as List;
    expect(components.length, 1);
    gated = false;
    replacement.complete(f.store);
    await settleReplacement(tester, inner);
    await tapFinder(tester, choose);
    await settle(tester);
    expect(find.byKey(const ValueKey('combined-source-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('a review finishing during a replacement freezes no command', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gateway = _GatedClock()..block = Completer<void>();
    final inner = await openCombined(
      tester,
      f,
      overrides: [
        combinedRecordSurfaceProvider.overrideWith(
          (ref) => ref.watch(_surfaceProvider),
        ),
        reminderGatewayProvider.overrideWithValue(gateway),
      ],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await waitUntil(tester, () => gateway.requested.isCompleted);
    final replacement = beginReplacement(inner);
    await settle(tester);
    gateway.block!.complete();
    await settle(tester);
    expect(find.text('Review entry'), findsNothing);
    expect(
      find.text('Check each source amount, unit and time, then review again.'),
      findsNothing,
    );
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.fields['frozen'], isEmpty);
    replacement.complete(f.store);
    gateway.block = null;
    await settleReplacement(tester, inner);
    await tap(tester, 'Review');
    await settle(tester);
    expect(find.text('Review entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('a review error during a failed replacement shows no banner', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    final gateway = _GatedClock()
      ..block = Completer<void>()
      ..fail = StateError('clock failed');
    final inner = await openCombined(
      tester,
      f,
      overrides: [
        combinedRecordSurfaceProvider.overrideWith(
          (ref) => ref.watch(_surfaceProvider),
        ),
        reminderGatewayProvider.overrideWithValue(gateway),
      ],
    );
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, '1');
    await amountAt(tester, 1, '2');
    await tap(tester, 'Review');
    await waitUntil(tester, () => gateway.requested.isCompleted);
    failReplacement(inner);
    await settle(tester);
    gateway.block!.complete();
    await settle(tester);
    expect(
      find.text('Check each source amount, unit and time, then review again.'),
      findsNothing,
    );
    expect(find.text('Review entry'), findsNothing);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.fields['frozen'], isEmpty);
    await healReplacement(tester, inner, f.store);
    gateway
      ..fail = null
      ..block = null;
    await settle(tester);
    await tap(tester, 'Review');
    await settle(tester);
    expect(find.text('Review entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
