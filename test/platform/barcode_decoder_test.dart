import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:true_grit_vital/domain/barcode/gtin.dart';

CameraImage imageFromLuminance(Uint8List data, int width, int height) =>
    CameraImage.fromPlatformInterface(
      CameraImageData(
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: data, bytesPerRow: width, bytesPerPixel: 1),
        ],
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      ),
    );

Encode encode(String text, int format, {int width = 720, int height = 240}) {
  final encoded = zx.encodeBarcode(
    contents: text,
    params: EncodeParams(
      format: format,
      width: width,
      height: height,
      margin: 24,
    ),
  );
  expect(encoded.isValid, isTrue, reason: encoded.error);
  return encoded;
}

Future<List<String>> decode(Encode encoded) async {
  final codes = await zx.processCameraImageMulti(
    imageFromLuminance(encoded.data!, encoded.width!, encoded.height!),
    DecodeParams(
      imageFormat: ImageFormat.lum,
      format: Format.linearCodes,
      width: encoded.width!,
      height: encoded.height!,
      tryHarder: true,
      isMultiScan: true,
      maxNumberOfSymbols: 8,
    ),
  );
  return [for (final code in codes.codes) ?code.text];
}

final nativeReady = Platform.environment['VITAL_BARCODE_NATIVE'] == '1';
const nativeSkip =
    'Set VITAL_BARCODE_NATIVE=1 and LD_LIBRARY_PATH to the built '
    'build/linux/x64/debug/bundle/lib directory to run real ZXing fixtures.';

void main() {
  setUpAll(() async {
    if (!nativeReady) return;
    expect(zx.version(), isNotEmpty);
    await zx.startCameraProcessing();
  });
  tearDownAll(() {
    if (nativeReady) zx.stopCameraProcessing();
  });

  test(
    'real ZXing decodes EAN-13, EAN-8 and UPC-A fixtures',
    skip: nativeReady ? false : nativeSkip,
    () async {
      for (final (text, format) in [
        ('4006381333931', Format.ean13),
        ('96385074', Format.ean8),
        ('036000291452', Format.upca),
        ('0012345678905', Format.ean13),
      ]) {
        final encoded = encode(text, format);
        final codes = await decode(encoded);
        final result = BarcodeDetectionResult.analyze(codes);
        expect(result.codes.map((code) => code.canonical), [
          Gtin.tryParse(text)!.canonical,
        ], reason: '$text decoded as $codes');
      }
    },
  );

  test(
    'real ZXing decodes a GS1 element string',
    skip: nativeReady ? false : nativeSkip,
    () async {
      final encoded = encode('(01)09501101530003(10)SYNTHETIC', Format.code128);
      final codes = await decode(encoded);
      final result = BarcodeDetectionResult.analyze(codes);
      expect(result.codes.single.canonical, '09501101530003');
    },
  );

  test(
    'real ZXing reports two distinct panel symbols',
    skip: nativeReady ? false : nativeSkip,
    () async {
      final left = encode(
        '4006381333931',
        Format.ean13,
        width: 480,
        height: 240,
      );
      final right = encode('96385074', Format.ean8, width: 480, height: 240);
      final width = left.width! > right.width! ? left.width! : right.width!;
      final height = left.height! + right.height!;
      final combined = Uint8List(width * height)
        ..fillRange(0, width * height, 255);
      for (var y = 0; y < left.height!; y++) {
        combined.setRange(
          y * width,
          y * width + left.width!,
          left.data!,
          y * left.width!,
        );
      }
      for (var y = 0; y < right.height!; y++) {
        final offset = (left.height! + y) * width;
        combined.setRange(
          offset,
          offset + right.width!,
          right.data!,
          y * right.width!,
        );
      }
      final codes = await decode(
        Encode(
          true,
          Format.any,
          null,
          combined,
          combined.length,
          null,
          width: width,
          height: height,
        ),
      );
      final result = BarcodeDetectionResult.analyze(codes);
      expect(result.codes, hasLength(2));
      expect(result.codes.map((code) => code.canonical).toSet(), {
        '04006381333931',
        '00000096385074',
      });
    },
  );
}
