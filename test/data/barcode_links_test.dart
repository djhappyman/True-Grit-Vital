import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/barcode/barcode_links.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/barcode/gtin.dart';

String gtin13(int serial) {
  final base = '40000000${serial.toString().padLeft(4, '0')}';
  var sum = 0;
  var weight = 3;
  for (var i = base.length - 1; i >= 0; i--) {
    sum += (base.codeUnitAt(i) - 0x30) * weight;
    weight = 4 - weight;
  }
  return '$base${(10 - sum % 10) % 10}';
}

void main() {
  late Directory directory;
  late RecordStore store;
  late SubstanceItem first;
  late SubstanceItem second;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-barcode-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 7),
      isNew: true,
    );
    first = await store.createItem(
      commandId: 'first',
      name: 'Synthetic pack one',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
      catalogueSnapshot: CatalogueSnapshot(
        product: const CatalogueProduct(
          code: 'synthetic-1',
          conceptClass: 'SYNTHETIC',
          name: 'Synthetic pack one',
          form: 'tablet',
          strength: '25 mg',
        ),
        manifest: CatalogueManifest(
          version: 'test',
          sourceId: 'synthetic',
          releaseDate: '2026-10-23',
          sourceUrl: 'https://example.invalid',
          sourceSha256: '0' * 64,
          projectionSha256: '0' * 64,
          licence: 'Synthetic',
          attribution: 'Synthetic',
          licenceSha256: '0' * 64,
          recordCount: 1,
          admissionReference: 'test-only',
          synthetic: true,
        ),
      ),
    );
    second = await store.createItem(
      commandId: 'second',
      name: 'Synthetic pack two',
      form: 'capsule',
      unit: 'count',
      type: 'medicine',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('decodes an absent or well-formed setting and sorts links', () {
    expect(BarcodeLinkIndex.decode(null).links, isEmpty);
    final code = Gtin.tryParse(gtin13(1))!;
    final index = BarcodeLinkIndex([
      BarcodeLink(
        gtin: code,
        itemId: first.id,
        reviewedName: first.name,
        reviewedForm: first.form,
        reviewedStrength: '25 mg',
        linkedAt: DateTime.utc(2026, 10, 23),
      ),
    ]);
    final decoded = BarcodeLinkIndex.decode(index.encode());
    expect(decoded.links.single.gtin, code);
    expect(decoded.links.single.itemId, first.id);
    expect(decoded.links.single.gtin.canonical, '0${gtin13(1)}');
  });

  test('rejects corrupt, unbounded and non-GTIN settings', () {
    expect(() => BarcodeLinkIndex.decode('{not json'), throwsFormatException);
    expect(
      () => BarcodeLinkIndex.decode(
        jsonEncode({'schema': 2, 'links': <Object>[]}),
      ),
      throwsFormatException,
    );
    expect(
      () => BarcodeLinkIndex.decode(
        jsonEncode({
          'schema': 1,
          'links': [
            for (var i = 0; i <= maxBarcodeLinks; i++)
              {
                'gtin': Gtin.tryParse(gtin13(i))!.canonical,
                'item': 'item',
                'name': 'name',
                'form': 'form',
                'strength': '',
                'linkedAt': '2026-10-23T00:00:00Z',
              },
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BarcodeLinkIndex.decode(
        jsonEncode({
          'schema': 1,
          'links': [
            {
              'gtin': 'not-a-gtin',
              'item': 'item',
              'name': 'name',
              'form': 'form',
              'strength': '',
              'linkedAt': '2026-10-23T00:00:00Z',
            },
          ],
        }),
      ),
      throwsFormatException,
    );
  });

  test(
    'persists one reviewed link and is idempotent for the same item',
    () async {
      final repository = BarcodeLinkRepository(store);
      final code = Gtin.tryParse(gtin13(2))!;
      final linked = await repository.link(
        code: code,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
      expect(linked.reviewedName, 'Synthetic pack one');
      expect(linked.reviewedForm, 'tablet');
      expect(linked.reviewedStrength, '25 mg');
      final again = await repository.link(
        code: code,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
      expect(again.itemId, first.id);
      expect((await repository.load()).forGtin(code), hasLength(1));
    },
  );

  test('treats EAN and GTIN forms as the same confirmed link', () async {
    final repository = BarcodeLinkRepository(store);
    final ean = Gtin.tryParse('0036000291452')!;
    final upc = Gtin.tryParse('036000291452')!;
    await repository.link(
      code: ean,
      itemId: first.id,
      expectedItemRevision: first.revision,
      expectedDetailRevision: 0,
      replace: false,
      canCommit: () => true,
    );
    expect((await repository.load()).forGtin(upc), hasLength(1));
  });

  test(
    'refuses an unconfirmed replacement and allows explicit replace',
    () async {
      final repository = BarcodeLinkRepository(store);
      final code = Gtin.tryParse(gtin13(3))!;
      await repository.link(
        code: code,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
      await expectLater(
        repository.link(
          code: code,
          itemId: second.id,
          expectedItemRevision: second.revision,
          expectedDetailRevision: 0,
          replace: false,
          canCommit: () => true,
        ),
        throwsA(
          isA<BarcodeLinkFailure>().having(
            (error) => error.code,
            'code',
            'barcode_link_conflict',
          ),
        ),
      );
      await repository.link(
        code: code,
        itemId: second.id,
        expectedItemRevision: second.revision,
        expectedDetailRevision: 0,
        replace: true,
        canCommit: () => true,
      );
      final links = (await repository.load()).forGtin(code);
      expect(links, hasLength(1));
      expect(links.single.itemId, second.id);
    },
  );

  test('bounds links per substance and in total', () async {
    final repository = BarcodeLinkRepository(store);
    for (var i = 0; i < maxBarcodeLinksPerItem; i++) {
      await repository.link(
        code: Gtin.tryParse(gtin13(100 + i))!,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
    }
    await expectLater(
      repository.link(
        code: Gtin.tryParse(gtin13(200))!,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      ),
      throwsA(
        isA<BarcodeLinkFailure>().having(
          (error) => error.code,
          'code',
          'barcode_link_item_limit',
        ),
      ),
    );

    final full = BarcodeLinkIndex([
      for (var i = 0; i < maxBarcodeLinks; i++)
        BarcodeLink(
          gtin: Gtin.tryParse(gtin13(1000 + i))!,
          itemId: 'bulk-$i',
          reviewedName: 'Bulk',
          reviewedForm: 'tablet',
          reviewedStrength: '',
          linkedAt: DateTime.utc(2026, 10, 23),
        ),
    ]);
    await store.writeSetting(barcodeLinksSettingKey, full.encode());
    await expectLater(
      repository.link(
        code: Gtin.tryParse(gtin13(300))!,
        itemId: second.id,
        expectedItemRevision: second.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      ),
      throwsA(
        isA<BarcodeLinkFailure>().having(
          (error) => error.code,
          'code',
          'barcode_link_limit',
        ),
      ),
    );
  });

  test('rechecks the item revision and the commit guard', () async {
    final repository = BarcodeLinkRepository(store);
    final code = Gtin.tryParse(gtin13(4))!;
    await expectLater(
      repository.link(
        code: code,
        itemId: first.id,
        expectedItemRevision: first.revision + 1,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      ),
      throwsA(
        isA<BarcodeLinkFailure>().having(
          (error) => error.code,
          'code',
          'barcode_link_changed',
        ),
      ),
    );
    await expectLater(
      repository.link(
        code: code,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => false,
      ),
      throwsA(isA<BarcodeLinkFailure>()),
    );
    expect((await repository.load()).forGtin(code), isEmpty);
  });

  test('reports a missing item and unreadable guarded setting', () async {
    final repository = BarcodeLinkRepository(store);
    await expectLater(
      repository.link(
        code: Gtin.tryParse(gtin13(5))!,
        itemId: 'missing-item',
        expectedItemRevision: 1,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      ),
      throwsA(
        isA<BarcodeLinkFailure>().having(
          (error) => error.code,
          'code',
          'barcode_link_item_missing',
        ),
      ),
    );
    await store.writeSetting(barcodeLinksSettingKey, 'corrupt');
    await expectLater(
      repository.load(),
      throwsA(
        isA<BarcodeLinkFailure>().having(
          (error) => error.code,
          'code',
          'barcode_link_unavailable',
        ),
      ),
    );
  });

  test('review uses exact saved catalogue wording without inference', () {
    final review = barcodeItemReview(first, null);
    expect(review.name, 'Synthetic pack one');
    expect(review.form, 'tablet');
    expect(review.strength, '25 mg');
  });
  test('current custom concentration takes priority over original catalogue strength', () {
    final detail = SubstanceDetail(
      itemId: first.id,
      personId: meId,
      instructions: '',
      notes: '',
      revision: 1,
      updatedAt: DateTime.utc(2026),
      profile: SubstanceProfile(
        route: SubstanceRoute.injectable,
        form: SubstanceForm.oil,
        strengthText: '400',
        massUnit: 'mg',
      ),
    );
    expect(barcodeItemReview(first, detail).strength, '400 mg/ml');
  });

  test(
    'concurrent links cannot silently overwrite an earlier confirmed link',
    () async {
      final repository = BarcodeLinkRepository(store);
      Future<bool> write(int n) async {
        try {
          await repository.link(
            code: Gtin.tryParse(gtin13(n))!,
            itemId: first.id,
            expectedItemRevision: first.revision,
            expectedDetailRevision: 0,
            replace: false,
            canCommit: () => true,
          );
          return true;
        } on BarcodeLinkFailure catch (error) {
          expect(error.code, 'barcode_link_stale');
          return false;
        }
      }

      final results = await Future.wait([write(70), write(71)]);
      final index = await repository.load();
      expect(index.links, hasLength(results.where((value) => value).length));
      for (var i = 0; i < results.length; i++) {
        if (!results[i]) expect(await write(70 + i), isTrue);
      }
      expect((await repository.load()).links, hasLength(2));
    },
  );
  test(
    'deleting the local owner removes barcode review snapshots too',
    () async {
      final repository = BarcodeLinkRepository(store);
      await repository.link(
        code: Gtin.tryParse(gtin13(90))!,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
      final owner = (await store.profileById(meId))!;
      await store.deleteProfile(
        commandId: 'erase',
        personId: meId,
        expectedRevision: owner.revision,
      );
      expect(await store.readSetting(barcodeLinksSettingKey), isNull);
    },
  );
}
