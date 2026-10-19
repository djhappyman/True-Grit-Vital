import 'dart:io';

import 'package:vital_storage_gate_probe/probe.dart';

void main(List<String> args) {
  final db = openProtected(args[0]);
  command(
    db,
    operation: 'op1',
    record: 'r1',
    person: 'me',
    expectedRevision: 0,
    entered: '0.1',
    abruptBeforeCommit: args[1] == 'before',
  );
  // Simulates durable commit followed by process death before a response.
  exit(72);
}
