import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/barcode/gtin.dart';

void main() {
  group('GTIN parsing', () {
    test('accepts EAN-13 and keeps its printed length', () {
      final code = Gtin.tryParse('4006381333931')!;
      expect(code.printed, '4006381333931');
      expect(code.canonical, '04006381333931');
      expect(code.format, GtinFormat.ean13);
    });

    test('accepts EAN-8 and UPC-A without dropping leading zeros', () {
      final ean8 = Gtin.tryParse('96385074')!;
      expect(ean8.printed, '96385074');
      expect(ean8.canonical, '00000096385074');
      expect(ean8.format, GtinFormat.ean8);

      final upc = Gtin.tryParse('036000291452')!;
      expect(upc.printed, '036000291452');
      expect(upc.canonical, '00036000291452');
      expect(upc.format, GtinFormat.upcA);

      final leadingZeroEan = Gtin.tryParse('0012345678905')!;
      expect(leadingZeroEan.printed, '0012345678905');
      expect(leadingZeroEan.canonical, '00012345678905');
    });

    test('accepts GTIN-14 including a significant leading zero', () {
      final code = Gtin.tryParse('09501101530003')!;
      expect(code.printed, '09501101530003');
      expect(code.canonical, '09501101530003');
      expect(code.format, GtinFormat.gtin14);
    });

    test('accepts GS1 element strings and ignores other elements', () {
      final bracketed = Gtin.tryParse('(01)09501101530003(10)SYNTHETIC')!;
      expect(bracketed.canonical, '09501101530003');
      final unbracketed = Gtin.tryParse('010950110153000310SYNTHETIC')!;
      expect(unbracketed.canonical, '09501101530003');
      final symbol = Gtin.tryParse(']C10109501101530003')!;
      expect(symbol.canonical, '09501101530003');
    });

    test(
      'GS1 suffixes cannot hide arbitrary or malformed trailing content',
      () {
        for (final value in [
          '(01)09501101530003garbage',
          '0109501101530003garbage',
          '(01)09501101530003(17)12',
          '(01)09501101530003(99)UNKNOWN',
        ]) {
          expect(Gtin.tryParse(value), isNull, reason: value);
        }
        expect(
          Gtin.tryParse('(01)09501101530003(17)270101(10)LOT(21)SERIAL'),
          isNotNull,
        );
        expect(
          Gtin.tryParse('01095011015300031727010110LOT\u001d21SERIAL'),
          isNotNull,
        );
      },
    );

    test('equivalent EAN and UPC forms compare as one product number', () {
      final ean = Gtin.tryParse('0036000291452')!;
      final upc = Gtin.tryParse('036000291452')!;
      expect(ean, upc);
      expect(ean.canonical, upc.canonical);
      expect({ean, upc}, hasLength(1));
    });

    test('rejects a wrong check digit and unsupported payloads', () {
      expect(Gtin.tryParse('4006381333932'), isNull);
      expect(Gtin.tryParse('00000000000001'), isNull);
      expect(Gtin.tryParse('(00)123456789012345675'), isNull);
      expect(Gtin.tryParse('medicine pack'), isNull);
      expect(Gtin.tryParse(''), isNull);
      expect(
        Gtin.tryParse(List.filled(Gtin.maxPayloadLength + 1, '1').join()),
        isNull,
      );
      expect(Gtin.tryParse('123456789'), isNull);
    });
  });

  group('multiple detections', () {
    test('deduplicates repeated and equivalent detections', () {
      final result = BarcodeDetectionResult.analyze([
        '4006381333931',
        '4006381333931',
        '(01)04006381333931',
        '0036000291452',
        '036000291452',
      ]);
      expect(result.codes, hasLength(2));
      expect(result.codes.map((code) => code.canonical), [
        '00036000291452',
        '04006381333931',
      ]);
      expect(result.sawInvalidCheckDigit, isFalse);
      expect(result.sawUnsupported, isFalse);
    });

    test('keeps distinct detections for an explicit choice', () {
      final result = BarcodeDetectionResult.analyze([
        '4006381333931',
        '96385074',
      ]);
      expect(result.codes, hasLength(2));
    });

    test('distinguishes an invalid check digit from unsupported content', () {
      final invalid = BarcodeDetectionResult.analyze(['4006381333932']);
      expect(invalid.codes, isEmpty);
      expect(invalid.sawInvalidCheckDigit, isTrue);

      final unsupported = BarcodeDetectionResult.analyze(['Not a pack code']);
      expect(unsupported.codes, isEmpty);
      expect(unsupported.sawInvalidCheckDigit, isFalse);
      expect(unsupported.sawUnsupported, isTrue);
    });

    test('a frame with no valid product number never yields a suggestion', () {
      final result = BarcodeDetectionResult.analyze([
        'https://example.invalid/product',
        '{"name":"synthetic"}',
      ]);
      expect(result.codes, isEmpty);
    });
  });
}
