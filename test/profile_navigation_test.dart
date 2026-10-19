import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/features/profiles/profile_pages.dart';

import 'vital_app_test.dart' show appTest, launch, tap;

void main() {
  appTest('first setup Back explains requirement without redirecting', (
    tester,
  ) async {
    await launch(tester, completeSetup: false);
    final originalState = tester.state(find.byType(ProfileForm));
    await tap(tester, 'Back');
    expect(tester.state(find.byType(ProfileForm)), same(originalState));
    expect(find.textContaining('select Save to open Today'), findsOneWidget);
    await tap(tester, 'Adult confirmed');
    await tap(tester, 'Save');
    expect(find.text('Today'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
