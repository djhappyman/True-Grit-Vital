import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/features/supporting/supporting_form_model.dart';

import '../supporting_categories_comparison_test.dart' show point;

void main() {
  test('lab metadata survives revisions, exact replay, reopen, exports and report selection', () async {
    final dir = await Directory.systemTemp.createTemp('vital-lab-metadata-');
    final path = '${dir.path}/records.sqlite';
    final key = List.generate(32, (i) => i + 1);
    var store = await RecordStore.open(path: path, key: key, isNew: true);
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    final original =
        point('panel', 20, category: 'Source category').snapshot
            as LabPanelSnapshot;
    Future<SupportingRevision> save(
      LabPanelSnapshot value,
      String command,
      int? revision,
    ) => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: command,
        generation: store.generation,
        expectedPersonRevision: 1,
        expectedRevision: revision,
        panel: value,
      ),
    );
    final first = await save(original, 'first', null);
    final form = SupportingFormModel(
      id: 'panel',
      personId: meId,
      observation: false,
    )..load(original);
    form.fields['accession'] = 'ACC-002';
    form.rows.single['category'] = 'Authored category';
    form.fields['notes'] = 'Private source note';
    final updated = form.snapshot() as LabPanelSnapshot;
    await save(updated, 'correction', 1);
    expect((await save(updated, 'correction', 1)).revision, 2);
    await expectLater(
      save(original, 'stale', 1),
      throwsA(isA<CommandConflict>()),
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final current = (await store.supportingRecord(meId, 'panel'))!;
    expect(current.revision, 2);
    expect(current.snapshot.provenance.accessionNumber, 'ACC-002');
    expect(current.snapshot.results.single.category, 'Authored category');
    expect(first.snapshot.provenance.accessionNumber, 'ACC-001');
    ExportSelection selection(
      ExportFormat format, {
      bool notes = false,
      bool supporting = true,
    }) => ExportSelection(
      personId: meId,
      fromDay: CivilDate(2026, 10, 1),
      beforeDay: CivilDate(2026, 11, 1),
      zoneId: 'UTC',
      contents: [
        if (supporting) ExportContent.supporting else ExportContent.doses,
      ],
      format: format,
      includeNotes: notes,
    );
    final document = await store.captureExport(selection(ExportFormat.json));
    final json = utf8.decode(ExportArtifact.build(document).bytes);
    expect(json, contains('Authored category'));
    expect(json, contains('ACC-002'));
    expect(json, contains('REPORT/09'));
    expect(json, isNot(contains('Private source note')));
    final csv = utf8.decode(
      ExportArtifact.build(
        await store.captureExport(selection(ExportFormat.csv)),
      ).bytes,
    );
    final lines = const LineSplitter().convert(csv);
    final header = lines.first.split(',');
    final values = lines.last.split(',');
    expect(values.length, header.length);
    expect(values[header.indexOf('supporting_category')], 'Authored category');
    expect(values[header.indexOf('supporting_accession')], 'ACC-002');
    expect(values[header.indexOf('supporting_report_identifier')], 'REPORT/09');
    expect(csv, isNot(contains('Private source note')));
    final withNotes = utf8.decode(
      ExportArtifact.build(
        await store.captureExport(selection(ExportFormat.json, notes: true)),
      ).bytes,
    );
    expect(withNotes, contains('Private source note'));
    final excluded = utf8.decode(
      ExportArtifact.build(
        await store.captureExport(
          selection(ExportFormat.json, supporting: false),
        ),
      ).bytes,
    );
    expect(excluded, isNot(contains('ACC-002')));
    final capture = await store.captureReport(
      selection: ReportSelection(
        personId: meId,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 11, 1),
        displayZone: 'UTC',
        includeSupporting: true,
      ),
      now: () => DateTime.utc(2026, 11, 1),
    );
    final context = ReportText.contextLines(capture.snapshot).join('\n');
    expect(context, contains('Authored category'));
    expect(context, contains('ACC-002'));
    expect(context, contains('REPORT/09'));
    expect(context, isNot(contains('Private source note')));
    final clear = SupportingFormModel(
      id: 'panel',
      personId: meId,
      observation: false,
    )..load(updated);
    clear.fields['accession'] = '';
    clear.fields['reportId'] = '';
    clear.rows.single['category'] = '';
    await save(clear.snapshot() as LabPanelSnapshot, 'clear', 2);
    expect(
      (await store.supportingRecord(
        meId,
        'panel',
      ))!.snapshot.provenance.accessionNumber,
      isNull,
    );
    expect(
      (await store.supportingRecord(
        meId,
        'panel',
        revision: 1,
      ))!.snapshot.provenance.accessionNumber,
      'ACC-001',
    );
  });
}
