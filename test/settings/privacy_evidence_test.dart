import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/domain/privacy/licences.dart';

/// Source-level privacy regression checks for native surfaces that the Flutter
/// test runner cannot exercise on this host. These assert the implemented
/// contract, not a device result.
void main() {
  test(
    'Android hides app-switcher previews and toggles protection honestly',
    () {
      final source = File(
        'android/app/src/main/kotlin/dev/truegrit/vital/MainActivity.kt',
      ).readAsStringSync();
      expect(source, contains('FLAG_SECURE'));
      expect(source, contains('setRecentsScreenshotEnabled(false)'));
      expect(source, contains('setRecentsScreenshotEnabled(!enabled)'));
    },
  );

  test('reminder notification text carries no person, product or quantity', () {
    final strings = File('android/app/src/main/res/values/strings.xml')
        .readAsStringSync();
    expect(strings, contains('<string name="reminder_title">Vital</string>'));
    expect(
      strings,
      contains(
        '<string name="reminder_body">Open Vital to review a reminder.</string>',
      ),
    );
    expect(strings, isNot(contains('{person}')));
    expect(strings, isNot(contains('{name}')));
    expect(strings, isNot(contains('{amount}')));
    final engine = File(
      'android/app/src/main/kotlin/dev/truegrit/vital/Reminders.kt',
    ).readAsStringSync();
    expect(engine, contains('Notification.VISIBILITY_PRIVATE'));
    expect(engine, contains('R.string.reminder_title'));
    expect(engine, contains('R.string.reminder_body'));
  });

  test('settings support surface contains no remote diagnostic sender', () {
    final files = Directory('lib/features/settings')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('dart:io')));
      expect(source, isNot(contains('HttpClient')));
      expect(source, isNot(contains('package:http')));
      expect(source, isNot(contains('Uri.parse')));
    }
  });

  test(
    'bundled application and package notices load from declared assets',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final application = await rootBundle.loadString(applicationLicenceAsset);
      expect(application, contains('MIT License'));
      final notices = decodeLicenceNotices(
        await rootBundle.loadString(adoptedNoticesAsset),
      );
      expect(notices.length, greaterThan(40));
      expect(notices.any((notice) => notice.title.contains('crypto')), isTrue);
    },
  );
}
