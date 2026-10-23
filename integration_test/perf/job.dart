import 'dart:convert';

/// Scenario registry and bounded job configuration for the Vital performance
/// harness. The host runner (`tool/performance/measure.py`) encodes one job as
/// the `VITAL_PERF_JOB` dart-define; the fixture refuses to run without one so
/// it can never enter ordinary test sessions by accident.
///
/// Job and scenario names are also consumed by the deterministic Python
/// validator, which parses the registry constants out of this file
/// (`tool/performance/selftest.py`). Keep the keys simple string literals.

/// The supported scenario keys, in canonical order.
const perfScenarioKeys = [
  'today_swipe',
  'history_scroll',
  'stock_scroll',
  'record_save',
];

/// Hard safety bounds for generated work. These are tooling bounds that keep a
/// misconfigured run from stalling a device for hours; they are not performance
/// budgets and never appear as pass/fail thresholds.
const perfJobMaxRepeats = 50;

/// Largest total synthetic administrations one fixture may seed.
const perfJobMaxRecords = 2000;

/// Largest number of stock containers one fixture may seed.
const perfJobMaxContainers = 200;

/// Largest number of substance items one fixture may seed.
const perfJobMaxItems = 40;

/// Artifact identity of the synthetic dataset spec this fixture emits.
const perfFixtureSpec = 'vital-perf-fixture/2';

/// Current artifact contract version.
const perfArtifactSchemaVersion = 2;

/// Fixed kind marker used by every artifact this harness produces.
const perfArtifactKind = 'vital-performance-artifact';

/// Harness version written into artifacts so tooling can detect contract age.
const perfHarnessToolVersion = 'vital-perf-harness/2';

/// Valid scenario-only status values in artifacts.
const perfScenarioStatuses = ['measured', 'unsupported'];

/// Valid device classes in artifacts.
const perfDeviceClasses = ['physical', 'emulator', 'host'];

/// Valid evidence classes in artifacts. Only `physical_device` can ever count
/// towards measured device evidence; everything else is explicitly labelled.
/// The selftest generator marks its synthetic artifacts with `selftest`.
const perfEvidenceClasses = [
  'physical_device',
  'emulator',
  'host_smoke',
  'selftest',
];

/// Build modes the harness distinguishes in artifacts. `host_smoke` marks a
/// host-run fixture exercise that must never be quoted as device evidence.
const perfBuildModes = ['profile', 'host_smoke'];

/// Fixed disclosure that every artifact carries about the glass gate.
const perfGlassDisclosure =
    'Fixture-only selection of glass or opaque surfaces. Production glass is '
    'enabled by owner direction; physical-device validation remains separate. '
    'This artifact never grants device acceptance.';

/// Seed default the fixture uses so mandated artefacts record an editable
/// provenance value instead of an ad-hoc choice at run time.
const perfDefaultSeed = 20261023;

/// Valid fixture dataset volume profiles.
const perfVolumeKeys = ['standard', 'wider'];

class PerfJob {
  PerfJob({
    required this.runId,
    required this.evidenceClass,
    required this.deviceClass,
    required this.deviceId,
    required this.deviceFacts,
    required this.host,
    required this.scenarios,
    required this.repeats,
    required this.volume,
    required this.glass,
    required this.reduceMotion,
    required this.textScale,
    required this.hostOut,
  });

  /// Decodes the job from the encoded JSON map (one was produced by
  /// [encode] on the host or by a `--dart-define` string). Unknown keys fail
  /// closed so an artifact can never silently gain unconsidered inputs.
  factory PerfJob.decode(Map<String, dynamic> raw) {
    final allowed = const {
      'runId',
      'evidenceClass',
      'deviceClass',
      'deviceId',
      'deviceFacts',
      'host',
      'scenarios',
      'repeats',
      'volume',
      'glass',
      'reduceMotion',
      'textScale',
      'hostOut',
    };
    for (final key in raw.keys) {
      if (!allowed.contains(key)) {
        throw PerfJobError('unknown_job_key:$key');
      }
    }

    final runId = _string(raw['runId'], 'runId', 1, 128);
    final evidenceClass = _one(raw['evidenceClass'], perfEvidenceClasses);
    final deviceClass = _one(raw['deviceClass'], perfDeviceClasses);
    final deviceId = _string(raw['deviceId'], 'deviceId', 0, 256);
    final facts = raw['deviceFacts'];
    if (facts != null && facts is! Map<String, dynamic>) {
      throw const PerfJobError('deviceFacts_not_object');
    }
    final host = raw['host'];
    if (host is! Map<String, dynamic>) {
      throw const PerfJobError('host_not_object');
    }

    final scenarioList = raw['scenarios'];
    if (scenarioList is! List ||
        scenarioList.isEmpty ||
        scenarioList.length > perfScenarioKeys.length) {
      throw const PerfJobError('scenarios_invalid');
    }
    final picked = scenarioList.map<String>((value) {
      if (!perfScenarioKeys.contains(value)) {
        throw PerfJobError('unknown_scenario:$value');
      }
      return value as String;
    }).toList();
    if (picked.toSet().length != picked.length) {
      throw const PerfJobError('scenarios_duplicate');
    }

    final repeats = _count(raw['repeats'], 1, perfJobMaxRepeats);
    final volume = _one(raw['volume'], perfVolumeKeys);
    // Glass may only be exercised on the explicitly labelled fixture runs and
    // only on labeled fixture-only artifact paths; a physical-device run with
    // glass is still fixture-only content, never a production behaviour.
    if (raw['glass'] is! bool) throw const PerfJobError('glass_not_bool');
    if (raw['reduceMotion'] is! bool) {
      throw const PerfJobError('reduceMotion_not_bool');
    }
    final textScale = raw['textScale'] as Object?;
    if (textScale != null && textScale is! num) {
      throw const PerfJobError('textScale_not_number');
    }
    double? scale;
    if (textScale != null) {
      scale = (textScale as num).toDouble();
      if (!scale.isFinite || scale < 0.5 || scale > 4.0) {
        throw const PerfJobError('textScale_out_of_range');
      }
    }
    final hostOut = raw['hostOut'];
    if (hostOut != null && hostOut is! String?) {
      throw const PerfJobError('hostOut_not_string');
    }
    return PerfJob(
      runId: runId,
      evidenceClass: evidenceClass,
      deviceClass: deviceClass,
      deviceId: deviceId,
      deviceFacts: (facts as Map<String, dynamic>?) ?? const {},
      host: host,
      scenarios: picked,
      repeats: repeats,
      volume: volume,
      glass: raw['glass'] as bool,
      reduceMotion: raw['reduceMotion'] as bool,
      textScale: scale,
      hostOut: hostOut is String && hostOut.isNotEmpty ? hostOut : null,
    );
  }

  factory PerfJob.fromJson(String encoded) =>
      PerfJob.decode(jsonDecode(encoded) as Map<String, dynamic>);

  factory PerfJob.standard({
    required String runId,
    required String evidenceClass,
    required String deviceClass,
    required String deviceId,
    Map<String, dynamic> deviceFacts = const {},
    Map<String, dynamic> host = const {},
    List<String> scenarios = perfScenarioKeys,
    int repeats = 12,
    String volume = 'standard',
    bool glass = false,
    bool reduceMotion = false,
    double? textScale,
    String? hostOut,
  }) => PerfJob.decode({
    'runId': runId,
    'evidenceClass': evidenceClass,
    'deviceClass': deviceClass,
    'deviceId': deviceId,
    'deviceFacts': deviceFacts,
    'host': host,
    'scenarios': scenarios,
    'repeats': repeats,
    'volume': volume,
    'glass': glass,
    'reduceMotion': reduceMotion,
    'textScale': textScale,
    'hostOut': hostOut,
  });

  final String runId;
  final String evidenceClass;
  final String deviceClass;
  final String deviceId;
  final Map<String, dynamic> deviceFacts;
  final Map<String, dynamic> host;
  final List<String> scenarios;
  final int repeats;
  final String volume;
  final bool glass;
  final bool reduceMotion;
  final double? textScale;
  final String? hostOut;

  Map<String, dynamic> get dataset {
    return switch (volume) {
      'standard' => const {'items': 6, 'records': 480, 'containers': 36},
      'wider' => const {'items': 12, 'records': 1200, 'containers': 96},
      _ => throw PerfJobError('unknown_volume:$volume'),
    };
  }
}

String _string(Object? value, String name, int min, int max) {
  if (value is! String || value.length < min || value.length > max) {
    throw PerfJobError('bad_$name');
  }
  return value;
}

String _one(Object? value, List<String> options) {
  if (value is! String || !options.contains(value)) {
    throw PerfJobError('bad_option:$value');
  }
  return value;
}

int _count(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw PerfJobError('count_out_of_bounds:$value');
  }
  return value;
}

final class PerfJobError implements Exception {
  const PerfJobError(this.code);
  final String code;
  @override
  String toString() => 'PerfJobError($code)';
}
