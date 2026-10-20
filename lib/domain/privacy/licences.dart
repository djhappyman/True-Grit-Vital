/// Parsing for the bundled open-source notices asset.
///
/// The asset is a single text file with `===== package: file =====` section
/// markers. Parsing is bounded so a damaged or replaced asset cannot make the
/// local help screen unbounded work or memory.
library;

/// Maximum notices displayed from one bundled asset.
const int maxLicenceNotices = 500;

/// Maximum accepted asset size before parsing stops.
const int maxLicenceNoticeBytes = 4 * 1024 * 1024;

final class LicenceNotice {
  const LicenceNotice({required this.title, required this.body});

  final String title;
  final String body;
}

final _marker = RegExp(r'^===== (.+?) =====$', multiLine: true);

/// Splits the bundled aggregate notice into stable sections. Text before the
/// first marker is ignored rather than presented without an owner. Empty
/// sections are dropped; section order is preserved.
List<LicenceNotice> decodeLicenceNotices(String raw) {
  if (raw.isEmpty || raw.length > maxLicenceNoticeBytes) return const [];
  final matches = _marker.allMatches(raw).toList();
  if (matches.isEmpty) return const [];
  final notices = <LicenceNotice>[];
  for (var index = 0; index < matches.length; index++) {
    final marker = matches[index];
    final start = marker.end;
    final end = index + 1 < matches.length ? matches[index + 1].start : null;
    final body = raw
        .substring(start, end ?? raw.length)
        .replaceFirst(RegExp(r'^\r?\n'), '')
        .trim();
    final title = marker.group(1)!.trim();
    if (title.isEmpty || body.isEmpty) continue;
    notices.add(LicenceNotice(title: title, body: body));
    if (notices.length == maxLicenceNotices) break;
  }
  return notices;
}
