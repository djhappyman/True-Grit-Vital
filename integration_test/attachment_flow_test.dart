import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/attachments.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import '../test/attachments/attachment_pdf_test.dart' show syntheticPdf;
import 'stock_flow_test.dart' as stock;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('protected PDF preview, rename, deletion and encrypted reopen', (
    tester,
  ) async {
    const bootstrap = AndroidStorageBootstrap();
    final location = await bootstrap.prepare();
    final store = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: location.isNew,
    );
    addTearDown(store.close);
    await bootstrap.activate(location);
    final me = (await store.profileById(meId))!;
    if (!me.adultConfirmed) {
      await store.editProfile(
        commandId: newCommandId(),
        personId: meId,
        expectedRevision: me.revision,
        name: me.name,
        adultConfirmed: true,
      );
    }
    final owner = await store.createProfile(
      commandId: newCommandId(),
      name: 'Synthetic file adult',
      adultConfirmed: true,
    );
    final item = await store.createItem(
      commandId: newCommandId(),
      personId: owner.id,
      expectedPersonRevision: owner.revision,
      name: 'Synthetic file source',
      form: 'Tablet',
      unit: 'count',
      type: 'Test',
    );
    final bytes = syntheticPdf(3, width: 40000, height: 40000);
    final job = AttachmentJob(
      id: newCommandId(),
      generation: store.generation,
      personId: owner.id,
      expectedPersonRevision: owner.revision,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: newCommandId(),
      versionId: newCommandId(),
      name: 'Synthetic original.pdf',
      createdAt: DateTime.now().toUtc(),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: newCommandId(), job: job),
    );
    final inspection = await defaultAttachmentMediaDecoder().inspect(bytes);
    var offset = 0;
    await for (final chunk in boundedAttachmentChunks(Stream.value(bytes))) {
      await store.appendAttachmentChunk(
        commandId: newCommandId(),
        jobId: job.id,
        generation: job.generation,
        offset: offset,
        bytes: chunk,
      );
      offset += chunk.length;
    }
    final original = await store.publishAttachment(
      commandId: newCommandId(),
      jobId: job.id,
      generation: job.generation,
      inspection: inspection,
      name: job.name,
    );
    final providers = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(providers.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: providers, child: const VitalApp()),
    );
    await stock.waitFor(tester, find.text('Substances'));
    providers.read(routerProvider).go('/attachment/${original.id}');
    await stock.waitFor(tester, find.text('Page 1 of 3'));
    await stock.waitFor(
      tester,
      find.byWidgetPredicate((w) => w is RawImage && w.image != null),
    );
    final image = tester
        .widget<RawImage>(
          find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        )
        .image!;
    expect(
      image.width * image.height * 4,
      lessThanOrEqualTo(AttachmentLimits.maxPreviewBytes),
    );
    await stock.tap(tester, find.text('Next'));
    await stock.waitFor(tester, find.text('Page 2 of 3'));
    await stock.tap(tester, find.text('Rename'));
    final input = find.descendant(
      of: find.widgetWithText(LabelledInput, 'File name'),
      matching: find.byType(TextField),
    );
    await stock.waitFor(tester, input);
    await tester.enterText(input, 'Synthetic renamed.pdf');
    await stock.tap(tester, find.text('Save'));
    await stock.waitFor(tester, find.byType(AttachmentViewerPage));
    final renamed = (await store.attachmentById(original.id))!;
    expect(renamed.name, 'Synthetic renamed.pdf');
    expect(renamed.versionId, original.versionId);
    final reopened = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: false,
    );
    try {
      final saved = (await reopened.attachmentById(original.id))!;
      final pin = await reopened.pinAttachment(
        id: saved.id,
        generation: reopened.generation,
        expectedRevision: saved.revision,
      );
      try {
        expect(
          await readAttachmentBytes(reopened.readAttachmentPin(pin)),
          bytes,
        );
      } finally {
        await reopened.releaseAttachmentPin(pin);
      }
    } finally {
      await reopened.close();
    }
    await stock.tap(tester, find.text('Delete'));
    await stock.waitFor(tester, find.text('Delete file'));
    await stock.tap(tester, find.text('Delete').last);
    await stock.waitFor(tester, find.byType(AttachmentListPage));
    expect(
      await store.attachments(
        personId: owner.id,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
      ),
      isEmpty,
    );
    expect(await store.records(personId: owner.id), isEmpty);
    expect(await store.dailyPlans(itemId: item.id), isEmpty);
  });
}
