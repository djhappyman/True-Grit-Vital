import 'report_selection.dart';

/// Template-specific input captured with the shared, immutable report
/// snapshot. R01 needs none. R02 carries a ledger and R03 an event review.
///
/// The payload is captured together with [ReportSnapshot.selection] and
/// cutoff so the same selection identity never renders two different bodies.
abstract interface class ReportTemplateData {
  ReportTemplateId get template;
}

/// Immutable identity and display attributes for one tracked item.
///
/// Plan occurrences and skipped actions do not store a form or type, so the
/// ledger needs this separately captured item identity rather than inventing
/// defaults.
final class ReportItemDescriptor {
  ReportItemDescriptor({
    required this.itemId,
    required this.name,
    required this.form,
    required this.type,
    required this.unit,
  }) {
    if (itemId.isEmpty || name.trim().isEmpty || unit.trim().isEmpty) {
      throw const ReportSelectionFailure('report_item_descriptor');
    }
  }
  final String itemId, name, form, type, unit;
}
