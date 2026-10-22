import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/reminder_health.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart'
    show ReminderConvergence;
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/domain/history/display_time.dart'
    show TimeFormat;
import 'package:true_grit_vital/domain/reminders/reminders.dart';
import 'package:true_grit_vital/features/reminders/reminder_cancellations.dart';
import 'package:true_grit_vital/features/reminders/reminder_health_panel.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/platform/reminders.dart';

const captureDirectory = String.fromEnvironment(
  'VITAL_REMINDER_CANCELLATION_CAPTURE',
);

const _capabilities = ReminderCapabilities(
  supported: true,
  notificationPermission: true,
  appEnabled: true,
  channelEnabled: true,
  exactAlarm: true,
  protectedStorageAvailable: true,
  bootIdentityAvailable: true,
  fingerprint: 'test-adapter',
);

final _reportedAt = DateTime.utc(2026, 10, 19, 8);

ReminderProjection _projection() => ReminderProjection(
  generation: 'g1',
  namespace: 'ns1',
  sequence: 1,
  desired: const [],
  obsoleteTokens: const [],
  complete: true,
  coverage: [
    ReminderCoverage(
      scope: 'everyone',
      generation: 'g1',
      basis: 'Europe/London',
      adapterFingerprint: 'test-adapter',
      checkedAt: _reportedAt,
      complete: true,
      preparedThrough: DateTime.utc(2026, 10, 20, 9),
    ),
  ],
);

ReminderHealthSummary _summary({
  int pending = 0,
  int unconfirmed = 0,
  bool observed = true,
  bool failed = false,
  DateTime? checkedAt,
}) => summariseReminderHealth(
  capabilities: observed ? _capabilities : null,
  projection: observed ? _projection() : null,
  convergence: failed
      ? ReminderConvergence.failed
      : pending > 0 || unconfirmed > 0
      ? ReminderConvergence.deferred
      : ReminderConvergence.converged,
  failed: failed,
  pendingCancellations: pending,
  unconfirmedCancellations: unconfirmed,
  checkedAt: checkedAt,
);

final _summaryProvider =
    NotifierProvider<_SummaryController, ReminderHealthSummary>(
      _SummaryController.new,
    );

final class _SummaryController extends Notifier<ReminderHealthSummary> {
  _SummaryController({this.initial});
  final ReminderHealthSummary? initial;
  @override
  ReminderHealthSummary build() => initial ?? _summary();
  void publish(ReminderHealthSummary summary) => state = summary;
}

/// Keeps the last-check stamp deterministic and stops the capture path from
/// opening the real store just to read the display preference.
final class _FixedDisplayPreferences extends DisplayPreferencesController {
  @override
  DisplayPreferences build() =>
      const DisplayPreferences(timeFormat: TimeFormat.h24);
}

final class _TestLock extends AppLockController {
  _TestLock({this.locked = false});
  bool locked;
  @override
  AppLockState build() =>
      AppLockState(ready: true, enabled: true, locked: locked);
  void setLocked(bool value) {
    locked = value;
    state = state.copy(locked: value);
  }
}

late ProviderContainer _container;

Future<void> _pumpPanel(
  WidgetTester tester,
  ReminderHealthSummary summary, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
  double height = 900,
  bool locked = false,
  GlobalKey? boundary,
}) async {
  _container = ProviderContainer(
    overrides: [
      _summaryProvider.overrideWith(() => _SummaryController(initial: summary)),
      reminderHealthProvider.overrideWith((ref) => ref.watch(_summaryProvider)),
      appLockProvider.overrideWith(() => _TestLock(locked: locked)),
      displayPreferencesProvider.overrideWith(_FixedDisplayPreferences.new),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
    ],
  );
  addTearDown(_container.dispose);
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: RepaintBoundary(
        key: boundary,
        child: ShadcnApp(
          debugShowCheckedModeBanner: false,
          theme: vitalTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ReminderHealthPanel(
                    scopeLabel: (scope) => 'Reminders',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  final details = find.text('Details');
  await tester.ensureVisible(details);
  await tester.pumpAndSettle();
  await tester.tap(details);
  await tester.pumpAndSettle();
}

/// Returns the single page scroller to the top after [ensureVisible] moved it.
Future<void> _scrollToTop(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (captureDirectory.isEmpty) return;
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  group('cancellation notice projection', () {
    test('keeps the two separate counts without adding them together', () {
      final notice = ReminderCancellationNotice.of(
        _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
      );
      expect(notice.visible, isTrue);
      expect(notice.pending, 2);
      expect(notice.unconfirmed, 1);
      expect(notice.hasPending, isTrue);
      expect(notice.hasUnconfirmed, isTrue);
      expect(notice.checkedAt, _reportedAt);
    });

    test('a completed pass with no counts makes no claim', () {
      final notice = ReminderCancellationNotice.of(_summary());
      expect(notice.visible, isFalse);
      expect(notice.hasPending, isFalse);
      expect(notice.hasUnconfirmed, isFalse);
    });

    test('a failed pass cannot publish retained counts', () {
      final notice = ReminderCancellationNotice.of(
        _summary(pending: 2, unconfirmed: 1, failed: true),
      );
      expect(notice.visible, isFalse);
    });

    test('an unreported dataset hides counts from an earlier pass', () {
      final health = _summary(
        pending: 3,
        unconfirmed: 1,
        observed: false,
        checkedAt: _reportedAt,
      );
      expect(health.attempted, isFalse);
      expect(ReminderCancellationNotice.of(health).visible, isFalse);
    });

    test('an unreported check time stays null', () {
      final notice = ReminderCancellationNotice.of(_summary(pending: 1));
      expect(notice.visible, isTrue);
      expect(notice.checkedAt, isNull);
    });
  });

  group('health panel cancellation attention', () {
    testWidgets('compact line opens separate counts and the last check', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
      );
      expect(
        find.text('2 alert cancellations are awaiting confirmation.'),
        findsOneWidget,
      );
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Awaiting confirmation: 2.'), findsNothing);
      await _expand(tester);
      expect(find.text('Awaiting confirmation: 2.'), findsOneWidget);
      expect(find.text('Not confirmed: 1.'), findsOneWidget);
      expect(find.text('These counts can overlap.'), findsOneWidget);
      expect(find.textContaining('Last check: '), findsOneWidget);
      expect(
        find.text(
          'Android has not confirmed these cancellations, so an alert may '
          'still appear or sound. Vital checks again when you reopen the app.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Android did not confirm these cancellations, so an alert may '
          'still appear or sound.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a check without a reported time never borrows the clock now', (
      tester,
    ) async {
      await _pumpPanel(tester, _summary(pending: 1));
      await _expand(tester);
      expect(find.text('Last check: unknown.'), findsOneWidget);
      expect(find.textContaining('Last check: Monday'), findsNothing);
    });

    testWidgets('an unconfirmed-only pass names its own state', (tester) async {
      await _pumpPanel(tester, _summary(unconfirmed: 1));
      expect(
        find.text('1 alert cancellation was not confirmed.'),
        findsOneWidget,
      );
      await _expand(tester);
      expect(find.text('Awaiting confirmation: 0.'), findsOneWidget);
      expect(find.text('Not confirmed: 1.'), findsOneWidget);
      expect(
        find.text('These counts can overlap.'),
        findsNothing,
        reason: 'One count alone cannot overlap with itself.',
      );
      expect(
        find.textContaining('Vital checks again'),
        findsNothing,
        reason: 'No retry claim for a cancellation that is not pending.',
      );
    });

    testWidgets('zero counts show neither a count nor a success claim', (
      tester,
    ) async {
      await _pumpPanel(tester, _summary());
      expect(find.text('Details'), findsNothing);
      expect(find.textContaining('cancellation'), findsNothing);
      expect(find.textContaining('Awaiting confirmation'), findsNothing);
    });

    testWidgets('a failed pass keeps its counts out of the panel', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        _summary(pending: 2, unconfirmed: 1, failed: true),
      );
      expect(find.text('Details'), findsNothing);
      expect(find.textContaining('awaiting confirmation'), findsNothing);
    });

    testWidgets('the retained details disappear while the app is locked', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
      );
      expect(find.text('Details'), findsOneWidget);
      (_container.read(appLockProvider.notifier) as _TestLock).setLocked(true);
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
      expect(find.textContaining('awaiting confirmation'), findsNothing);
      (_container.read(appLockProvider.notifier) as _TestLock).setLocked(false);
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('a later pass replaces the earlier count', (tester) async {
      await _pumpPanel(tester, _summary(pending: 2));
      expect(
        find.text('2 alert cancellations are awaiting confirmation.'),
        findsOneWidget,
      );
      _container
          .read(_summaryProvider.notifier)
          .publish(_summary(unconfirmed: 1));
      await tester.pumpAndSettle();
      expect(
        find.text('2 alert cancellations are awaiting confirmation.'),
        findsNothing,
      );
      expect(
        find.text('1 alert cancellation was not confirmed.'),
        findsOneWidget,
      );
      _container.read(_summaryProvider.notifier).publish(_summary());
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
    });

    testWidgets('keyboard expands and collapses the details', (tester) async {
      await _pumpPanel(tester, _summary(pending: 1));
      expect(find.text('Awaiting confirmation: 1.'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Awaiting confirmation: 1.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Awaiting confirmation: 1.'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        'wraps at 320, 390 and 430 with double text in ${brightness.name}',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpPanel(
            tester,
            _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
            brightness: brightness,
            textScale: 2,
          );
          await _expand(tester);
          for (final width in [320.0, 390.0, 430.0]) {
            tester.view.physicalSize = Size(width, 3000);
            await tester.pumpAndSettle();
            expect(find.text('Awaiting confirmation: 2.'), findsOneWidget);
            expect(find.text('Not confirmed: 1.'), findsOneWidget);
            expect(find.text('These counts can overlap.'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        },
      );

      testWidgets(
        'cancellation captures use synthetic fixtures in ${brightness.name}',
        (tester) async {
          if (captureDirectory.isEmpty) return;
          final boundary = GlobalKey();
          await _pumpPanel(
            tester,
            _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
            brightness: brightness,
            boundary: boundary,
          );
          await _capture(
            tester,
            boundary,
            '${brightness.name}-cancellations-compact',
          );
          await _expand(tester);
          await _capture(
            tester,
            boundary,
            '${brightness.name}-cancellations-details',
          );
          // A fresh key builds a fresh disclosure state, so the narrow capture
          // starts collapsed and expands like a first visit.
          final narrowBoundary = GlobalKey();
          await _pumpPanel(
            tester,
            _summary(pending: 2, unconfirmed: 1, checkedAt: _reportedAt),
            brightness: brightness,
            width: 320,
            height: 4200,
            textScale: 2,
            boundary: narrowBoundary,
          );
          await _expand(tester);
          expect(find.text('Awaiting confirmation: 2.'), findsOneWidget);
          expect(find.text('These counts can overlap.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _scrollToTop(tester);
          await _capture(
            tester,
            narrowBoundary,
            '${brightness.name}-cancellations-narrow',
          );
        },
      );
    }
  });
}
