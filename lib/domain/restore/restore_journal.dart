import 'dart:convert';

import 'restore_models.dart';

enum RestoreJournalPhase { staged, ready, replaced, committed }

/// One durable activation intent. The journal is written to the protected
/// restore directory before the live file is replaced and advanced only after
/// the replacement opens successfully.
final class RestoreJournal {
  const RestoreJournal({
    required this.phase,
    required this.previousGeneration,
    required this.newGeneration,
    required this.previousNamespace,
    required this.reminderNamespace,
    required this.stagedFile,
    required this.rollbackFile,
    required this.databaseFile,
    required this.startedAt,
  });

  static const int version = 1;

  final RestoreJournalPhase phase;
  final String previousGeneration;
  final String newGeneration;
  final String? previousNamespace;
  final String reminderNamespace;
  final String stagedFile;
  final String rollbackFile;
  final String databaseFile;
  final DateTime startedAt;

  RestoreJournal advance(RestoreJournalPhase next) => RestoreJournal(
    phase: next,
    previousGeneration: previousGeneration,
    newGeneration: newGeneration,
    previousNamespace: previousNamespace,
    reminderNamespace: reminderNamespace,
    stagedFile: stagedFile,
    rollbackFile: rollbackFile,
    databaseFile: databaseFile,
    startedAt: startedAt,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'phase': phase.name,
    'previousGeneration': previousGeneration,
    'newGeneration': newGeneration,
    'previousNamespace': previousNamespace,
    'reminderNamespace': reminderNamespace,
    'stagedFile': stagedFile,
    'rollbackFile': rollbackFile,
    'databaseFile': databaseFile,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };

  factory RestoreJournal.fromJson(Map<String, Object?> json) {
    if (_integer(json['version']) != version) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    final phase = RestoreJournalPhase.values
        .where((value) => value.name == json['phase'])
        .firstOrNull;
    final startedAt = DateTime.tryParse(_string(json['startedAt']));
    final previousNamespace = json['previousNamespace'] == null
        ? null
        : _identifier(json['previousNamespace']);
    final journal = RestoreJournal(
      phase:
          phase ?? (throw const RestoreFailure(RestoreCodes.recoveryRequired)),
      previousGeneration: _identifier(json['previousGeneration']),
      newGeneration: _identifier(json['newGeneration']),
      previousNamespace: previousNamespace,
      reminderNamespace: _identifier(json['reminderNamespace']),
      stagedFile: _fileName(json['stagedFile']),
      rollbackFile: _fileName(json['rollbackFile']),
      databaseFile: _fileName(json['databaseFile']),
      startedAt: startedAt == null || !startedAt.isUtc
          ? throw const RestoreFailure(RestoreCodes.recoveryRequired)
          : startedAt,
    );
    if (journal.previousGeneration == journal.newGeneration ||
        journal.previousNamespace == journal.reminderNamespace) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    return journal;
  }

  static String encode(RestoreJournal journal) => jsonEncode(journal.toJson());
}

String _string(Object? value) => value is String
    ? value
    : throw const RestoreFailure(RestoreCodes.recoveryRequired);

int _integer(Object? value) => value is int
    ? value
    : throw const RestoreFailure(RestoreCodes.recoveryRequired);

String _identifier(Object? value) {
  final text = _string(value);
  if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(text)) {
    throw const RestoreFailure(RestoreCodes.recoveryRequired);
  }
  return text;
}

String _fileName(Object? value) {
  final text = _string(value);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(text) ||
      text.contains('..')) {
    throw const RestoreFailure(RestoreCodes.recoveryRequired);
  }
  return text;
}

enum RestoreRecoveryAction {
  none,
  cleanupStaging,
  completeReplacement,
  rollBack,
  preserve,
}

final class RestoreRecoveryDecision {
  const RestoreRecoveryDecision(this.action, this.reason);
  final RestoreRecoveryAction action;
  final String reason;
}

/// Pure decision for an interrupted activation. It never trusts a journal
/// alone: a replacement is completed only when the live file opens and reports
/// the journal's new generation.
RestoreRecoveryDecision decideRestoreRecovery({
  required bool journalPresent,
  required RestoreJournalPhase? phase,
  required bool liveOpened,
  required String? liveGeneration,
  required bool rollbackExists,
  required bool rollbackOpened,
  required String? rollbackGeneration,
  required bool stagedExists,
  required String newGeneration,
  required String previousGeneration,
}) {
  if (!journalPresent) {
    if (!liveOpened) {
      if (rollbackExists &&
          rollbackOpened &&
          rollbackGeneration == previousGeneration) {
        return const RestoreRecoveryDecision(
          RestoreRecoveryAction.rollBack,
          'missing_journal_live_unreadable',
        );
      }
      return const RestoreRecoveryDecision(
        RestoreRecoveryAction.preserve,
        'missing_journal_unreadable_live',
      );
    }
    if (stagedExists || rollbackExists) {
      return const RestoreRecoveryDecision(
        RestoreRecoveryAction.cleanupStaging,
        'stale_staging',
      );
    }
    return const RestoreRecoveryDecision(RestoreRecoveryAction.none, 'clear');
  }
  if (!liveOpened) {
    if (rollbackExists &&
        rollbackOpened &&
        rollbackGeneration == previousGeneration) {
      return const RestoreRecoveryDecision(
        RestoreRecoveryAction.rollBack,
        'live_unreadable',
      );
    }
    return const RestoreRecoveryDecision(
      RestoreRecoveryAction.preserve,
      'live_unreadable_no_rollback',
    );
  }
  if (liveGeneration == newGeneration) {
    return RestoreRecoveryDecision(
      RestoreRecoveryAction.completeReplacement,
      '${phase?.name ?? 'unknown'}_live_new_generation',
    );
  }
  if (liveGeneration == previousGeneration) {
    return RestoreRecoveryDecision(
      RestoreRecoveryAction.cleanupStaging,
      '${phase?.name ?? 'unknown'}_live_previous_generation',
    );
  }
  return const RestoreRecoveryDecision(
    RestoreRecoveryAction.preserve,
    'live_unknown_generation',
  );
}
