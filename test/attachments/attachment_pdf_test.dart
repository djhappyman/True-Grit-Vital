import 'dart:convert';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/attachments.dart';
import 'package:true_grit_vital/platform/attachments.dart';

Uint8List syntheticPdf(int pages, {int width = 612, int height = 792}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count $pages /Kids [${List.generate(pages, (i) => '${i + 3} 0 R').join(' ')}] >>',
  ];
  for (var i = 0; i < pages; i++) {
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] /Resources << >> /Contents ${pages + 3} 0 R >>',
    );
  }
  const stream = '0.2 0.5 0.7 rg 20 20 100 100 re f';
  objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  final out = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Flutter host tests use a separate code-asset map from dart run.
    // Use the engine's supported explicit module path for this fixture only.
    if (Platform.isLinux) {
      Pdfrx.pdfiumModulePath = File('build/native_assets/linux/libpdfium.so')
          .absolute
          .path;
    }
  });
  test('one admitted PDFium engine inspects and renders one bounded page in memory', () async {
    final decoder = defaultAttachmentMediaDecoder(),
        bytes = syntheticPdf(3, width: 40000, height: 40000);
    final watch = Stopwatch()..start();
    final inspection = await decoder.inspect(bytes);
    final inspectMs = watch.elapsedMilliseconds;
    watch.reset();
    final page = await decoder.preview(bytes, inspection: inspection, page: 3);
    try {
      expect(inspection.mediaKind, AttachmentMediaKind.pdf);
      expect(inspection.pageCount, 3);
      expect(
        page.image.width * page.image.height * 4,
        lessThanOrEqualTo(AttachmentLimits.maxPreviewBytes),
      );
      // ignore: avoid_print
      print(
        'ATTACHMENT_PDF_PROBE ${jsonEncode({'sourceBytes': bytes.length, 'pages': 3, 'displayWidth': page.image.width, 'displayHeight': page.image.height, 'inspectMs': inspectMs, 'renderMs': watch.elapsedMilliseconds, 'engine': 'PDFium 157.0.8100.0'})}',
      );
    } finally {
      page.dispose();
    }
    await expectLater(
      decoder.preview(bytes, inspection: inspection, page: 4),
      throwsA(isA<AttachmentFailure>()),
    );
  });
  test(
    'page overflow and malformed PDF fail without a plaintext cache',
    () async {
      final decoder = defaultAttachmentMediaDecoder();
      await expectLater(
        decoder.inspect(syntheticPdf(101)),
        throwsA(isA<AttachmentFailure>()),
      );
      await expectLater(
        decoder.inspect(Uint8List.fromList(ascii.encode('%PDF-1.7\nbroken'))),
        throwsA(isA<AttachmentFailure>()),
      );
    },
  );
}
