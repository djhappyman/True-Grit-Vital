import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';
import 'package:true_grit_vital/features/supporting/supporting_widgets.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

Widget host(
  Widget child, {
  Size size = const Size(360, 900),
  double scale = 1,
}) => ShadcnApp(
  theme: vitalTheme(Brightness.light),
  locale: const Locale('en', 'GB'),
  supportedLocales: const [Locale('en', 'GB')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: SingleChildScrollView(
      child: VitalComponentThemes(
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      ),
    ),
  ),
);

LabResultSnapshot numeric({String value = '0', String? unit = 'mg/L'}) =>
    LabResultSnapshot(
      id: 'result',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric(value),
      unit: unit,
      referenceRange: unit == null
          ? null
          : SourceReferenceRange(originalText: '3 to 7'),
    );

void main() {
  testWidgets('zero, a missing result and a missing unit stay distinct', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            SupportingResultView(
              key: const ValueKey('zero'),
              result: numeric(),
            ),
            SupportingResultView(
              key: const ValueKey('missing'),
              result: LabResultSnapshot(
                id: 'missing',
                metricId: 'metric',
                markerName: 'Missing marker',
                originalMarkerText: 'Missing marker',
                value: SupportingValue.missing(),
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('0 mg/L'), findsOneWidget);
    expect(find.text('3 to 7'), findsNothing);
    expect(find.text('Source range: 3 to 7'), findsOneWidget);
    expect(find.text('Range not supplied.'), findsOneWidget);
    expect(find.text('No result supplied.'), findsOneWidget);
    expect(find.text('Unit not supplied.'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('missing result with source words keeps words and unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SupportingResultView(
          result: LabResultSnapshot(
            id: 'missing',
            metricId: 'metric',
            markerName: 'Marker',
            originalMarkerText: 'Marker',
            value: SupportingValue.missing(originalText: 'Not detected'),
            unit: 'mg/L',
          ),
        ),
      ),
    );
    expect(find.text('No result supplied.'), findsOneWidget);
    expect(find.text('Not detected mg/L'), findsOneWidget);
    expect(find.text('Unit not supplied.'), findsNothing);
    expect(find.text('Source range: null'), findsNothing);
    expect(find.text('Range not supplied.'), findsOneWidget);
  });

  testWidgets('long names and values wrap at 320 pixels and 200 percent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const marker =
        'Very long original marker name with a source qualifier and method';
    const unit = 'very-long-original-unit-name';
    const range =
        'Laboratory supplied source range with several words and a limit';
    await tester.pumpWidget(
      host(
        SupportingResultView(
          result: LabResultSnapshot(
            id: 'long',
            metricId: 'metric',
            markerName: marker,
            originalMarkerText: marker,
            value: SupportingValue.numeric('12345.6789'),
            unit: unit,
            referenceRange: SourceReferenceRange(originalText: range),
            sourceFlag: 'Source supplied flag',
          ),
        ),
        size: const Size(320, 800),
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(marker), findsWidgets);
    expect(find.textContaining(range), findsOneWidget);
    expect(find.textContaining('12345.6789 $unit'), findsOneWidget);
  });

  testWidgets('source flags remain accessible beside the result summary', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(
          SupportingResultView(
            result: LabResultSnapshot(
              id: 'flagged',
              metricId: 'metric',
              markerName: 'Marker',
              value: SupportingValue.numeric('4'),
              sourceFlag: 'Original source flag',
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('Original source flag')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('result row exposes complete accessible marker and values', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(SupportingResultView(result: numeric(value: '-0'))),
    );
    final label = find.bySemanticsLabel('-0 mg/L');
    expect(label, findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Marker\. Original value: -0\. Unit: mg/L\. '
          r'Source range: 3 to 7\.',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
