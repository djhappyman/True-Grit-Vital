import 'fixtures/single_user.dart';

import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

Future<void> tap(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester
        .widgetList<VitalButton>(find.byType(VitalButton))
        .any((b) => b.isLoading)) {
      break;
    }
  }
  await settle(tester);
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find
      .byWidgetPredicate((w) => w is LabelledInput && w.label == label)
      .first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    value,
  );
  await tester.pump();
}

LabPanelSnapshot panel(
  String id,
  String person, {
  String value = '1',
  String metric = 'marker',
  SupportingDate? date,
  List<LabResultSnapshot>? results,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: person),
  title: 'Source $id',
  collectionDate: date ?? SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.partial(
    originalText: 'October 2026',
    year: 2026,
    month: 10,
  ),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: 'same-lab',
    laboratoryName: 'Source laboratory',
    methodId: 'same-method',
    specimenId: 'same-specimen',
  ),
  results:
      results ??
      [
        LabResultSnapshot(
          id: 'result-$id',
          metricId: metric,
          markerName: 'Custom marker',
          value: SupportingValue.numeric(value),
          unit: 'U/L',
          referenceRange: SourceReferenceRange(
            originalText: 'source: less than 8',
          ),
        ),
      ],
);

class SupportingOpenLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

LabPanelSnapshot supportingUiPanel(
  String id, {
  String title = 'Source report',
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: 'lab',
    laboratoryName: 'Source laboratory',
    methodId: 'method',
    methodText: 'Immunoassay',
    specimenId: 'serum',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      value: SupportingValue.numeric('2'),
      unit: 'mg/L',
    ),
  ],
);

Future<AttachmentRecord> seedSupportingFile(
  RecordStore store,
  SupportingRevision record,
) async {
  final bytes = Uint8List.fromList('Synthetic source report'.codeUnits);
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: record.id.personId,
    expectedPersonRevision: (await store.profileById(record.id.personId))!
        .revision,
    targetKind: AttachmentTargetKind.supporting,
    targetId: record.id.id,
    targetRevision: record.revision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: 'Original report',
    createdAt: DateTime.now().toUtc(),
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: newCommandId(), job: job),
  );
  await store.appendAttachmentChunk(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    offset: 0,
    bytes: bytes,
  );
  return store.publishAttachment(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    inspection: AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/octet-stream',
    ),
  );
}

void main() {
  appTest(
    'manual empty panel saves for captured adult before files are available',
    (tester) async {
      final f = await launch(tester);
      final adult = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: 'adult',
          name: 'Morgan',
          adultConfirmed: true,
        ),
      ))!;
      f.container.read(routerProvider).go('/supporting/${adult.id}/add-panel');
      await settle(tester);
      expect(find.text('Person: Morgan'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
      await enter(tester, 'Title', 'Original report without results');
      await tap(tester, 'Save');
      await waitForText(tester, 'No results recorded.');
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      expect(find.text('No results recorded.'), findsOneWidget);
      final saved = (await runIo(
        tester,
        () => f.store.supportingRecords(SupportingQuery(personId: adult.id)),
      ))!.entries.single;
      expect(saved.snapshot.title, 'Original report without results');
      expect(saved.snapshot.results, isEmpty);
      expect(
        saved.snapshot.collectionDate.precision,
        SupportingDatePrecision.unknown,
      );
      expect(
        (await runIo(
          tester,
          () => f.store.supportingRecords(SupportingQuery(personId: meId)),
        ))!.entries,
        hasLength(1),
      );
      await tap(tester, 'Files');
      expect(
        find.text('Supporting record: Original report without results'),
        findsOneWidget,
      );
    },
  );
  appTest('observation preserves qualified custom value and original unit', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/supporting/$meId/add-observation');
    await settle(tester);
    await enter(tester, 'Title', 'Manual observation');
    await tap(tester, 'Add');
    await enter(tester, 'Component', 'Source custom marker');
    await enter(tester, 'Original value', '<1.20e-3');
    await enter(tester, 'Original unit', 'source/unit');
    expect(find.text('Source range'), findsNothing);
    await tap(tester, 'Save');
    expect(find.byType(SupportingDetailPage), findsOneWidget);
    expect(find.text('<1.20e-3 source/unit'), findsOneWidget);
    final saved = (await runIo(
      tester,
      () => f.store.supportingRecords(SupportingQuery(personId: meId)),
    ))!.entries.single;
    expect(saved.kind, SupportingRecordKind.observation);
    expect(
      saved.snapshot.results.single.value.qualifier,
      SupportingQualifier.lessThan,
    );
    expect(saved.snapshot.results.single.value.originalText, '<1.20e-3');
  });
  appTest('note-only observation saves without a fabricated value', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/supporting/$meId/add-observation');
    await settle(tester);
    await enter(tester, 'Title', 'Source note');
    await tap(tester, 'Save');
    expect(
      find.text('Add a value or a note before saving this observation.'),
      findsOneWidget,
    );
    await tap(tester, 'Details');
    await enter(tester, 'Notes', 'Noted after reviewing the source.');
    await tap(tester, 'Save');
    expect(find.byType(SupportingDetailPage), findsOneWidget);
    expect(find.text('Noted after reviewing the source.'), findsOneWidget);
    final saved = (await runIo(
      tester,
      () => f.store.supportingRecords(SupportingQuery(personId: meId)),
    ))!.entries.single;
    expect(saved.kind, SupportingRecordKind.observation);
    expect(saved.snapshot.results, isEmpty);
    expect(saved.snapshot.notes, 'Noted after reviewing the source.');
  });
  appTest('saved file is captured as an exact source through the form', (
    tester,
  ) async {
    final f = await launch(tester);
    final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
    final panel = (await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'source-parent',
          generation: f.store.generation,
          expectedPersonRevision: owner.revision,
          panel: supportingUiPanel('source-parent'),
        ),
      ),
    ))!;
    final file = (await runIo(
      tester,
      () => seedSupportingFile(f.store, panel),
    ))!;
    f.container.read(routerProvider).go('/supporting/$meId/source-parent/edit');
    await settle(tester);
    await tap(tester, 'Source');
    expect(find.text('Original report'), findsOneWidget);
    await tap(tester, 'Attach');
    expect(find.text('Attached'), findsOneWidget);
    await tap(tester, 'Save');
    expect(find.byType(SupportingDetailPage), findsOneWidget);
    expect(find.text('Saved sources'), findsOneWidget);
    final saved = (await runIo(
      tester,
      () => f.store.supportingRecord(meId, 'source-parent'),
    ))!;
    final source = saved.snapshot.provenance.sourceReferences.single;
    expect(source.id, file.id);
    expect(source.version, file.revision);
    expect(source.contentVersionId, file.versionId);
    expect(source.originalText, 'Original report');
    expect(find.text('Open'), findsOneWidget);
  });
  appTest('supporting form reports a stale record with supporting wording', (
    tester,
  ) async {
    final f = await launch(tester);
    final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'stale-parent',
          generation: f.store.generation,
          expectedPersonRevision: owner.revision,
          panel: supportingUiPanel('stale-parent'),
        ),
      ),
    );
    f.container.read(routerProvider).go('/supporting/$meId/stale-parent/edit');
    await settle(tester);
    await enter(tester, 'Title', 'Locally edited title');
    final changed = supportingUiPanel(
      'stale-parent',
      title: 'Changed elsewhere',
    );
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'stale-external',
          generation: f.store.generation,
          expectedPersonRevision: owner.revision,
          expectedRevision: 1,
          panel: changed,
        ),
      ),
    );
    await tap(tester, 'Save');
    expect(
      find.text(
        'This supporting record changed. Open Supporting records and review the latest revision before editing.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Return to History'), findsNothing);
  });
  appTest(
    'source correction retains revisions and void restore retains source',
    (tester) async {
      final f = await launch(tester);
      await runIo(
        tester,
        () => f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'seed',
            generation: f.store.generation,
            expectedPersonRevision: 2,
            panel: panel('report', meId, value: '-0'),
          ),
        ),
      );
      f.container.read(routerProvider).go('/supporting/$meId/report');
      await settle(tester);
      await tap(tester, 'Edit');
      await enter(tester, 'Title', 'Corrected report');
      await tap(tester, 'Save');
      expect(find.text('Corrected report'), findsOneWidget);
      expect(find.text('-0 U/L'), findsOneWidget);
      final history = (await runIo(
        tester,
        () => f.store.supportingRevisions(meId, 'report'),
      ))!;
      expect(history.map((e) => e.revision), [2, 1]);
      expect(history.last.snapshot.title, 'Source report');
      expect(
        history.first.snapshot.results.single.referenceRange!.originalText,
        'source: less than 8',
      );
      await tap(tester, 'Void');
      await tap(tester, 'Void');
      expect(find.text('Voided'), findsOneWidget);
      await tap(tester, 'Restore');
      await tap(tester, 'Restore');
      expect(find.text('Voided'), findsNothing);
    },
  );
  appTest(
    'supporting trends preserve gaps equal dates ownership and exact source revision',
    (tester) async {
      final f = await launch(tester);
      await runIo(tester, () async {
        for (final id in ['a', 'b', 'c']) {
          await f.store.saveLabPanel(
            SaveLabPanelCommand(
              commandId: id,
              generation: f.store.generation,
              expectedPersonRevision: 2,
              panel: panel(
                id,
                meId,
                value: id == 'a' ? '-2' : '3',
                results: id == 'b'
                    ? [
                        LabResultSnapshot(
                          id: 'result-b',
                          metricId: 'marker',
                          markerName: 'Custom marker',
                          value: SupportingValue.missing(
                            originalText: 'Not measured',
                          ),
                          unit: 'U/L',
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }
        final other = await f.store.configureOwnProfile(
          commandId: 'other',
          name: 'Other adult',
          adultConfirmed: true,
        );
        await f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'private',
            generation: f.store.generation,
            expectedPersonRevision: other.revision,
            panel: panel(
              'private',
              other.id,
              metric: 'other-marker',
              value: '999',
            ),
          ),
        );
      });
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=marker');
      await settle(tester);
      expect(find.byType(SupportingTrendsPage), findsOneWidget);
      expect(find.byType(SupportingPlot), findsOneWidget);
      expect(find.byType(plot.LineChart), findsOneWidget);
      final chart = tester.widget<plot.LineChart>(find.byType(plot.LineChart));
      expect(chart.data.lineBarsData.length, 2);
      expect(chart.data.lineBarsData.every((bar) => !bar.isCurved), isTrue);
      expect(find.text('Not measured U/L'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
      await tap(tester, 'Open');
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      expect(find.text('Revision 1'), findsOneWidget);
    },
  );
  appTest('320px at 200 percent and keyboard preserve incomplete draft', (
    tester,
  ) async {
    final f = await launch(tester);
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(2),
          ),
          child: const VitalApp(),
        ),
      ),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/supporting/$meId/add-panel');
    await settle(tester);
    await enter(tester, 'Title', 'Retained draft');
    await tap(tester, 'Add');
    await enter(tester, 'Marker name', 'Incomplete custom');
    await enter(tester, 'Original value', '1e-');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await settle(tester);
    expect(
      (await runIo(tester, f.store.drafts))!.single.fields['payload'],
      contains('1e-'),
    );
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go('/supporting/$meId/add-panel');
    await settle(tester);
    final field = tester.widget<LabelledInput>(
      find
          .byWidgetPredicate(
            (w) => w is LabelledInput && w.label == 'Original value',
          )
          .first,
    );
    expect(field.controller.text, '1e-');
    expect(tester.takeException(), isNull);
  });
  for (final committed in [false, true]) {
    appTest(
      'same frozen command retries after ${committed ? 'committed response loss' : 'precommit failure'}',
      (tester) async {
        final f = await launch(tester), attempts = <SupportingSave>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => f.store),
            appLockProvider.overrideWith(SupportingOpenLock.new),
            observedDeviceZoneProvider.overrideWith(
              (ref) =>
                  Stream.value(DeviceZoneObservation.fromId('Europe/London')),
            ),
            supportingWriterProvider.overrideWithValue((input) async {
              attempts.add(input);
              if (attempts.length == 1 && !committed) {
                throw StateError('injected_before_commit');
              }
              final saved = await f.store.saveLabPanel(
                SaveLabPanelCommand(
                  commandId: input.commandId,
                  generation: input.generation,
                  expectedPersonRevision: input.personRevision,
                  expectedRevision: input.targetRevision,
                  panel: input.snapshot as LabPanelSnapshot,
                ),
              );
              if (attempts.length == 1 && committed) {
                throw StateError('injected_lost_response');
              }
              return saved;
            }),
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
        container.read(routerProvider).go('/supporting/$meId/add-panel');
        await settle(tester);
        await enter(tester, 'Title', 'Frozen panel');
        await tap(tester, 'Save');
        expect(find.text('Retry'), findsOneWidget);
        final drafts = (await runIo(tester, f.store.drafts))!;
        if (committed) {
          expect(drafts, isEmpty);
          expect(
            await runIo(
              tester,
              () => f.store.operationCommitted(attempts.single.commandId),
            ),
            isTrue,
          );
        } else {
          expect(drafts.single.submitted, isTrue);
          expect(drafts.single.operationId, attempts.single.commandId);
        }
        final title = tester.widget<LabelledInput>(
          find.byWidgetPredicate(
            (w) => w is LabelledInput && w.label == 'Title',
          ),
        );
        expect(title.enabled, isFalse);
        await tap(tester, 'Retry');
        expect(find.byType(SupportingDetailPage), findsOneWidget);
        final rows = (await runIo(
          tester,
          () => f.store.supportingRecords(SupportingQuery(personId: meId)),
        ))!.entries;
        expect(rows.length, 1);
        expect(rows.single.revision, 1);
        expect(attempts.length, committed ? 1 : 2);
        if (!committed) {
          expect(attempts[0].commandId, attempts[1].commandId);
          expect(
            jsonEncode(attempts[0].snapshot.toJson()),
            jsonEncode(attempts[1].snapshot.toJson()),
          );
        }
      },
    );
  }
  appTest('saved void intent survives navigation and resumes once', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'recovery-seed',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: panel('report', meId),
        ),
      ),
    );
    final attempts = <OrdinaryDraft>[];
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => f.store),
        appLockProvider.overrideWith(SupportingOpenLock.new),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        supportingVoidWriterProvider.overrideWithValue((draft) async {
          attempts.add(draft);
          if (attempts.length == 1) {
            throw StateError('injected_before_commit');
          }
          return f.store.resumeSupportingVoidDraft(draft);
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);
    container.read(routerProvider).go('/supporting/$meId/report');
    await settle(tester);
    await tap(tester, 'Void');
    await tap(tester, 'Void');
    expect(
      find.text(
        'Your request is saved on this device. Resume to check and finish it, or discard it.',
      ),
      findsOneWidget,
    );
    final saved = (await runIo(tester, f.store.drafts))!.single;
    expect(saved.kind, DraftKind.supportingVoid);
    expect(saved.operationId, attempts.single.operationId);
    expect(saved.personId, meId);
    expect(saved.targetId, 'report');
    expect(saved.targetRevision, 1);
    expect(saved.fields, {'isVoided': 'true'});

    // The intent is shown again from storage after leaving the screen.
    container.read(routerProvider).go('/today');
    await settle(tester);
    expect(find.text('Unfinished entries'), findsOneWidget);
    container.read(routerProvider).go('/supporting/$meId/report');
    await settle(tester);
    expect(
      find.text(
        'Your request is saved on this device. Resume to check and finish it, or discard it.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Resume');
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('Record voided.'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text('Record voided.'),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .liveRegion,
      isTrue,
    );
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(
      (await runIo(
        tester,
        () => f.store.supportingRevisions(meId, 'report'),
      ))!.length,
      2,
    );
    expect(attempts.length, 2);
    expect(attempts.first.operationId, attempts.last.operationId);
  });
  appTest(
    'committed void with a lost reply resolves without another revision',
    (tester) async {
      final f = await launch(tester);
      await runIo(
        tester,
        () => f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'lost-seed',
            generation: f.store.generation,
            expectedPersonRevision: 2,
            panel: panel('report', meId),
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => f.store),
          appLockProvider.overrideWith(SupportingOpenLock.new),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
          supportingVoidWriterProvider.overrideWithValue((draft) async {
            await f.store.resumeSupportingVoidDraft(draft);
            throw StateError('injected_lost_response');
          }),
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
      container.read(routerProvider).go('/supporting/$meId/report');
      await settle(tester);
      await tap(tester, 'Void');
      await tap(tester, 'Void');
      expect(find.text('Voided'), findsOneWidget);
      expect(await runIo(tester, f.store.drafts), isEmpty);
      expect(
        (await runIo(
          tester,
          () => f.store.supportingRevisions(meId, 'report'),
        ))!.length,
        2,
      );
    },
  );
  appTest('failed intent write runs no command and can be retried', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'blocked-seed',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: panel('report', meId),
        ),
      ),
    );
    f.container.read(routerProvider).go('/supporting/$meId/report');
    await settle(tester);
    f.store.suspendWrites(true);
    await tap(tester, 'Void');
    await tap(tester, 'Void');
    expect(
      find.text('Request not saved. Nothing changed. Try again.'),
      findsOneWidget,
    );
    f.store.suspendWrites(false);
    expect(await runIo(tester, f.store.drafts), isEmpty);
    var history = (await runIo(
      tester,
      () => f.store.supportingRevisions(meId, 'report'),
    ))!;
    expect(history.length, 1);
    expect(history.single.isVoided, isFalse);

    await tap(tester, 'Void');
    await tap(tester, 'Void');
    expect(find.text('Voided'), findsOneWidget);
    history = (await runIo(
      tester,
      () => f.store.supportingRevisions(meId, 'report'),
    ))!;
    expect(history.length, 2);
  });
  appTest('discarding a saved void intent invalidates it', (tester) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'discard-seed',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: panel('report', meId),
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => f.store),
        appLockProvider.overrideWith(SupportingOpenLock.new),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        supportingVoidWriterProvider.overrideWithValue(
          (draft) async => throw StateError('injected_before_commit'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);
    container.read(routerProvider).go('/supporting/$meId/report');
    await settle(tester);
    await tap(tester, 'Void');
    await tap(tester, 'Void');
    final draft = (await runIo(tester, f.store.drafts))!.single;
    await tap(tester, 'Discard');
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(find.text('Void'), findsOneWidget);
    CommandConflict? failure;
    await runIo(tester, () async {
      try {
        await f.store.resumeSupportingVoidDraft(draft);
      } on CommandConflict catch (error) {
        failure = error;
      }
    });
    expect(failure?.code, 'deleted_context');
    final history = (await runIo(
      tester,
      () => f.store.supportingRevisions(meId, 'report'),
    ))!;
    expect(history.length, 1);
    expect(history.single.isVoided, isFalse);
  });

  appTest('History supporting entry retains named adult and return context', (
    tester,
  ) async {
    final f = await launch(tester);
    final adult = (await runIo(
      tester,
      () => f.store.configureOwnProfile(
        commandId: 'named',
        name: 'Named adult',
        adultConfirmed: true,
      ),
    ))!;
    final location =
        '/history?scope=${adult.id}&status=voided&mode=calendar&day=2026-10-19';
    f.container.read(routerProvider).go(location);
    await settle(tester);
    await tap(tester, 'Supporting');
    expect(find.text('Person: Named adult'), findsOneWidget);
    expect(find.byType(SupportingRecordsPage), findsOneWidget);
    await tap(tester, 'Back');
    expect(
      f.container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['scope'],
      adult.id,
    );
    expect(
      f.container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['status'],
      'voided',
    );
  });
}
