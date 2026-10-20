import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-single-user-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('single-user activation preserves records and rejects another owner after restart', () async {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    final record = await store.record(
      commandId: 'record',
      itemId: item.id,
      amount: '1.25',
      actualAt: DateTime.utc(2026, 10, 20),
    );
    await store.saveBrowsingScope(const FeedScope.everyone());
    await store.enableSingleUser();
    expect(await store.readSetting('browsing_scope'), isNull);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    await store.enableSingleUser();
    await expectLater(
      store.createProfile(
        commandId: 'second',
        name: 'Another adult',
        adultConfirmed: true,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('single_user_required'),
        ),
      ),
    );
    expect((await store.profiles()).single.id, meId);
    expect((await store.recordById(record.id))!.enteredAmount, '1.25');
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'rename',
      personId: meId,
      expectedRevision: me.revision,
      name: 'My full name',
      adultConfirmed: true,
    );
    expect((await store.profileById(meId))!.name, 'My full name');
  });

  test('unexpected legacy people are retained and activation fails without deletion or merge', () async {
    final other = await store.createProfile(
      commandId: 'legacy',
      name: 'Synthetic legacy adult',
      adultConfirmed: true,
    );
    final item = await store.createItem(
      commandId: 'legacy-item',
      personId: other.id,
      name: 'Legacy item',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    await expectLater(
      store.enableSingleUser(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'code',
          'single_user_required',
        ),
      ),
    );
    expect(await store.itemById(item.id), isNotNull);
    expect((await store.profiles()).length, 2);
  });

  test(
    'delete clears the sole users records and keeps a usable profile',
    () async {
      await store.enableSingleUser();
      final item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await store.record(
        commandId: 'dose',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.now().toUtc(),
      );
      await store.deleteProfile(
        commandId: 'clear',
        personId: meId,
        expectedRevision: 1,
      );
      expect(await store.records(), isEmpty);
      expect(await store.items(), isEmpty);
      expect((await store.profiles()).single.id, meId);
      await store.createItem(
        commandId: 'new-item',
        name: 'New item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
        expectedPersonRevision: 2,
      );
    },
  );

  test('restore refuses a legacy multi-person database before changing live records', () async {
    final archivePath = '${directory.path}/legacy.db';
    final legacy = await RecordStore.open(
      path: archivePath,
      key: key,
      isNew: true,
    );
    await legacy.createProfile(
      commandId: 'legacy',
      name: 'Other adult',
      adultConfirmed: true,
    );
    await legacy.close();
    await store.enableSingleUser();
    final generation = store.generation;
    await expectLater(
      store.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (_) async {},
      ),
      throwsA(
        isA<RestoreFailure>().having(
          (error) => error.code,
          'code',
          'restore_multiple_people',
        ),
      ),
    );
    expect(store.generation, generation);
    expect((await store.profiles()).single.id, meId);
  });
}
