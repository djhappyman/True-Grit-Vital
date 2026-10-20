import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

import '../../domain/supporting/supporting_value.dart';

/// Reads the current locale's decimal and grouping marks for exact entry.
///
/// The app never rewrites the saved source text. These marks only let exact
/// entry accept the same number the person would type in their own locale.
/// A missing or unsupported locale falls back to the ASCII marks.
SupportingNumberFormat supportingNumberFormat(BuildContext context) {
  try {
    final symbols = intl.NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).symbols;
    return SupportingNumberFormat(
      decimalSeparator: symbols.DECIMAL_SEP,
      groupSeparator: symbols.GROUP_SEP,
    );
  } catch (_) {
    return const SupportingNumberFormat();
  }
}
