// Separate-process fixture for protected artifact staging recovery.
//
// Each scenario stages in one process and dies without cleanup, then a fresh
// process must reclaim only the known artifact, never an unrelated file.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:true_grit_vital/platform/artifact_transfer_files.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'usage: artifact_transfer_process <directory> <stage|cleanup> <orphan|partial>',
    );
    exit(2);
  }
  final root = Directory(args[0]);
  final mode = args[1];
  final expectation = args[2];
  final clock = DateTime.utc(2026, 10, 20, 12);
  final store = ArtifactFileStore(rootOverride: root, clock: () => clock);
  final expires = clock.add(const Duration(hours: 1));
  final id = expectation == 'orphan' ? 'orphan' : 'interrupted';

  if (mode == 'stage') {
    final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 251));
    await store.begin(
      id: id,
      name: id == 'orphan' ? 'vital-summary.pdf' : 'vital-export.csv',
      mimeType: id == 'orphan' ? 'application/pdf' : 'text/csv',
      byteCount: id == 'orphan' ? bytes.length : 2048,
      expiresAt: expires,
    );
    await store.append(
      id: id,
      offset: 0,
      bytes: id == 'orphan' ? bytes : Uint8List.fromList(List.filled(512, 7)),
    );
    if (id == 'orphan') {
      await store.publish(
        id: id,
        byteCount: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
    }
    // Process death: no cancel, cleanup or shutdown callback runs.
    stdout.writeln('staged $id');
    exit(0);
  }

  if (mode == 'cleanup') {
    final unrelated = File('${root.path}/keep-me.txt');
    await unrelated.writeAsString('preserve');
    final removed = await store.cleanup();
    if (removed.length != 1 || removed.single != id) {
      stderr.writeln('unexpected cleanup: $removed');
      exit(73);
    }
    if (await unrelated.readAsString() != 'preserve') {
      stderr.writeln('unrelated file was changed');
      exit(74);
    }
    final leftovers = root
        .listSync()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .where(
          (name) =>
              name.endsWith('.meta') ||
              name.endsWith('.part') ||
              name.endsWith('.bin') ||
              name.endsWith('.next'),
        );
    if (leftovers.isNotEmpty) {
      stderr.writeln('staging remained: ${leftovers.toList()}');
      exit(75);
    }
    stdout.writeln('clean $id');
    exit(0);
  }

  stderr.writeln('unknown mode');
  exit(2);
}
