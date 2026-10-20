import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/privacy/settings_capabilities.dart';

void main() {
  test('defaults expose no dependent data capability', () {
    const capabilities = SettingsCapabilities.none();
    expect(capabilities.hasReports, false);
    expect(capabilities.hasExports, false);
    expect(capabilities.hasBackup, false);
    expect(capabilities.hasRestore, false);
    expect(capabilities.hasDataSection, false);
  });

  test('only in-app absolute routes count as available', () {
    const capabilities = SettingsCapabilities(
      reportsPath: '/reports',
      exportsPath: 'exports',
      backupPath: '//host/path',
      restorePath: ' /restore',
    );
    expect(capabilities.hasReports, true);
    expect(capabilities.hasExports, false);
    expect(capabilities.hasBackup, false);
    expect(capabilities.hasRestore, false);
    expect(capabilities.hasDataSection, true);
  });
}
