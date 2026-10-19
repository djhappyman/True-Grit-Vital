import 'dart:ffi' as ffi;

// ABI-only regression intentionally inspects the exact admitted transitive fork.
// ignore: depend_on_referenced_packages
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:pdfium_dart/pdfium_dart.dart';

void main() {
  test('retained config prefix size and offsets match the native ABI', () {
    final wide = ffi.sizeOf<ffi.Pointer<ffi.Void>>() == 8;
    final pointer = calloc<FPDF_LIBRARY_CONFIG>();
    try {
      expect(ffi.sizeOf<FPDF_LIBRARY_CONFIG>(), wide ? 48 : 28);
      final bytes = pointer.cast<ffi.Uint8>().asTypedList(
        ffi.sizeOf<FPDF_LIBRARY_CONFIG>(),
      );
      void check(int expectedOffset, void Function() write) {
        bytes.fillRange(0, bytes.length, 0);
        write();
        expect(bytes.indexWhere((value) => value != 0), expectedOffset);
      }

      check(0, () => pointer.ref.version = 1);
      check(
        wide ? 8 : 4,
        () => pointer.ref.m_pUserFontPaths = ffi.Pointer.fromAddress(1),
      );
      check(
        wide ? 16 : 8,
        () => pointer.ref.m_pIsolate = ffi.Pointer.fromAddress(1),
      );
      check(wide ? 24 : 12, () => pointer.ref.m_v8EmbedderSlot = 1);
      check(
        wide ? 32 : 16,
        () => pointer.ref.m_pPlatform = ffi.Pointer.fromAddress(1),
      );
      check(wide ? 40 : 20, () => pointer.ref.m_RendererTypeAsInt = 1);
      check(wide ? 44 : 24, () => pointer.ref.m_FontLibraryTypeAsInt = 1);
    } finally {
      calloc.free(pointer);
    }
  });

  test('unsupported config versions fail before native lookup or invocation', () {
    var lookedUp = false;
    final api = PDFium.fromLookup(<T extends ffi.NativeType>(String name) {
      lookedUp = true;
      throw StateError('Native lookup must not occur');
    });
    final pointer = calloc<FPDF_LIBRARY_CONFIG>();
    try {
      for (final version in [-1, 0, 6, 7, 8, 2147483647]) {
        pointer.ref.version = version;
        expect(
          () => api.FPDF_InitLibraryWithConfig(pointer),
          throwsArgumentError,
        );
      }
      expect(
        () => api.FPDF_InitLibraryWithConfig(ffi.nullptr),
        throwsArgumentError,
      );
      expect(lookedUp, isFalse);
      // Accepted versions reach the lookup boundary (without invoking native).
      for (final version in [1, 2, 3, 4, 5]) {
        pointer.ref.version = version;
        expect(() => api.FPDF_InitLibraryWithConfig(pointer), throwsStateError);
        expect(lookedUp, isTrue);
      }
    } finally {
      calloc.free(pointer);
    }
  });
}
