import 'dart:convert';

import 'backup_format.dart';

/// Local receipts, not proof that an external file still exists or restores.
final class BackupReceipt {
  const BackupReceipt({
    required this.generation,
    required this.sha256,
    required this.byteCount,
    required this.schemaVersion,
    required this.recordCount,
    required this.itemCount,
    required this.attachmentCount,
    required this.createdAt,
    required this.verifiedAt,
    this.savedAt,
  });

  final String generation, sha256;
  final int byteCount, schemaVersion, recordCount, itemCount, attachmentCount;
  final DateTime createdAt, verifiedAt;
  final DateTime? savedAt;

  Map<String, Object?> toJson() => {
    'generation': generation,
    'sha256': sha256,
    'bytes': byteCount,
    'schema': schemaVersion,
    'records': recordCount,
    'items': itemCount,
    'attachments': attachmentCount,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    if (savedAt != null) 'savedAt': savedAt!.toUtc().toIso8601String(),
  };

  factory BackupReceipt.fromJson(Map<String, dynamic> json) {
    final receipt = BackupReceipt(
      generation: json['generation'] as String,
      sha256: json['sha256'] as String,
      byteCount: json['bytes'] as int,
      schemaVersion: json['schema'] as int,
      recordCount: json['records'] as int,
      itemCount: json['items'] as int,
      attachmentCount: json['attachments'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      verifiedAt: DateTime.parse(json['verifiedAt'] as String).toUtc(),
      savedAt: json['savedAt'] == null
          ? null
          : DateTime.parse(json['savedAt'] as String).toUtc(),
    );
    backupIdentity(receipt.generation, 'backup_history_invalid');
    if (!isSha256(receipt.sha256) ||
        receipt.byteCount < 1 ||
        receipt.byteCount > BackupLimits.maxArchiveBytes ||
        receipt.schemaVersion < 1 ||
        receipt.schemaVersion > 1000 ||
        receipt.recordCount < 0 ||
        receipt.itemCount < 0 ||
        receipt.attachmentCount < 0) {
      throw const FormatException('backup_history_invalid');
    }
    return receipt;
  }
}

abstract final class BackupHistory {
  static const settingKey = 'backup_history_v1';
  static const limit = 20;

  static List<BackupReceipt> decode(String? value, String generation) {
    if (value == null) return const [];
    if (value.length > 65536) {
      throw const FormatException('backup_history_invalid');
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    final rows = json['receipts'] as List;
    if (json['version'] != 1 || rows.length > limit) {
      throw const FormatException('backup_history_invalid');
    }
    return List.unmodifiable(
      [
        for (final row in rows)
          BackupReceipt.fromJson(Map<String, dynamic>.from(row as Map)),
      ].where((receipt) => receipt.generation == generation),
    );
  }

  static String encode(Iterable<BackupReceipt> receipts) => jsonEncode({
    'version': 1,
    'receipts': receipts
        .take(limit)
        .map((receipt) => receipt.toJson())
        .toList(),
  });
}
