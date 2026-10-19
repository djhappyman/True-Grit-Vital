/// Public source metadata, never a substitute for the separate licence gate.
final class CatalogueManifest {
  CatalogueManifest({
    required this.version,
    required this.sourceId,
    required this.releaseDate,
    required this.sourceUrl,
    required this.sourceSha256,
    required this.projectionSha256,
    required this.licence,
    required this.attribution,
    required this.licenceSha256,
    required this.recordCount,
    required this.admissionReference,
    this.synthetic = false,
  });
  final String version,
      sourceId,
      releaseDate,
      sourceUrl,
      sourceSha256,
      projectionSha256,
      licence,
      attribution,
      licenceSha256,
      admissionReference;
  final int recordCount;
  final bool synthetic;
  Map<String, Object> toJson() => {
    'schema': 1,
    'version': version,
    'sourceId': sourceId,
    'releaseDate': releaseDate,
    'sourceUrl': sourceUrl,
    'sourceSha256': sourceSha256,
    'projectionSha256': projectionSha256,
    'licence': licence,
    'attribution': attribution,
    'licenceSha256': licenceSha256,
    'recordCount': recordCount,
    'admissionReference': admissionReference,
    'synthetic': synthetic,
  };
  factory CatalogueManifest.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) throw const FormatException('catalogue_schema');
    return CatalogueManifest(
      version: j['version'] as String,
      sourceId: j['sourceId'] as String,
      releaseDate: j['releaseDate'] as String,
      sourceUrl: j['sourceUrl'] as String,
      sourceSha256: j['sourceSha256'] as String,
      projectionSha256: j['projectionSha256'] as String,
      licence: j['licence'] as String,
      attribution: j['attribution'] as String,
      licenceSha256: j['licenceSha256'] as String,
      recordCount: j['recordCount'] as int,
      admissionReference: j['admissionReference'] as String,
      synthetic: j['synthetic'] as bool,
    );
  }
}

/// Immutable source wording; strength is descriptive, never dose arithmetic.
final class CatalogueProduct {
  const CatalogueProduct({
    required this.code,
    required this.conceptClass,
    required this.name,
    required this.form,
    required this.strength,
  });
  final String code, conceptClass, name, form, strength;
  Map<String, Object> toJson() => {
    'code': code,
    'conceptClass': conceptClass,
    'name': name,
    'form': form,
    'strength': strength,
  };
  factory CatalogueProduct.fromJson(Map<String, dynamic> j) => CatalogueProduct(
    code: j['code'] as String,
    conceptClass: j['conceptClass'] as String,
    name: j['name'] as String,
    form: j['form'] as String,
    strength: j['strength'] as String,
  );
}

final class CatalogueSearchPage {
  CatalogueSearchPage({
    required this.query,
    required List<CatalogueProduct> products,
    required this.manifest,
    required this.needsRefinement,
  }) : products = List.unmodifiable(products);

  /// The complete original input is retained even when validation rejects search.
  final String query;
  final List<CatalogueProduct> products;
  final CatalogueManifest manifest;
  final bool needsRefinement;
  String get customEntryName => query;
}

/// The complete selected source wording and provenance retained with personal data.
/// Descriptive strength does not establish a concentration or conversion.
final class CatalogueSnapshot {
  const CatalogueSnapshot({required this.product, required this.manifest});
  final CatalogueProduct product;
  final CatalogueManifest manifest;
  Map<String, Object> toJson() => {
    'schema': 1,
    'product': product.toJson(),
    'manifest': manifest.toJson(),
  };
  factory CatalogueSnapshot.fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1) {
      throw const FormatException('catalogue_snapshot_schema');
    }
    return CatalogueSnapshot(
      product: CatalogueProduct.fromJson(
        value['product'] as Map<String, dynamic>,
      ),
      manifest: CatalogueManifest.fromJson(
        value['manifest'] as Map<String, dynamic>,
      ),
    );
  }
}
