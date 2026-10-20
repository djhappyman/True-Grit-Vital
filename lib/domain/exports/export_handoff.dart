import 'export_selection.dart';
import 'export_serializer.dart';

/// Truthful outcome of one destination handoff.
enum ExportDelivery { saved, shared, cancelled, unavailable, failed }

/// Injected destination boundary for a completed export artifact.
///
/// The shared G04 artifact-transfer implementation supplies the real gateway.
/// It receives the exact reviewed bytes, a neutral file name and MIME type, and
/// reports progress and cancellation. This feature never opens a platform
/// dialog itself and never claims a recipient copied the file.
abstract interface class ExportHandoff {
  bool get isAvailable;

  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double progress)? onProgress,
  });
}

/// Honest default until the shared handoff gateway is wired.
///
/// The UI disables Save and explains that saving is unavailable rather than
/// pretending a local no-op succeeded.
final class UnavailableExportHandoff implements ExportHandoff {
  const UnavailableExportHandoff();

  @override
  bool get isAvailable => false;

  @override
  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async => ExportDelivery.unavailable;
}
