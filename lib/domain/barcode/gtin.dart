/// A validated GTIN, EAN or UPC pack number.
///
/// The scanner can return the digits printed under a barcode, or a GS1 element
/// string beginning with application identifier `01`. This type validates the
/// check digit and keeps the printed length for display. [canonical] is the
/// zero-padded GTIN-14 form used only for exact local lookup, so leading zeros
/// survive and equivalent EAN/UPC forms compare equal.
final class Gtin implements Comparable<Gtin> {
  const Gtin._({
    required this.canonical,
    required this.printed,
    required this.format,
  });

  /// Fourteen digits, including any leading zeros added for GTIN-14.
  final String canonical;

  /// The digits as printed by the barcode, including its own leading zeros.
  final String printed;
  final GtinFormat format;

  /// Bounds scanner content before any parsing work.
  static const maxPayloadLength = 4096;

  static final _digits = RegExp(r'^[0-9]+$');
  static final _gs1Parenthesised = RegExp(r'^\(01\)([0-9]{14})');
  static final _gs1Raw = RegExp(r'^01([0-9]{14})');
  static final _symbologyIdentifier = RegExp(r'^\][A-Za-z0-9]{2}');

  /// Accepts a bare EAN-8, UPC-A, EAN-13 or GTIN-14, a parenthesised GS1
  /// element string such as `(01)09501101530003`, an unbracketed GS1 `01`
  /// element, or the same payload behind a symbology identifier.
  ///
  /// Returns null when the payload is not a supported product number or its
  /// check digit is wrong. No name, dose, strength or catalogue record is
  /// inferred from the number.
  static Gtin? tryParse(String raw) => _attempt(raw).gtin;

  static _Attempt _attempt(String raw) {
    if (raw.isEmpty || raw.length > maxPayloadLength) {
      return const _Attempt.unsupported();
    }
    var value = raw.trim();
    if (value.isEmpty) return const _Attempt.unsupported();
    final symbology = _symbologyIdentifier.firstMatch(value);
    if (symbology != null) value = value.substring(symbology.end);
    if (value.isEmpty) return const _Attempt.unsupported();

    if (_gs1Parenthesised.firstMatch(value) case final match?) {
      if (!_validGs1Suffix(value.substring(match.end), bracketed: true)) {
        return const _Attempt.unsupported();
      }
      return _fromDigits(match.group(1)!);
    }
    if (_gs1Raw.firstMatch(value) case final match?) {
      if (!_validGs1Suffix(value.substring(match.end), bracketed: false)) {
        return const _Attempt.unsupported();
      }
      return _fromDigits(match.group(1)!);
    }
    if (!_digits.hasMatch(value)) return const _Attempt.unsupported();
    return _fromDigits(value);
  }

  // A bounded pharmaceutical subset: expiry (17), lot (10) and serial (21).
  // Unknown/malformed suffixes use the manual digits path rather than treating
  // arbitrary QR text beginning with a valid GTIN as a GS1 product symbol.
  static bool _validGs1Suffix(String tail, {required bool bracketed}) {
    var rest = tail;
    while (rest.isNotEmpty) {
      if (!bracketed && rest.startsWith('\u001d')) {
        rest = rest.substring(1);
        if (rest.isEmpty) return true;
      }
      final match = RegExp(bracketed ? r'^\((17|10|21)\)' : r'^(17|10|21)')
          .firstMatch(rest);
      if (match == null) return false;
      final ai = match.group(1)!;
      rest = rest.substring(match.end);
      if (ai == '17') {
        if (rest.length < 6 ||
            !RegExp(r'^[0-9]{6}$').hasMatch(rest.substring(0, 6))) {
          return false;
        }
        rest = rest.substring(6);
      } else {
        final separator = rest.indexOf(bracketed ? '(' : '\u001d');
        final length = separator < 0 ? rest.length : separator;
        final value = rest.substring(0, length);
        if (value.isEmpty ||
            value.length > 20 ||
            !RegExp(r'^[ -~]+$').hasMatch(value)) {
          return false;
        }
        rest = rest.substring(length);
      }
    }
    return true;
  }

  static _Attempt _fromDigits(String digits) {
    final format = switch (digits.length) {
      8 => GtinFormat.ean8,
      12 => GtinFormat.upcA,
      13 => GtinFormat.ean13,
      14 => GtinFormat.gtin14,
      _ => null,
    };
    if (format == null) return const _Attempt.unsupported();
    if (!_validCheckDigit(digits)) return const _Attempt.invalidCheckDigit();
    return _Attempt.valid(
      Gtin._(
        canonical: digits.padLeft(14, '0'),
        printed: digits,
        format: format,
      ),
    );
  }

  static bool _validCheckDigit(String digits) {
    var sum = 0;
    var weight = 3;
    for (var i = digits.length - 2; i >= 0; i--) {
      final code = digits.codeUnitAt(i) - 0x30;
      if (code < 0 || code > 9) return false;
      sum += code * weight;
      weight = 4 - weight;
    }
    final expected = (10 - sum % 10) % 10;
    return expected == digits.codeUnitAt(digits.length - 1) - 0x30;
  }

  @override
  int compareTo(Gtin other) => canonical.compareTo(other.canonical);

  @override
  bool operator ==(Object other) =>
      other is Gtin && canonical == other.canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => printed;
}

enum GtinFormat { ean8, upcA, ean13, gtin14 }

/// One scanner frame or manual entry, reduced to distinct valid numbers.
///
/// Repeated detections of the same printed value or an equivalent EAN/UPC form
/// collapse to one [Gtin]. Distinct valid numbers remain separate so the person
/// chooses; none is selected automatically.
final class BarcodeDetectionResult {
  BarcodeDetectionResult._({
    required List<Gtin> codes,
    required this.sawInvalidCheckDigit,
    required this.sawUnsupported,
  }) : codes = List.unmodifiable(codes);

  final List<Gtin> codes;

  /// A numeric candidate had the wrong check digit.
  final bool sawInvalidCheckDigit;

  /// At least one payload was not a supported product number.
  final bool sawUnsupported;

  static BarcodeDetectionResult analyze(Iterable<String> payloads) {
    final codes = <String, Gtin>{};
    var invalid = false;
    var unsupported = false;
    for (final payload in payloads) {
      final attempt = Gtin._attempt(payload);
      final gtin = attempt.gtin;
      if (gtin != null) {
        codes[gtin.canonical] = gtin;
      } else if (attempt.invalidCheckDigit) {
        invalid = true;
      } else {
        unsupported = true;
      }
    }
    final ordered = codes.values.toList()..sort();
    return BarcodeDetectionResult._(
      codes: ordered,
      sawInvalidCheckDigit: invalid,
      sawUnsupported: unsupported,
    );
  }
}

final class _Attempt {
  const _Attempt.valid(this.gtin)
    : invalidCheckDigit = false,
      unsupported = false;
  const _Attempt.invalidCheckDigit()
    : gtin = null,
      invalidCheckDigit = true,
      unsupported = false;
  const _Attempt.unsupported()
    : gtin = null,
      invalidCheckDigit = false,
      unsupported = true;
  final Gtin? gtin;
  final bool invalidCheckDigit;
  final bool unsupported;
}
