import '../stock/stock_widgets.dart' show stockRecordAmountNumber;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../substances/substance_collection.dart';
import 'record_pages.dart';

/// One task route: searchable identity choice, minimal creation or the existing
/// durable dose editor. Changing steps never stacks task sheets.
class QuickRecordSheet extends ConsumerStatefulWidget {
  const QuickRecordSheet({super.key, required this.location});
  final String location;
  @override
  ConsumerState<QuickRecordSheet> createState() => _QuickRecordSheetState();
}

class _QuickRecordSheetState extends ConsumerState<QuickRecordSheet> {
  final search = TextEditingController();
  int offset = 0;
  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() => offset = 0));
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final parameters = Uri.parse(widget.location).queryParameters;
    final day = DateTime.tryParse(parameters['day'] ?? '');
    final selected = day == null || day.year < 1 || day.year > 9999
        ? null
        : CivilDate.fromDateTime(day);
    final plan = parameters['plan'] == '1';
    final time =
        RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$')
            .hasMatch(parameters['time'] ?? '')
        ? parameters['time']
        : null;
    if (parameters['new'] == '1') {
      return ItemForm(
        key: ValueKey(widget.location),
        quick: true,
        day: selected,
        plan: plan,
        initialTime: time,
      );
    }
    if (parameters['item'] case final id?) {
      return DoseForm(
        key: ValueKey(id),
        itemId: id,
        initialDay: selected,
        returnLocation: '/today',
      );
    }
    final query = SubstancesPageQuery(
      scope: const FeedScope.me(),
      search: search.text.trim(),
      typeId: '',
      offset: offset,
    );
    final items = ref.watch(substancesPageProvider(query));
    return EntryPage(
      panelled: false,
      children: [
        Heading(plan ? t.dashboardPlanTitle : t.dashboardQuickTitle),
        Text(
          plan ? t.dashboardPlanHelp : t.dashboardQuickHelp,
          style: StitchType.caption,
        ),
        const SizedBox(height: 16),
        LabelledInput(label: t.search, controller: search),
        const SizedBox(height: 8),
        VitalButton.secondary(
          leading: const Icon(LucideIcons.plus),
          onPressed: () => context.replace(
            Uri(
              path: '/unplanned',
              queryParameters: {
                'new': '1',
                if (plan) 'plan': '1',
                'time': ?time,
                if (selected != null) 'day': selected.toString(),
              },
            ).toString(),
          ),
          child: Text(t.create),
        ),
        const SizedBox(height: 16),
        if (items.isLoading)
          Text(t.loadingRecords)
        else if (items.hasError)
          LoadFailure(
            onRetry: () => ref.invalidate(substancesPageProvider(query)),
          )
        else ...[
          for (final item in items.requireValue.take(50)) ...[
            VitalButton.secondary(
              multiline: true,
              onPressed: () => plan
                  ? context.replace(
                      Uri(
                        path: '/schedule/${item.id}',
                        queryParameters: {
                          if (selected != null) 'start': selected.toString(),
                          'time': ?time,
                        },
                      ).toString(),
                    )
                  : context.replace(
                      Uri(
                        path: '/unplanned',
                        queryParameters: {
                          'item': item.id,
                          if (selected != null) 'day': selected.toString(),
                        },
                      ).toString(),
                    ),
              child: Text(item.name),
            ),
            const SizedBox(height: 8),
          ],
          if (items.requireValue.isEmpty)
            Text(t.historyNoOptions, style: StitchType.caption),
          if (items.requireValue.length > 50)
            VitalButton.secondary(
              onPressed: () => setState(() => offset += 50),
              child: Text(t.more),
            ),
          if (offset > 0)
            VitalButton.secondary(
              onPressed: () =>
                  setState(() => offset = (offset - 50).clamp(0, offset)),
              child: Text(t.back),
            ),
        ],
      ],
    );
  }
}

typedef UnplannedDay = ({CivilDate day, String zone, int limit});
final unplannedDayProvider = StreamProvider.autoDispose
    .family<List<UseRecord>, UnplannedDay>(retry: (_, _) => null, (
      ref,
      request,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      final bounds = DisplayTime().dayBounds(request.day, request.zone);
      yield* store.watchUnplannedUses(
        from: bounds.start,
        before: bounds.endExclusive,
        limit: request.limit,
      );
    });

class UnplannedMedication extends ConsumerStatefulWidget {
  const UnplannedMedication({
    super.key,
    required this.day,
    required this.today,
  });
  final CivilDate day, today;
  @override
  ConsumerState<UnplannedMedication> createState() =>
      _UnplannedMedicationState();
}

class _UnplannedMedicationState extends ConsumerState<UnplannedMedication> {
  int limit = 51;
  @override
  void didUpdateWidget(UnplannedMedication oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) limit = 51;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final query = (
      day: widget.day,
      zone: ref.watch(displayZoneProvider),
      limit: limit,
    );
    final records = ref.watch(unplannedDayProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StitchSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t.dashboardUnplanned, style: StitchType.name),
                  ),
                  Semantics(
                    label: t.dashboardUnplannedHelp,
                    button: true,
                    child: StitchButton(
                      quiet: true,
                      compact: true,
                      onPressed: () => showVitalDialog<void>(
                        context: context,
                        builder: (context) => VitalDialog(
                          title: Text(t.dashboardUnplanned),
                          content: Text(t.dashboardUnplannedHelp),
                          actions: [
                            VitalButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(t.done),
                            ),
                          ],
                        ),
                      ),
                      child: const Icon(LucideIcons.info, size: 20),
                    ),
                  ),
                ],
              ),
              Text(
                t.dashboardUnplannedSubtitle,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              if (records.isLoading)
                Text(t.loadingRecords, style: StitchType.caption)
              else if (records.hasError)
                LoadFailure(
                  onRetry: () => ref.invalidate(unplannedDayProvider(query)),
                )
              else if (records.requireValue.isEmpty)
                Text(
                  widget.day == widget.today
                      ? t.dashboardUnplannedEmptyToday
                      : t.dashboardUnplannedEmptyDay,
                  style: StitchType.caption.copyWith(color: c.muted),
                )
              else
                for (final record in records.requireValue.take(limit - 1)) ...[
                  StitchSurface(
                    inset: true,
                    padding: EdgeInsets.zero,
                    radius: VitalLayout.sectionRadius,
                    child: VitalCompactRow(
                      title: record.name,
                      subtitle:
                          '${stockRecordAmountNumber(t, record)} ${record.actualUnit}',
                      onPressed: () => context.push('/correct/${record.id}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              if (records.hasValue &&
                  !records.isLoading &&
                  records.requireValue.length == limit)
                if (limit < 500)
                  VitalButton.secondary(
                    onPressed: () =>
                        setState(() => limit = (limit + 50).clamp(1, 500)),
                    child: Text(t.more),
                  )
                else
                  VitalButton.secondary(
                    onPressed: () => context.push('/history'),
                    child: Text(t.history),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StitchButton(
          outlined: true,
          icon: LucideIcons.plus,
          onPressed: () => context.push('/unplanned?day=${widget.day}'),
          child: Text(t.add),
        ),
      ],
    );
  }
}
