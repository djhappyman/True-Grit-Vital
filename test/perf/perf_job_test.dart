import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/perf/job.dart';

PerfJob jobWith(Map<String, Object?> extra) => PerfJob.decode({
  'runId': 'run-1',
  'evidenceClass': 'host_smoke',
  'deviceClass': 'host',
  'deviceId': 'host-x86_64',
  'deviceFacts': <String, dynamic>{},
  'host': <String, dynamic>{},
  'scenarios': ['today_swipe', 'record_save'],
  'repeats': 3,
  'volume': 'standard',
  'glass': false,
  'reduceMotion': false,
  'textScale': null,
  'hostOut': null,
  ...extra,
});

void main() {
  test('registry constants stay in sync with the scenario workloads', () {
    expect(perfScenarioKeys, [
      'today_swipe',
      'history_scroll',
      'stock_scroll',
      'record_save',
    ]);
    expect(perfEvidenceClasses, [
      'physical_device',
      'emulator',
      'host_smoke',
      'selftest',
    ]);
    expect(perfDeviceClasses, ['physical', 'emulator', 'host']);
    expect(perfScenarioStatuses, ['measured', 'unsupported']);
    expect(perfVolumeKeys, ['standard', 'wider']);
  });

  test('decode accepts a well-formed job and normalises hostOut', () {
    final job = jobWith({'hostOut': '/tmp/artifact.json'});
    expect(job.runId, 'run-1');
    expect(job.scenarios, ['today_swipe', 'record_save']);
    expect(job.evidenceClass, 'host_smoke');
    expect(job.deviceClass, 'host');
    expect(job.textScale, isNull);
    expect(job.hostOut, '/tmp/artifact.json');
  });

  test('bounds stop oversized workload requests', () {
    expect(
      () => jobWith({'repeats': perfJobMaxRepeats + 1}),
      throwsA(isA<PerfJobError>()),
    );
    expect(() => jobWith({'repeats': 0}), throwsA(isA<PerfJobError>()));
  });

  test('unknown keys, scenarios and enums fail closed', () {
    expect(() => jobWith({'whyNot': 1}), throwsA(isA<PerfJobError>()));
    expect(
      () => jobWith({
        'scenarios': ['why_not'],
      }),
      throwsA(isA<PerfJobError>()),
    );
    expect(
      () => jobWith({
        'scenarios': ['today_swipe', 'today_swipe'],
      }),
      throwsA(isA<PerfJobError>()),
    );
    expect(
      () => jobWith({'evidenceClass': 'legendary'}),
      throwsA(isA<PerfJobError>()),
    );
    expect(
      () => jobWith({'deviceClass': 'cloud'}),
      throwsA(isA<PerfJobError>()),
    );
    expect(() => jobWith({'volume': 'huge'}), throwsA(isA<PerfJobError>()));
    expect(() => jobWith({'runId': ''}), throwsA(isA<PerfJobError>()));
    expect(() => jobWith({'glass': 'yes'}), throwsA(isA<PerfJobError>()));
    expect(() => jobWith({'reduceMotion': 'no'}), throwsA(isA<PerfJobError>()));
    expect(() => jobWith({'textScale': 99.0}), throwsA(isA<PerfJobError>()));
    expect(() => jobWith({'textScale': 0.1}), throwsA(isA<PerfJobError>()));
  });

  test('textScale records a finite supported scale', () {
    expect(jobWith({'textScale': 1.3}).textScale, 1.3);
  });

  test('dataset profiles stay inside the declared bounds', () {
    expect(perfJobMaxRepeats >= 1, isTrue);
    expect(perfJobMaxRecords, 2000);
    expect(perfJobMaxContainers, 200);
    expect(perfJobMaxItems, 40);
  });

  test('job string round-trips through the encoded dart-define form', () {
    final job = PerfJob.standard(
      runId: 'run-2',
      evidenceClass: 'host_smoke',
      deviceClass: 'host',
      deviceId: 'linux-x86_64',
      scenarios: ['history_scroll'],
      repeats: 2,
      glass: true,
      hostOut: '/tmp/one.json',
    );
    expect(job.glass, isTrue);
    expect(job.scenarios, ['history_scroll']);
    expect(job.hostOut, '/tmp/one.json');
    expect(job.dataset, {'items': 6, 'records': 480, 'containers': 36});
  });

  test('wider volume declares its bounded dataset', () {
    final wider = PerfJob.standard(
      runId: 'run-3',
      evidenceClass: 'host_smoke',
      deviceClass: 'host',
      deviceId: 'linux-x86_64',
      volume: 'wider',
    );
    expect(wider.dataset, {'items': 12, 'records': 1200, 'containers': 96});
  });

  test('selftest artifact runs keep the selftest role requirement honest', () {
    final selftest = PerfJob.standard(
      runId: 'run-4',
      evidenceClass: 'selftest',
      deviceClass: 'host',
      deviceId: 'linux-x86_64',
    );
    expect(selftest.hostOut, isNull);
  });
}
