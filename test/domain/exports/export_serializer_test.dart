import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';

ExportSelection selection({
  ExportFormat format = ExportFormat.json,
  bool includeNotes = false,
  ExportLimits limits = ExportLimits.standard,
}) => ExportSelection(
  personId: meId,
  fromDay: CivilDate(2026, 10, 1),
  beforeDay: CivilDate(2026, 11, 1),
  zoneId: 'UTC',
  contents: const [ExportContent.doses, ExportContent.supporting],
  format: format,
  includeNotes: includeNotes,
  limits: limits,
);

ExportDoseRevision dose({
  String name = 'Synthetic dose',
  required ExactAmount amount,
  String entered = '2.5',
  String recordId = 'dose-1',
}) => ExportDoseRevision(
  recordId: recordId,
  itemId: 'item-1',
  revision: 1,
  currentRevision: 1,
  itemName: name,
  itemForm: 'Liquid',
  itemType: 'Medicine',
  primaryUnit: 'ml',
  enteredAmount: entered,
  enteredUnit: 'ml',
  actualAmount: amount,
  actualUnit: 'ml',
  actualAt: DateTime.utc(2026, 10, 5, 10),
  enteredAt: DateTime.utc(2026, 10, 5, 10, 2),
  isVoided: false,
  source: RecordSource.selfReported,
);

LabPanelSnapshot panel({String? notes, String title = 'Original report'}) =>
    LabPanelSnapshot(
      id: SupportingRecordId(id: 'panel-1', personId: meId),
      title: title,
      collectionDate: SupportingDate.day(CivilDate(2026, 10, 2)),
      reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
      provenance: SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        laboratoryName: 'Synthetic laboratory',
        sourceReferences: [
          SupportingSourceReference(
            id: 'attachment-1',
            personId: meId,
            version: 1,
            kind: SupportingSourceKind.report,
          ),
        ],
      ),
      results: [
        LabResultSnapshot(
          id: 'result-1',
          metricId: 'metric-1',
          markerName: 'Marker',
          value: SupportingValue.numeric('1.5'),
          unit: 'mg/L',
        ),
      ],
      notes: notes,
    );

ExportSupportingRevision supporting({
  String? notes,
  bool includeNotes = false,
  String title = 'Original report',
}) {
  final saved = panel(notes: notes, title: title);
  final revision = SupportingRevision(
    snapshot: saved,
    revision: 1,
    operationId: 'operation-1',
    enteredAt: DateTime.utc(2026, 10, 4, 9),
    revisionEnteredAt: DateTime.utc(2026, 10, 4, 9),
  );
  return ExportSupportingRevision.fromRevision(
    revision,
    currentRevision: 1,
    includeNotes: includeNotes,
  );
}

ExportDocument document({
  ExportFormat format = ExportFormat.json,
  bool includeNotes = false,
  List<ExportDoseRevision>? doses,
  List<ExportSupportingRevision>? supportingRows,
  ExportLimits? limits,
}) => ExportDocument(
  selection: selection(
    format: format,
    includeNotes: includeNotes,
    limits: limits ?? ExportLimits.standard,
  ),
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  personName: 'Alex',
  reportName: 'A. Example',
  doses: doses ?? [dose(amount: ExactAmount(BigInt.from(5), BigInt.two))],
  supporting: supportingRows ?? [supporting(notes: 'Private note')],
);

void main() {
  group('exact decimal semantics', () {
    test('reviewed bytes cannot be changed through list or buffer views', () {
      final artifact = ExportArtifact.build(document());
      expect(() => artifact.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => artifact.bytes.buffer.asUint8List()[0] = 0,
        throwsUnsupportedError,
      );
    });
    test('terminating rationals stay exact and non-terminating stay null', () {
      expect(exactDecimal(ExactAmount(BigInt.one, BigInt.from(4))), '0.25');
      expect(exactDecimal(ExactAmount(BigInt.from(5), BigInt.two)), '2.5');
      expect(exactDecimal(ExactAmount(BigInt.from(2))), '2');
      expect(exactDecimal(ExactAmount(BigInt.one, BigInt.from(3))), isNull);
      expect(
        exactDecimal(ExactAmount(BigInt.one, BigInt.from(1 << 20))),
        isNull,
        reason: 'more than 12 exact places are omitted rather than rounded',
      );
    });
  });

  group('CSV safety', () {
    test('leading formula characters are neutralised before quoting', () {
      expect(csvCell('=1+1'), "'=1+1");
      expect(csvCell('+SUM(A1:A2)'), "'+SUM(A1:A2)");
      expect(csvCell(' @cmd'), "' @cmd");
      expect(csvCell('-2'), '-2');
      expect(csvCell('-1/8'), '-1/8');
      expect(csvCell('-2+3'), "'-2+3");
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('a"b'), '"a""b"');
      expect(csvCell('a\nb'), '"a\nb"');
      expect(csvCell(null), '');
      expect(csvCell('ordinary'), 'ordinary');
    });

    test('CSV rows keep the documented header shape', () {
      final text = encodeExportCsv(document(format: ExportFormat.csv));
      final lines = text.split('\r\n');
      expect(lines.first.split(','), exportCsvHeader);
      for (final line in lines) {
        expect(
          _fieldCount(line),
          exportCsvHeader.length,
          reason: 'Neither a silent extra column nor a missing value',
        );
      }
    });

    test('formula text from a record is escaped in the artifact', () {
      final text = encodeExportCsv(
        document(
          format: ExportFormat.csv,
          doses: [
            dose(
              name: '=HYPERLINK("http://example.invalid")',
              amount: ExactAmount(BigInt.one),
            ),
          ],
          supportingRows: [supporting(title: '-source')],
        ),
      );
      expect(text, contains("'=HYPERLINK"));
      expect(text, contains("'-source"));
    });
  });

  group('JSON artifact', () {
    test('carries schema semantics, selection and exact quantities', () {
      final json = document().toJson();
      expect(json['schemaVersion'], exportSchemaVersion);
      expect(json['selection'], isA<Map<String, Object?>>());
      final selectionJson = json['selection'] as Map<String, Object?>;
      expect(selectionJson['fromDay'], '2026-10-01');
      expect(selectionJson['beforeDay'], '2026-11-01');
      expect(selectionJson['notesIncluded'], false);
      final semantics = json['semantics'] as Map<String, Object?>;
      for (final key in [
        'quantities',
        'units',
        'times',
        'provenance',
        'corrections',
        'privacy',
      ]) {
        expect(semantics[key], isA<String>());
      }
      final rows = json['doses'] as List<Object?>;
      final row = rows.single as Map<String, Object?>;
      final actual = row['actual'] as Map<String, Object?>;
      expect(actual['amountExact'], '5/2');
      expect(actual['amountDecimal'], '2.5');
      expect(row['entered'], {'amount': '2.5', 'unit': 'ml'});
      expect(row['isCurrent'], true);
    });

    test('unrelated people never appear', () {
      final encoded = utf8.decode(ExportArtifact.build(document()).bytes);
      expect(encoded, isNot(contains('another-person')));
      expect(encoded, contains('"id": "me"'));
      expect(encoded, contains('Alex'));
    });

    test('notes and source links are private by default', () {
      final without = document().toJson();
      final supportingRows = without['supporting'] as List<Object?>;
      final record =
          (supportingRows.single as Map<String, Object?>)['record']
              as Map<String, Object?>;
      expect(record['notes'], isNull);
      final provenance = record['provenance'] as Map<String, Object?>;
      expect(provenance['sourceReferences'], isEmpty);
      expect(provenance['laboratoryName'], 'Synthetic laboratory');

      final withNotes = document(
        includeNotes: true,
        supportingRows: [
          supporting(notes: 'Selected note', includeNotes: true),
        ],
      ).toJson();
      final selected =
          ((withNotes['supporting'] as List<Object?>).single
                  as Map<String, Object?>)['record']
              as Map<String, Object?>;
      expect(selected['notes'], 'Selected note');
      expect(
        (selected['provenance'] as Map<String, Object?>)['sourceReferences'],
        isEmpty,
      );
    });

    test('artifact, preview and bytes describe one reviewed file', () {
      final artifact = ExportArtifact.build(document());
      final text = utf8.decode(artifact.bytes);
      expect(artifact.preview.sha256, artifact.sha256);
      expect(artifact.preview.byteCount, artifact.bytes.length);
      expect(
        artifact.preview.excerpt,
        text.substring(0, artifact.preview.excerpt.length),
      );
      expect(artifact.mimeType, 'application/json');
      expect(artifact.fileName, endsWith('.json'));
      expect(artifact.fileName, isNot(contains('Alex')));
      expect(
        artifact.fileName,
        matches(RegExp(r'^vital-export-\d{8}-[0-9a-f]{8}\.json$')),
      );
      expect(artifact.preview.doseRecords, 1);
      expect(artifact.preview.supportingRecords, 1);
      expect(artifact.preview.supportingResults, 1);
      expect(artifact.preview.notesIncluded, false);
    });

    test('encoding is deterministic for the same capture', () {
      final first = ExportArtifact.build(document());
      final second = ExportArtifact.build(document());
      expect(first.sha256, second.sha256);
      expect(first.bytes, second.bytes);
    });

    test('byte bound fails before a preview is offered', () {
      expect(
        () => ExportArtifact.build(
          document(limits: const ExportLimits(maxBytes: 1024)),
        ),
        throwsA(
          isA<ExportLimitException>().having(
            (error) => error.code,
            'code',
            'export_bytes',
          ),
        ),
      );
    });

    test('cancellation stops artifact construction', () {
      final token = ExportCancellation()..cancel();
      expect(
        () => ExportArtifact.build(document(), cancellation: token),
        throwsA(isA<ExportCancelled>()),
      );
    });
  });

  group('selection bounds', () {
    test('empty content, reversed or excessive ranges are rejected', () {
      expect(
        () => ExportSelection(
          personId: meId,
          fromDay: CivilDate(2026, 10, 1),
          beforeDay: CivilDate(2026, 11, 1),
          zoneId: 'UTC',
          contents: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportSelection(
          personId: meId,
          fromDay: CivilDate(2026, 11, 1),
          beforeDay: CivilDate(2026, 10, 1),
          zoneId: 'UTC',
          contents: const [ExportContent.doses],
        ),
        throwsArgumentError,
      );
      expect(
        () => ExportSelection(
          personId: meId,
          fromDay: CivilDate(2010, 1, 1),
          beforeDay: CivilDate(2026, 1, 1),
          zoneId: 'UTC',
          contents: const [ExportContent.doses],
          limits: const ExportLimits(maxDays: 365),
        ),
        throwsA(isA<ExportLimitException>()),
      );
    });

    test('identity changes when any reviewed choice changes', () {
      final base = selection();
      expect(base.identity, selection().identity);
      expect(
        base.identity,
        isNot(selection(format: ExportFormat.csv).identity),
      );
      expect(base.identity, isNot(selection(includeNotes: true).identity));
    });
  });
}

int _fieldCount(String line) {
  var fields = 1;
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit == 0x22) {
      if (quoted && i + 1 < line.length && line.codeUnitAt(i + 1) == 0x22) {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (unit == 0x2C && !quoted) {
      fields++;
    }
  }
  return fields;
}
