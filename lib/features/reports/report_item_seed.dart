import '../../domain/history/display_time.dart';
import '../../domain/records.dart' show SubstanceItem;
import '../../domain/reports/reports.dart';
import '../../domain/scheduling/daily_plan.dart';

/// Canonical report editor entry point. Reports remain the only selection and
/// generation screen.
const itemReportsLocation = '/reports';

final _itemIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Reads one exact item identifier from a report route.
///
/// An absent parameter means no item seed. A malformed value is rejected rather
/// than treated as an empty selection, because empty [ReportSelection.itemIds]
/// would include every item.
String? reportItemId(String? value) {
  if (value == null || value.isEmpty) return null;
  return _itemIdPattern.hasMatch(value) ? value : null;
}

/// An item is usable only when it still belongs to the report's single owner.
bool reportItemOwnedBy(SubstanceItem? item, String personId) =>
    item != null && item.personId == personId;

enum ItemReportBlock { zoneUnavailable, rangeUnavailable }

sealed class ItemReportPlan {
  const ItemReportPlan();
}

final class ItemReportReady extends ItemReportPlan {
  const ItemReportReady({required this.selection, required this.item});
  final ReportSelection selection;
  final SubstanceItem item;
}

final class ItemReportBlocked extends ItemReportPlan {
  const ItemReportBlocked(this.reason);
  final ItemReportBlock reason;
}

/// Builds the reviewable R01 selection for one existing item.
///
/// The range is the editor's existing default: 1 January in the display year
/// through the current display day, with the current display zone shown. The
/// first dose date is never assumed or used to narrow the range. Unavailable
/// zones and unrepresentable range edges are reported instead of throwing.
ItemReportPlan itemReportPlan({
  required SubstanceItem item,
  required String displayZone,
  required DateTime now,
}) {
  final shown = DisplayTime().instant(now.toUtc(), displayZone);
  if (shown.zoneFallback) {
    return const ItemReportBlocked(ItemReportBlock.zoneUnavailable);
  }
  try {
    final today = shown.civilDate;
    final before = today.addDays(1);
    return ItemReportReady(
      item: item,
      selection: ReportSelection(
        template: ReportTemplateId.r01SubstanceSummary,
        personId: item.personId,
        fromDate: CivilDate(today.year, 1, 1),
        beforeDate: before,
        displayZone: displayZone,
        itemIds: [item.id],
      ),
    );
  } on ReportSelectionFailure {
    return const ItemReportBlocked(ItemReportBlock.rangeUnavailable);
  } catch (_) {
    return const ItemReportBlocked(ItemReportBlock.rangeUnavailable);
  }
}

/// URI-safe location for the existing editor. [returnLocation] keeps the
/// originating overview as the explicit target for a direct link that has no
/// stacked route to pop.
String itemReportLocation({
  required ItemReportReady plan,
  required String returnLocation,
}) {
  final query = Uri(
    queryParameters: {
      'item': plan.item.id,
      'template': 'summary',
      'from': plan.selection.fromDate.toString(),
      'before': plan.selection.beforeDate.toString(),
      'return': returnLocation,
    },
  ).query;
  return '$itemReportsLocation?$query';
}
