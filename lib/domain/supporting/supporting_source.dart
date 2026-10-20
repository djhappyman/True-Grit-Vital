import '../attachments.dart';

/// A saved file can be cited as a source only while it belongs to the named
/// adult, is ready to open, and comes from the current dataset generation.
/// A staging, deleting, other-person or replaced-generation file is not
/// offered, even if an older query still returned it.
bool supportingSourceEligible(
  AttachmentRecord record, {
  required String personId,
  required String generation,
}) =>
    record.personId == personId &&
    record.state == AttachmentState.ready &&
    record.generation == generation;

/// Appends one bounded page without repeating a file already shown.
///
/// Pages are read newest first, so a file saved while browsing can shift the
/// next offset window. Skipping ids already displayed keeps the visible list
/// free of duplicates while the offset still advances by the rows read.
List<AttachmentRecord> mergeSupportingSourcePage(
  List<AttachmentRecord> shown,
  Iterable<AttachmentRecord> page,
) {
  final ids = {for (final record in shown) record.id};
  return [
    ...shown,
    for (final record in page)
      if (ids.add(record.id)) record,
  ];
}
