import 'dart:convert';

import '../../domain/barcode/gtin.dart';
import '../record_store.dart';

/// User-confirmed links from a validated pack number to one saved substance.
///
/// This is a small guarded setting, not a catalogue or a source admission. It
/// stores no scanned image, no batch/serial element and no inferred product
/// identity. A camera result can only create a link after the person reviews the
/// current saved name, form and strength and explicitly links it.
const barcodeLinksSettingKey = 'barcode_links';
const maxBarcodeLinks = 200;
const maxBarcodeLinksPerItem = 8;

final class BarcodeLink {
  const BarcodeLink({
    required this.gtin,
    required this.itemId,
    required this.reviewedName,
    required this.reviewedForm,
    required this.reviewedStrength,
    required this.linkedAt,
  });

  final Gtin gtin;
  final String itemId, reviewedName, reviewedForm, reviewedStrength;
  final DateTime linkedAt;

  Map<String, Object> toJson() => {
    'gtin': gtin.canonical,
    'item': itemId,
    'name': reviewedName,
    'form': reviewedForm,
    'strength': reviewedStrength,
    'linkedAt': linkedAt.toUtc().toIso8601String(),
  };
}

/// The complete bounded link set read as one snapshot.
final class BarcodeLinkIndex {
  BarcodeLinkIndex(Iterable<BarcodeLink> links)
    : links = List.unmodifiable(
        links.toList()..sort((a, b) {
          final byCode = a.gtin.compareTo(b.gtin);
          return byCode != 0 ? byCode : a.itemId.compareTo(b.itemId);
        }),
      );

  static const schema = 1;
  final List<BarcodeLink> links;

  static final _empty = BarcodeLinkIndex(const []);

  factory BarcodeLinkIndex.decode(String? raw) {
    if (raw == null || raw.isEmpty) return _empty;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['schema'] != schema) {
      throw const FormatException('barcode_links_schema');
    }
    final rows = value['links'];
    if (rows is! List || rows.length > maxBarcodeLinks) {
      throw const FormatException('barcode_links_bound');
    }
    final result = <BarcodeLink>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('barcode_links_row');
      }
      final itemId = row['item'];
      final name = row['name'];
      final form = row['form'];
      final strength = row['strength'];
      final linkedAt = row['linkedAt'];
      final gtin = switch (row['gtin']) {
        final String value => Gtin.tryParse(value),
        _ => null,
      };
      if (gtin == null ||
          itemId is! String ||
          itemId.isEmpty ||
          itemId.length > 256 ||
          name is! String ||
          name.length > 2048 ||
          form is! String ||
          form.length > 2048 ||
          strength is! String ||
          strength.length > 4000 ||
          linkedAt is! String) {
        throw const FormatException('barcode_links_fields');
      }
      final instant = DateTime.tryParse(linkedAt);
      if (instant == null) throw const FormatException('barcode_links_time');
      result.add(
        BarcodeLink(
          gtin: gtin,
          itemId: itemId,
          reviewedName: name,
          reviewedForm: form,
          reviewedStrength: strength,
          linkedAt: instant.toUtc(),
        ),
      );
    }
    return BarcodeLinkIndex(result);
  }

  String encode() => jsonEncode({
    'schema': schema,
    'links': [for (final link in links) link.toJson()],
  });

  List<BarcodeLink> forGtin(Gtin code) => [
    for (final link in links)
      if (link.gtin == code) link,
  ];

  int countForItem(String itemId) =>
      links.where((link) => link.itemId == itemId).length;

  BarcodeLinkIndex upsert(BarcodeLink link) => BarcodeLinkIndex([
    for (final existing in links)
      if (existing.gtin != link.gtin) existing,
    link,
  ]);
}

/// Typed link failure with a stable code for user-facing recovery.
final class BarcodeLinkFailure implements Exception {
  const BarcodeLinkFailure(this.code);
  final String code;

  @override
  String toString() => 'BarcodeLinkFailure($code)';
}

/// A guarded association repository over the encrypted record setting store.
///
/// Every write checks the current item and detail revisions, the per-item and
/// total bounds, and a caller-supplied lock/dataset/route guard inside the
/// setting transaction. It never creates an item, dose or stock movement.
final class BarcodeLinkRepository {
  const BarcodeLinkRepository(this.store);
  final RecordStore store;

  Future<BarcodeLinkIndex> load() async {
    try {
      return BarcodeLinkIndex.decode(
        await store.readSetting(barcodeLinksSettingKey),
      );
    } on FormatException {
      throw const BarcodeLinkFailure('barcode_link_unavailable');
    } catch (_) {
      throw const BarcodeLinkFailure('barcode_link_unavailable');
    }
  }

  Future<BarcodeLink> link({
    required Gtin code,
    required String itemId,
    required int expectedItemRevision,
    required int expectedDetailRevision,
    required bool replace,
    required bool Function() canCommit,
  }) async {
    final String? previous;
    final BarcodeLinkIndex index;
    try {
      previous = await store.readSetting(barcodeLinksSettingKey);
      index = BarcodeLinkIndex.decode(previous);
    } catch (_) {
      throw const BarcodeLinkFailure('barcode_link_unavailable');
    }
    final owner = await store.profileById(meId);
    if (owner == null || owner.isArchived) {
      throw const BarcodeLinkFailure('barcode_link_item_missing');
    }
    final item = await store.itemById(itemId, personId: meId);
    final detail = await store.itemDetail(itemId, personId: meId);
    if (item == null) {
      throw const BarcodeLinkFailure('barcode_link_item_missing');
    }
    if (item.revision != expectedItemRevision ||
        (detail?.revision ?? 0) != expectedDetailRevision) {
      throw const BarcodeLinkFailure('barcode_link_changed');
    }
    final review = barcodeItemReview(item, detail);
    final existing = index.forGtin(code);
    final other = existing.where((link) => link.itemId != itemId).toList();
    if (other.isNotEmpty && !replace) {
      throw const BarcodeLinkFailure('barcode_link_conflict');
    }
    final itemCount =
        index.countForItem(itemId) -
        existing.where((link) => link.itemId == itemId).length;
    if (itemCount >= maxBarcodeLinksPerItem) {
      throw const BarcodeLinkFailure('barcode_link_item_limit');
    }
    final total = index.links.length - existing.length + 1;
    if (total > maxBarcodeLinks) {
      throw const BarcodeLinkFailure('barcode_link_limit');
    }
    final link = BarcodeLink(
      gtin: code,
      itemId: itemId,
      reviewedName: review.name,
      reviewedForm: review.form,
      reviewedStrength: review.strength,
      linkedAt: DateTime.now().toUtc(),
    );
    try {
      await store.writeItemBoundSetting(
        key: barcodeLinksSettingKey,
        value: index.upsert(link).encode(),
        expectedValue: previous,
        itemId: itemId,
        expectedItemRevision: expectedItemRevision,
        expectedDetailRevision: expectedDetailRevision,
        expectedPersonRevision: owner.revision,
        canCommit: canCommit,
      );
    } on CommandConflict catch (error) {
      throw BarcodeLinkFailure(
        error.code == 'app_locked'
            ? 'barcode_link_locked'
            : 'barcode_link_stale',
      );
    } catch (error) {
      if (error is BarcodeLinkFailure) rethrow;
      throw const BarcodeLinkFailure('barcode_link_failed');
    }
    return link;
  }
}

/// The exact saved identity shown before a link or use.
final class BarcodeItemReview {
  const BarcodeItemReview({
    required this.item,
    required this.detailRevision,
    required this.name,
    required this.form,
    required this.strength,
    this.profile,
  });

  final SubstanceProfile? profile;
  final SubstanceItem item;
  final int detailRevision;
  final String name, form, strength;

  int get itemRevision => item.revision;
  String get itemId => item.id;
}

BarcodeItemReview barcodeItemReview(
  SubstanceItem item,
  SubstanceDetail? detail,
) {
  final catalogue = item.catalogueSnapshot?.product.strength;
  final profile = detail?.profile;
  final enteredStrength = profile?.strengthText;
  final strength = enteredStrength != null
      ? '${enteredStrength.trim()} ${profile!.massUnit}/${profile.isCount ? 'count' : 'ml'}'
      : catalogue?.trim() ?? '';
  return BarcodeItemReview(
    item: item,
    detailRevision: detail?.revision ?? 0,
    name: item.name,
    form: item.form,
    strength: strength,
    profile: profile,
  );
}
