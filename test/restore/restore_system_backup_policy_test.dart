import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

const _domains = [
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
  'device_root',
  'device_file',
  'device_database',
  'device_sharedpref',
];

List<String> _excluded(String xml, String section) {
  final start = xml.indexOf('<$section>');
  final end = xml.indexOf('</$section>');
  expect(start, greaterThanOrEqualTo(0), reason: section);
  expect(end, greaterThan(start), reason: section);
  final body = xml.substring(start, end);
  expect(body, isNot(contains('<include')));
  return [
    for (final match in RegExp(
      r'<exclude\s+domain="([^"]+)"\s+path="([^"]+)"\s*/>',
    ).allMatches(body))
      '${match.group(1)}:${match.group(2)}',
  ]..sort();
}

void main() {
  test('Android backup and device transfer still exclude the whole app', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('@xml/backup_rules'));
    expect(manifest, contains('@xml/data_extraction_rules'));

    final expected = [for (final domain in _domains) '$domain:.']..sort();
    final fullBackup = File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsStringSync();
    expect(_excluded(fullBackup, 'full-backup-content'), expected);

    final extraction = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(_excluded(extraction, 'cloud-backup'), expected);
    expect(_excluded(extraction, 'device-transfer'), expected);
  });

  test('Android dataset and restore staging stay in noBackupFilesDir', () {
    final source = File(
      'android/app/src/main/kotlin/dev/truegrit/vital/SecureStorage.kt',
    ).readAsStringSync();
    expect(source, contains('context.noBackupFilesDir'));
    expect(source, isNot(contains('context.filesDir')));
    // The restore directory is a sibling of the encrypted database, never a
    // world-visible or cloud-backed location.
    final activation = RestoreActivation(
      databasePath: '/synthetic/vital/records.sqlite',
    );
    expect(activation.restoreDirectory, '/synthetic/vital/restore');
  });
}
