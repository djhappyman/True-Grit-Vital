import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:pdfrx/pdfrx.dart';

import '../domain/attachments.dart';
import 'attachment_media.dart';

/// Direct document/page API avoids viewer disk caches and its default 100MB cache.
final class PdfrxAttachmentDecoder implements AttachmentPdfDecoder {
  const PdfrxAttachmentDecoder();
  static Future<void>? _initialization;
  Future<PdfDocument> _open(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > AttachmentLimits.maxInputBytes) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    // Memory/custom sources need only the native entry functions, no asset/URL cache.
    try {
      await (_initialization ??= PdfrxEntryFunctions.instance.init());
      final document = await PdfDocument.openData(
        bytes,
        useProgressiveLoading: true,
        maxSizeToCacheOnMemory: 0,
        sourceName: 'memory:attachment-${sha256.convert(bytes)}',
      );
      if (document.pages.isEmpty ||
          document.pages.length > AttachmentLimits.maxPdfPages) {
        await document.dispose();
        throw const AttachmentFailure('attachment_page_limit');
      }
      return document;
    } on AttachmentFailure {
      rethrow;
    } catch (_) {
      throw const AttachmentFailure('attachment_pdf_invalid');
    }
  }

  @override
  Future<int> pageCount(Uint8List bytes) async {
    final document = await _open(bytes);
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  Future<PdfPage> _page(PdfDocument document, int page) async {
    if (page < 1 || page > document.pages.length) {
      throw const AttachmentFailure('attachment_page_limit');
    }
    if (!document.pages[page - 1].isLoaded) {
      await document.loadPagesProgressively(
        startPageNumber: page,
        loadUnitDuration: Duration.zero,
        onPageLoadProgress: (_, _, _) => false,
      );
    }
    final source = document.pages[page - 1];
    if (!source.isLoaded ||
        !source.width.isFinite ||
        !source.height.isFinite ||
        source.width <= 0 ||
        source.height <= 0) {
      throw const AttachmentFailure('attachment_pdf_invalid');
    }
    return source;
  }

  @override
  Future<ui.Image> render(
    Uint8List bytes, {
    required int page,
    required int maxEdge,
  }) async {
    if (maxEdge < 1 || maxEdge > AttachmentLimits.maxDisplayEdge) {
      throw const AttachmentFailure('attachment_preview_limit');
    }
    final document = await _open(bytes);
    try {
      final source = await _page(document, page);
      final largest = math.max(source.width, source.height);
      final scale = math.min(
        maxEdge / largest,
        math.sqrt(
          AttachmentLimits.maxPreviewBytes / (source.width * source.height * 4),
        ),
      );
      final width = (source.width * scale).floor().clamp(1, maxEdge),
          height = (source.height * scale).floor().clamp(1, maxEdge);
      if (width * height * 4 > AttachmentLimits.maxPreviewBytes) {
        throw const AttachmentFailure('attachment_preview_limit');
      }
      final rendered = await source.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) {
        throw const AttachmentFailure('attachment_pdf_invalid');
      }
      try {
        return await rendered.createImage();
      } finally {
        rendered.dispose();
      }
    } on AttachmentFailure {
      rethrow;
    } catch (_) {
      throw const AttachmentFailure('attachment_pdf_invalid');
    } finally {
      await document.dispose();
    }
  }
}
