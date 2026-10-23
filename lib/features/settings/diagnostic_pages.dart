import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/privacy.dart';
import '../../domain/privacy/diagnostics.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show EntryPage, Heading, LoadFailure;
import 'settings_widgets.dart';

/// Bounded, redacted, local-only diagnostic history. No sender exists in this
/// build, so no upload toggle is shown.
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _busy = false;
  bool _failed = false;
  String? _notice;

  String _label(AppLocalizations t, DiagnosticCode code) => switch (code) {
    DiagnosticCode.dataLoad => t.diagnosticDataLoad,
    DiagnosticCode.licenceNotice => t.diagnosticLicenceNotice,
    DiagnosticCode.profileArchive => t.diagnosticProfileArchive,
    DiagnosticCode.profileDelete => t.diagnosticProfileDelete,
  };

  Future<void> _clear() async {
    if (_busy) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _failed = false;
      _notice = null;
    });
    try {
      final log = await ref.read(diagnosticLogProvider.future);
      await log.clear();
      ref.invalidate(diagnosticEventsProvider);
      if (mounted) setState(() => _notice = t.diagnosticsCleared);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = t.diagnosticsClearFailure;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final events = ref.watch(diagnosticEventsProvider);
    return EntryPage(
      children: [
        Heading(t.diagnostics),
        Text(t.diagnosticsBody),
        const SizedBox(height: 8),
        Text(t.diagnosticsNoSend),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          SettingsNotice(message: _notice!, isError: _failed),
        ],
        const SizedBox(height: 24),
        events.when(
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isEmpty)
                Text(t.diagnosticsEmpty)
              else ...[
                for (final event in items.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VitalSettingsCard(
                      child: Semantics(
                        container: true,
                        label:
                            '${_label(t, event.code)}, ${displayStamp(context, ref, event.at)}',
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _label(t, event.code),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(displayStamp(context, ref, event.at)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                VitalButton.secondary(
                  onPressed: _busy ? null : _clear,
                  child: Text(t.clear),
                ),
                if (_busy) ...[
                  const SizedBox(height: 8),
                  Semantics(liveRegion: true, child: Text(t.saving)),
                ],
              ],
            ],
          ),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(diagnosticEventsProvider),
          ),
          loading: () => Text(t.loadingRecords),
        ),
      ],
    );
  }
}
