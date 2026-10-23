import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/perf/artifact.dart';

/// A structurally valid artifact assembled outside the fixture so the
/// serializer's error codes can be driven directly on the host.
Map<String, dynamic> validArtifact() => {
  'schemaVersion': 2,
  'kind': 'vital-performance-artifact',
  'role': 'selftest',
  'toolVersion': 'vital-perf-harness/2',
  'runId': 'vital-perf-selftest-00000001',
  'createdUtc': '2026-10-23T00:00:00Z',
  'evidenceClass': 'selftest',
  'buildMode': 'host_smoke',
  'host': {
    'gitRevision': 'g',
    'flutterSdkVersion': 'f',
    'dartSdkVersion': 'd',
    'pubspecLockSha256': 'p',
    'fixtureSourceRevision': 's',
    'sourceTreeSha256': 'tree',
  },
  'device': {
    'deviceClass': 'host',
    'id': 'host',
    'model': null,
    'manufacturer': 'host',
    'osRelease': 'release',
    'osSdk': null,
    'isEmulator': false,
  },
  'conditions': {
    'refreshRateHz': null,
    'refreshRateKnown': false,
    'textScaleSystem': 1.0,
    'appearanceOpaquePreference': false,
    'appearanceReduceMotion': false,
    'systemReduceAnimations': false,
    'systemHighContrast': false,
  },
  'glass': {
    'requested': false,
    'fixtureOnly': true,
    'productionDeviceValidated': false,
    'disclosure':
        'Fixture-only glass disclosure well beyond 40 characters '
        'so the serializer length expectations are engaged.',
  },
  'fixtureIdentity': {
    'spec': 'vital-perf-fixture/2',
    'seed': 20261023,
    'dataset': {'items': 6, 'records': 480, 'containers': 36},
    'datasetHash': 'hash',
    'storeGeneration': 'gen',
  },
  'scenarios': [
    {
      'key': 'today_swipe',
      'status': 'measured',
      'reason': null,
      'repeats': 12,
      'refreshRateHz': 60.0,
      'refreshRateKnown': true,
      'frameBudgetMicros': 16667,
      'memoryBeforeKb': 102400,
      'memoryAfterKb': 103424,
      'frames': validFrames(),
    },
    {
      'key': 'record_save',
      'status': 'unsupported',
      'reason': 'prepared_route_dead',
      'repeats': 0,
      'refreshRateHz': null,
      'refreshRateKnown': false,
      'frameBudgetMicros': null,
      'memoryBeforeKb': null,
      'memoryAfterKb': null,
      'frames': null,
    },
  ],
  'limitations': ['Synthetic host-side serializer test artifact.'],
};

Map<String, dynamic> validFrames() => {
  'average_frame_build_time_millis': 10.0,
  '90th_percentile_frame_build_time_millis': 12.0,
  '99th_percentile_frame_build_time_millis': 14.0,
  'worst_frame_build_time_millis': 15.0,
  'missed_frame_build_budget_count': 1,
  'average_frame_rasterizer_time_millis': 4.0,
  '90th_percentile_frame_rasterizer_time_millis': 5.0,
  '99th_percentile_frame_rasterizer_time_millis': 6.0,
  'worst_frame_rasterizer_time_millis': 7.0,
  'average_layer_cache_count': 1.0,
  '90th_percentile_layer_cache_count': 1,
  '99th_percentile_layer_cache_count': 1,
  'worst_layer_cache_count': 2,
  'average_layer_cache_memory': 0.0,
  '90th_percentile_layer_cache_memory': 0.0,
  '99th_percentile_layer_cache_memory': 0.0,
  'worst_layer_cache_memory': 0.0,
  'average_picture_cache_count': 0.0,
  '90th_percentile_picture_cache_count': 0,
  '99th_percentile_picture_cache_count': 0,
  'worst_picture_cache_count': 0,
  'average_picture_cache_memory': 0.0,
  '90th_percentile_picture_cache_memory': 0.0,
  '99th_percentile_picture_cache_memory': 0.0,
  'worst_picture_cache_memory': 0.0,
  'missed_frame_rasterizer_budget_count': 0,
  'frame_count': 3,
  'frame_build_times': [9999, 15000, 8000],
  'frame_rasterizer_times': [4000, 5000, 3000],
  'new_gen_gc_count': 0,
  'old_gen_gc_count': 0,
};

void main() {
  test('valid artifact serialises to canonical sorted-key JSON', () {
    final encoded = serializePerfArtifact(validArtifact());
    // Recursive key ordering: runId comes createdUtc under sorted order.
    expect(encoded.startsWith('{"buildMode":'), isTrue);
    expect(encoded.contains(',"scenarios":['), isTrue);
    // No whitespace separators in the canonical form.
    expect(encoded.contains(': '), isFalse);
    expect(encoded.contains(', '), isFalse);
  });

  test('wrong evidence-class/role pairing is refused', () {
    final artifact = validArtifact();
    artifact['role'] = 'measured';
    expect(
      () => serializePerfArtifact(artifact),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('role_evidence_mismatch:measured/selftest'),
        ),
      ),
    );
    final fake = validArtifact()..['evidenceClass'] = 'legendary';
    expect(
      () => serializePerfArtifact(fake),
      throwsA(predicate((e) => e.toString().contains('bad_evidence_class'))),
    );
  });

  test('keys mismatch is named in the error', () {
    final artifact = validArtifact()..remove('glass');
    expect(
      () => serializePerfArtifact(artifact),
      throwsA(predicate((e) => e.toString().contains('keys_mismatch'))),
    );
  });

  test('glass forgery cannot be serialised', () {
    final artifact = validArtifact();
    (artifact['glass']! as Map<String, Object?>)['productionDeviceValidated'] =
        true;
    expect(
      () => serializePerfArtifact(artifact),
      throwsA(predicate((e) => e.toString().contains('glass_gate_forgery'))),
    );
  });

  test('unknown scenario key is refused', () {
    final artifact = validArtifact();
    (artifact['scenarios'][0] as Map)['key'] = 'why_not';
    expect(
      () => serializePerfArtifact(artifact),
      throwsA(predicate((e) => e.toString().contains('scenario_key_unknown'))),
    );
  });

  test(
    'measured scenarios need full frame maps, unsupported ones need a reason',
    () {
      final missingFrames = validArtifact();
      (missingFrames['scenarios'][0] as Map)['frames'] = <String, Object?>{};
      expect(
        () => serializePerfArtifact(missingFrames),
        throwsA(predicate((e) => e.toString().contains('frames_shape'))),
      );

      final noReason = validArtifact();
      (noReason['scenarios'][1] as Map)['reason'] = null;
      expect(
        () => serializePerfArtifact(noReason),
        throwsA(
          predicate((e) => e.toString().contains('unsupported_missing_reason')),
        ),
      );

      final unexpectedFrames = validArtifact();
      (unexpectedFrames['scenarios'][1] as Map)['frames'] = validFrames();
      expect(
        () => serializePerfArtifact(unexpectedFrames),
        throwsA(
          predicate((e) => e.toString().contains('unsupported_frames_present')),
        ),
      );

      final withReason = validArtifact();
      (withReason['scenarios'][0] as Map)['reason'] = 'cannot explain success';
      expect(
        () => serializePerfArtifact(withReason),
        throwsA(
          predicate((e) => e.toString().contains('measured_with_reason')),
        ),
      );
    },
  );

  test('dataset identity counts must be non-negative integers', () {
    final artifact = validArtifact();
    (artifact['fixtureIdentity'] as Map)['dataset'] = {
      'items': -1,
      'records': 480,
      'containers': 36,
    };
    expect(
      () => serializePerfArtifact(artifact),
      throwsA(predicate((e) => e.toString().contains('bad_count:items'))),
    );
  });

  test('non-finite numbers cannot enter the canonical encoding', () {
    expect(
      () => perfCanonicalJson(<String, dynamic>{'x': double.nan}),
      throwsA(predicate((e) => e.toString().contains('non_finite_number'))),
    );
    expect(perfCanonicalJson(<String, dynamic>{'x': 1.5}), '{"x":1.5}');
    expect(
      perfCanonicalJson([
        'b',
        'a',
        {'z': 1, 'y': 2},
      ]),
      '["b","a",{"y":2,"z":1}]',
    );
  });
}
