import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/domain/privacy/settings_capabilities.dart';

void main() {
  test('registered routes expose only present dependent capabilities', () {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/reports', builder: (_, _) => const SizedBox()),
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            GoRoute(path: '/backup', builder: (_, _) => const SizedBox()),
            GoRoute(
              path: '/reports/detail',
              builder: (_, _) => const SizedBox(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    final capabilities = settingsCapabilitiesFor(router);
    expect(capabilities.hasReports, true);
    expect(capabilities.hasBackup, true);
    expect(capabilities.hasExports, false);
    expect(capabilities.hasRestore, false);
  });

  test('explicit injection wins for a concrete integrated route', () {
    final router = GoRouter(
      routes: [GoRoute(path: '/reports', builder: (_, _) => const SizedBox())],
    );
    addTearDown(router.dispose);
    final capabilities = settingsCapabilitiesFor(
      router,
      configured: const SettingsCapabilities(
        reportsPath: '/custom-reports',
        restorePath: '/restore',
      ),
    );
    expect(capabilities.reportsPath, '/custom-reports');
    expect(capabilities.restorePath, '/restore');
    expect(capabilities.exportsPath, isNull);
  });
}
