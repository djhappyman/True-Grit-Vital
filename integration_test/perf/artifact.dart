import 'dart:convert';

import 'job.dart';

// Artifact contract of the Vital performance harness.
//
// The fixture assembles one JSON artifact per run out of the job, the device
// and condition facts it can observe and per-scenario frame data collected
// with the pinned SDK's `IntegrationTestWidgetsFlutterBinding
// .watchPerformance`. The deterministic host validator
// (`tool/performance/validate.py`) parses the key lists
// `perfArtifactTopLevelKeys` and `perfArtifactScenarioKeys` below and must
// match them; `tool/performance/selftest.py` asserts that cross-language
// drift cannot happen silently.

/// Top-level artifact keys, in canonical emission order.
const perfArtifactTopLevelKeys = [
  'schemaVersion',
  'kind',
  'role',
  'toolVersion',
  'runId',
  'createdUtc',
  'evidenceClass',
  'buildMode',
  'host',
  'device',
  'conditions',
  'glass',
  'fixtureIdentity',
  'scenarios',
  'limitations',
];

/// Per-scenario artifact keys, in canonical emission order.
const perfArtifactScenarioKeys = [
  'key',
  'status',
  'reason',
  'repeats',
  'refreshRateHz',
  'refreshRateKnown',
  'frameBudgetMicros',
  'memoryBeforeKb',
  'memoryAfterKb',
  'frames',
];

/// Keys inside the per-scenario `frames` map. These mirror the pinned SDK
/// `FrameTimingSummarizer.summary` field names
/// (flutter_test/src/frame_timing_summarizer.dart) so the summarizer's output
/// can be validated element by element.
const perfFrameSummaryKeys = [
  'average_frame_build_time_millis',
  '90th_percentile_frame_build_time_millis',
  '99th_percentile_frame_build_time_millis',
  'worst_frame_build_time_millis',
  'missed_frame_build_budget_count',
  'average_frame_rasterizer_time_millis',
  '90th_percentile_frame_rasterizer_time_millis',
  '99th_percentile_frame_rasterizer_time_millis',
  'worst_frame_rasterizer_time_millis',
  'average_layer_cache_count',
  '90th_percentile_layer_cache_count',
  '99th_percentile_layer_cache_count',
  'worst_layer_cache_count',
  'average_layer_cache_memory',
  '90th_percentile_layer_cache_memory',
  '99th_percentile_layer_cache_memory',
  'worst_layer_cache_memory',
  'average_picture_cache_count',
  '90th_percentile_picture_cache_count',
  '99th_percentile_picture_cache_count',
  'worst_picture_cache_count',
  'average_picture_cache_memory',
  '90th_percentile_picture_cache_memory',
  '99th_percentile_picture_cache_memory',
  'worst_picture_cache_memory',
  'missed_frame_rasterizer_budget_count',
  'frame_count',
  'frame_build_times',
  'frame_rasterizer_times',
  'new_gen_gc_count',
  'old_gen_gc_count',
];

/// Valid artifact roles. `measured` records a run classified as physical
/// device evidence; the other roles label exactly what was exercised. Only
/// `measured` artifacts with `evidenceClass: physical_device` may ever count
/// towards device evidence. The Python mirror lives in
/// `tool/performance/validate.py`.
const perfArtifactRoles = ['measured', 'emulator', 'host_smoke', 'selftest'];

/// Required role for each evidence class, enforced by [validatePerfArtifact].
const perfEvidenceRoleRequirement = {
  'physical_device': 'measured',
  'emulator': 'emulator',
  'host_smoke': 'host_smoke',
  'selftest': 'selftest',
};

/// Required key set for the artifact `host` block.
const perfArtifactHostKeys = [
  'gitRevision',
  'flutterSdkVersion',
  'dartSdkVersion',
  'pubspecLockSha256',
  'fixtureSourceRevision',
  'sourceTreeSha256',
];

/// Required key set for the artifact `device` block. `model` may be null on
/// the host; every other device fact must be present, with `null` used only
/// where the platform cannot supply the fact.
const perfArtifactDeviceKeys = [
  'deviceClass',
  'id',
  'model',
  'manufacturer',
  'osRelease',
  'osSdk',
  'isEmulator',
];

/// Required key set for the artifact `conditions` block.
const perfArtifactConditionKeys = [
  'refreshRateHz',
  'refreshRateKnown',
  'textScaleSystem',
  'appearanceOpaquePreference',
  'appearanceReduceMotion',
  'systemReduceAnimations',
  'systemHighContrast',
];

/// Required key set for the artifact `glass` block.
const perfArtifactGlassKeys = [
  'requested',
  'fixtureOnly',
  'productionGateProviderValue',
  'disclosure',
];

/// Required key set for the artifact `fixtureIdentity` block.
const perfArtifactFixtureIdentityKeys = [
  'spec',
  'seed',
  'dataset',
  'datasetHash',
  'storeGeneration',
];

/// Dataset count keys inside the fixture identity, parsed and mirrored by
/// the host validator.
const perfArtifactDatasetKeys = ['items', 'records', 'containers'];

/// Validates one run's assembled artifact map and returns its canonical
/// (sorted-key, compact) JSON encoding. Throws [ArtifactError] with a stable
/// code for every structural violation; the same codes appear in the
/// deterministic Python validator so fixes stay aligned.
String serializePerfArtifact(Map<String, dynamic> artifact) {
  if (artifact.keys.length != perfArtifactTopLevelKeys.length ||
      !artifact.keys.toSet().containsAll(perfArtifactTopLevelKeys)) {
    throw const ArtifactError('keys_mismatch');
  }
  if (artifact['schemaVersion'] != 1) {
    throw const ArtifactError('schema_version');
  }
  if (artifact['toolVersion'] != 'vital-perf-harness/1') {
    throw const ArtifactError('tool_version');
  }
  final evidenceClass = artifact['evidenceClass'];
  final role = artifact['role'];
  if (perfEvidenceRoleRequirement[evidenceClass] == null) {
    throw ArtifactError('bad_evidence_class:$evidenceClass');
  }
  if (role != perfEvidenceRoleRequirement[evidenceClass]) {
    throw ArtifactError('role_evidence_mismatch:$role/$evidenceClass');
  }

  for (final block in [
    const ('host', perfArtifactHostKeys),
    const ('device', perfArtifactDeviceKeys),
    const ('conditions', perfArtifactConditionKeys),
    const ('glass', perfArtifactGlassKeys),
    const ('fixtureIdentity', perfArtifactFixtureIdentityKeys),
  ]) {
    final section = artifact[block.$1];
    if (section is! Map ||
        section.keys.length != block.$2.length ||
        !(section.keys.cast<String>().toSet()).containsAll(block.$2)) {
      throw ArtifactError('block_keys_mismatch:${block.$1}');
    }
  }

  final fixtureIdentity = artifact['fixtureIdentity'] as Map;
  final dataset = fixtureIdentity['dataset'];
  if (dataset is! Map ||
      dataset.keys.length != perfArtifactDatasetKeys.length ||
      !(dataset.keys.cast<String>().toSet()).containsAll(
        perfArtifactDatasetKeys,
      )) {
    throw const ArtifactError('fixture_identity_dataset_mismatch');
  }
  for (final field in perfArtifactDatasetKeys) {
    final value = dataset[field];
    if (value is! int || value < 0) {
      throw ArtifactError('fixture_identity_bad_count:$field');
    }
  }

  final glass = artifact['glass'] as Map;
  if (glass['productionGateProviderValue'] != false ||
      glass['fixtureOnly'] != true) {
    throw const ArtifactError('glass_gate_forgery');
  }

  final scenarios = artifact['scenarios'];
  if (scenarios is! List || scenarios.isEmpty) {
    throw const ArtifactError('scenarios_missing');
  }
  final seen = <String>{};
  for (final scenario in scenarios) {
    if (scenario is! Map ||
        scenario.keys.length != perfArtifactScenarioKeys.length ||
        !(scenario.keys.cast<String>().toSet()).containsAll(
          perfArtifactScenarioKeys,
        )) {
      throw const ArtifactError('scenario_keys_mismatch');
    }
    final key = scenario['key'];
    if (key is! String || !perfScenarioKeys.contains(key) || !seen.add(key)) {
      throw ArtifactError('scenario_key_unknown:$key');
    }
    final status = scenario['status'];
    if (status != 'measured' && status != 'unsupported') {
      throw ArtifactError('scenario_status_invalid:$status');
    }
    if (status == 'unsupported' && scenario['reason'] is! String) {
      throw ArtifactError('unsupported_missing_reason:$key');
    }
    if (status == 'measured' && scenario['reason'] != null) {
      throw ArtifactError('measured_with_reason:$key');
    }
    final frames = scenario['frames'];
    if (status == 'measured') {
      if (frames is! Map ||
          frames.keys.length != perfFrameSummaryKeys.length ||
          !(frames.keys.cast<String>().toSet()).containsAll(
            perfFrameSummaryKeys,
          )) {
        throw ArtifactError('frames_shape:$key');
      }
    } else if (frames != null) {
      throw ArtifactError('unsupported_frames_present:$key');
    }
  }

  return perfCanonicalJson(artifact);
}

/// Encodes [value] with recursively sorted keys and compact separators so an
/// artifact is byte-comparable across runs with identical inputs.
String perfCanonicalJson(Object? value) {
  final out = StringBuffer();
  _writeCanonical(value, out);
  return out.toString();
}

void _writeCanonical(Object? value, StringBuffer out) {
  switch (value) {
    case null:
      out.write('null');
    case bool b:
      out.write(b ? 'true' : 'false');
    case num n:
      if (n.isNaN || n.isInfinite) {
        throw const ArtifactError('non_finite_number');
      }
      out.write(n.toString());
    case String s:
      out.write(jsonEncode(s));
    case List<Object?> l:
      out.write('[');
      for (final (index, item) in l.indexed) {
        if (index > 0) out.write(',');
        _writeCanonical(item, out);
      }
      out.write(']');
    case Map<Object?, Object?> m:
      final keys = m.keys.map((Object? k) => k.toString()).toList()..sort();
      out.write('{');
      for (final (index, key) in keys.indexed) {
        if (index > 0) out.write(',');
        out.write(jsonEncode(key));
        out.write(':');
        _writeCanonical(_mapEntry(m, key), out);
      }
      out.write('}');
    default:
      throw ArtifactError('unsupported_value:${value.runtimeType}');
  }
}

/// Looks a value up by its canonical string key, tolerant of the
/// heterogeneous maps the fixture and tests hand in.
Object? _mapEntry(Map<Object?, Object?> map, String key) {
  for (final entry in map.entries) {
    if (entry.key.toString() == key) return entry.value;
  }
  throw ArtifactError('unsupported_value:missing_key:$key');
}

final class ArtifactError implements Exception {
  const ArtifactError(this.code);
  final String code;
  @override
  String toString() => 'ArtifactError($code)';
}
