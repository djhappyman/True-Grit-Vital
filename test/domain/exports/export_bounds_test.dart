import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';

void main() {
  test('host encodes the bounded maximum without pathological growth', () {
    final selection = ExportSelection(
      personId: meId,
      fromDay: CivilDate(2016, 1, 1),
      beforeDay: CivilDate(2026, 1, 1),
      zoneId: 'UTC',
      contents: const [ExportContent.doses],
    );
    final rows = [
      for (var i = 0; i < 20000; i++)
        ExportDoseRevision(
          recordId: 'record-$i',
          itemId: 'item',
          revision: 1,
          currentRevision: 1,
          itemName: 'Synthetic item',
          itemForm: 'Liquid',
          itemType: 'Medicine',
          primaryUnit: 'ml',
          enteredAmount: '1.25',
          enteredUnit: 'ml',
          actualAmount: ExactAmount(BigInt.from(5), BigInt.from(4)),
          actualUnit: 'ml',
          actualAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          enteredAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          isVoided: false,
          source: RecordSource.selfReported,
        ),
    ];
    final document = ExportDocument(
      selection: selection,
      generatedAt: DateTime.utc(2026, 10, 20, 12),
      personName: 'Alex',
      doses: rows,
      supporting: const [],
    );
    final watch = Stopwatch()..start();
    final artifact = ExportArtifact.build(document);
    watch.stop();
    // Host smoke bound only. Device budgets remain G06 work.
    // ignore: avoid_print
    print(
      'export host encode: ${rows.length} revisions, '
      '${artifact.byteCount} bytes, ${watch.elapsedMilliseconds} ms',
    );
    expect(
      artifact.byteCount,
      lessThanOrEqualTo(ExportLimits.standard.maxBytes),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });
}
