import 'fixtures/single_user.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_widgets.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

class LockedAppLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}

LabPanelSnapshot panelWithSource({
  String id = 'panel',
  String title = 'Original report',
  SupportingProvenance? provenance,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance:
      provenance ??
      SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        laboratoryName: 'Source laboratory',
      ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric('2'),
      unit: 'mg/L',
    ),
  ],
);

Future<SupportingRevision> save(
  WidgetTester tester,
  RecordStore store,
  LabPanelSnapshot panel, {
  int? expectedRevision,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId:
            'save-${panel.id.id}-${panel.title}-${expectedRevision ?? 0}',
        generation: store.generation,
        expectedPersonRevision: person.revision,
        expectedRevision: expectedRevision,
        panel: panel,
      ),
    ),
  ))!;
}

Future<AttachmentRecord> seedSupportingFile(
  WidgetTester tester,
  RecordStore store, {
  required String targetId,
  required int targetRevision,
  String name = 'Original report.pdf',
}) async => (await runIo(tester, () async {
  final bytes = Uint8List.fromList(utf8.encode('Synthetic original report'));
  final owner = (await store.profileById(meId))!;
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: owner.revision,
    targetKind: AttachmentTargetKind.supporting,
    targetId: targetId,
    targetRevision: targetRevision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: name,
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
    name: name,
  );
}))!;

String sourceRoute(AttachmentRecord file, {String? personId}) => Uri(
  path: '/supporting-source/${personId ?? meId}/${file.id}',
  queryParameters: {
    'revision': file.revision.toString(),
    'version': file.versionId,
  },
).toString();

void main() {
  appTest('source opened directly returns to its captured adult', (
    tester,
  ) async {
    final f = await launch(tester);
    final adult = (await runIo(
      tester,
      () => f.store.configureOwnProfile(
        commandId: 'source-back-adult',
        name: 'Morgan',
        adultConfirmed: true,
      ),
    ))!;
    f.container
        .read(routerProvider)
        .go(
          '/supporting-source/${adult.id}/missing?revision=1&version=missing',
        );
    await settle(tester);
    final page = tester.widget<EntryPage>(find.byType(EntryPage));
    page.onBack!();
    await settle(tester);
    expect(find.text('Supporting records'), findsOneWidget);
    expect(find.text('Person: Morgan'), findsOneWidget);
  });

  test(
    'only an attachment reference with a captured version opens a source',
    () {
      final attachment = SupportingSourceReference(
        id: 'source',
        personId: meId,
        version: 4,
        kind: SupportingSourceKind.attachment,
        contentVersionId: 'version-id',
        originalText: 'Original report',
      );
      expect(
        supportingSourceRoute(attachment),
        '/supporting-source/$meId/source?revision=4&version=version-id',
      );
      expect(
        supportingSourceRoute(
          SupportingSourceReference(
            id: 'report',
            personId: meId,
            version: 1,
            kind: SupportingSourceKind.report,
            originalText: 'Paper report',
          ),
        ),
        isNull,
      );
      expect(
        supportingSourceRoute(
          SupportingSourceReference(
            id: 'source',
            personId: meId,
            version: 4,
            kind: SupportingSourceKind.attachment,
          ),
        ),
        isNull,
      );
    },
  );

  appTest('same-owner exact saved source opens through the protected viewer', (
    tester,
  ) async {
    final f = await launch(tester);
    final first = await save(tester, f.store, panelWithSource());
    final file = await seedSupportingFile(
      tester,
      f.store,
      targetId: 'panel',
      targetRevision: first.revision,
    );
    await save(
      tester,
      f.store,
      panelWithSource(
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          sourceReferences: [
            SupportingSourceReference(
              id: file.id,
              personId: meId,
              version: file.revision,
              kind: SupportingSourceKind.attachment,
              contentVersionId: file.versionId,
              originalText: file.name,
            ),
          ],
        ),
      ),
      expectedRevision: first.revision,
    );
    f.container.read(routerProvider).go('/supporting/$meId/panel');
    await settle(tester);
    expect(find.text(file.name), findsOneWidget);
    await tap(tester, 'Open');
    expect(find.byType(SupportingSourceViewerPage), findsOneWidget);
    expect(find.text('Saved source version 1.'), findsOneWidget);
    expect(find.text(file.name), findsOneWidget);
    final preview = tester.widget<AttachmentPreviewSurface>(
      find.byType(AttachmentPreviewSurface),
    );
    expect(preview.attachment.id, file.id);
    expect(preview.attachment.revision, file.revision);
    expect(preview.attachment.versionId, file.versionId);
    expect(preview.attachment.personId, meId);
    final stored = (await runIo(
      tester,
      () => f.store.attachmentById(file.id),
    ))!;
    expect(stored.targetKind, AttachmentTargetKind.supporting);
    expect(stored.targetId, 'panel');
    expect(stored.targetRevision, first.revision);
    expect(stored.versionId, file.versionId);
  });

  appTest('a renamed current source never stands in for the saved version', (
    tester,
  ) async {
    final f = await launch(tester);
    final first = await save(tester, f.store, panelWithSource());
    final file = await seedSupportingFile(
      tester,
      f.store,
      targetId: 'panel',
      targetRevision: first.revision,
    );
    final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
    await runIo(
      tester,
      () => f.store.renameAttachment(
        commandId: 'rename',
        attachment: file,
        expectedPersonRevision: owner.revision,
        name: 'Renamed current report',
      ),
    );
    f.container.read(routerProvider).go(sourceRoute(file));
    await settle(tester);
    expect(
      find.text(
        'This saved source changed after it was saved. Its exact original is not available.',
      ),
      findsOneWidget,
    );
    expect(find.text('Renamed current report'), findsNothing);
    expect(find.text('Saved source version 1.'), findsNothing);
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });

  appTest('a different content version never stands in for the saved source', (
    tester,
  ) async {
    final f = await launch(tester);
    final first = await save(tester, f.store, panelWithSource());
    final file = await seedSupportingFile(
      tester,
      f.store,
      targetId: 'panel',
      targetRevision: first.revision,
    );
    f.container
        .read(routerProvider)
        .go(
          Uri(
            path: '/supporting-source/$meId/${file.id}',
            queryParameters: {
              'revision': file.revision.toString(),
              'version': 'different-version',
            },
          ).toString(),
        );
    await settle(tester);
    expect(
      find.text(
        'This saved source changed after it was saved. Its exact original is not available.',
      ),
      findsOneWidget,
    );
    expect(find.text(file.name), findsNothing);
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });

  appTest('a deleted source is unavailable rather than replaced', (
    tester,
  ) async {
    final f = await launch(tester);
    final first = await save(tester, f.store, panelWithSource());
    final file = await seedSupportingFile(
      tester,
      f.store,
      targetId: 'panel',
      targetRevision: first.revision,
    );
    final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
    await runIo(
      tester,
      () => f.store.deleteAttachment(
        commandId: 'delete',
        attachment: file,
        expectedPersonRevision: owner.revision,
      ),
    );
    f.container.read(routerProvider).go(sourceRoute(file));
    await settle(tester);
    expect(
      find.text(
        'This saved source is no longer available. The record keeps its saved source details.',
      ),
      findsOneWidget,
    );
    expect(find.text(file.name), findsNothing);
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });

  appTest('an old foreign-person source route exposes no attachment', (
    tester,
  ) async {
    final f = await launch(tester);
    final first = await save(tester, f.store, panelWithSource());
    final file = await seedSupportingFile(
      tester,
      f.store,
      targetId: 'panel',
      targetRevision: first.revision,
    );
    f.container
        .read(routerProvider)
        .go(sourceRoute(file, personId: 'another-person'));
    await settle(tester);
    expect(
      f.container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/today',
    );
    expect(find.text(file.name), findsNothing);
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });

  testWidgets('locked app shows no saved source identity or bytes', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [appLockProvider.overrideWith(LockedAppLock.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadcnApp(
          theme: vitalTheme(Brightness.light),
          locale: const Locale('en', 'GB'),
          supportedLocales: const [Locale('en', 'GB')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const VitalComponentThemes(
            child: SupportingSourceViewerPage(
              personId: meId,
              attachmentId: 'attachment',
              revision: 1,
              contentVersionId: 'version',
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Unlock Vital to view supporting records.'),
      findsOneWidget,
    );
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });
}
