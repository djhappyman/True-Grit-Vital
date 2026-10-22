import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<RecordStore> _openStore() async {
  final directory = await Directory.systemTemp.createTemp('vital-privacy-');
  final store = await RecordStore.open(
    path: '${directory.path}/test.db',
    key: List<int>.generate(32, (index) => index + 1),
    isNew: true,
  );
  addTearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  return store;
}

OrdinaryDraft _draft(String generation, int personRevision) => OrdinaryDraft(
  id: 'draft-1',
  generation: generation,
  operationId: 'draft-operation-1',
  kind: DraftKind.profile,
  personId: meId,
  personRevision: personRevision,
  targetId: meId,
  targetRevision: null,
  fields: const {'name': 'Draft'},
);

Matcher _conflict(String code) =>
    throwsA(isA<CommandConflict>().having((error) => error.code, 'code', code));

void main() {
  group('profile delete authority', () {
    test('matching capture requires both generation and owner revision', () {
      const captured = ProfileDeleteAuthority(
        generation: 'generation-a',
        personRevision: 3,
      );

      expect(
        captured.matches(generation: 'generation-a', personRevision: 3),
        isTrue,
      );
      expect(
        captured.matches(generation: 'generation-a', personRevision: 4),
        isFalse,
      );
      expect(
        captured.matches(generation: 'generation-b', personRevision: 3),
        isFalse,
      );
      expect(captured.matches(generation: null, personRevision: null), isFalse);
    });

    test(
      'a matching owner revision cannot delete a replaced dataset',
      () async {
        final captured = await _openStore();
        final replacement = await _openStore();
        final capturedProfile = (await captured.profileById(meId))!;
        final replacementProfile = (await replacement.profileById(meId))!;
        // The dangerous case: the replacement reuses the same person ID and
        // revision, so only the captured dataset generation can tell them
        // apart.
        expect(replacementProfile.revision, capturedProfile.revision);
        await replacement.saveDraft(
          _draft(replacement.generation, replacementProfile.revision),
        );
        var cleanupStarted = false;
        final actions = StoreProfilePrivacyActions(
          () async => replacement,
          beforeDelete: () async => cleanupStarted = true,
          canCommit: () => true,
        );

        await expectLater(
          actions.delete(
            commandId: 'replacement-delete',
            personId: meId,
            expectedRevision: capturedProfile.revision,
            expectedGeneration: captured.generation,
          ),
          _conflict('generation'),
        );

        expect(cleanupStarted, isFalse);
        final after = (await replacement.profileById(meId))!;
        expect(after.revision, replacementProfile.revision);
        expect(after.remindersStopped, replacementProfile.remindersStopped);
        expect(await replacement.draftById('draft-1'), isNotNull);
        expect(await replacement.drafts(), hasLength(1));
      },
    );

    test(
      'expired authority rolls back a delete at the commit boundary',
      () async {
        final store = await _openStore();
        final before = (await store.profileById(meId))!;
        await store.saveDraft(_draft(store.generation, before.revision));
        var current = true;
        await expectLater(
          store.deleteProfile(
            commandId: 'expired-at-commit',
            personId: meId,
            expectedRevision: before.revision,
            canCommit: () => current,
            beforeCommit: () async => current = false,
          ),
          _conflict('app_locked'),
        );
        expect((await store.profileById(meId))!.revision, before.revision);
        expect(await store.draftById('draft-1'), isNotNull);
        expect(await store.reminderStopIntents(), isEmpty);
        current = true;
        await store.deleteProfile(
          commandId: 'expired-at-commit',
          personId: meId,
          expectedRevision: before.revision,
          canCommit: () => current,
        );
        expect((await store.profileById(meId))!.revision, before.revision + 1);
        expect(await store.draftById('draft-1'), isNull);
      },
    );

    test(
      'a lock cycle during cleanup invalidates the captured guard',
      () async {
        final store = await _openStore();
        final before = (await store.profileById(meId))!;
        var epoch = 0;
        final actions = StoreProfilePrivacyActions(
          () async => store,
          captureGuard: () {
            final captured = epoch;
            return () => epoch == captured;
          },
          beforeDelete: () async {
            epoch += 2;
          },
          canCommit: () => true,
        );
        await expectLater(
          actions.delete(
            commandId: 'lock-cycle',
            personId: meId,
            expectedRevision: before.revision,
            expectedGeneration: store.generation,
          ),
          _conflict('app_locked'),
        );
        expect((await store.profileById(meId))!.revision, before.revision);
      },
    );

    test('a stale owner revision writes nothing', () async {
      final store = await _openStore();
      final before = (await store.profileById(meId))!;
      await store.saveDraft(_draft(store.generation, before.revision));
      final actions = StoreProfilePrivacyActions(
        () async => store,
        canCommit: () => true,
      );

      await expectLater(
        actions.delete(
          commandId: 'stale-delete',
          personId: meId,
          expectedRevision: before.revision + 1,
          expectedGeneration: store.generation,
        ),
        _conflict('person_context'),
      );

      final after = (await store.profileById(meId))!;
      expect(after.revision, before.revision);
      expect(after.remindersStopped, isFalse);
      expect(await store.draftById('draft-1'), isNotNull);
      expect(await store.reminderStopIntents(), isEmpty);
    });

    test('a lock refusal writes nothing', () async {
      final store = await _openStore();
      final before = (await store.profileById(meId))!;
      await store.saveDraft(_draft(store.generation, before.revision));
      final actions = StoreProfilePrivacyActions(
        () async => store,
        canCommit: () => false,
      );

      await expectLater(
        actions.delete(
          commandId: 'locked-delete',
          personId: meId,
          expectedRevision: before.revision,
          expectedGeneration: store.generation,
        ),
        _conflict('app_locked'),
      );

      final after = (await store.profileById(meId))!;
      expect(after.revision, before.revision);
      expect(after.remindersStopped, isFalse);
      expect(await store.draftById('draft-1'), isNotNull);
    });

    test('a lock during cleanup stops before the writer', () async {
      final store = await _openStore();
      final before = (await store.profileById(meId))!;
      await store.saveDraft(_draft(store.generation, before.revision));
      var open = true;
      final actions = StoreProfilePrivacyActions(
        () async => store,
        beforeDelete: () async => open = false,
        canCommit: () => open,
      );

      await expectLater(
        actions.delete(
          commandId: 'interrupted-delete',
          personId: meId,
          expectedRevision: before.revision,
          expectedGeneration: store.generation,
        ),
        _conflict('app_locked'),
      );

      final after = (await store.profileById(meId))!;
      expect(after.revision, before.revision);
      expect(await store.draftById('draft-1'), isNotNull);
      expect(await store.reminderStopIntents(), isEmpty);
    });

    test('a replacement during cleanup stops before the writer', () async {
      final first = await _openStore();
      final replacement = await _openStore();
      final firstProfile = (await first.profileById(meId))!;
      final replacementProfile = (await replacement.profileById(meId))!;
      await replacement.saveDraft(
        _draft(replacement.generation, replacementProfile.revision),
      );
      var active = first;
      final actions = StoreProfilePrivacyActions(
        () async => active,
        beforeDelete: () async => active = replacement,
        canCommit: () => true,
      );

      await expectLater(
        actions.delete(
          commandId: 'swapped-delete',
          personId: meId,
          expectedRevision: firstProfile.revision,
          expectedGeneration: first.generation,
        ),
        _conflict('generation'),
      );

      final after = (await replacement.profileById(meId))!;
      expect(after.revision, replacementProfile.revision);
      expect(await replacement.draftById('draft-1'), isNotNull);
    });

    test('a failed cleanup can be retried with the same payload', () async {
      final store = await _openStore();
      final before = (await store.profileById(meId))!;
      await store.saveDraft(_draft(store.generation, before.revision));
      var fail = true;
      final actions = StoreProfilePrivacyActions(
        () async => store,
        beforeDelete: () async {
          if (fail) {
            fail = false;
            throw StateError('synthetic_cleanup_failure');
          }
        },
        canCommit: () => true,
      );

      await expectLater(
        actions.delete(
          commandId: 'retry-delete',
          personId: meId,
          expectedRevision: before.revision,
          expectedGeneration: store.generation,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await store.profileById(meId))!.revision, before.revision);
      expect(await store.draftById('draft-1'), isNotNull);

      await actions.delete(
        commandId: 'retry-delete',
        personId: meId,
        expectedRevision: before.revision,
        expectedGeneration: store.generation,
      );
      final after = (await store.profileById(meId))!;
      expect(after.revision, before.revision + 1);
      expect(after.remindersStopped, isTrue);
      expect(await store.draftById('draft-1'), isNull);
    });

    test(
      'matching authority deletes records, drafts and reminder intent once',
      () async {
        final store = await _openStore();
        final before = (await store.profileById(meId))!;
        await store.saveDraft(_draft(store.generation, before.revision));
        final actions = StoreProfilePrivacyActions(
          () async => store,
          canCommit: () => true,
        );

        Future<void> delete() => actions.delete(
          commandId: 'confirmed-delete',
          personId: meId,
          expectedRevision: before.revision,
          expectedGeneration: store.generation,
        );
        await delete();

        final after = (await store.profileById(meId))!;
        expect(after.revision, before.revision + 1);
        expect(after.remindersStopped, isTrue);
        expect(await store.draftById('draft-1'), isNull);
        expect(await store.drafts(), isEmpty);
        expect(
          await store.reminderStopIntents(),
          containsPair(meId, before.revision + 1),
        );

        // The same command identity and captured payload replay the committed
        // result instead of deleting again under the advanced revision.
        await delete();
        expect((await store.profileById(meId))!.revision, before.revision + 1);
      },
    );
  });
}
