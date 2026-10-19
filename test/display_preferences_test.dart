import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, runIo, settle;

final shownInstant = DateTime.utc(2026, 7, 1, 13, 30, 45);

class TimeProbe extends ConsumerWidget {
  const TimeProbe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLockProvider);
    return Column(
      children: [
        const TimeFormatSettings(),
        Text(displayStamp(context, ref, shownInstant), key: const Key('shown')),
        Text(
          displayWallTime(context, ref, WallTime(14, 30)),
          key: const Key('wall'),
        ),
        Text(
          displayStamp(
            context,
            ref,
            shownInstant,
            zoneId: 'UTC',
            includeSeconds: true,
          ),
          key: const Key('utc'),
        ),
        Text(
          displayStamp(context, ref, shownInstant, zoneId: 'Invalid/Zone'),
          key: const Key('fallback'),
        ),
      ],
    );
  }
}

Widget host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: ShadcnApp(
    theme: vitalTheme(Brightness.dark),
    locale: const Locale('en', 'GB'),
    supportedLocales: const [Locale('en', 'GB')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const VitalComponentThemes(child: TimeProbe()),
  ),
);

void main() {
  test(
    'exact zone offsets distinguish repeated clocks without changing instants',
    () {
      final display = DisplayTime();
      final before = display.instant(
        DateTime.utc(2026, 10, 25, 0, 30),
        'Europe/London',
      );
      final after = display.instant(
        DateTime.utc(2026, 10, 25, 1, 30),
        'Europe/London',
      );
      // Zone formatting is independent from localised time output.
      final formatter = DisplayTimeFormatter(
        localizations: const DefaultMaterialLocalizations(),
        preference: TimeFormat.h24,
        systemUses24Hour: true,
      );
      expect(formatter.time(before), formatter.time(after));
      expect(formatter.zoneWithOffset(before), 'Europe/London (UTC+01:00)');
      expect(formatter.zoneWithOffset(after), 'Europe/London (UTC+00:00)');
      expect(before.instant, DateTime.utc(2026, 10, 25, 0, 30));
      expect(after.instant, DateTime.utc(2026, 10, 25, 1, 30));
    },
  );
  appTest(
    'shared format updates exact instants and wall summaries and survives restart',
    (tester) async {
      final directory = (await runIo(
        tester,
        () => Directory.systemTemp.createTemp('vital-time-format-'),
      ))!;
      final path = '${directory.path}/db';
      final key = List.generate(32, (i) => i + 1);
      var store = (await runIo(
        tester,
        () => RecordStore.open(path: path, key: key, isNew: true),
      ))!;
      ProviderContainer createContainer() => ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
        ],
      );
      var container = createContainer();
      addTearDown(() async {
        container.dispose();
        await store.close();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(host(container));
      await settle(tester);
      await tester.tap(find.text('12-hour'));
      await settle(tester);
      expect(
        container.read(displayPreferencesProvider).timeFormat,
        TimeFormat.h12,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('shown'))).data,
        contains('2:30 PM, Europe/London'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('wall'))).data,
        '2:30 PM',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('utc'))).data,
        contains('1:30:45 PM, UTC'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('fallback'))).data,
        contains('1:30 PM, UTC'),
      );
      expect(find.byType(OutlineButton), findsNothing);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('12-hour')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      semantics.dispose();
      expect(
        (await runIo(tester, () => store.readSetting('display')))!,
        contains('h12'),
      );

      // Reopen the encrypted dataset with a fresh provider tree, rather than
      // carrying the in-memory preference into the restart assertion.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await runIo(tester, store.close);
      store = (await runIo(
        tester,
        () => RecordStore.open(path: path, key: key, isNew: false),
      ))!;
      container = createContainer();
      await tester.pumpWidget(host(container));
      await settle(tester);
      expect(
        container.read(displayPreferencesProvider).timeFormat,
        TimeFormat.h12,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('shown'))).data,
        contains('2:30 PM, Europe/London'),
      );
      await tester.tap(find.text('24-hour'));
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('shown'))).data,
        contains('14:30, Europe/London'),
      );
      expect(tester.widget<Text>(find.byKey(const Key('wall'))).data, '14:30');
      expect(
        tester.widget<Text>(find.byKey(const Key('utc'))).data,
        contains('13:30:45, UTC'),
      );
      expect(shownInstant, DateTime.utc(2026, 7, 1, 13, 30, 45));
      expect(tester.takeException(), isNull);
    },
  );
}
