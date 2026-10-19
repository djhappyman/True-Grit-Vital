import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/domain/attachments.dart';
import 'package:true_grit_vital/platform/attachment_media.dart';

Future<Uint8List> png(int width, int height) async {
  final picture = ui.PictureRecorder();
  final canvas = ui.Canvas(picture);
  canvas.drawColor(const ui.Color(0xff347fba), ui.BlendMode.src);
  final recording = picture.endRecording();
  final image = await recording.toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    recording.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'existing encrypted engine retains bounded complete original chunks',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'vital-attachment-probe-',
      );
      final measurements = <String, Object?>{
        'platform': Platform.operatingSystem,
        'limits': {
          'inputBytes': AttachmentLimits.maxInputBytes,
          'chunkBytes': AttachmentLimits.chunkBytes,
          'pixels': AttachmentLimits.maxDecodedPixels,
          'pages': AttachmentLimits.maxPdfPages,
          'concurrency': AttachmentLimits.maxConcurrentJobs,
          'previewBytes': AttachmentLimits.maxPreviewBytes,
        },
      };
      try {
        final path = '${temp.path}/probe.sqlite';
        final db = sqlite3.open(path);
        try {
          db.execute("PRAGMA cipher='chacha20'");
          db.execute("PRAGMA key=\"x'${List.filled(32, '73').join()}'\"");
          db.execute('PRAGMA journal_mode=WAL');
          db.execute('PRAGMA synchronous=FULL');
          db.execute(
            'CREATE TABLE chunk (ordinal INTEGER PRIMARY KEY, bytes BLOB NOT NULL)',
          );
          final marker = utf8.encode(
            'SYNTHETIC-ATTACHMENT-ORIGINAL-PROBE-ONLY',
          );
          final chunk = Uint8List(AttachmentLimits.chunkBytes);
          for (var i = 0; i < chunk.length; i++) {
            chunk[i] = marker[i % marker.length];
          }
          final write = Stopwatch()..start();
          for (
            var i = 0;
            i < AttachmentLimits.maxInputBytes ~/ chunk.length;
            i++
          ) {
            db.execute('INSERT INTO chunk VALUES (?,?)', [i, chunk]);
          }
          write.stop();
          final read = Stopwatch()..start();
          var total = 0;
          final expected = sha256.convert(chunk);
          for (
            var i = 0;
            i < AttachmentLimits.maxInputBytes ~/ chunk.length;
            i++
          ) {
            final bytes =
                db.select('SELECT bytes FROM chunk WHERE ordinal=?', [
                      i,
                    ]).single['bytes']
                    as Uint8List;
            expect(bytes.length, AttachmentLimits.chunkBytes);
            expect(sha256.convert(bytes), expected);
            total += bytes.length;
          }
          read.stop();
          expect(total, AttachmentLimits.maxInputBytes);
          expect(
            db.select('PRAGMA integrity_check').single.values.single,
            'ok',
          );
          measurements['encrypted16MiBWriteMs'] = write.elapsedMilliseconds;
          measurements['encrypted16MiBReadMs'] = read.elapsedMilliseconds;
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        } finally {
          db.close();
        }
        final raw = await File(path).readAsBytes();
        expect(
          utf8
              .decode(raw, allowMalformed: true)
              .contains('SYNTHETIC-ATTACHMENT-ORIGINAL-PROBE-ONLY'),
          false,
        );
        final unkeyed = sqlite3.open(path);
        try {
          expect(
            () => unkeyed.select('SELECT count(*) FROM chunk'),
            throwsA(isA<SqliteException>()),
          );
        } finally {
          unkeyed.close();
        }
        measurements['ciphertextBytes'] = raw.length;
        if (Platform.isLinux) {
          measurements['hostRss'] = await File('/proc/self/status')
              .readAsLines()
              .then(
                (v) => v
                    .where(
                      (s) => s.startsWith('VmRSS:') || s.startsWith('VmHWM:'),
                    )
                    .toList(),
              );
        }
        // ignore: avoid_print
        print('ATTACHMENT_PROBE ${jsonEncode(measurements)}');
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test('image probe enforces decoded pixels and display byte budget', () async {
    const decoder = AttachmentMediaDecoder();
    final bytes = await png(4000, 4000);
    final inspect = Stopwatch()..start();
    final metadata = await decoder.inspect(bytes);
    inspect.stop();
    final render = Stopwatch()..start();
    final preview = await decoder.preview(bytes, inspection: metadata);
    render.stop();
    try {
      expect(metadata.width, 4000);
      expect(metadata.height, 4000);
      expect(
        preview.image.width * preview.image.height * 4,
        lessThanOrEqualTo(AttachmentLimits.maxPreviewBytes),
      );
      // ignore: avoid_print
      print(
        'ATTACHMENT_IMAGE_PROBE ${jsonEncode({'compressedBytes': bytes.length, 'sourcePixels': 16000000, 'displayWidth': preview.image.width, 'displayHeight': preview.image.height, 'inspectMs': inspect.elapsedMilliseconds, 'renderMs': render.elapsedMilliseconds})}',
      );
    } finally {
      preview.dispose();
    }
    final oversize = await png(4096, 4096);
    await expectLater(
      decoder.inspect(oversize),
      throwsA(isA<AttachmentFailure>()),
    );
    await expectLater(
      decoder.inspect(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0])),
      throwsA(isA<AttachmentFailure>()),
    );
  });
}
