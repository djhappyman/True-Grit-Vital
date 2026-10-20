import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/data/record_store.dart';

class SourcePageLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void setLocked(bool locked) =>
      state = AppLockState(ready: true, locked: locked);
}

AttachmentInspection sourceInspection() => AttachmentInspection(
  mediaKind: AttachmentMediaKind.other,
  byteCount: 1,
  sha256: 'a' * 64,
  mimeType: 'application/octet-stream',
);

AttachmentRecord sourceRecord({
  String personId = meId,
  String generation = 'generation',
  AttachmentState state = AttachmentState.ready,
  AttachmentTargetKind targetKind = AttachmentTargetKind.supporting,
  String? id,
}) => AttachmentRecord(
  id: id ?? newCommandId(),
  generation: generation,
  personId: personId,
  targetKind: targetKind,
  targetId: 'record',
  targetRevision: 1,
  revision: 1,
  versionId: newCommandId(),
  name: 'Source file',
  state: state,
  createdAt: DateTime.utc(2026, 10, 20),
  inspection: state == AttachmentState.ready ? sourceInspection() : null,
);

LabPanelSnapshot sourcePanel(String id) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: 'Source panel',
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
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

Future<AttachmentRecord> seedSourceFile(
  RecordStore store,
  SupportingRevision panel,
  String name,
  DateTime createdAt,
) async {
  final bytes = Uint8List.fromList('Synthetic $name'.codeUnits);
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    targetKind: AttachmentTargetKind.supporting,
    targetId: panel.id.id,
    targetRevision: panel.revision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: name,
    createdAt: createdAt,
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
  group('supporting source eligibility', () {
    test('accepts only a ready file from this adult and generation', () {
      expect(
        supportingSourceEligible(
          sourceRecord(),
          personId: meId,
          generation: 'generation',
        ),
        isTrue,
      );
      expect(
        supportingSourceEligible(
          sourceRecord(personId: 'another_adult'),
          personId: meId,
          generation: 'generation',
        ),
        isFalse,
      );
      expect(
        supportingSourceEligible(
          sourceRecord(state: AttachmentState.staging),
          personId: meId,
          generation: 'generation',
        ),
        isFalse,
      );
      expect(
        supportingSourceEligible(
          sourceRecord(state: AttachmentState.deleting),
          personId: meId,
          generation: 'generation',
        ),
        isFalse,
      );
      expect(
        supportingSourceEligible(
          sourceRecord(generation: 'replaced'),
          personId: meId,
          generation: 'generation',
        ),
        isFalse,
      );
    });

    test('a file can be cited whatever record first held it', () {
      for (final kind in AttachmentTargetKind.values) {
        expect(
          supportingSourceEligible(
            sourceRecord(targetKind: kind),
            personId: meId,
            generation: 'generation',
          ),
          isTrue,
        );
      }
    });

    test('a later page never repeats a displayed file', () {
      final a = sourceRecord(id: 'a'),
          b = sourceRecord(id: 'b'),
          c = sourceRecord(id: 'c');
      final merged = mergeSupportingSourcePage([a, b], [b, c]);
      expect(merged.map((record) => record.id), ['a', 'b', 'c']);
    });
  });

  group('bounded source pages', () {
    late Directory dir;
    late RecordStore store;
    late ProviderContainer container;
    late SourcePageLock lock;

    Future<void> turns() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-source-pages-');
      store = await RecordStore.open(
        path: '${dir.path}/records.db',
        key: List.generate(32, (i) => i + 1),
        isNew: true,
      );
      final owner = (await store.profileById(meId))!;
      await store.editProfile(
        commandId: 'source-owner',
        personId: meId,
        expectedRevision: owner.revision,
        name: 'Me',
        adultConfirmed: true,
      );
      final adult = (await store.profileById(meId))!;
      final panel = await store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'source-panel',
          generation: store.generation,
          expectedPersonRevision: adult.revision,
          panel: sourcePanel('source-panel'),
        ),
      );
      final base = DateTime.utc(2026, 10, 20, 9);
      for (var i = 0; i < 51; i++) {
        await seedSourceFile(
          store,
          panel,
          'Source ${i.toString().padLeft(2, '0')}',
          base.add(Duration(seconds: i)),
        );
      }
      container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(SourcePageLock.new),
        ],
      );
      lock = container.read(appLockProvider.notifier) as SourcePageLock;
      await container.read(recordStoreProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });

    test('the oldest eligible file is reachable after fifty', () async {
      const first = SupportingSourceRequest(personId: meId, offset: 0);
      const second = SupportingSourceRequest(personId: meId, offset: 50);
      final pageOne = await container.read(
        supportingSourceCandidatesProvider(first).future,
      );
      expect(pageOne.records, hasLength(supportingSourcePageSize));
      expect(pageOne.hasMore, isTrue);
      expect(pageOne.nextOffset, 50);
      expect(pageOne.records.first.name, 'Source 50');
      expect(pageOne.records.last.name, 'Source 01');
      expect(
        pageOne.records.every(
          (record) =>
              record.generation == store.generation &&
              record.personId == meId &&
              record.state == AttachmentState.ready,
        ),
        isTrue,
      );

      final pageTwo = await container.read(
        supportingSourceCandidatesProvider(second).future,
      );
      expect(pageTwo.records.single.name, 'Source 00');
      expect(pageTwo.hasMore, isFalse);
      expect(pageTwo.nextOffset, isNull);

      final merged = mergeSupportingSourcePage(
        pageOne.records,
        pageTwo.records,
      );
      expect(merged, hasLength(51));
      expect(merged.map((record) => record.id).toSet(), hasLength(51));
    });

    test('a lock discards the page and unlock reloads it', () async {
      const request = SupportingSourceRequest(personId: meId, offset: 0);
      final provider = supportingSourceCandidatesProvider(request);
      final subscription = container.listen(provider, (_, _) {});
      await turns();
      expect(
        (await container.read(provider.future)).records,
        hasLength(supportingSourcePageSize),
      );

      lock.setLocked(true);
      await turns();
      expect(container.read(provider).value?.records, isEmpty);
      expect(container.read(provider).value?.generation, isNull);

      lock.setLocked(false);
      await turns();
      expect(
        (await container.read(provider.future)).records,
        hasLength(supportingSourcePageSize),
      );
      subscription.close();
    });
  });

  group('source page cancellation', () {
    test('a replaced request cannot publish its stale page', () async {
      final pending =
          <
            ({
              SupportingSourceRequest request,
              Completer<SupportingSourcePage> result,
            })
          >[];
      final container = ProviderContainer(
        overrides: [
          appLockProvider.overrideWith(SourcePageLock.new),
          supportingSourceReaderProvider.overrideWithValue((request) {
            final result = Completer<SupportingSourcePage>();
            pending.add((request: request, result: result));
            return result.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      const request = SupportingSourceRequest(personId: meId, offset: 0);
      final provider = supportingSourceCandidatesProvider(request);
      final subscription = container.listen(provider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(pending, hasLength(1));

      container.invalidate(provider);
      final current = container.read(provider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(pending, hasLength(2));

      pending.first.result.complete(
        SupportingSourcePage(
          records: [sourceRecord(id: 'stale')],
          nextOffset: null,
          generation: 'generation',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(provider).value, isNull);

      pending.last.result.complete(
        SupportingSourcePage(
          records: [sourceRecord(id: 'fresh')],
          nextOffset: null,
          generation: 'generation',
        ),
      );
      expect((await current).records.single.id, 'fresh');
      expect(container.read(provider).value!.records.single.id, 'fresh');
      subscription.close();
    });
  });
}
