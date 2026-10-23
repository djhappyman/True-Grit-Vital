import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host driver for the Vital performance fixture. It only hands the
/// device-produced artifact to the host filesystem; all measurement, status
/// recording and condition capture happen in the fixture itself so the same
/// bytes validate under `tool/performance/validate.py` for both device and
/// host smoke runs.
Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      final artifact = data?['artifact'];
      if (artifact is! String) {
        stderr.writeln('vital-perf: no artifact arrived from the fixture');
        exitCode = 1;
        return;
      }
      final id = data?['runId'];
      // Without the fixture job the driver has no run identity, so runId was
      // always set alongside the artifact. Defaulting keeps a failed handoff
      // visible instead of silently unreadable.
      final runId = id is String && id.isNotEmpty ? id : 'vital-perf';
      final file = File(
        Platform.environment['VITAL_PERF_ARTIFACT_PATH'] ??
            'build/performance/$runId/artifact.json',
      );
      file.parent.createSync(recursive: true);
      await file.writeAsString('$artifact\n');
      stdout.writeln('vital-perf artifact: ${file.path}');
    },
  );
}
