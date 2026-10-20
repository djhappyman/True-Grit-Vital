# Protected backup v1

This is the development format implemented on 20 October 2026. Host tests cover round trips, wrong passwords, authenticated tampering, truncation, hostile framing, cancellation and staged restoration. G04 expert review and Android timing/storage/power-loss evidence remain open.

The backup contains a coherent encrypted SQLite snapshot, including protected attachment chunks and the sole local profile. It is a full-installation backup. A date-filtered JSON/CSV export is a separate feature.

## Layout

All framing integers use big-endian order.

| Field | Size |
|---|---:|
| Magic `VITALBK1` | 8 bytes |
| Format version `1` | 1 byte |
| JSON core length | 4 bytes |
| JSON core | At most 64 KiB |
| Dataset-key wrapping nonce | 24 bytes |
| Wrapped-key length | 2 bytes; must be 48 |
| Wrapped key and authentication tag | 48 bytes |
| Content frames | 4-byte length, then ciphertext and 16-byte tag |

The JSON core records creation time, schema version, captured generation, KDF/cipher parameters, snapshot length/SHA-256 and the ready-attachment count/length/manifest hash. It contains no profile names. Exact core bytes are authenticated; parsing does not substitute a re-encoded object for authentication.

## Cryptography

Primitives come from `cryptography` 2.9.0, admitted under Apache-2.0. The application implements framing and lifecycle rules.

- Writers use Argon2id version 19 with 64 MiB, three iterations, parallelism one, a random 16-byte salt and a 32-byte output. Readers bound memory to 8–256 MiB, iterations to 1–10, parallelism to 1–4 and salt length to 16–32 bytes before deriving a key.
- HKDF-SHA256 derives separate 32-byte wrapping and content keys using `vital-backup/1/wrap` and `vital-backup/1/content`.
- XChaCha20-Poly1305 wraps the 32-byte dataset key with a fresh 24-byte nonce and the core as associated data.
- Content uses 256 KiB plaintext chunks. A fresh 16-byte prefix plus an eight-byte chunk ordinal forms each 24-byte nonce. Associated data includes the core, wrapped-key nonce/ciphertext and chunk ordinal.
- Readers require exact frame lengths, total archive length, authenticated chunks and final snapshot SHA-256. Appended or missing bytes are rejected.

Creation requires at least 12 password characters and at most 1,024 UTF-8 bytes. The password is not persisted. Losing it prevents recovery from that archive.

## Capture and restore

`VACUUM INTO` captures the live encrypted database. Backup-purpose pins retain ready attachment versions until capture/self-validation finishes. The completed archive is decrypted and reopened before the app offers it for saving. Integrity, foreign keys, ownership, ready-attachment hashes and historical quantity representations are checked. Quantity validation is paged and bounded to two million rows per quantity table.

Restore copies the selected file into protected intake storage, authenticates and validates a staged database, previews its records and coverage, then requires explicit full-replacement confirmation. Preparation migrates the staged copy, rekeys it for this installation, preserves the installation app-lock preference, clears device-local drafts/jobs/actions, tombstones operation receipts and assigns fresh dataset/reminder namespaces.

Activation closes the live store, verifies a previous-dataset copy, writes a recovery journal, atomically renames the prepared database, reopens it and completes or rolls back. Generated previews and staged outbound copies are cleared before switching. Native reminder registrations are rebuilt from durable intent. Startup recovery preserves evidence when neither a valid active nor previous dataset can be established.

## Limits

The reader bounds the inner snapshot to 4 GiB and ready attachments to 20,000. Destination limits are separate: Android outbound staging is at most 512 MiB; the current Linux portal save adapter buffers at most 64 MiB. An oversized save is rejected while its staged backup remains available. Multi-gigabyte performance, actual storage exhaustion and Android release-binary behaviour are not accepted by host tests alone.

Process-checkpoint recovery has been exercised. Directory syncing outside Linux and real device power-loss behaviour still require platform evidence; this is not a durability certification.

The app accepts only a snapshot containing the sole active `me` owner. Legacy multi-person archives are rejected before replacement; records are never silently merged or discarded. Ownership keys remain in format v1 for referential integrity and older snapshot validation.
