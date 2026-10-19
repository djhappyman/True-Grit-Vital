import '../scheduling/daily_plan.dart' show CivilDate;
import 'supporting_value.dart';

enum SupportingDatePrecision { unknown, exact, day, partial }

/// Precision and source zone are provenance, independent of app entry time.
final class SupportingDate {
  factory SupportingDate.unknown({String? originalText}) => SupportingDate._(
    SupportingDatePrecision.unknown,
    originalText: originalText,
  );
  factory SupportingDate.exact(
    DateTime instant, {
    required String zoneId,
    required int utcOffsetMinutes,
    String? originalText,
  }) {
    if (!instant.isUtc) throw ArgumentError('supporting_date_utc');
    supportingText(zoneId, 'supporting_date_zone', max: 256);
    if (utcOffsetMinutes.abs() > 24 * 60) {
      throw ArgumentError('supporting_date_offset');
    }
    return SupportingDate._(
      SupportingDatePrecision.exact,
      instant: instant,
      zoneId: zoneId,
      utcOffsetMinutes: utcOffsetMinutes,
      originalText: originalText,
    );
  }
  factory SupportingDate.day(
    CivilDate date, {
    String? zoneId,
    String? originalText,
  }) => SupportingDate._(
    SupportingDatePrecision.day,
    civilDate: date,
    zoneId: zoneId,
    originalText: originalText,
  );
  factory SupportingDate.partial({
    int? year,
    int? month,
    required String originalText,
  }) {
    supportingText(originalText, 'supporting_partial_date');
    if (year != null && (year < 1 || year > 9999) ||
        month != null && (month < 1 || month > 12)) {
      throw ArgumentError('supporting_partial_date');
    }
    return SupportingDate._(
      SupportingDatePrecision.partial,
      year: year,
      month: month,
      originalText: originalText,
    );
  }
  SupportingDate._(
    this.precision, {
    this.instant,
    this.civilDate,
    this.zoneId,
    this.utcOffsetMinutes,
    this.year,
    this.month,
    this.originalText,
  }) {
    supportingOptionalText(originalText, 'supporting_date_text');
    supportingOptionalText(zoneId, 'supporting_date_zone', max: 256);
  }
  final SupportingDatePrecision precision;
  final DateTime? instant;
  final CivilDate? civilDate;
  final String? zoneId, originalText;
  final int? utcOffsetMinutes, year, month;
  bool get isPositionable =>
      precision == SupportingDatePrecision.day ||
      precision == SupportingDatePrecision.exact;
  Map<String, Object?> toJson() => {
    'precision': precision.name,
    'instant': instant?.microsecondsSinceEpoch,
    'civilDate': civilDate?.toString(),
    'zoneId': zoneId,
    'utcOffsetMinutes': utcOffsetMinutes,
    'year': year,
    'month': month,
    'originalText': originalText,
  };
  factory SupportingDate.fromJson(Map<String, dynamic> json) =>
      switch (SupportingDatePrecision.values.byName(
        json['precision'] as String,
      )) {
        SupportingDatePrecision.unknown => SupportingDate.unknown(
          originalText: json['originalText'] as String?,
        ),
        SupportingDatePrecision.exact => SupportingDate.exact(
          DateTime.fromMicrosecondsSinceEpoch(
            json['instant'] as int,
            isUtc: true,
          ),
          zoneId: json['zoneId'] as String,
          utcOffsetMinutes: json['utcOffsetMinutes'] as int,
          originalText: json['originalText'] as String?,
        ),
        SupportingDatePrecision.day => SupportingDate.day(
          CivilDate.parse(json['civilDate'] as String),
          zoneId: json['zoneId'] as String?,
          originalText: json['originalText'] as String?,
        ),
        SupportingDatePrecision.partial => SupportingDate.partial(
          year: json['year'] as int?,
          month: json['month'] as int?,
          originalText: json['originalText'] as String,
        ),
      };
}
