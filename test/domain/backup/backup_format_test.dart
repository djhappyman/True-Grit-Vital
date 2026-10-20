import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

void main() {
  group('backup format', () {
    BackupHeader header({Uint8List? salt}) => BackupHeader(
      createdAt: DateTime.utc(2026, 10, 20, 12),
      schemaVersion: 21,
      generation: 'generation_1',
      kdf: BackupKdfParameters(
        memoryKiB: 8192,
        iterations: 1,
        parallelism: 1,
        hashLength: 32,
        salt: salt ?? Uint8List.fromList(List.generate(16, (i) => i)),
      ),
      cipher: BackupCipherParameters(
        chunkBytes: BackupLimits.chunkBytes,
        noncePrefix: Uint8List.fromList(List.generate(16, (i) => i)),
      ),
      snapshot: BackupSnapshotSummary(
        bytes: 10,
        sha256: 'a' * 64,
        attachmentCount: 0,
        attachmentBytes: 0,
        attachmentSha256: 'b' * 64,
      ),
    );

    test('header round trips with fixed version and parameters', () {
      final original = header();
      final decoded = BackupHeader.fromJson(
        Map<String, Object?>.from(original.toJson()),
      );
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.generation, original.generation);
      expect(decoded.kdf.memoryKiB, 8192);
      expect(decoded.cipher.chunkBytes, BackupLimits.chunkBytes);
      expect(decoded.snapshot.sha256, 'a' * 64);
    });

    test('rejects a future format and unknown cipher', () {
      final json = Map<String, Object?>.from(header().toJson());
      json['version'] = 2;
      expect(
        () => BackupHeader.fromJson(json),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.code,
            'code',
            'backup_unsupported_version',
          ),
        ),
      );
      final cipher = Map<String, Object?>.from(header().toJson());
      final cipherJson = Map<String, Object?>.from(cipher['cipher']! as Map);
      cipherJson['name'] = 'homegrown';
      cipher['cipher'] = cipherJson;
      expect(
        () => BackupHeader.fromJson(cipher),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('rejects hostile KDF bounds and malformed identities', () {
      final json = Map<String, Object?>.from(header().toJson());
      final kdf = Map<String, Object?>.from(json['kdf']! as Map);
      kdf['memoryKiB'] = 4 * 1024 * 1024;
      json['kdf'] = kdf;
      expect(() => BackupHeader.fromJson(json), throwsA(isA<BackupFailure>()));
      expect(
        () => BackupHeader.fromJson({
          ...header().toJson(),
          'generation': '../escape',
        }),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('password policy counts characters and bounds bytes', () {
      expect(
        () => BackupLimits.checkPassword('short'),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.code,
            'code',
            'backup_password_short',
          ),
        ),
      );
      BackupLimits.checkPassword('twelve-chars!');
      expect(
        () => BackupLimits.checkPassword('é' * 11),
        throwsA(isA<BackupFailure>()),
      );
      expect(
        () => BackupLimits.checkPassword('x' * 1025),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.code,
            'code',
            'backup_password_long',
          ),
        ),
      );
    });

    test('chunk arithmetic includes framing and authentication tags', () {
      expect(BackupLimits.chunkCountFor(1), 1);
      expect(BackupLimits.chunkCountFor(BackupLimits.chunkBytes), 1);
      expect(BackupLimits.chunkCountFor(BackupLimits.chunkBytes + 1), 2);
      expect(
        BackupLimits.archiveBodyBytes(BackupLimits.chunkBytes + 1),
        BackupLimits.chunkBytes + 1 + 2 * (4 + BackupLimits.tagBytes),
      );
    });
  });
}
