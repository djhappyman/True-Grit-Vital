import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

void main() {
  testWidgets('one theme override reaches both surface APIs', (tester) async {
    final theme = vitalTheme(Brightness.light);
    const customCard = Color(0xffd9e9e3);
    await tester.pumpWidget(
      ShadcnApp(
        theme: theme.copyWith(
          colorScheme: () => theme.colorScheme.copyWith(card: () => customCard),
        ),
        home: const Column(
          children: [
            VitalSurface(child: Text('Existing surface')),
            StitchSurface(child: Text('Reference surface')),
          ],
        ),
      ),
    );
    final frames = find.byType(VitalSurfaceFrame);
    expect(frames, findsNWidgets(2));
    for (final frame in frames.evaluate()) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byElementPredicate((e) => e == frame),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, customCard);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(VitalLayout.surfaceRadius),
      );
    }
    expect(StitchType.title, VitalType.title);
    expect(StitchType.body, VitalType.body);
    expect(StitchType.name.fontFamily, 'StitchSans');
  });

  testWidgets('both control APIs keep icon targets at least48 pixels', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadcnApp(
        theme: vitalTheme(Brightness.dark),
        home: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VitalButton.secondary(
                onPressed: () {},
                child: const Icon(LucideIcons.plus),
              ),
              StitchButton(
                compact: true,
                quiet: true,
                onPressed: () {},
                child: const Icon(LucideIcons.settings),
              ),
            ],
          ),
        ),
      ),
    );
    for (final button in find.byType(Button).evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == button));
      expect(size.width, greaterThanOrEqualTo(VitalLayout.target));
      expect(size.height, greaterThanOrEqualTo(VitalLayout.target));
    }
    expect(tester.takeException(), isNull);
  });
}
