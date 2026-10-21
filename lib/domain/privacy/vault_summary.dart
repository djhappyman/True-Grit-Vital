/// Current local records, counted independently of collection pagination.
final class VaultSummary {
  const VaultSummary({
    required this.generation,
    required this.substances,
    required this.doses,
    required this.supportingRecords,
    required this.files,
    required this.databaseBytes,
  });

  final String generation;
  final int substances, doses, supportingRecords, files;

  /// Main database plus any current WAL/shared-memory files, or unavailable.
  /// Exported artifacts and backup archives are outside this measurement.
  final int? databaseBytes;
}
