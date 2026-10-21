part of 'record_store.dart';

extension VaultSummaryStore on RecordStore {
  Future<VaultSummary> vaultSummary() async {
    _requireWritable();
    final row = (await _rows('''
      SELECT
        (SELECT COUNT(*) FROM item WHERE person='me') AS substances,
        (SELECT COUNT(*) FROM administration a JOIN revision r
          ON r.record=a.id AND r.person=a.person AND r.revision=a.revision
          WHERE a.person='me' AND r.voided=0) AS doses,
        (SELECT COUNT(*) FROM supporting_record
          WHERE person='me' AND voided=0) AS supporting,
        (SELECT COUNT(*) FROM attachment_record
          WHERE person='me' AND state='ready') AS files
      ''')).single;
    int? bytes;
    try {
      // Only known files belonging to this opened store, never a directory scan.
      bytes = await File(databasePath).length();
      for (final suffix in ['-wal', '-shm']) {
        final file = File('$databasePath$suffix');
        if (await file.exists()) bytes = bytes! + await file.length();
      }
    } on FileSystemException {
      // Keep correct record counts when physical size cannot be measured.
      bytes = null;
    }
    _requireWritable();
    return VaultSummary(
      generation: generation,
      substances: row['substances'] as int,
      doses: row['doses'] as int,
      supportingRecords: row['supporting'] as int,
      files: row['files'] as int,
      databaseBytes: bytes,
    );
  }

  Stream<VaultSummary> watchVaultSummary() => _watch(
    vaultSummary,
    changes: Stream<void>.multi((sink) {
      var completed = 0;
      void done() {
        if (++completed == 2) sink.close();
      }

      final records = _changes.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: done,
      );
      final drafts = _draftChanges.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: done,
      );
      sink.onCancel = () async {
        await records.cancel();
        await drafts.cancel();
      };
    }),
  );
}
