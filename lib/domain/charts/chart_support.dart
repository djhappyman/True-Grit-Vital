import 'chart_limits.dart';

/// Shared identity validation for the chart domain.
///
/// These helpers stay out of the public barrel; callers use the typed models.
void chartRequireText(String value, String code, {int maxLength = 256}) {
  if (value.isEmpty || value.trim().isEmpty || value.length > maxLength) {
    throw ChartModelException(code);
  }
}

void chartRequireOptionalText(
  String? value,
  String code, {
  int maxLength = 256,
}) {
  if (value != null) chartRequireText(value, code, maxLength: maxLength);
}

void chartRequireUtc(DateTime value, String code) {
  if (!value.isUtc || value.year < 1 || value.year > 9999) {
    throw ChartRangeException(code);
  }
}
