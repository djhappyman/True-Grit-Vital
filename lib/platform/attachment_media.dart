import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../domain/attachments.dart';

/// One admitted PDF engine supplies parsing/rendering; no temporary file needed.
abstract interface class AttachmentPdfDecoder {
  Future<int> pageCount(Uint8List bytes);
  Future<ui.Image> render(
    Uint8List bytes, {
    required int page,
    required int maxEdge,
  });
}

final class AttachmentPreview {
  AttachmentPreview(this.image);
  final ui.Image image;
  bool _disposed = false;
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      image.dispose();
    }
  }
}

final class AttachmentMediaDecoder {
  const AttachmentMediaDecoder({this.pdf});
  final AttachmentPdfDecoder? pdf;
  static bool _working = false;
  Future<T> _one<T>(Future<T> Function() operation) async {
    if (_working) throw const AttachmentFailure('attachment_busy');
    _working = true;
    try {
      return await operation();
    } finally {
      _working = false;
    }
  }

  Future<AttachmentInspection> inspect(Uint8List bytes) =>
      _one(() => _inspect(bytes));
  Future<AttachmentInspection> _inspect(Uint8List bytes) async {
    _validateBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final kind = sniffAttachment(bytes);
    if (kind == AttachmentMediaKind.pdf) {
      final decoder = pdf;
      if (decoder == null) {
        throw const AttachmentFailure('attachment_pdf_unavailable');
      }
      final pages = await decoder.pageCount(bytes);
      return AttachmentInspection(
        mediaKind: kind,
        byteCount: bytes.length,
        sha256: hash,
        mimeType: 'application/pdf',
        pageCount: pages,
      );
    }
    if (kind == AttachmentMediaKind.image) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width < 1 ||
            descriptor.height < 1 ||
            descriptor.width * descriptor.height >
                AttachmentLimits.maxDecodedPixels) {
          throw const AttachmentFailure('attachment_image_limit');
        }
        codec = await descriptor.instantiateCodec(
          targetWidth: 1,
          targetHeight: 1,
        );
        if (codec.frameCount != 1) {
          throw const AttachmentFailure('attachment_frame_limit');
        }
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        return AttachmentInspection(
          mediaKind: kind,
          byteCount: bytes.length,
          sha256: hash,
          mimeType: _imageMime(bytes),
          width: descriptor.width,
          height: descriptor.height,
          frameCount: codec.frameCount,
        );
      } on AttachmentFailure {
        rethrow;
      } catch (_) {
        throw const AttachmentFailure('attachment_image_invalid');
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    }
    return AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: hash,
      mimeType: 'application/octet-stream',
    );
  }

  /// Returns one bounded image. The caller disposes it on hide, lock or replacement.
  Future<AttachmentPreview> preview(
    Uint8List bytes, {
    required AttachmentInspection inspection,
    int page = 1,
    int maxEdge = AttachmentLimits.maxDisplayEdge,
  }) => _one(
    () => _preview(bytes, inspection: inspection, page: page, maxEdge: maxEdge),
  );
  Future<AttachmentPreview> _preview(
    Uint8List bytes, {
    required AttachmentInspection inspection,
    required int page,
    required int maxEdge,
  }) async {
    _validateBytes(bytes);
    if (maxEdge < 1 ||
        maxEdge > AttachmentLimits.maxDisplayEdge ||
        inspection.byteCount != bytes.length ||
        inspection.sha256 != sha256.convert(bytes).toString()) {
      throw const AttachmentFailure('attachment_preview_input');
    }
    if (inspection.mediaKind == AttachmentMediaKind.pdf) {
      if (pdf == null || page < 1 || page > inspection.pageCount!) {
        throw const AttachmentFailure('attachment_page_limit');
      }
      return AttachmentPreview(
        await pdf!.render(bytes, page: page, maxEdge: maxEdge),
      );
    }
    if (inspection.mediaKind != AttachmentMediaKind.image || page != 1) {
      throw const AttachmentFailure('attachment_preview_unavailable');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width, height = descriptor.height;
      if (width * height > AttachmentLimits.maxDecodedPixels) {
        throw const AttachmentFailure('attachment_image_limit');
      }
      final edge = width > height ? width : height;
      final scale = math.min(
        edge > maxEdge ? maxEdge / edge : 1.0,
        math.sqrt(AttachmentLimits.maxPreviewBytes / (width * height * 4)),
      );
      final targetWidth = (width * scale).floor().clamp(1, maxEdge);
      final targetHeight = (height * scale).floor().clamp(1, maxEdge);
      if (targetWidth * targetHeight * 4 > AttachmentLimits.maxPreviewBytes) {
        throw const AttachmentFailure('attachment_preview_limit');
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      if (codec.frameCount != 1) {
        throw const AttachmentFailure('attachment_frame_limit');
      }
      return AttachmentPreview((await codec.getNextFrame()).image);
    } on AttachmentFailure {
      rethrow;
    } catch (_) {
      throw const AttachmentFailure('attachment_image_invalid');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

void _validateBytes(Uint8List bytes) {
  if (bytes.isEmpty) throw const AttachmentFailure('attachment_empty');
  if (bytes.length > AttachmentLimits.maxInputBytes) {
    throw const AttachmentFailure('attachment_byte_limit');
  }
}

AttachmentMediaKind sniffAttachment(Uint8List bytes) {
  bool prefix(List<int> signature) =>
      bytes.length >= signature.length &&
      Iterable<int>.generate(signature.length)
          .every((i) => bytes[i] == signature[i]);
  if (prefix([0x25, 0x50, 0x44, 0x46, 0x2d])) return AttachmentMediaKind.pdf;
  if (prefix([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) ||
      prefix([0xff, 0xd8, 0xff]) ||
      prefix([0x47, 0x49, 0x46, 0x38]) ||
      prefix([0x52, 0x49, 0x46, 0x46]) &&
          bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return AttachmentMediaKind.image;
  }
  return AttachmentMediaKind.other;
}

String _imageMime(Uint8List bytes) => bytes[0] == 0x89
    ? 'image/png'
    : bytes[0] == 0xff
    ? 'image/jpeg'
    : bytes[0] == 0x47
    ? 'image/gif'
    : 'image/webp';

Future<Uint8List> readAttachmentBytes(Stream<List<int>> source) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in boundedAttachmentChunks(source)) {
    result.add(chunk);
  }
  return result.takeBytes();
}
