import 'dart:convert';
import 'dart:typed_data';

/// One generated, reviewed artifact. Bytes and text describe the same capture.
final class ReportArtifact {
  ReportArtifact({
    required this.selectionIdentity,
    required this.artifactId,
    required this.templateId,
    required this.templateVersion,
    required this.templateTitle,
    required this.personName,
    this.reportName,
    required this.periodText,
    required this.generatedAt,
    required Uint8List bytes,
    required this.text,
    required this.fileName,
    required this.textFileName,
    required this.pageCount,
    required this.sha256,
    required this.fontsEmbedded,
    required this.use24Hour,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.isEmpty ||
        pageCount < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('report_artifact');
    }
  }
  final String selectionIdentity, artifactId, templateId, templateVersion;
  final String templateTitle, personName, periodText;
  final String? reportName;
  final DateTime generatedAt;
  final Uint8List bytes;
  final String text, fileName, textFileName, sha256;
  final int pageCount;
  final bool fontsEmbedded, use24Hour;
  int get byteCount => bytes.length;

  /// Structured alternative bytes can use the same injected destination handoff.
  Uint8List get textBytes => Uint8List.fromList(utf8.encode(text));
}
