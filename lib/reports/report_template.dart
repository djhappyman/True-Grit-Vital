import 'dart:typed_data';

import '../domain/reports/reports.dart';

final class ReportRenderedDocument {
  ReportRenderedDocument({
    required this.bytes,
    required this.pageCount,
    required this.fontsEmbedded,
  });
  final Uint8List bytes;
  final int pageCount;
  final bool fontsEmbedded;
}

/// Shared seam for R01, R02 and R03. T06 adds templates without another
/// renderer or a second preview/artifact path.
abstract interface class ReportTemplateRenderer {
  ReportTemplateId get template;
  String get version;

  Future<ReportRenderedDocument> render(
    ReportSnapshot snapshot, {
    required bool use24Hour,
    ReportCancellation cancellation = const NeverCancelled(),
    void Function(int completed, int total)? onProgress,
  });
}
