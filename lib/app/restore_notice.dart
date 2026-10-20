import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/restore/restore.dart';

/// One startup recovery result, kept in memory only. Settings/help can show a
/// truthful notice; the value is cleared when the user acknowledges it.
final restoreRecoveryNoticeProvider =
    NotifierProvider<RestoreRecoveryNotice, RestoreRecovery?>(
      RestoreRecoveryNotice.new,
    );

final class RestoreRecoveryNotice extends Notifier<RestoreRecovery?> {
  @override
  RestoreRecovery? build() => null;

  void record(RestoreRecovery recovery) {
    state = recovery;
  }

  void clear() {
    state = null;
  }
}
