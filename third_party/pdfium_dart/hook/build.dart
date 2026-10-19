// Copyright (c) 2025 @espresso3389 (Takashi Kawasaki).
// Vital's verified local-supply adaptation: Copyright 2026 Vital contributors.
// SPDX-License-Identifier: MIT. See ../LICENSE and ../VITAL_PATCH.md.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final platform = switch (input.config.code.targetOS) {
      OS.android => 'android',
      OS.linux => 'linux',
      _ => throw UnsupportedError('PDFium platform has no admitted binary'),
    };
    final arch = switch (input.config.code.targetArchitecture) {
      Architecture.arm => 'arm',
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x64',
      _ => throw UnsupportedError('PDFium architecture has no admitted binary'),
    };
    final target = '$platform-$arch';
    final manifestUri = input.packageRoot.resolve('native/manifest.json');
    final manifest = jsonDecode(
      await File.fromUri(manifestUri).readAsString(),
    ) as Map<String, dynamic>;
    if (manifest['release'] != 'chromium/8100' ||
        manifest['immutable'] != true) {
      throw StateError('PDFium manifest identity mismatch');
    }
    final asset =
        (manifest['assets'] as Map<String, dynamic>)[target]
            as Map<String, dynamic>?;
    if (asset == null) {
      throw UnsupportedError('PDFium target has no admitted binary: $target');
    }
    final archiveUri = input.packageRoot.resolve('native/$target/pdfium.tgz');
    final sourceArchive = File.fromUri(archiveUri);
    if (await sourceArchive.length() != asset['archiveBytes']) {
      throw StateError('PDFium archive integrity mismatch');
    }
    final bytes = await sourceArchive.readAsBytes();
    if (sha256.convert(bytes).toString() != asset['archiveSha256']) {
      throw StateError('PDFium archive integrity mismatch');
    }
    final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    final member = archive.findFile('lib/libpdfium.so');
    if (member == null) throw StateError('PDFium archive library missing');
    final library = member.content as List<int>;
    if (sha256.convert(library).toString() != asset['librarySha256']) {
      throw StateError('PDFium library integrity mismatch');
    }
    final file = input.outputDirectoryShared.resolve(
      'chromium_8100/$target/libpdfium.so',
    );
    final destination = File.fromUri(file);
    if (await destination.exists()) {
      if (await destination.length() != asset['libraryBytes'] ||
          sha256.convert(await destination.readAsBytes()).toString() !=
              asset['librarySha256']) {
        throw StateError('PDFium cached library integrity mismatch');
      }
    } else {
      await destination.parent.create(recursive: true);
      final staged = File('${destination.path}.part');
      await staged.writeAsBytes(library, flush: true);
      await staged.rename(destination.path);
    }
    output.dependencies.addAll([manifestUri, archiveUri]);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'libpdfium',
        linkMode: DynamicLoadingBundled(),
        file: file,
      ),
    );
  });
}
