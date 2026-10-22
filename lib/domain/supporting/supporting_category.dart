/// One authored or source-supplied category grouping.
///
/// The label is the exact saved text. Nothing is trimmed, case-folded or
/// expanded into a taxonomy: near names stay separate. A blank or absent label
/// is grouped as the single unnamed group, which the interface may present as
/// "Other".
final class SupportingCategoryGroup<T> {
  SupportingCategoryGroup({required this.label, required Iterable<T> values})
    : values = List.unmodifiable(values);
  final String? label;
  final List<T> values;
  bool get isUnnamed => label == null;
  bool get isEmpty => values.isEmpty;
}

/// Groups rows by their saved category while keeping first-appearance order.
///
/// Unnamed rows always form the last group. If every row is unnamed, the result
/// is one unnamed group and callers can omit the redundant "Other" heading.
List<SupportingCategoryGroup<T>> groupSupportingCategories<T>(
  Iterable<T> values,
  String? Function(T value) category,
) {
  final named = <String, List<T>>{};
  final unnamed = <T>[];
  for (final value in values) {
    final label = category(value);
    if (label == null || label.trim().isEmpty) {
      unnamed.add(value);
    } else {
      (named[label] ??= []).add(value);
    }
  }
  return [
    for (final entry in named.entries)
      SupportingCategoryGroup(label: entry.key, values: entry.value),
    if (unnamed.isNotEmpty)
      SupportingCategoryGroup(label: null, values: unnamed),
  ];
}
