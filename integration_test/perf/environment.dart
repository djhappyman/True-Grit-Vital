import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'job.dart';

/// Fixture-side condition and environment facts. Everything here is best-
/// effort: a fact that cannot be read truthfully is reported as null with an
/// explicit reason rather than guessed. No reliance on the production runtime
/// or user health data.

/// Reserved fixture subdirectory that must never collide with production
/// storage (`no_backup/vital`). On Android the fixture probes app-private
/// candidates that the profile build can write; on the Linux host the runner
/// supplies the directory explicitly.
List<String> perfFixtureDirCandidates() {
  final manual = const String.fromEnvironment('VITAL_PERF_FIXTURE_DIR');
  final facts = [if (manual.isNotEmpty) manual];
  if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
    for (final prefix in const ['/data/user/0', '/data/data']) {
      facts.add('$prefix/${perfAndroidPackageName()}/cache/vital-perf-fixture');
    }
    facts.add(
      '/storage/emulated/0/Android/data/'
      '${perfAndroidPackageName()}/files/vital-perf-fixture',
    );
  } else {
    facts.add('${Directory.systemTemp.path}/vital-perf-fixture-probe');
  }
  return facts;
}

/// The known Android application id for the Vital app. Reading it from the
/// process environment directly is not portable; the app id is a build
/// configuration fact held in one place here and asserted by the runner.
String perfAndroidPackageName() => 'dev.truegrit.vital';

/// Creates the fixture directory and returns it on success.
Directory? createWritableFixtureDirectory(List<String> candidates) {
  for (final candidate in candidates) {
    final dir = Directory(candidate);
    final existing = dir.existsSync();
    if (existing && dir.listSync().isNotEmpty) {
      continue; // Never reuse a populated fixture directory.
    }
    try {
      dir.createSync(recursive: true);
      final marker = File('${dir.path}/.probe');
      marker.writeAsStringSync('vital-perf-fixture');
      marker.deleteSync();
      return dir;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Obtains the current refresh rate in Hz from the primary view's display.
/// Returns null when the platform cannot report it truthfully.
double? readRefreshRateHz() {
  try {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    final rate = views.first.display.refreshRate;
    if (!rate.isFinite || rate < 20 || rate > 500) return null;
    return rate;
  } catch (_) {
    return null;
  }
}

/// Reads text scale from the platform dispatcher (1.0 unless the operating
/// system applies an accessibility setting).
double? readSystemTextScale() {
  try {
    final scale = WidgetsBinding.instance.platformDispatcher.textScaleFactor;
    return scale.isFinite && scale > 0 ? scale : null;
  } catch (_) {
    return null;
  }
}

/// Snapshot of process memory (in kB) read from `/proc/self/status`, the one
/// portable, factual, zero-dependency reading available on Android and Linux.
/// Everything else reports an explicit unsupported reason.
({int rssKb, int highWaterKb})? readProcessMemoryKb() {
  try {
    final status = File('/proc/self/status').readAsLinesSync();
    int? value(String prefix) {
      for (final line in status) {
        if (line.startsWith(prefix)) {
          return int.tryParse(
            line.substring(prefix.length).trim().split(' ').first,
          );
        }
      }
      return null;
    }

    final rss = value('VmRSS:');
    final hwm = value('VmHWM:');
    if (rss == null || hwm == null) return null;
    return (rssKb: rss, highWaterKb: hwm);
  } catch (_) {
    return null;
  }
}

/// Patterns for the platform facts the job carries in plain values so the
/// artifact can explain the run. On a device run the runner collects these
/// from `adb getprop`; on the host they come from the environment itself.
Map<String, Object?> collectDeviceFactsForHost() {
  final locale = Platform.localeName;
  final version = Platform.operatingSystemVersion;
  return {'platformVersion': version, 'locale': locale};
}

/// Assembles the condition block the artifact records for every run. Facts
/// the platform cannot report are null with `refreshRateKnown`/source
/// strings explaining the gap; nothing is guessed.
Map<String, Object?> collectConditions({
  required bool appearanceOpaquePreference,
  required bool appearanceReduceMotion,
}) {
  final refresh = readRefreshRateHz();
  final systemScale = readSystemTextScale();
  return {
    'refreshRateHz': refresh,
    'refreshRateKnown': refresh != null,
    'textScaleSystem': systemScale,
    'appearanceOpaquePreference': appearanceOpaquePreference,
    'appearanceReduceMotion': appearanceReduceMotion,
    'systemReduceAnimations': readAccessibilityFlag(
      (features) => features.disableAnimations,
    ),
    'systemHighContrast': readAccessibilityFlag(
      (features) => features.highContrast,
    ),
  };
}

/// The fixture reads the per-view accessibility flags through the implicit
/// view's dispatcher. A flag that cannot be read truthfully reports null and
/// the pump-updated value replaces it once the shell builds its first frame.
bool? readAccessibilityFlag(bool Function(AccessibilityFeatures) pick) {
  try {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    return pick(views.first.platformDispatcher.accessibilityFeatures);
  } catch (_) {
    return null;
  }
}

/// Canonical serialisation helper for the encoded dart-define job plus guard
/// so the fixture only ever accepts a job string with no surrounding bytes.
PerfJob decodePerfJob(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) throw const PerfJobError('job_empty');
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw const PerfJobError('job_not_json');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const PerfJobError('job_not_object');
  }
  return PerfJob.decode(decoded);
}
