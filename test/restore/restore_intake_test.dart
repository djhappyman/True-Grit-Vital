import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/restore/restore_archive_picker.dart';
import 'package:true_grit_vital/restore/restore_intake.dart';

final class _FakePicker implements RestoreArchivePicker {
  _FakePicker(this.selection);
  RestorePickedFile? selection;
  int picks = 0;

  @override
  bool get supported => true;

  @override
  Future<RestorePickedFile?> pick() async {
    picks++;
    return selection;
  }
}

RestorePickedFile _selection(
  List<int> bytes, {
  int? declared,
  String name = 'folder/backup.vitalbackup',
}) => RestorePickedFile(
  name: name,
  byteCount: declared ?? bytes.length,
  openRead: () => Stream.value(bytes),
);

void main() {
  late Directory directory;
  late RestoreArchiveIntake intake;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-intake-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('copies a bounded archive under the fixed protected name', () async {
    final picker = _FakePicker(_selection([1, 2, 3, 4]));
    intake = RestoreArchiveIntake(
      picker: picker,
      directory: Directory('${directory.path}/restore'),
    );
    final pick = await intake.choose();
    expect(pick, isNotNull);
    expect(pick!.name, 'backup.vitalbackup');
    expect(pick.byteCount, 4);
    expect(await pick.file.readAsBytes(), [1, 2, 3, 4]);
    expect(picker.picks, 1);
  });

  test('accepts an archive above the source-attachment picker limit', () async {
    const length = 17 * 1024 * 1024;
    final chunk = List<int>.filled(64 * 1024, 7);
    final picker = _FakePicker(
      RestorePickedFile(
        name: 'large.vitalbackup',
        byteCount: length,
        openRead: () => Stream.fromIterable(
          List.generate(length ~/ chunk.length, (_) => chunk),
        ),
      ),
    );
    intake = RestoreArchiveIntake(
      picker: picker,
      directory: Directory('${directory.path}/restore'),
    );
    final pick = await intake.choose();
    expect(pick, isNotNull);
    expect(pick!.byteCount, length);
    expect(await pick.file.length(), length);
  });

  test(
    'accepts an unknown declared length within the archive ceiling',
    () async {
      intake = RestoreArchiveIntake(
        picker: _FakePicker(
          RestorePickedFile(
            name: 'unknown.vitalbackup',
            byteCount: null,
            openRead: () => Stream.value([1, 2, 3]),
          ),
        ),
        directory: Directory('${directory.path}/restore'),
      );
      final pick = await intake.choose();
      expect(pick, isNotNull);
      expect(pick!.byteCount, 3);
      expect(await pick.file.readAsBytes(), [1, 2, 3]);
    },
  );

  test('rejects an oversized declared archive before writing', () async {
    intake = RestoreArchiveIntake(
      picker: _FakePicker(
        _selection([1], declared: RestoreLimits.maxArchiveBytes + 1),
      ),
      directory: Directory('${directory.path}/restore'),
    );
    await expectLater(
      intake.choose(),
      throwsA(
        isA<RestoreFailure>().having(
          (error) => error.code,
          'code',
          RestoreCodes.tooLarge,
        ),
      ),
    );
    expect(
      await File('${directory.path}/restore/${RestoreLimits.intakeFile}')
          .exists(),
      isFalse,
    );
  });

  test('rejects a stream that ends before its declared byte count', () async {
    intake = RestoreArchiveIntake(
      picker: _FakePicker(_selection([1, 2], declared: 3)),
      directory: Directory('${directory.path}/restore'),
    );
    await expectLater(
      intake.choose(),
      throwsA(
        isA<RestoreFailure>().having(
          (error) => error.code,
          'code',
          RestoreCodes.archiveChanged,
        ),
      ),
    );
    expect(
      await File('${directory.path}/restore/${RestoreLimits.intakeFile}')
          .exists(),
      isFalse,
    );
  });

  test('discard never removes an original outside this intake', () async {
    final original = File('${directory.path}/original.vitalbackup');
    await original.writeAsBytes([1, 2, 3]);
    intake = RestoreArchiveIntake(
      picker: _FakePicker(null),
      directory: Directory('${directory.path}/restore'),
    );
    await expectLater(
      intake.discard(
        RestorePick(name: 'original', file: original, byteCount: 3),
      ),
      throwsA(isA<RestoreFailure>()),
    );
    expect(await original.readAsBytes(), [1, 2, 3]);
  });

  test('cancelled picker leaves no intake file', () async {
    intake = RestoreArchiveIntake(
      picker: _FakePicker(null),
      directory: Directory('${directory.path}/restore'),
    );
    expect(await intake.choose(), isNull);
    expect(
      await File('${directory.path}/restore/${RestoreLimits.intakeFile}')
          .exists(),
      isFalse,
    );
  });
}
