#!/usr/bin/env python3
"""Generate deterministic synthetic attachment fixtures for ticket 16.

Standard library only. The tool writes fixtures and ``manifest.json`` to the
explicit ``--output`` directory and nowhere else. It never downloads assets,
installs packages, starts Flutter or contacts a device.

The generated content is synthetic. A valid PNG or PDF here proves only that
the fixture has the declared structure. It does not prove that any renderer,
decoder or platform adapter accepts or rejects it.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import os
import shutil
import struct
import sys
import tracemalloc
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from fixture_spec import (  # noqa: E402
    CHUNK_BYTES,
    DEFAULT_INPUT_LIMIT,
    GENERATOR,
    GENERATOR_VERSION,
    MAX_DECODED_PIXELS,
    MAX_FRAMES,
    MAX_PDF_PAGES,
    MAX_PREVIEW_BYTES,
    MANIFEST_READ_LIMIT,
    PNG_SIGNATURE,
    PNG_TEXT_KEYWORD,
    SAFE_NAME,
    SCHEMA,
    default_sizes,
    iter_pattern_bytes,
    iter_stream_bytes,
    stream_entry_name,
)


class FixtureError(Exception):
    """A safe, actionable generation failure."""


class HashingWriter:
    """Write one fixture while hashing it and tracking the largest buffer."""

    max_buffer_seen = 0

    def __init__(self, path: Path) -> None:
        self.path = path
        self.handle = path.open("wb")
        self.digest = hashlib.sha256()
        self.size = 0
        self.max_buffer = 0

    def write(self, data: bytes) -> None:
        self.max_buffer = max(self.max_buffer, len(data))
        HashingWriter.max_buffer_seen = max(HashingWriter.max_buffer_seen, len(data))
        self.handle.write(data)
        self.digest.update(data)
        self.size += len(data)

    def write_pieces(self, pieces: Iterator[bytes]) -> None:
        for piece in pieces:
            self.write(piece)

    def close(self) -> str:
        self.handle.flush()
        os.fsync(self.handle.fileno())
        self.handle.close()
        return self.digest.hexdigest()


@dataclass
class Fixture:
    name: str
    kind: str
    media_kind: str
    mime: str
    classification: str
    size: int
    sha256: str
    extension_matches_content: bool
    byte_limit: str | None = None
    width: int | None = None
    height: int | None = None
    declared_pixels: int | None = None
    page_count: int | None = None
    notes: str = ""

    def manifest_entry(self) -> dict[str, object]:
        return {
            "name": self.name,
            "kind": self.kind,
            "bytes": self.size,
            "sha256": self.sha256,
            "media_kind": self.media_kind,
            "mime": self.mime,
            "classification": self.classification,
            "extension_matches_content": self.extension_matches_content,
            "byte_limit": self.byte_limit,
            "width": self.width,
            "height": self.height,
            "declared_pixels": self.declared_pixels,
            "page_count": self.page_count,
            "notes": self.notes,
        }


def _chunk_bytes(chunk_type: bytes, payload: bytes) -> bytes:
    crc = binascii.crc32(chunk_type)
    crc = binascii.crc32(payload, crc) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", crc)
    )


def _stored_zlib(payload: bytes) -> bytes:
    """Return a deterministic zlib stream using stored deflate blocks.

    Python's zlib output can vary between zlib builds. Stored blocks make the
    fixture bytes stable across hosts while keeping the stream valid zlib.
    """
    output = bytearray(b"\x78\x01")
    position = 0
    while True:
        block = payload[position : position + 65535]
        final = position + len(block) >= len(payload)
        output.append(1 if final else 0)
        output += struct.pack("<HH", len(block), 0xFFFF ^ len(block))
        output += block
        if final:
            break
        position += len(block)
    output += struct.pack(">I", zlib.adler32(payload) & 0xFFFFFFFF)
    return bytes(output)


def _png_pixels(width: int, height: int) -> bytes:
    rows = bytearray()
    for y in range(height):
        rows.append(0)  # No per-row filter.
        for x in range(width):
            rows += bytes(
                (
                    (x * 32) % 256,
                    (y * 32) % 256,
                    ((x + y) * 16) % 256,
                    255,
                )
            )
    return bytes(rows)


def _png_idat(width: int, height: int) -> bytes:
    return _stored_zlib(_png_pixels(width, height))


def _png_ihdr(width: int, height: int) -> bytes:
    return struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)


def _png_bytes(width: int, height: int) -> bytes:
    return (
        PNG_SIGNATURE
        + _chunk_bytes(b"IHDR", _png_ihdr(width, height))
        + _chunk_bytes(b"IDAT", _png_idat(width, height))
        + _chunk_bytes(b"IEND", b"")
    )


def _png_malformed_idat(width: int, height: int) -> bytes:
    # Chunk structure and CRCs remain valid; the zlib payload does not decode.
    return (
        PNG_SIGNATURE
        + _chunk_bytes(b"IHDR", _png_ihdr(width, height))
        + _chunk_bytes(b"IDAT", b"\x78\x01\xff\xff")
        + _chunk_bytes(b"IEND", b"")
    )


def _png_dimension_bomb() -> bytes:
    # IHDR declares 65535 x 65535 RGBA pixels (4,294,836,225 pixels). The file
    # is tiny and contains no pixel buffer. A decoder must reject by metadata
    # before allocating the declared size.
    return (
        PNG_SIGNATURE
        + _chunk_bytes(b"IHDR", _png_ihdr(65535, 65535))
        + _chunk_bytes(b"IDAT", _stored_zlib(b"\x00"))
        + _chunk_bytes(b"IEND", b"")
    )


def _pdf_bytes(declared_page_count: int) -> bytes:
    content = (
        b"BT\n/F1 12 Tf\n24 100 Td\n"
        b"(Vital synthetic attachment fixture. No real record data.) Tj\n"
        b"ET\n"
    )
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        (
            b"<< /Type /Pages /Kids [3 0 R] /Count "
            + str(declared_page_count).encode("ascii")
            + b" >>"
        ),
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
            b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"
        ),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        (
            b"<< /Length "
            + str(len(content)).encode("ascii")
            + b" >>\nstream\n"
            + content
            + b"endstream"
        ),
    ]
    output = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output += f"{index} 0 obj\n".encode("ascii")
        output += body
        output += b"\nendobj\n"
    xref_offset = len(output)
    output += f"xref\n0 {len(objects) + 1}\n".encode("ascii")
    output += b"0000000000 65535 f \n"
    for offset in offsets[1:]:
        output += f"{offset:010d} 00000 n \n".encode("ascii")
    output += (
        b"trailer\n<< /Size "
        + str(len(objects) + 1).encode("ascii")
        + b" /Root 1 0 R >>\nstartxref\n"
        + str(xref_offset).encode("ascii")
        + b"\n%%EOF\n"
    )
    return bytes(output)


def _pdf_malformed_xref() -> bytes:
    data = _pdf_bytes(1)
    marker = b"startxref\n"
    position = data.rfind(marker)
    if position < 0:
        raise FixtureError("valid PDF fixture has no startxref marker")
    end = data.find(b"\n", position + len(marker))
    return data[: position + len(marker)] + b"0" + data[end:]


def _safe_extension(name: str) -> str:
    return Path(name).suffix.lower()


def _write_bytes(
    directory: Path,
    file_name: str,
    payload: bytes,
    **metadata: object,
) -> Fixture:
    metadata = dict(metadata)
    metadata_name = metadata.pop("name", file_name)
    if metadata_name != file_name:
        raise FixtureError(
            f"Fixture metadata names {metadata_name} but writes {file_name}"
        )
    writer = HashingWriter(directory / file_name)
    try:
        writer.write(payload)
        digest = writer.close()
        size = writer.size
    except Exception:
        writer.handle.close()
        raise
    return Fixture(name=file_name, size=size, sha256=digest, **metadata)  # type: ignore[arg-type]


def _write_stream(
    directory: Path,
    file_name: str,
    size: int,
    **metadata: object,
) -> Fixture:
    metadata = dict(metadata)
    metadata_name = metadata.pop("name", file_name)
    if metadata_name != file_name:
        raise FixtureError(
            f"Fixture metadata names {metadata_name} but writes {file_name}"
        )
    writer = HashingWriter(directory / file_name)
    try:
        writer.write_pieces(iter_stream_bytes(size))
        digest = writer.close()
        actual = writer.size
    except Exception:
        writer.handle.close()
        raise
    if actual != size:
        raise FixtureError(f"{file_name} wrote {actual} bytes, expected {size}")
    return Fixture(name=file_name, size=actual, sha256=digest, **metadata)  # type: ignore[arg-type]


def _write_png(
    directory: Path,
    file_name: str,
    pixel_width: int,
    pixel_height: int,
    pad_to: int | None = None,
    **metadata: object,
) -> Fixture:
    metadata = dict(metadata)
    metadata_name = metadata.pop("name", file_name)
    if metadata_name != file_name:
        raise FixtureError(
            f"Fixture metadata names {metadata_name} but writes {file_name}"
        )
    writer = HashingWriter(directory / file_name)
    try:
        idat = _png_idat(pixel_width, pixel_height)
        writer.write(PNG_SIGNATURE)
        writer.write(_chunk_bytes(b"IHDR", _png_ihdr(pixel_width, pixel_height)))
        if pad_to is None:
            writer.write(_chunk_bytes(b"IDAT", idat))
        else:
            fixed = (
                len(PNG_SIGNATURE)
                + len(_chunk_bytes(b"IHDR", _png_ihdr(pixel_width, pixel_height)))
                + len(_chunk_bytes(b"IDAT", idat))
                + len(_chunk_bytes(b"IEND", b""))
            )
            text_length = pad_to - fixed - 12
            if text_length < len(PNG_TEXT_KEYWORD):
                raise FixtureError(
                    f"{file_name} needs a larger target; {pad_to} bytes is too small"
                )
            padding = text_length - len(PNG_TEXT_KEYWORD)
            writer.write(struct.pack(">I", text_length) + b"tEXt")
            crc = binascii.crc32(b"tEXt")
            crc = binascii.crc32(PNG_TEXT_KEYWORD, crc)
            writer.write(PNG_TEXT_KEYWORD)
            written = 0
            for piece in iter_pattern_bytes(padding):
                written += len(piece)
                crc = binascii.crc32(piece, crc)
                writer.write(piece)
            if written != padding:
                raise FixtureError(f"{file_name} padding length mismatch")
            writer.write(struct.pack(">I", crc & 0xFFFFFFFF))
            writer.write(_chunk_bytes(b"IDAT", idat))
        writer.write(_chunk_bytes(b"IEND", b""))
        digest = writer.close()
        actual = writer.size
    except Exception:
        writer.handle.close()
        raise
    if pad_to is not None and actual != pad_to:
        raise FixtureError(f"{file_name} wrote {actual} bytes, expected {pad_to}")
    return Fixture(name=file_name, size=actual, sha256=digest, **metadata)  # type: ignore[arg-type]


def _fixture_bytes(
    name: str,
    kind: str,
    media_kind: str,
    mime: str,
    classification: str,
    content_mime: str,
    notes: str,
    width: int | None = None,
    height: int | None = None,
    page_count: int | None = None,
    byte_limit: str | None = None,
) -> dict[str, object]:
    return {
        "name": name,
        "kind": kind,
        "media_kind": media_kind,
        "mime": mime,
        "classification": classification,
        "extension_matches_content": _extension_matches(name, content_mime),
        "notes": notes,
        "width": width,
        "height": height,
        "declared_pixels": None
        if width is None or height is None
        else width * height,
        "page_count": page_count,
        "byte_limit": byte_limit,
    }


def _extension_matches(name: str, content_mime: str) -> bool:
    expected = {
        "image/png": ".png",
        "application/pdf": ".pdf",
        "text/plain": ".txt",
        "application/octet-stream": ".bin",
    }.get(content_mime)
    if expected is None:
        return True
    return _safe_extension(name) == expected


def _build_fixtures(
    directory: Path,
    input_limit: int,
    sizes: list[int],
) -> list[Fixture]:
    fixtures: list[Fixture] = []
    base_png = _png_bytes(8, 8)
    fixtures.append(
        _write_bytes(
            directory,
            "image-valid-8x8.png",
            base_png,
            **_fixture_bytes(
                "image-valid-8x8.png",
                "png_valid",
                "image",
                "image/png",
                "valid_image",
                "image/png",
                "Known valid 8 x 8 RGBA PNG. Synthetic pixels only.",
                width=8,
                height=8,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "image-valid-as-jpg.jpg",
            base_png,
            **_fixture_bytes(
                "image-valid-as-jpg.jpg",
                "png_valid_misleading_extension",
                "image",
                "image/png",
                "valid_image",
                "image/png",
                "Valid PNG bytes with a .jpg name. Content sniffing must ignore the name.",
                width=8,
                height=8,
            ),
        )
    )
    text = (
        b"This is plain text, not an image.\n"
        b"Synthetic attachment fixture for ticket 16.\n"
    )
    fixtures.append(
        _write_bytes(
            directory,
            "image-text-misleading.png",
            text,
            **_fixture_bytes(
                "image-text-misleading.png",
                "text_misleading_extension",
                "other",
                "text/plain",
                "misleading_text",
                "text/plain",
                "Plain text with a .png name. It has no image signature.",
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "pdf-valid-one-page.pdf",
            _pdf_bytes(1),
            **_fixture_bytes(
                "pdf-valid-one-page.pdf",
                "pdf_valid",
                "pdf",
                "application/pdf",
                "valid_pdf",
                "application/pdf",
                "One-page PDF with a valid xref and fixed text. No real record data.",
                page_count=1,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "pdf-truncated.pdf",
            _pdf_bytes(1)[:-48],
            **_fixture_bytes(
                "pdf-truncated.pdf",
                "pdf_truncated",
                "pdf",
                "application/pdf",
                "truncated",
                "application/pdf",
                "Valid PDF prefix cut before startxref and EOF.",
                page_count=1,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "pdf-malformed-xref.pdf",
            _pdf_malformed_xref(),
            **_fixture_bytes(
                "pdf-malformed-xref.pdf",
                "pdf_malformed_xref",
                "pdf",
                "application/pdf",
                "malformed",
                "application/pdf",
                "PDF with a present EOF marker and a startxref that points nowhere.",
                page_count=1,
            ),
        )
    )
    truncated_png = _png_bytes(8, 8)[:-20]
    fixtures.append(
        _write_bytes(
            directory,
            "image-truncated.png",
            truncated_png,
            **_fixture_bytes(
                "image-truncated.png",
                "png_truncated",
                "image",
                "image/png",
                "truncated",
                "image/png",
                "PNG prefix with a partial IDAT and no IEND.",
                width=8,
                height=8,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "image-malformed-idat.png",
            _png_malformed_idat(8, 8),
            **_fixture_bytes(
                "image-malformed-idat.png",
                "png_malformed_idat",
                "image",
                "image/png",
                "malformed",
                "image/png",
                "PNG chunks and CRCs are valid; the IDAT zlib stream is invalid.",
                width=8,
                height=8,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "image-decompression-bomb.png",
            _png_dimension_bomb(),
            **_fixture_bytes(
                "image-decompression-bomb.png",
                "png_dimension_bomb",
                "image",
                "image/png",
                "dimension_bomb",
                "image/png",
                "IHDR declares 65535 x 65535 pixels in a tiny file. Decode must be refused by metadata.",
                width=65535,
                height=65535,
            ),
        )
    )
    fixtures.append(
        _write_bytes(
            directory,
            "pdf-page-count-bomb.pdf",
            _pdf_bytes(1_000_000),
            **_fixture_bytes(
                "pdf-page-count-bomb.pdf",
                "pdf_page_count_bomb",
                "pdf",
                "application/pdf",
                "page_count_bomb",
                "application/pdf",
                "Page tree declares 1,000,000 pages in a tiny file with one page object.",
                page_count=1_000_000,
            ),
        )
    )
    empty_meta = _fixture_bytes(
        "empty.bin",
        "empty",
        "other",
        "application/octet-stream",
        "empty",
        "application/octet-stream",
        "Zero-byte file. Empty input must not become a ready attachment.",
    )
    fixtures.append(_write_bytes(directory, "empty.bin", b"", **empty_meta))

    for size in sizes:
        name, boundary = stream_entry_name(size, input_limit)
        fixtures.append(
            _write_stream(
                directory,
                name,
                size,
                **_fixture_bytes(
                    name,
                    "opaque_stream",
                    "other",
                    "application/octet-stream",
                    "opaque_stream",
                    "application/octet-stream",
                    "Deterministic opaque stream for bounded import tests.",
                    byte_limit=boundary,
                )
            )
        )

    for label, target in (("at", input_limit), ("over", input_limit + 1)):
        name = f"image-{label}-byte-limit.png"
        fixtures.append(
            _write_png(
                directory,
                name,
                8,
                8,
                pad_to=target,
                **_fixture_bytes(
                    name,
                    "png_padded_to_byte_limit",
                    "image",
                    "image/png",
                    "valid_image",
                    "image/png",
                    (
                        "Valid 8 x 8 PNG padded to exactly the input byte limit."
                        if label == "at"
                        else "Valid PNG padded to one byte over the input limit."
                    ),
                    width=8,
                    height=8,
                    byte_limit=label,
                ),
            )
        )
    return fixtures


def _check_output_scope(output: Path) -> Path:
    if output.is_symlink():
        raise FixtureError("Output path is a symbolic link. Choose a plain directory.")
    resolved = output.resolve(strict=False)
    if resolved == Path("/"):
        raise FixtureError("Output must not be the filesystem root.")
    source = HERE
    if resolved == source or source.is_relative_to(resolved):
        raise FixtureError(
            "Output must not be this tool's source directory or one of its parents."
        )
    if resolved.is_relative_to(source):
        raise FixtureError("Output must not be inside this tool's source directory.")
    if not resolved.parent.exists():
        raise FixtureError(
            f"Output parent does not exist: {resolved.parent}. Create it first."
        )
    if not resolved.parent.is_dir():
        raise FixtureError(f"Output parent is not a directory: {resolved.parent}")
    if resolved.exists() and not resolved.is_dir():
        raise FixtureError(f"Output exists and is not a directory: {resolved}")
    return resolved


def _existing_generated_files(output: Path, replace: bool) -> set[str]:
    if not output.exists():
        return set()
    entries = list(output.iterdir())
    if not entries:
        return set()
    manifest_path = output / "manifest.json"
    if not replace:
        raise FixtureError(
            "Output is not empty. Use --replace only when replacing a set generated "
            "by this tool."
        )
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise FixtureError(
            "Output is not empty and has no regular manifest.json. Refusing to overwrite it."
        )
    if manifest_path.stat().st_size > MANIFEST_READ_LIMIT:
        raise FixtureError("Existing manifest is too large. Refusing to replace.")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise FixtureError(f"Existing manifest cannot be read: {error}") from error
    if manifest.get("schema") != SCHEMA:
        raise FixtureError("Existing manifest has a different schema. Refusing to replace.")
    if manifest.get("generator") != GENERATOR:
        raise FixtureError("Existing manifest came from another generator. Refusing to replace.")
    provenance = manifest.get("provenance")
    if not isinstance(provenance, dict) or provenance.get("synthetic_only") is not True:
        raise FixtureError(
            "Existing manifest does not declare synthetic-only provenance. "
            "Refusing to replace."
        )
    files = manifest.get("files")
    if not isinstance(files, list):
        raise FixtureError("Existing manifest has no file list. Refusing to replace.")
    names: set[str] = set()
    for item in files:
        if not isinstance(item, dict):
            raise FixtureError("Existing manifest has an invalid file entry.")
        name = item.get("name")
        if not isinstance(name, str) or not SAFE_NAME.fullmatch(name):
            raise FixtureError("Existing manifest has an unsafe file name.")
        if name == "manifest.json" or name in names:
            raise FixtureError("Existing manifest repeats a file name.")
        names.add(name)
        path = output / name
        if path.is_symlink() or not path.is_file():
            raise FixtureError(f"Existing generated file is missing or unsafe: {name}")
        expected_size = item.get("bytes")
        expected_hash = item.get("sha256")
        if not isinstance(expected_size, int) or not isinstance(expected_hash, str):
            raise FixtureError(f"Existing manifest entry is incomplete: {name}")
        digest = hashlib.sha256()
        size = 0
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(CHUNK_BYTES)
                if not chunk:
                    break
                digest.update(chunk)
                size += len(chunk)
        if size != expected_size or digest.hexdigest() != expected_hash:
            raise FixtureError(
                f"Existing generated file was modified: {name}. Refusing to overwrite it."
            )
    actual = {entry.name for entry in entries}
    allowed = names | {"manifest.json"}
    unknown = sorted(actual - allowed)
    if unknown:
        raise FixtureError(
            "Output contains files this tool did not generate: " + ", ".join(unknown)
        )
    for entry in entries:
        if entry.is_symlink() or not entry.is_file():
            raise FixtureError(f"Output entry is not a regular file: {entry.name}")
    return names


def _write_manifest(path: Path, manifest: dict[str, object]) -> None:
    text = json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=True) + "\n"
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _parse_sizes(value: str) -> list[int]:
    sizes: set[int] = set()
    for part in value.split(","):
        part = part.strip()
        if not part:
            raise argparse.ArgumentTypeError("Sizes must be comma-separated integers.")
        try:
            size = int(part, 10)
        except ValueError as error:
            raise argparse.ArgumentTypeError(
                f"Not a whole number of bytes: {part}"
            ) from error
        if size < 0 or size > 1024 * 1024 * 1024:
            raise argparse.ArgumentTypeError(
                "Each size must be between 0 and 1073741824 bytes."
            )
        sizes.add(size)
    if not sizes:
        raise argparse.ArgumentTypeError("At least one size is required.")
    return sorted(sizes)


def generate(
    output: Path,
    input_limit: int,
    sizes: list[int],
    replace: bool,
    max_total_bytes: int,
) -> dict[str, object]:
    output = _check_output_scope(output)
    predicted = sum(sizes) + input_limit + (input_limit + 1) + CHUNK_BYTES
    if predicted > max_total_bytes:
        raise FixtureError(
            f"Requested sizes would use at least {predicted} bytes, above the "
            f"--max-total-bytes guard of {max_total_bytes}."
        )
    old_names = _existing_generated_files(output, replace)
    if not output.exists():
        output.mkdir(mode=0o700)
    staging = output / f".vital-attachment-fixtures-staging-{os.getpid()}"
    if staging.exists():
        raise FixtureError(f"Staging path already exists: {staging.name}")
    staging.mkdir(mode=0o700)

    tracemalloc.start()
    HashingWriter.max_buffer_seen = 0
    try:
        fixtures = _build_fixtures(staging, input_limit, sizes)
        names = [fixture.name for fixture in fixtures]
        if len(names) != len(set(names)):
            raise FixtureError("Fixture names are not unique.")
        total = sum(fixture.size for fixture in fixtures)
        if total > max_total_bytes:
            raise FixtureError(
                f"Fixture set would use {total} bytes, above the "
                f"--max-total-bytes guard of {max_total_bytes}."
            )
        manifest = {
            "schema": SCHEMA,
            "generator": GENERATOR,
            "generator_version": GENERATOR_VERSION,
            "provenance": {
                "origin": "generated",
                "synthetic_only": True,
                "external_assets": False,
                "network_access": False,
                "source": "Python standard library",
                "deterministic": True,
                "seed": "fixed-pattern-v1",
                "notes": (
                    "Synthetic bytes only. No real records, photos, downloads, "
                    "fonts or renderers."
                ),
            },
            "contract": {
                "source": "lib/domain/attachments.dart",
                "maxInputBytes": input_limit,
                "chunkBytes": CHUNK_BYTES,
                "maxDecodedPixels": MAX_DECODED_PIXELS,
                "maxPdfPages": MAX_PDF_PAGES,
                "maxPreviewBytes": MAX_PREVIEW_BYTES,
                "maxFrames": MAX_FRAMES,
                "inputLimitOverridden": input_limit != DEFAULT_INPUT_LIMIT,
            },
            "files": [fixture.manifest_entry() for fixture in sorted(fixtures, key=lambda f: f.name)],
        }
        _write_manifest(staging / "manifest.json", manifest)
        _fsync_directory(staging)

        new_names = {fixture.name for fixture in fixtures}
        for stale in sorted(old_names - new_names):
            (output / stale).unlink()
        for fixture in fixtures:
            os.replace(staging / fixture.name, output / fixture.name)
        os.replace(staging / "manifest.json", output / "manifest.json")
        _fsync_directory(output)
        staging.rmdir()
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    finally:
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()

    return {
        "schema": SCHEMA,
        "output": str(output),
        "fileCount": len(fixtures) + 1,
        "fixtureCount": len(fixtures),
        "totalFixtureBytes": total,
        "peakTracedBytes": peak,
        "maxWriteBufferBytes": HashingWriter.max_buffer_seen,
        "replaced": bool(old_names),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate deterministic synthetic attachment fixtures in an explicit "
            "output directory."
        )
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--input-limit",
        type=int,
        default=DEFAULT_INPUT_LIMIT,
        help=f"Fixture byte limit (default {DEFAULT_INPUT_LIMIT}).",
    )
    parser.add_argument(
        "--sizes",
        type=_parse_sizes,
        default=None,
        help=(
            "Comma-separated opaque stream sizes. Defaults to under, at and over "
            "the input limit."
        ),
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace a complete set previously generated by this tool.",
    )
    parser.add_argument(
        "--max-total-bytes",
        type=int,
        default=256 * 1024 * 1024,
        help="Refuse to generate a fixture set larger than this (default 268435456).",
    )
    parser.add_argument("--json", action="store_true", help="Print a JSON summary.")
    args = parser.parse_args()

    if args.input_limit < 4096 or args.input_limit > 1024 * 1024 * 1024:
        parser.error("--input-limit must be between 4096 and 1073741824 bytes.")
    if args.max_total_bytes < 0:
        parser.error("--max-total-bytes must not be negative.")
    sizes = args.sizes if args.sizes is not None else default_sizes(args.input_limit)
    try:
        summary = generate(
            args.output.expanduser(),
            args.input_limit,
            sizes,
            args.replace,
            args.max_total_bytes,
        )
    except FixtureError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"ERROR: unable to write fixtures: {error}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(
            f"PASS generated {summary['fixtureCount']} fixtures and manifest "
            f"({summary['totalFixtureBytes']} bytes) in {summary['output']}"
        )
        print(f"manifest: {Path(summary['output']) / 'manifest.json'}")
        print(
            "Peak Python allocation: "
            f"{summary['peakTracedBytes']} bytes; write buffers stayed bounded."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
