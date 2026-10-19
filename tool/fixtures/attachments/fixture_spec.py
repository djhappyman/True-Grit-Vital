"""Shared, deterministic contract for synthetic attachment fixtures.

The app contract currently lives in ``lib/domain/attachments.dart``. These
values are copied here so this standard-library-only tool can run without a
Flutter, Dart or device toolchain. They are fixture inputs, not evidence that
the application enforces a limit correctly.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Iterator

SCHEMA = "vital-attachment-fixtures-1"
GENERATOR = "tool/fixtures/attachments/generate.py"
GENERATOR_VERSION = 1

# Mirrors lib/domain/attachments.dart. Keep this in sync when that contract
# changes, and record the change in docs/implementation/16-attachment-fixtures.md.
DEFAULT_INPUT_LIMIT = 16 * 1024 * 1024
CHUNK_BYTES = 64 * 1024
MANIFEST_READ_LIMIT = 1024 * 1024
MAX_DECODED_PIXELS = 16_000_000
MAX_PDF_PAGES = 100
MAX_PREVIEW_BYTES = 8 * 1024 * 1024
MAX_FRAMES = 1

SAFE_NAME = re.compile(r"^[a-z0-9][a-z0-9.-]{0,127}$")

STREAM_PREFIX = b"VITAL-SYNTHETIC-ATTACHMENT-STREAM\n"
STREAM_PATTERN = (
    b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_ "
    b"synthetic-only no-real-records\n"
)

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_TEXT_KEYWORD = b"Comment\x00"


def iter_stream_bytes(size: int) -> Iterator[bytes]:
    """Yield the deterministic opaque stream content without buffering it."""
    if size < 0:
        raise ValueError("stream size must not be negative")
    remaining = size
    prefix = STREAM_PREFIX[:remaining]
    if prefix:
        yield prefix
        remaining -= len(prefix)
    while remaining:
        piece = STREAM_PATTERN[: remaining]
        yield piece
        remaining -= len(piece)


def iter_pattern_bytes(size: int) -> Iterator[bytes]:
    """Yield deterministic padding bytes for PNG text chunks."""
    if size < 0:
        raise ValueError("padding size must not be negative")
    remaining = size
    while remaining:
        piece = STREAM_PATTERN[: remaining]
        yield piece
        remaining -= len(piece)


def read_chunks(path: Path, chunk_bytes: int = CHUNK_BYTES) -> Iterator[bytes]:
    """Read a file in bounded chunks. Callers must not load a whole fixture."""
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_bytes)
            if not chunk:
                return
            yield chunk


def sha256_file(path: Path, chunk_bytes: int = CHUNK_BYTES) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    for chunk in read_chunks(path, chunk_bytes):
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest(), size


def stream_entry_name(size: int, input_limit: int) -> tuple[str, str | None]:
    """Return a stable name and boundary label for an opaque stream size."""
    if size == input_limit - 1:
        return "stream-under-byte-limit.bin", "under"
    if size == input_limit:
        return "stream-at-byte-limit.bin", "at"
    if size == input_limit + 1:
        return "stream-over-byte-limit.bin", "over"
    return f"stream-size-{size}-bytes.bin", None


def default_sizes(input_limit: int) -> list[int]:
    return sorted({max(0, input_limit - 1), input_limit, input_limit + 1})
