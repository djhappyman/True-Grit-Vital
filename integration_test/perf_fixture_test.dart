import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'perf/artifact.dart';
import 'perf/dataset.dart';
import 'perf/environment.dart';
import 'perf/job.dart';
import 'perf/scenarios.dart';

// Vital performance fixture: one opt-in, bounded, self-labelling run.
//
// The file is excluded from ordinary host checks (tool/verify only runs
// `test/`), refuses to execute without the harness job dart-define and never
// touches production storage: the encrypted dataset is created in a
// fixture-only directory that the artifact declares. The fixture selects glass
// or opaque explicitly without changing production preferences or granting
// physical-device acceptance.
//
// Device runs:   tool/performance/measure.py   (physical device, profile)
// Host smoke:    tool/performance/measure.py --host-smoke

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Continuously scheduled real frames: the harness only ever reads
  // engine-reported FrameTimings, never its own pump timings.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const jobDefine = String.fromEnvironment('VITAL_PERF_JOB');
  const hostOut = String.fromEnvironment('VITAL_PERF_HOST_OUT');

  testWidgets('vital performance fixture honours its job', (tester) async {
    if (jobDefine.isEmpty) {
      fail(
        'VITAL_PERF_JOB is unset. Run this fixture only through '
        'tool/performance/measure.py (device or --host-smoke); it is not part '
        'of ordinary host checks and must not decide its own workload.',
      );
    }
    final job = decodePerfJob(jobDefine);

    final dir = createWritableFixtureDirectory(perfFixtureDirCandidates());
    if (dir == null) {
      fail(
        'No writable fixture directory was available; the fixture must never '
        'fall back onto production storage. Report this run as unsupported.',
      );
    }
    final dbPath = '${dir.path}/perf-fixture.sqlite';
    final key = List.generate(32, (i) => i + 1);
    RecordStore? store;
    try {
      final memoryAtStart = readProcessMemoryKb();
      store = await RecordStore.open(path: dbPath, key: key, isNew: true);
      final dataset = await seedPerfDataset(
        store,
        seed: perfDefaultSeed,
        items: job.dataset['items'] as int,
        records: job.dataset['records'] as int,
        containers: job.dataset['containers'] as int,
      );
      // Appearance preferences live in the fixture store, never production.
      await store.writeSetting(
        'appearance',
        jsonEncode({
          'mode': 'system',
          'opaque': false,
          'reduceMotion': job.reduceMotion,
        }),
      );

      var overrides = [
        storeLoaderProvider.overrideWithValue(() async => store!),
      ];
      // Fixture-only glass exercise. The production provider stays untouched;
      // the override lives in this scope and the artifact reports it as
      // fixture-only.
      overrides.add(glassEnabledProvider.overrideWithValue(job.glass));
      final providers = ProviderContainer(overrides: overrides);
      addTearDown(providers.dispose);

      final app = UncontrolledProviderScope(
        container: providers,
        child: const VitalApp(),
      );
      if (job.textScale != null) {
        tester.platformDispatcher.textScaleFactorTestValue = job.textScale!;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      await tester.pumpWidget(app);
      await perfWaitFor(tester, find.text('Today'));

      // The frame budget the SDK jank counters compare against is the
      // actually observed display rate, never a universal 16 ms assertion.
      final conditions = collectConditions(
        appearanceOpaquePreference: false,
        appearanceReduceMotion: job.reduceMotion,
      );
      final refreshRateHz = conditions['refreshRateHz'] as double?;
      final frameBudget = perfFrameBudget(refreshRateHz);
      // The SDK summarizer counts jank against the mutable global
      // `kBuildBudget`; the fixture sets it from the observed display rate so
      // `missed_frame_*_budget_count` matches the declared budget instead of
      // the summarizer's universal 16 ms default.
      kBuildBudget = frameBudget;

      // Measure one scenario after another. Every scenario keeps its own
      // status so one failure never rewrites another's.
      final scenarioResults = <Map<String, dynamic>>[];
      final itemId = dataset.items.first.id;
      for (final key in job.scenarios) {
        final prepared = await _prepareScenario(tester, providers, key, itemId);
        if (!prepared) {
          scenarioResults.add(_unsupported(key, 'prepare_route_dead'));
          continue;
        }
        final memoryBefore = readProcessMemoryKb()?.rssKb;
        try {
          final workload = perfScenarioWorkload(key: key, itemId: itemId);
          await binding.watchPerformance(
            () => workload(
              tester,
              job.repeats,
              (route) => providers.read(routerProvider).go(route),
            ),
            reportKey: 'perf_$key',
          );
          final memoryAfter = readProcessMemoryKb()?.rssKb;
          scenarioResults.add({
            'key': key,
            'status': 'measured',
            'reason': null,
            'repeats': job.repeats,
            'refreshRateHz': refreshRateHz,
            'refreshRateKnown': refreshRateHz != null,
            'frameBudgetMicros': frameBudget.inMicroseconds,
            'memoryBeforeKb': memoryBefore,
            'memoryAfterKb': memoryAfter,
            'frames': Map<String, dynamic>.from(
              binding.reportData!['perf_$key'] as Map,
            ),
          });
        } on PerfScenarioError catch (error) {
          scenarioResults.add(_unsupported(key, error.code));
        } catch (error) {
          scenarioResults.add(_unsupported(key, 'scenario_failed:$error'));
        }
      }

      final artifact = <String, dynamic>{
        'schemaVersion': perfArtifactSchemaVersion,
        'kind': perfArtifactKind,
        'role': switch (job.evidenceClass) {
          'physical_device' => 'measured',
          'emulator' => 'emulator',
          'host_smoke' => 'host_smoke',
          _ => 'selftest',
        },
        'toolVersion': perfHarnessToolVersion,
        'runId': job.runId,
        'createdUtc': DateTime.now().toUtc().toIso8601String(),
        'evidenceClass': job.evidenceClass,
        'buildMode': job.deviceClass == 'host' ? 'host_smoke' : 'profile',
        'host': Map<String, Object?>.from(job.host),
        'device': {
          'deviceClass': job.deviceClass,
          'id': job.deviceId,
          'model': job.deviceFacts['model'],
          'manufacturer': job.deviceFacts['manufacturer'],
          'osRelease': job.deviceFacts['osRelease'],
          'osSdk': job.deviceFacts['osSdk'],
          'isEmulator': job.deviceClass == 'emulator',
        },
        'conditions': conditions,
        'glass': {
          'requested': job.glass,
          'fixtureOnly': true,
          'productionDeviceValidated': false,
          'disclosure': perfGlassDisclosure,
        },
        'fixtureIdentity': {
          'spec': perfFixtureSpec,
          'seed': perfDefaultSeed,
          'dataset': Map<String, Object?>.from(job.dataset),
          'datasetHash': perfDatasetHash(
            spec: perfFixtureSpec,
            seed: perfDefaultSeed,
            items: job.dataset['items'] as int,
            records: job.dataset['records'] as int,
            containers: job.dataset['containers'] as int,
          ),
          'storeGeneration': store.generation,
        },
        'scenarios': scenarioResults,
        'limitations': [
          if (job.glass)
            'Glass surfaces were exercised through the fixture-only provider '
                'override; the composed glass render path still needs human visual '
                'review and performance acceptance on the target device.',
          if (memoryAtStart == null)
            'Process memory reading was unavailable on this host.',
          // The per-scenario jank counts come from the pinned SDK summarizer
          // against the device's reported refresh budget; the tool compares
          // values only when the user explicitly supplies budgets.
          'No numerical budget is bundled with the tool; comparisons run '
              'only against user-supplied budget files.',
        ],
      };

      final encoded = serializePerfArtifact(artifact);
      if (hostOut.isNotEmpty) {
        // Host smoke runs only. Device runs hand the artifact through the
        // driver, which writes this same canonical encoding.
        File(hostOut).writeAsStringSync('$encoded\n');
      } else {
        binding.reportData!['artifact'] = encoded;
        binding.reportData!['runId'] = job.runId;
      }
    } on ArtifactError catch (error) {
      fail('Artifact contract violation: ${error.code}');
    } on PerfJobError catch (error) {
      fail('Invalid fixture job: ${error.code}');
    } finally {
      await store?.close();
      // Remove the fixture's own dataset so the device keeps no synthetic
      // residue; failures here stay visible in the runner report.
      const keepFixtureOnFailure = bool.fromEnvironment(
        'VITAL_PERF_KEEP_FIXTURE',
      );
      if (!keepFixtureOnFailure) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  });
}

/// Navigates to the scenario's route and waits for its landmark. Returns
/// false when the route fails to produce the expected surface, so the run
/// records the scenario as unsupported instead of guessing.
Future<bool> _prepareScenario(
  WidgetTester tester,
  ProviderContainer providers,
  String key,
  String itemId,
) async {
  final route = perfScenarioRoutes(itemId)[key]!;
  providers.read(routerProvider).go(route);
  try {
    await perfWaitFor(tester, perfScenarioLandmark(key, itemId));
    return true;
  } on PerfScenarioError {
    return false;
  }
}

Map<String, dynamic> _unsupported(String key, String reason) => {
  'key': key,
  'status': 'unsupported',
  'reason': reason,
  'repeats': 0,
  'refreshRateHz': null,
  'refreshRateKnown': false,
  'frameBudgetMicros': null,
  'memoryBeforeKb': null,
  'memoryAfterKb': null,
  'frames': null,
};
