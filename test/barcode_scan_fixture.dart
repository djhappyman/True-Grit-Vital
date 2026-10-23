import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/barcode_scan_panel.dart';
import 'package:true_grit_vital/features/recording/quick_record_sheet.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/app_auth.dart';
import 'package:true_grit_vital/platform/barcode_camera.dart';

Future<void> loadBarcodeFonts() async {
  await (FontLoader('StitchSans')
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
      .load();
  await (FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
      .load();
  await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
        rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
      ))
      .load();
}

final class BarcodeCameraProbe {
  ValueChanged<List<String>>? detected;
  ValueChanged<BarcodeCameraFailure>? failure;
  int mounts = 0;
  int disposed = 0;

  Widget build({
    required ValueChanged<List<String>> onDetected,
    required ValueChanged<BarcodeCameraFailure> onFailure,
    required Widget loading,
  }) {
    detected = onDetected;
    failure = onFailure;
    mounts++;
    return _FakeCamera(probe: this);
  }
}

class _FakeCamera extends StatefulWidget {
  const _FakeCamera({required this.probe});
  final BarcodeCameraProbe probe;
  @override
  State<_FakeCamera> createState() => _FakeCameraState();
}

class _FakeCameraState extends State<_FakeCamera> {
  @override
  void dispose() {
    widget.probe.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(
    key: ValueKey('barcode-fake-camera'),
    child: ColoredBox(
      color: Color(0xff20242a),
      child: Center(
        child: Text(
          'Synthetic camera preview',
          style: TextStyle(color: Color(0xffffffff)),
        ),
      ),
    ),
  );
}

class TestAppLock extends AppLockController {
  void reopenForTest() => state = state.copy(locked: false);
  @override
  AppLockState build() => const AppLockState(
    ready: true,
    enabled: true,
    locked: false,
    availability: AppAuthAvailability.available,
  );
}

final class NoLockAuth implements AppAuthGateway {
  @override
  Future<AppAuthAvailability> availability() async =>
      AppAuthAvailability.unsupported;
  @override
  Future<AppAuthResult> authenticate() async => AppAuthResult.cancelled;
  @override
  Future<void> setPrivacyEnabled(bool enabled) async {}
}

Future<void> settleBarcode(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<Directory> barcodeDirectory(WidgetTester tester) async => (await tester
    .runAsync(() => Directory.systemTemp.createTemp('vital-barcode-ui-')))!;

Future<RecordStore> openBarcodeStore(
  WidgetTester tester,
  Directory directory,
) async => (await tester.runAsync(
  () => RecordStore.open(
    path: '${directory.path}/records.db',
    key: List.generate(32, (i) => i + 11),
    isNew: true,
  ),
))!;

Future<ProviderContainer> pumpBarcodePanel(
  WidgetTester tester, {
  required RecordStore store,
  required BarcodeCameraProbe probe,
  bool Function(SubstanceItem item)? onUse,
  VoidCallback? onClose,
  AppLockController Function()? lockFactory,
  ProviderListenable<RecordStore>? storeSource,
  GlobalKey? captureKey,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final source = storeSource ?? Provider<RecordStore>((ref) => store);
  final container = ProviderContainer(
    overrides: [
      recordStoreProvider.overrideWith((ref) async => ref.watch(source)),
      barcodeCameraBuilderProvider.overrideWithValue(probe.build),
      appAuthGatewayProvider.overrideWithValue(NoLockAuth()),
      if (lockFactory != null) appLockProvider.overrideWith(lockFactory),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: captureKey,
        child: ShadcnApp(
          debugShowCheckedModeBanner: false,
          theme: vitalTheme(brightness),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: BarcodeScanPanel(
                  onUse: onUse ?? (_) => true,
                  onClose: onClose ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settleBarcode(tester);
  return container;
}

Future<ProviderContainer> pumpQuickChoice(
  WidgetTester tester, {
  required RecordStore store,
  required BarcodeCameraProbe probe,
}) async {
  final container = ProviderContainer(
    overrides: [
      recordStoreProvider.overrideWith((ref) async => store),
      barcodeCameraBuilderProvider.overrideWithValue(probe.build),
      appAuthGatewayProvider.overrideWithValue(NoLockAuth()),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: vitalTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: Scaffold(
          child: SafeArea(
            child: const QuickRecordSheet(location: '/unplanned'),
          ),
        ),
      ),
    ),
  );
  await settleBarcode(tester);
  return container;
}
