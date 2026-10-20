import '../fixtures/single_user.dart';

import 'package:flutter/foundation.dart' show Key, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/privacy.dart';

import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

Future<void> tapKey(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  appTest(
    'failed data-management write preserves records and logs a redacted code',
    (tester) async {
      final f = await launch(tester, privacyActions: _FailingPrivacyActions());
      final a = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: 'failure-adult',
          name: 'Alex Example',
          adultConfirmed: true,
        ),
      ))!;
      await tap(tester, 'Settings');
      await tap(tester, 'Privacy');
      await tapKey(tester, const ValueKey('privacy-delete-me'));
      await tap(tester, 'Delete');

      expect(
        find.text(
          'Could not confirm the change. Review your records before trying again.',
        ),
        findsOneWidget,
      );
      final current = (await runIo(tester, () => f.store.profileById(a.id)))!;
      expect(current.isArchived, false);
      final diagnostics = await runIo(
        tester,
        () => f.store.readSetting('privacy_diagnostics_v1'),
      );
      expect(diagnostics, contains('profile_delete'));
      expect(diagnostics, isNot(contains('Alex Example')));
    },
  );
}

final class _FailingPrivacyActions implements ProfilePrivacyActions {
  Never _fail() => throw StateError('synthetic_privacy_failure');

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async => _fail();
}
