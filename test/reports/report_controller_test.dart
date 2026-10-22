import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/reports/report_preview_page.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/reports/report_template.dart';

class FixtureReportArtifactGateway implements ReportArtifactGateway {
  FixtureReportArtifactGateway({
    this.capabilities = const {
      ReportArtifactCapability.save,
      ReportArtifactCapability.share,
      ReportArtifactCapability.saveText,
    },
  });
  @override
  final Set<ReportArtifactCapability> capabilities;
  ReportArtifact? saved, shared, savedText;

  @override
  Future<ReportHandoffResult> save(
    ReportArtifact artifact, {
    bool asText = false,
  }) async {
    if (asText) {
      savedText = artifact;
    } else {
      saved = artifact;
    }
    return const ReportHandoffResult(ReportHandoffOutcome.completed);
  }

  @override
  Future<ReportHandoffResult> share(ReportArtifact artifact) async {
    shared = artifact;
    return const ReportHandoffResult(ReportHandoffOutcome.completed);
  }
}

class _Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);

  void lockNow() => state = const AppLockState(ready: true, locked: true);
}

ReportSnapshot _snapshot(ReportSelection selection, DateTime now) =>
    ReportSnapshot.build(
      selection: selection,
      cutoff: ReportCutoff(
        generatedAt: now,
        datasetGeneration: 'generation',
        personRevision: 2,
        schemaVersion: 21,
      ),
      person: const ReportPerson(
        id: 'me',
        name: 'Synthetic Person',
        reportName: 'Example report',
      ),
      records: [
        ReportRecord.fromUseRecord(
          UseRecord(
            id: '1',
            personId: 'me',
            itemId: 'item',
            name: 'Synthetic item',
            form: 'Tablet',
            unit: 'mg',
            type: 'Medicine',
            enteredAmount: '0.125',
            actualAt: DateTime.utc(2026, 10, 2, 9),
            enteredAt: DateTime.utc(2026, 10, 2, 9, 5),
            revision: 1,
            isVoided: false,
          ),
        ),
      ],
    );

class _Renderer implements ReportTemplateRenderer {
  _Renderer({this.gate});
  final Completer<void>? gate;
  int calls = 0;
  @override
  ReportTemplateId get template => ReportTemplateId.r01SubstanceSummary;
  @override
  String get version => '1.0';
  @override
  Future<ReportRenderedDocument> render(
    ReportSnapshot snapshot, {
    required bool use24Hour,
    ReportCancellation cancellation = const NeverCancelled(),
    void Function(int completed, int total)? onProgress,
  }) async {
    calls++;
    onProgress?.call(0, 1);
    if (gate != null) await gate!.future;
    if (cancellation.isCancelled) throw const ReportCancelled();
    onProgress?.call(1, 1);
    return ReportRenderedDocument(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      pageCount: 2,
      fontsEmbedded: true,
    );
  }
}

Future<ProviderContainer> _container({
  required ReportArtifactGateway gateway,
  ReportTemplateRenderer? renderer,
  Future<void> Function()? releasePins,
}) async {
  final selection = ReportSelection(
    personId: 'me',
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
    displayZone: 'UTC',
  );
  final now = DateTime.utc(2026, 10, 20, 12);
  final container = ProviderContainer(
    overrides: [
      appLockProvider.overrideWith(_Unlocked.new),
      reportArtifactGatewayProvider.overrideWithValue(gateway),
      reportRendererProvider.overrideWithValue((_) => renderer ?? _Renderer()),
      reportNowProvider.overrideWithValue(() => now),
      reportCaptureProvider.overrideWithValue(
        (request) async => ReportCapture(
          snapshot: _snapshot(request.selection, request.now()),
          pins: const [],
          releasePins: releasePins,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(reportControllerProvider.notifier).select(selection);
  return container;
}

Future<void> _until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException('controller did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test(
    'generation produces one artifact and save/share use injected gateway',
    () async {
      final gateway = FixtureReportArtifactGateway();
      final container = await _container(gateway: gateway);
      final subscription = container.listen(
        reportControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      final state = container.read(reportControllerProvider);
      expect(state.phase, ReportPhase.ready, reason: state.errorCode);
      expect(state.artifact, isNotNull);
      expect(state.artifact!.pageCount, 2);
      expect(state.artifact!.text, contains('Recorded doses: 1'));
      expect(state.artifact!.fileName, startsWith('vital-substance-summary-'));
      expect(state.artifact!.fileName, isNot(contains('Synthetic Person')));

      await container.read(reportControllerProvider.notifier).save();
      await container.read(reportControllerProvider.notifier).share();
      expect(gateway.saved, isNotNull);
      expect(gateway.shared, isNotNull);
      expect(
        container.read(reportControllerProvider).handoffMessage,
        'handoff_complete',
      );
    },
  );

  test('cancel stops a gated render and leaves no artifact', () async {
    final gate = Completer<void>();
    final container = await _container(
      gateway: FixtureReportArtifactGateway(),
      renderer: _Renderer(gate: gate),
    );
    final subscription = container.listen(reportControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    final pending = container
        .read(reportControllerProvider.notifier)
        .generate(use24Hour: false);
    await _until(
      () =>
          container.read(reportControllerProvider).phase ==
          ReportPhase.rendering,
    );
    container.read(reportControllerProvider.notifier).cancel();
    gate.complete();
    await pending;
    final state = container.read(reportControllerProvider);
    expect(state.phase, ReportPhase.cancelled);
    expect(state.artifact, isNull);
  });

  test(
    'locking during generation clears the pending private artifact',
    () async {
      final gate = Completer<void>();
      final container = await _container(
        gateway: FixtureReportArtifactGateway(),
        renderer: _Renderer(gate: gate),
      );
      final subscription = container.listen(
        reportControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final pending = container
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      await _until(
        () =>
            container.read(reportControllerProvider).phase ==
            ReportPhase.rendering,
      );
      (container.read(appLockProvider.notifier) as _Unlocked).lockNow();
      gate.complete();
      await pending;
      expect(container.read(reportControllerProvider).artifact, isNull);
    },
  );

  test(
    'reviewed PDF bytes cannot be changed through their backing buffer',
    () async {
      final container = await _container(
        gateway: FixtureReportArtifactGateway(),
      );
      final subscription = container.listen(
        reportControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      final artifact = container.read(reportControllerProvider).artifact!;
      expect(
        () => artifact.bytes.buffer.asUint8List()[0] = 255,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'disposed generation releases capture pins without reading a dead ref',
    () async {
      final gate = Completer<void>();
      var released = false;
      final container = await _container(
        gateway: FixtureReportArtifactGateway(),
        renderer: _Renderer(gate: gate),
        releasePins: () async {
          released = true;
        },
      );
      container.listen(reportControllerProvider, (_, _) {});
      final pending = container
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      await _until(
        () =>
            container.read(reportControllerProvider).phase ==
            ReportPhase.rendering,
      );
      container.dispose();
      gate.complete();
      await pending;
      expect(released, isTrue);
    },
  );

  test('selection change invalidates an existing artifact', () async {
    final container = await _container(gateway: FixtureReportArtifactGateway());
    final subscription = container.listen(reportControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    await container
        .read(reportControllerProvider.notifier)
        .generate(use24Hour: true);
    expect(container.read(reportControllerProvider).artifact, isNotNull);
    container.read(reportControllerProvider.notifier).setIncludeNotes(true);
    expect(container.read(reportControllerProvider).artifact, isNull);
    expect(
      container.read(reportControllerProvider).selection!.includeNotes,
      true,
    );
  });

  test(
    'stock details toggle invalidates an artifact and waits for busy work',
    () async {
      final container = await _container(
        gateway: FixtureReportArtifactGateway(),
      );
      final subscription = container.listen(
        reportControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      expect(container.read(reportControllerProvider).artifact, isNotNull);
      container.read(reportControllerProvider.notifier).setIncludeStock(true);
      expect(container.read(reportControllerProvider).artifact, isNull);
      expect(
        container.read(reportControllerProvider).selection!.includeStock,
        isTrue,
      );

      final gate = Completer<void>();
      final busy = await _container(
        gateway: FixtureReportArtifactGateway(),
        renderer: _Renderer(gate: gate),
      );
      final busySubscription = busy.listen(reportControllerProvider, (_, _) {});
      addTearDown(busySubscription.close);
      final pending = busy
          .read(reportControllerProvider.notifier)
          .generate(use24Hour: true);
      await _until(
        () =>
            busy.read(reportControllerProvider).phase == ReportPhase.rendering,
      );
      busy.read(reportControllerProvider.notifier).setIncludeStock(true);
      expect(
        busy.read(reportControllerProvider).selection!.includeStock,
        isFalse,
      );
      gate.complete();
      await pending;
    },
  );

  test('unavailable handoff is truthful, never a silent success', () async {
    final container = await _container(
      gateway: const UnavailableReportArtifactGateway(),
    );
    final subscription = container.listen(reportControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    await container
        .read(reportControllerProvider.notifier)
        .generate(use24Hour: true);
    await container.read(reportControllerProvider.notifier).save();
    expect(
      container.read(reportControllerProvider).handoffMessage,
      'handoff_unavailable',
    );
  });

  testWidgets('preview offers the same artifact, structured text and handoff', (
    tester,
  ) async {
    final gateway = FixtureReportArtifactGateway();
    final container = await _container(gateway: gateway);
    final subscription = container.listen(reportControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    await container
        .read(reportControllerProvider.notifier)
        .generate(use24Hour: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en', 'GB')],
          home: ReportPreviewPage(
            documentView: (context, artifact) =>
                Text('PDF viewer ${artifact.pageCount} pages'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Report preview'), findsOneWidget);
    expect(find.text('Example report'), findsOneWidget);
    expect(find.text('Synthetic Person'), findsOneWidget);
    expect(find.text('PDF viewer 2 pages'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Substance summary'), findsWidgets);
    expect(find.textContaining('Recorded doses: 1'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.savedText, isNotNull);
    expect(find.text('Report saved to the chosen location.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
