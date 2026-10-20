import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';

RestoreJournal journal({
  RestoreJournalPhase phase = RestoreJournalPhase.ready,
  String previousGeneration = 'aaaaaaaaaaaaaaaa',
  String newGeneration = 'bbbbbbbbbbbbbbbb',
  String? previousNamespace = 'cccccccccccccccc',
  String reminderNamespace = 'dddddddddddddddd',
}) => RestoreJournal(
  phase: phase,
  previousGeneration: previousGeneration,
  newGeneration: newGeneration,
  previousNamespace: previousNamespace,
  reminderNamespace: reminderNamespace,
  stagedFile: RestoreLimits.stagedFile,
  rollbackFile: RestoreLimits.rollbackFile,
  databaseFile: 'records.sqlite',
  startedAt: DateTime.utc(2026, 10, 20, 12),
);

void main() {
  test('journal round-trips and advances without changing identity', () {
    final ready = journal();
    final decoded = RestoreJournal.fromJson(
      _decode(RestoreJournal.encode(ready)),
    );
    expect(decoded.phase, RestoreJournalPhase.ready);
    expect(decoded.previousGeneration, ready.previousGeneration);
    expect(decoded.newGeneration, ready.newGeneration);
    expect(decoded.previousNamespace, ready.previousNamespace);
    expect(decoded.reminderNamespace, ready.reminderNamespace);
    expect(decoded.startedAt, ready.startedAt);
    final replaced = ready.advance(RestoreJournalPhase.replaced);
    expect(replaced.phase, RestoreJournalPhase.replaced);
    expect(replaced.newGeneration, ready.newGeneration);
    expect(replaced.startedAt, ready.startedAt);
  });

  test('malformed journals fail closed', () {
    final valid = RestoreJournal.encode(journal());
    for (final broken in [
      valid.replaceFirst('"version":1', '"version":2'),
      valid.replaceFirst('"ready"', '"unknown"'),
      valid.replaceFirst('"staged.sqlite"', '"../staged.sqlite"'),
      valid.replaceFirst(
        '"newGeneration":"bbbbbbbbbbbbbbbb"',
        '"newGeneration":"short"',
      ),
      valid.replaceFirst('2026-10-20T12:00:00.000Z', '2026-10-20T12:00:00'),
      valid.replaceFirst(
        '"previousGeneration":"aaaaaaaaaaaaaaaa"',
        '"previousGeneration":"bbbbbbbbbbbbbbbb"',
      ),
    ]) {
      expect(
        () => RestoreJournal.fromJson(_decode(broken)),
        throwsA(
          isA<RestoreFailure>().having(
            (error) => error.code,
            'code',
            RestoreCodes.recoveryRequired,
          ),
        ),
        reason: broken,
      );
    }
  });

  test('no journal keeps a valid live dataset and cleans stale staging', () {
    expect(
      decideRestoreRecovery(
        journalPresent: false,
        phase: null,
        liveOpened: true,
        liveGeneration: 'aaaaaaaaaaaaaaaa',
        rollbackExists: true,
        rollbackOpened: true,
        rollbackGeneration: 'aaaaaaaaaaaaaaaa',
        stagedExists: true,
        newGeneration: '',
        previousGeneration: '',
      ).action,
      RestoreRecoveryAction.cleanupStaging,
    );
  });

  test('no journal and an unreadable live file uses a verified rollback', () {
    expect(
      decideRestoreRecovery(
        journalPresent: false,
        phase: null,
        liveOpened: false,
        liveGeneration: null,
        rollbackExists: true,
        rollbackOpened: true,
        rollbackGeneration: 'aaaaaaaaaaaaaaaa',
        stagedExists: true,
        newGeneration: '',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.rollBack,
    );
  });

  test('ready with the previous generation cleans staging', () {
    expect(
      decideRestoreRecovery(
        journalPresent: true,
        phase: RestoreJournalPhase.ready,
        liveOpened: true,
        liveGeneration: 'aaaaaaaaaaaaaaaa',
        rollbackExists: true,
        rollbackOpened: true,
        rollbackGeneration: 'aaaaaaaaaaaaaaaa',
        stagedExists: true,
        newGeneration: 'bbbbbbbbbbbbbbbb',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.cleanupStaging,
    );
  });

  test('replaced with the new generation completes the replacement', () {
    expect(
      decideRestoreRecovery(
        journalPresent: true,
        phase: RestoreJournalPhase.replaced,
        liveOpened: true,
        liveGeneration: 'bbbbbbbbbbbbbbbb',
        rollbackExists: true,
        rollbackOpened: true,
        rollbackGeneration: 'aaaaaaaaaaaaaaaa',
        stagedExists: false,
        newGeneration: 'bbbbbbbbbbbbbbbb',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.completeReplacement,
    );
  });

  test('replaced with an unreadable live file rolls back', () {
    expect(
      decideRestoreRecovery(
        journalPresent: true,
        phase: RestoreJournalPhase.replaced,
        liveOpened: false,
        liveGeneration: null,
        rollbackExists: true,
        rollbackOpened: true,
        rollbackGeneration: 'aaaaaaaaaaaaaaaa',
        stagedExists: false,
        newGeneration: 'bbbbbbbbbbbbbbbb',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.rollBack,
    );
  });

  test('unknown live or missing rollback preserves evidence', () {
    expect(
      decideRestoreRecovery(
        journalPresent: true,
        phase: RestoreJournalPhase.replaced,
        liveOpened: true,
        liveGeneration: 'ffffffffffffffff',
        rollbackExists: false,
        rollbackOpened: false,
        rollbackGeneration: null,
        stagedExists: false,
        newGeneration: 'bbbbbbbbbbbbbbbb',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.preserve,
    );
    expect(
      decideRestoreRecovery(
        journalPresent: true,
        phase: RestoreJournalPhase.replaced,
        liveOpened: false,
        liveGeneration: null,
        rollbackExists: true,
        rollbackOpened: false,
        rollbackGeneration: null,
        stagedExists: false,
        newGeneration: 'bbbbbbbbbbbbbbbb',
        previousGeneration: 'aaaaaaaaaaaaaaaa',
      ).action,
      RestoreRecoveryAction.preserve,
    );
  });
}

Map<String, Object?> _decode(String source) =>
    Map<String, Object?>.from(jsonDecode(source) as Map);
