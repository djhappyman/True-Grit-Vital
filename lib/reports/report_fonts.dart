import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Embedded Noto Sans is the approved report face. The standard PDF fonts are
/// a truthful fallback only when the packaged asset is unavailable.
final class ReportFonts {
  const ReportFonts({
    required this.regular,
    required this.bold,
    required this.embedded,
  });
  final pw.Font regular, bold;
  final bool embedded;
}

abstract interface class ReportFontLoader {
  Future<ReportFonts> load();
}

final class AssetReportFontLoader implements ReportFontLoader {
  const AssetReportFontLoader();
  static const regularAsset = 'assets/fonts/NotoSans-Regular.ttf';
  static const boldAsset = 'assets/fonts/NotoSans-Bold.ttf';
  static Future<ReportFonts>? _cached;

  @override
  Future<ReportFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final loading = _load();
    _cached = loading;
    try {
      return await loading;
    } catch (_) {
      _cached = null;
      rethrow;
    }
  }

  Future<ReportFonts> _load() async {
    try {
      final regular = await rootBundle.load(regularAsset);
      final bold = await rootBundle.load(boldAsset);
      return ReportFonts(
        regular: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        embedded: true,
      );
    } catch (_) {
      return ReportFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        embedded: false,
      );
    }
  }
}
