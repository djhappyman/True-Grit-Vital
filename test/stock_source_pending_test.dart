import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';
import 'package:true_grit_vital/features/stock/stock_source_link.dart';
import 'package:true_grit_vital/features/stock/stock_widgets.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, launch, settle;

class _SourceLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void hide() => state = state.copy(locked: true);
  void show() => state = state.copy(locked: false);
}

void main() {
  for (final scenario in [
    'lock',
    'lock-unlock',
    'double',
    'leave',
    'failure',
  ]) {
    appTest('pending stock source respects $scenario', (tester) async {
      final f = await launch(tester);
      final pending = Completer<StockSourceTarget>();
      final movement = StoredStockMovement(
        id: 'movement',
        personId: meId,
        containerId: 'container',
        sequence: 1,
        kind: StockMovementKind.actualUse,
        amount: ExactAmount.parseEntry('1'),
        strength: LabelledStrength(ingredientId: 'item', label: '10 mg/ml'),
        recordedAt: DateTime.utc(2026, 10, 22),
        recordId: 'dose',
      );
      final scoped = ProviderContainer(
        parent: f.container,
        overrides: [
          appLockProvider.overrideWith(_SourceLock.new),
          stockSourceTargetProvider.overrideWith((ref, key) => pending.future),
          stockMovementsProvider.overrideWith((ref, query) async => [movement]),
        ],
      );
      addTearDown(scoped.dispose);
      final router = GoRouter(
        initialLocation: '/stock',
        routes: [
          GoRoute(
            path: '/stock',
            builder: (_, _) => const VitalPage(
              children: [
                StockMovementHistory(
                  personId: meId,
                  containerId: 'container',
                  unit: 'ml',
                ),
              ],
            ),
          ),
          GoRoute(path: '/other', builder: (_, _) => const Text('Other page')),
          GoRoute(
            path: '/history-source/:kind/:id',
            builder: (_, state) => Text('Source ${state.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scoped,
          child: ShadcnApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'GB')],
          ),
        ),
      );
      await settle(tester);
      final open = find.widgetWithText(VitalButton, 'Open');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      if (scenario == 'double') {
        // A second activation is blocked while the real source lookup waits.
        expect(tester.widget<VitalButton>(open).onPressed, isNull);
      } else if (scenario == 'lock' || scenario == 'lock-unlock') {
        (scoped.read(appLockProvider.notifier) as _SourceLock).hide();
        if (scenario == 'lock-unlock') {
          (scoped.read(appLockProvider.notifier) as _SourceLock).show();
        }
      } else if (scenario == 'leave') {
        router.push('/other');
        await settle(tester);
      }
      if (scenario == 'failure') {
        pending.completeError(StateError('synthetic source lookup'));
      } else {
        pending.complete(singleStockSourceTarget('dose'));
      }
      await settle(tester);
      if (scenario == 'double' || scenario == 'failure') {
        expect(find.text('Source dose'), findsOneWidget);
        router.pop();
        await settle(tester);
        expect(router.canPop(), isFalse);
        expect(tester.widget<VitalButton>(open).onPressed, isNotNull);
      } else {
        expect(find.text('Source dose'), findsNothing);
        if (scenario == 'leave') {
          expect(find.text('Other page'), findsOneWidget);
          router.pop();
          await settle(tester);
        }
        expect(tester.widget<VitalButton>(open).onPressed, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
