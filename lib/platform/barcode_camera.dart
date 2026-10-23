import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/widgets.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Explicit camera outcomes. The caller always keeps a manual code or item
/// search path; a camera failure never blocks recording.
enum BarcodeCameraFailure { permissionDenied, unsupported, unavailable }

/// Builds the real camera surface. Tests replace this builder with a fixture
/// that never opens hardware, while the shipped app uses ZXing over CameraX.
typedef BarcodeCameraBuilder = Widget Function({
  required ValueChanged<List<String>> onDetected,
  required ValueChanged<BarcodeCameraFailure> onFailure,
  required Widget loading,
});

/// The product-code formats used by medicine packs.
///
/// GTIN-bearing linear symbols are preferred; DataMatrix and QR are included
/// because GS1 pack marks can use them. Content is still validated by
/// [Gtin.tryParse], so arbitrary QR text is rejected rather than treated as a
/// product identity.
const barcodeProductFormats =
    Format.linearCodes | Format.dataMatrix | Format.qrCode;

/// Fully open-source camera scanner: Flutter camera/CameraX plus ZXing C++.
/// No ML Kit, OCR, upload, telemetry or image retention is involved.
Widget buildBarcodeCamera({
  required ValueChanged<List<String>> onDetected,
  required ValueChanged<BarcodeCameraFailure> onFailure,
  required Widget loading,
}) => ReaderWidget(
  isMultiScan: true,
  multiScanModeAlignment: Alignment.bottomLeft,
  multiScanModePadding: const EdgeInsets.all(12),
  codeFormat: barcodeProductFormats,
  tryHarder: true,
  tryRotate: true,
  tryDownscale: false,
  maxNumberOfSymbols: 8,
  showScannerOverlay: false,
  showFlashlight: false,
  showToggleCamera: false,
  showGallery: false,
  allowPinchZoom: true,
  resolution: ResolutionPreset.high,
  scanDelay: const Duration(milliseconds: 350),
  scanDelaySuccess: const Duration(milliseconds: 150),
  loading: loading,
  onMultiScan: (codes) {
    final values = [
      for (final code in codes.codes)
        if (code.text case final text? when text.trim().isNotEmpty) text,
    ];
    if (values.isNotEmpty) onDetected(List.unmodifiable(values));
  },
  onControllerCreated: (controller, error) {
    if (error != null) onFailure(_cameraFailure(error));
  },
);

BarcodeCameraFailure _cameraFailure(Object error) {
  if (error is CameraException) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
        return BarcodeCameraFailure.permissionDenied;
    }
  }
  if (error is UnsupportedError) {
    return BarcodeCameraFailure.unsupported;
  }
  return BarcodeCameraFailure.unavailable;
}
