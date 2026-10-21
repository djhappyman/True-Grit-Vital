import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../domain/reports/report_period.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

final vaultSummaryProvider = StreamProvider.autoDispose<VaultSummary>(
  retry: (_, _) => null,
  (ref) async* {
    if (ref.watch(appLockProvider.select((state) => state.locked))) return;
    final store = await ref.watch(recordStoreProvider.future);
    yield* store.watchVaultSummary();
  },
);

/// A testable device-local civil clock; no dosing/reminder clock is changed.
final settingsDateClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class SettingsVaultSummary extends ConsumerWidget {
  const SettingsVaultSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appLockProvider.select((state) => state.locked))) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    return ref
        .watch(vaultSummaryProvider)
        .when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: false,
          loading: () => Text(t.loadingRecords, style: VitalType.metadata),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.featureVaultFailed),
              VitalButton.secondary(
                onPressed: () => ref.invalidate(vaultSummaryProvider),
                child: Text(t.retry),
              ),
            ],
          ),
          data: (summary) {
            final locale = Localizations.localeOf(context).toLanguageTag();
            final numbers = NumberFormat.decimalPattern(locale);
            final bytes = summary.databaseBytes;
            var value = t.featureVaultUnavailable;
            if (bytes != null) {
              var amount = bytes.toDouble();
              var unit = 0;
              while (amount >= 1024 && unit < 3) {
                amount /= 1024;
                unit++;
              }
              value = unit == 0
                  ? t.featureVaultExactBytes(numbers.format(bytes))
                  : t.featureVaultSize(
                      NumberFormat('#,##0.0', locale).format(amount),
                      ['', 'KiB', 'MiB', 'GiB'][unit],
                    );
            }
            final metrics = [
              (t.substances, summary.substances),
              (t.featureVaultDoses, summary.doses),
              (t.supportingRecordsHeading, summary.supportingRecords),
              (t.attachments, summary.files),
            ];
            return VitalSurfaceFrame(
              inset: true,
              radius: VitalLayout.sectionRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.featureVaultTitle, style: VitalType.section),
                  const SizedBox(height: 12),
                  Semantics(
                    label: t.featureVaultDatabase,
                    value: bytes == null
                        ? t.featureVaultUnavailable
                        : t.featureVaultExactBytes(numbers.format(bytes)),
                    child: ExcludeSemantics(
                      child: VitalMetric(
                        label: t.featureVaultDatabase,
                        value: value,
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 280 &&
                              MediaQuery.textScalerOf(context).scale(14) <= 21
                          ? 2
                          : 1;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final (label, count) in metrics)
                            SizedBox(
                              width:
                                  (constraints.maxWidth - 12 * (columns - 1)) /
                                  columns,
                              child: VitalMetric(
                                label: label,
                                value: numbers.format(count),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(t.featureVaultCountsHelp, style: VitalType.metadata),
                  Text(t.featureVaultBody, style: VitalType.metadata),
                ],
              ),
            );
          },
        );
  }
}

class SettingsReportDates extends ConsumerStatefulWidget {
  const SettingsReportDates({super.key, required this.reportsPath});
  final String reportsPath;
  @override
  ConsumerState<SettingsReportDates> createState() =>
      _SettingsReportDatesState();
}

class _SettingsReportDatesState extends ConsumerState<SettingsReportDates> {
  ReportPeriod period = ReportPeriod.thirtyDays;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final today = CivilDate.fromDateTime(
      ref.watch(settingsDateClockProvider)(),
    );
    final dates = reportPeriodDates(today, period);
    final range = t.featureVaultRange(
      dates.from.toString(),
      dates.before.addDays(-1).toString(),
    );
    final descriptions = [
      t.featureVaultThirtyLabel,
      t.featureVaultNinetyLabel,
      t.featureVaultYearLabel,
    ];
    return VitalSurfaceFrame(
      inset: true,
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.featureVaultReportDates, style: VitalType.section),
          const SizedBox(height: 12),
          Semantics(
            label: descriptions[period.index],
            child: VitalSegments<ReportPeriod>(
              values: ReportPeriod.values,
              selected: period,
              onChanged: (value) => setState(() => period = value),
              label: (value) => [
                t.featureVaultThirty,
                t.featureVaultNinety,
                t.featureVaultYear,
              ][value.index],
            ),
          ),
          const SizedBox(height: 12),
          Text(range, style: VitalType.metadata),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalButton.secondary(
              onPressed: () {
                final base = Uri.parse(widget.reportsPath);
                context.push(
                  base
                      .replace(
                        queryParameters: {
                          ...base.queryParameters,
                          'from': dates.from.toString(),
                          'before': dates.before.toString(),
                          'return': '/settings?group=data',
                        },
                      )
                      .toString(),
                );
              },
              leading: const Icon(LucideIcons.fileText),
              child: Text(t.review),
            ),
          ),
        ],
      ),
    );
  }
}
