#!/usr/bin/env python3
"""Validate generated synthetic attachment fixtures and their manifest.

This validator is deliberately separate from generation. It re-reads every
file, checks the manifest hash and structure, and reports bounded-memory
observations. It does not decode pixels, render pages, start Flutter or claim
that any application adapter rejects a fixture.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import re
import struct
import sys
import tracemalloc
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from fixture_spec import (  # noqa: E402
    CHUNK_BYTES,
    MANIFEST_READ_LIMIT,
    MAX_DECODED_PIXELS,
    MAX_FRAMES,
    MAX_PDF_PAGES,
    MAX_PREVIEW_BYTES,
    PNG_SIGNATURE,
    SAFE_NAME,
    SCHEMA,
    STREAM_PREFIX,
)

PNG_IDAT_COLLECT_LIMIT = 1024 * 1024
PDF_READ_LIMIT = 2 * 1024 * 1024
BOMB_FILE_LIMIT = 64 * 1024


class ValidationFailure(Exception):
    """A fixture or manifest failed a required check."""


class UnexpectedEnd(Exception):
    """A bounded read reached the end of a truncated file."""


@dataclass
class ReadBudget:
    max_read: int = 0

    def read(self, handle, size: int) -> bytes:
        data = handle.read(size)
        self.max_read = max(self.max_read, len(data))
        return data

    def exact(self, handle, size: int) -> bytes:
        pieces = bytearray()
        remaining = size
        while remaining:
            piece = self.read(handle, min(CHUNK_BYTES, remaining))
            if not piece:
                raise UnexpectedEnd
            pieces += piece
            remaining -= len(piece)
        return bytes(pieces)


@dataclass
class PngInfo:
    width: int | None = None
    height: int | None = None
    chunks: list[str] = field(default_factory=list)
    crc_ok: bool = True
    truncated: bool = False
    has_iend: bool = False
    idat: bytes | None = None
    idat_collected: bool = True
    zlib_ok: bool | None = None
    raw_length: int | None = None


@dataclass
class PdfInfo:
    header_ok: bool = False
    eof: bool = False
    startxref: int | None = None
    xref_ok: bool = False
    trailer_size: int | None = None
    trailer_root: int | None = None
    declared_pages: int | None = None
    page_objects: int = 0
    valid_object_offsets: bool = False


def _sniff(prefix: bytes) -> tuple[str, str]:
    """Return (format, media kind) from content, never from a file extension."""
    if prefix.startswith(b"%PDF-"):
        return "pdf", "pdf"
    if prefix.startswith(PNG_SIGNATURE):
        return "png", "image"
    if prefix.startswith(b"\xff\xd8\xff"):
        return "jpeg", "image"
    if prefix.startswith(b"GIF8"):
        return "gif", "image"
    if (
        prefix.startswith(b"RIFF")
        and len(prefix) >= 12
        and prefix[8:12] == b"WEBP"
    ):
        return "webp", "image"
    if prefix and all(byte in b"\t\n\r" or 32 <= byte <= 126 for byte in prefix):
        return "text", "other"
    return "other", "other"


def _prefix(path: Path, budget: ReadBudget, size: int = 32) -> bytes:
    with path.open("rb") as handle:
        return budget.read(handle, size)


def _sha256(path: Path, budget: ReadBudget) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while True:
            chunk = budget.read(handle, CHUNK_BYTES)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _read_all(path: Path, budget: ReadBudget, limit: int) -> bytes:
    pieces = bytearray()
    with path.open("rb") as handle:
        while True:
            chunk = budget.read(handle, CHUNK_BYTES)
            if not chunk:
                break
            pieces += chunk
            if len(pieces) > limit:
                raise ValidationFailure(
                    f"{path.name} is larger than the validator read limit of {limit} bytes"
                )
    return bytes(pieces)


def parse_png(path: Path, budget: ReadBudget) -> PngInfo:
    info = PngInfo()
    with path.open("rb") as handle:
        try:
            signature = budget.exact(handle, 8)
        except UnexpectedEnd:
            info.truncated = True
            return info
        if signature != PNG_SIGNATURE:
            raise ValidationFailure(f"{path.name} has no PNG signature")
        while True:
            try:
                header = budget.exact(handle, 8)
            except UnexpectedEnd:
                info.truncated = True
                break
            length, chunk_type = struct.unpack(">I4s", header)
            if length > 0x7FFFFFFF:
                raise ValidationFailure(f"{path.name} has an invalid PNG chunk length")
            crc = binascii.crc32(chunk_type)
            collected = bytearray() if chunk_type == b"IDAT" else None
            remaining = length
            while remaining:
                try:
                    piece = budget.exact(handle, min(CHUNK_BYTES, remaining))
                except UnexpectedEnd:
                    info.truncated = True
                    return info
                crc = binascii.crc32(piece, crc)
                remaining -= len(piece)
                if collected is not None:
                    if len(collected) + len(piece) <= PNG_IDAT_COLLECT_LIMIT:
                        collected += piece
                    else:
                        info.idat_collected = False
            try:
                stored_crc = struct.unpack(">I", budget.exact(handle, 4))[0]
            except UnexpectedEnd:
                info.truncated = True
                break
            if stored_crc != (crc & 0xFFFFFFFF):
                info.crc_ok = False
                raise ValidationFailure(f"{path.name} has a CRC mismatch")
            name = chunk_type.decode("ascii", "replace")
            info.chunks.append(name)
            if chunk_type == b"IHDR":
                if len(info.chunks) != 1 or length != 13:
                    raise ValidationFailure(f"{path.name} has a misplaced IHDR")
                # Payload was streamed, so parse it only for the small IHDR.
                # Re-read is avoided by collecting IHDR bytes below.
            if chunk_type == b"IDAT" and collected is not None:
                if info.idat is None:
                    info.idat = b""
                info.idat += bytes(collected)
            if chunk_type == b"IEND":
                info.has_iend = True
                break
    if info.chunks and info.chunks[0] == "IHDR":
        # The payload is available from the file only through a second bounded
        # read of this tiny chunk. It is at most 13 bytes plus 4 CRC bytes.
        with path.open("rb") as handle:
            budget.exact(handle, 8)
            length, _ = struct.unpack(">I4s", budget.exact(handle, 8))
            if length == 13:
                payload = budget.exact(handle, 13)
                info.width, info.height = struct.unpack(">II", payload[:8])
    return info


def parse_pdf(path: Path, budget: ReadBudget) -> PdfInfo:
    data = _read_all(path, budget, PDF_READ_LIMIT)
    info = PdfInfo()
    info.header_ok = data.startswith(b"%PDF-1.")
    info.eof = data.rstrip().endswith(b"%%EOF")
    info.page_objects = len(re.findall(rb"/Type\s*/Page(?!s)", data))
    count_match = re.search(rb"/Count\s+(\d+)", data)
    if count_match:
        info.declared_pages = int(count_match.group(1))
    start_match = re.search(rb"startxref\s+(\d+)\s+%%EOF\s*$", data)
    if not start_match:
        return info
    offset = int(start_match.group(1))
    info.startxref = offset
    if offset < 0 or offset >= len(data) or not data[offset:].startswith(b"xref"):
        return info
    lines = data[offset:].split(b"\n")
    entries: dict[int, tuple[int, str]] = {}
    index = 1
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            index += 1
            continue
        if line.startswith(b"trailer"):
            break
        parts = line.split()
        if len(parts) != 2:
            return info
        try:
            first, count = int(parts[0]), int(parts[1])
        except ValueError:
            return info
        if count < 0 or count > 1_000_000:
            return info
        index += 1
        for number in range(first, first + count):
            if index >= len(lines):
                return info
            entry = lines[index].ljust(20)
            try:
                object_offset = int(entry[:10])
                marker = entry[17:18]
            except ValueError:
                return info
            entries[number] = (object_offset, marker.decode("ascii", "replace"))
            index += 1
    trailer_start = data.find(b"trailer", offset)
    if trailer_start < 0:
        return info
    trailer = data[trailer_start : trailer_start + 4096]
    size_match = re.search(rb"/Size\s+(\d+)", trailer)
    root_match = re.search(rb"/Root\s+(\d+)\s+0\s+R", trailer)
    if not size_match or not root_match:
        return info
    info.trailer_size = int(size_match.group(1))
    info.trailer_root = int(root_match.group(1))
    valid_offsets = True
    for number, (object_offset, marker) in entries.items():
        if marker != "n":
            continue
        expected = f"{number} 0 obj".encode("ascii")
        if object_offset >= len(data) or not data[object_offset:].startswith(expected):
            valid_offsets = False
            break
    info.valid_object_offsets = valid_offsets
    info.xref_ok = (
        info.valid_object_offsets
        and info.trailer_root == 1
        and info.trailer_size == max(entries) + 1
    )
    return info


def _decode_png_idat(info: PngInfo) -> tuple[bool, int | None]:
    if info.idat is None:
        return False, None
    expected = None
    if info.width is not None and info.height is not None:
        expected = info.height * (1 + info.width * 4)
        if expected > MAX_DECODED_PIXELS * 5:
            # Never expand a declared-pixel bomb. The caller checks metadata.
            return False, None
    decoder = zlib.decompressobj()
    try:
        raw = decoder.decompress(info.idat, (expected or PNG_IDAT_COLLECT_LIMIT) + 1)
    except zlib.error:
        return False, None
    if expected is not None and (
        len(raw) != expected or decoder.unconsumed_tail or not decoder.eof
    ):
        return False, len(raw)
    return True, len(raw)


def _check_named_entry(
    output: Path,
    entry: dict[str, object],
    contract_limit: int,
    budget: ReadBudget,
) -> list[str]:
    checks: list[str] = []
    name = entry["name"]
    path = output / name
    digest, size = _sha256(path, budget)
    if size != entry["bytes"]:
        raise ValidationFailure(
            f"{name} is {size} bytes, manifest says {entry['bytes']}"
        )
    if digest != entry["sha256"]:
        raise ValidationFailure(f"{name} hash does not match its manifest entry")
    checks.append("hash")

    boundary = entry.get("byte_limit")
    if boundary == "under" and size != contract_limit - 1:
        raise ValidationFailure(f"{name} is not one byte under the limit")
    if boundary == "at" and size != contract_limit:
        raise ValidationFailure(f"{name} is not exactly at the limit")
    if boundary == "over" and size != contract_limit + 1:
        raise ValidationFailure(f"{name} is not one byte over the limit")

    sniffed_format, media = _sniff(_prefix(path, budget))
    expected_extension = {
        "png": ".png",
        "pdf": ".pdf",
        "text": ".txt",
        "other": ".bin",
    }.get(sniffed_format)
    if expected_extension is not None and entry["kind"] not in (
        "opaque_stream",
        "empty",
    ):
        actual = path.suffix.lower()
        matches = actual == expected_extension
        if matches != entry["extension_matches_content"]:
            raise ValidationFailure(
                f"{name} extension/content expectation does not match"
            )
    if entry["media_kind"] != media and entry["classification"] not in (
        "empty",
    ):
        raise ValidationFailure(
            f"{name} sniffed as {media}, manifest says {entry['media_kind']}"
        )
    checks.append("content-sniff")

    kind = entry["kind"]
    classification = entry["classification"]
    if kind in (
        "png_valid",
        "png_valid_misleading_extension",
        "png_padded_to_byte_limit",
        "png_truncated",
        "png_malformed_idat",
        "png_dimension_bomb",
    ):
        info = parse_png(path, budget)
        checks.append("png-structure")
        if info.width is None or info.height is None:
            if kind != "png_truncated":
                raise ValidationFailure(f"{name} has no readable IHDR")
        else:
            if entry["width"] != info.width or entry["height"] != info.height:
                raise ValidationFailure(f"{name} dimensions do not match the manifest")
            declared = info.width * info.height
            if entry["declared_pixels"] != declared:
                raise ValidationFailure(f"{name} declared pixels are inconsistent")
        if kind in ("png_valid", "png_valid_misleading_extension", "png_padded_to_byte_limit"):
            if info.truncated or not info.has_iend:
                raise ValidationFailure(f"{name} is not a complete PNG")
            ok, _ = _decode_png_idat(info)
            if not ok:
                raise ValidationFailure(f"{name} IDAT does not decode as declared")
            if declared > contract_limit:
                raise ValidationFailure(f"{name} exceeds the declared pixel contract")
            checks.append("png-idat")
        elif kind == "png_truncated":
            if info.has_iend:
                raise ValidationFailure(f"{name} unexpectedly has an IEND")
            checks.append("png-truncated")
        elif kind == "png_malformed_idat":
            if not info.has_iend:
                raise ValidationFailure(f"{name} is not structurally complete")
            ok, _ = _decode_png_idat(info)
            if ok:
                raise ValidationFailure(f"{name} unexpectedly decodes")
            checks.append("png-invalid-idat")
        elif kind == "png_dimension_bomb":
            if size > BOMB_FILE_LIMIT:
                raise ValidationFailure(f"{name} is not a small header-only bomb")
            if declared <= MAX_DECODED_PIXELS:
                raise ValidationFailure(f"{name} does not exceed the pixel limit")
            if not info.has_iend:
                raise ValidationFailure(f"{name} lacks a complete PNG envelope")
            checks.append("png-bomb-metadata-only")
    elif kind in (
        "pdf_valid",
        "pdf_truncated",
        "pdf_malformed_xref",
        "pdf_page_count_bomb",
    ):
        info = parse_pdf(path, budget)
        checks.append("pdf-structure")
        if kind == "pdf_valid":
            if not info.header_ok or not info.eof:
                raise ValidationFailure(f"{name} lacks a PDF header or EOF")
            if not info.xref_ok:
                raise ValidationFailure(f"{name} xref or trailer is invalid")
            if info.declared_pages != 1 or info.page_objects != 1:
                raise ValidationFailure(f"{name} page metadata is inconsistent")
            if entry["page_count"] != 1:
                raise ValidationFailure(f"{name} manifest page count is inconsistent")
            checks.append("pdf-xref")
        elif kind == "pdf_truncated":
            if info.eof and info.xref_ok:
                raise ValidationFailure(f"{name} is not truncated")
            checks.append("pdf-truncated")
        elif kind == "pdf_malformed_xref":
            if not info.eof or info.xref_ok:
                raise ValidationFailure(f"{name} does not have the expected bad xref")
            checks.append("pdf-invalid-xref")
        elif kind == "pdf_page_count_bomb":
            if size > BOMB_FILE_LIMIT:
                raise ValidationFailure(f"{name} is not a small page-count bomb")
            if info.declared_pages is None or info.declared_pages <= MAX_PDF_PAGES:
                raise ValidationFailure(f"{name} does not exceed the page limit")
            if entry["page_count"] != info.declared_pages:
                raise ValidationFailure(f"{name} declared page count is inconsistent")
            checks.append("pdf-page-count-metadata-only")
    elif kind == "empty":
        if size != 0:
            raise ValidationFailure(f"{name} is not empty")
        checks.append("empty")
    elif kind == "text_misleading_extension":
        if size == 0 or media != "other":
            raise ValidationFailure(f"{name} is not the expected plain text")
        checks.append("text-content")
    elif kind == "opaque_stream":
        prefix = _prefix(path, budget, min(size, len(STREAM_PREFIX)))
        expected_prefix = STREAM_PREFIX[: len(prefix)]
        if prefix != expected_prefix:
            raise ValidationFailure(f"{name} has no deterministic stream prefix")
        checks.append("stream-size")
    else:
        raise ValidationFailure(f"{name} has an unknown kind: {kind}")

    if classification == "valid_image" and entry["media_kind"] != "image":
        raise ValidationFailure(f"{name} claims valid_image with another media kind")
    if classification == "valid_pdf" and entry["media_kind"] != "pdf":
        raise ValidationFailure(f"{name} claims valid_pdf with another media kind")
    return checks


def validate(output: Path, max_peak_bytes: int) -> dict[str, object]:
    if output.is_symlink() or not output.is_dir():
        raise ValidationFailure("Input must be a plain fixture directory")
    manifest_path = output / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValidationFailure("manifest.json is missing or not a regular file")
    if manifest_path.stat().st_size > MANIFEST_READ_LIMIT:
        raise ValidationFailure("manifest.json is larger than the read limit")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValidationFailure(f"manifest.json cannot be read: {error}") from error
    if manifest.get("schema") != SCHEMA:
        raise ValidationFailure("Manifest schema does not match this validator")
    provenance = manifest.get("provenance")
    if (
        not isinstance(provenance, dict)
        or provenance.get("synthetic_only") is not True
        or provenance.get("external_assets") is not False
        or provenance.get("network_access") is not False
    ):
        raise ValidationFailure("Manifest does not declare synthetic-only provenance")
    contract = manifest.get("contract")
    if not isinstance(contract, dict):
        raise ValidationFailure("Manifest has no contract block")
    limit = contract.get("maxInputBytes")
    if not isinstance(limit, int) or limit < 1:
        raise ValidationFailure("Manifest input limit is invalid")
    expected_contract = {
        "chunkBytes": CHUNK_BYTES,
        "maxDecodedPixels": MAX_DECODED_PIXELS,
        "maxPdfPages": MAX_PDF_PAGES,
        "maxPreviewBytes": MAX_PREVIEW_BYTES,
        "maxFrames": MAX_FRAMES,
    }
    for key, value in expected_contract.items():
        if contract.get(key) != value:
            raise ValidationFailure(f"Manifest contract value {key} is inconsistent")
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise ValidationFailure("Manifest has no files")

    names: set[str] = set()
    entries: list[dict[str, object]] = []
    for entry in files:
        if not isinstance(entry, dict):
            raise ValidationFailure("Manifest has a non-object file entry")
        name = entry.get("name")
        if not isinstance(name, str) or not SAFE_NAME.fullmatch(name):
            raise ValidationFailure("Manifest has an unsafe file name")
        if name == "manifest.json" or name in names:
            raise ValidationFailure("Manifest repeats a file name")
        for key in (
            "kind",
            "bytes",
            "sha256",
            "media_kind",
            "mime",
            "classification",
            "extension_matches_content",
        ):
            if key not in entry:
                raise ValidationFailure(f"{name} has no {key} field")
        if not isinstance(entry["bytes"], int) or entry["bytes"] < 0:
            raise ValidationFailure(f"{name} has an invalid byte count")
        if not isinstance(entry["sha256"], str) or not re.fullmatch(
            r"[0-9a-f]{64}", entry["sha256"]
        ):
            raise ValidationFailure(f"{name} has an invalid hash")
        names.add(name)
        entries.append(entry)

    actual = {item.name for item in output.iterdir()}
    expected = names | {"manifest.json"}
    extra = sorted(actual - expected)
    missing = sorted(expected - actual)
    if extra:
        raise ValidationFailure("Unexpected files: " + ", ".join(extra))
    if missing:
        raise ValidationFailure("Missing files: " + ", ".join(missing))
    for item in output.iterdir():
        if item.is_symlink() or not item.is_file():
            raise ValidationFailure(f"Unsafe directory entry: {item.name}")

    budget = ReadBudget()
    file_reports: list[dict[str, object]] = []
    for entry in sorted(entries, key=lambda item: str(item["name"])):
        checks = _check_named_entry(output, entry, limit, budget)
        file_reports.append(
            {"name": entry["name"], "kind": entry["kind"], "checks": checks}
        )

    return {
        "schema": SCHEMA,
        "input": str(output),
        "pass": True,
        "fileCount": len(entries),
        "files": file_reports,
        "maxReadBytes": budget.max_read,
        "maxReadBytesBudget": CHUNK_BYTES,
        "limitations": [
            "Structure and hashes only.",
            "No pixel decode, page render, renderer or platform adapter was exercised.",
            "Renderer acceptance or rejection remains to be measured against the admitted engine.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate generated attachment fixtures without rendering them."
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument(
        "--max-peak-bytes",
        type=int,
        default=16 * 1024 * 1024,
        help="Fail if traced Python allocation exceeds this (default 16777216).",
    )
    parser.add_argument("--json", action="store_true", help="Print a JSON report.")
    args = parser.parse_args()

    tracemalloc.start()
    try:
        report = validate(args.input.expanduser(), args.max_peak_bytes)
        _, peak = tracemalloc.get_traced_memory()
        report["peakTracedBytes"] = peak
        report["peakTracedBytesBudget"] = args.max_peak_bytes
        if peak > args.max_peak_bytes:
            raise ValidationFailure(
                f"Traced Python allocation reached {peak} bytes, above the "
                f"{args.max_peak_bytes} byte budget"
            )
        if report["maxReadBytes"] > CHUNK_BYTES:
            raise ValidationFailure("A validator read exceeded the chunk budget")
    except ValidationFailure as error:
        tracemalloc.stop()
        if args.json:
            print(
                json.dumps(
                    {"pass": False, "error": str(error)},
                    indent=2,
                    sort_keys=True,
                )
            )
        else:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        tracemalloc.stop()

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(
            f"PASS validated {report['fileCount']} fixtures and manifest in "
            f"{report['input']}"
        )
        print(
            f"Peak traced Python allocation: {report['peakTracedBytes']} bytes; "
            f"largest read: {report['maxReadBytes']} bytes."
        )
        print(
            "Scope: structure and hashes only. No renderer, decoder or device "
            "acceptance is claimed."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
