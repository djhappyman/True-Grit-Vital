import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/privacy.dart';
import '../../data/record_store.dart';
import '../../domain/privacy/diagnostics.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart' show profilesProvider;
import '../recording/record_pages.dart' show EntryPage, Heading, LoadFailure;
import 'settings_widgets.dart';

class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  final _commands = <String, String>{};
  final _busy = <String>{};
  final _confirming = <String>{};
  String? _notice;
  bool _failed = false;
  bool _recordedLoadFailure = false;

  Future<void> _recordFailure(DiagnosticCode code) async {
    try {
      final log = await ref.read(diagnosticLogProvider.future);
      await log.record(code, platform: ref.read(diagnosticPlatformProvider));
      ref.invalidate(diagnosticEventsProvider);
    } catch (_) {
      // Diagnostics must never change the primary result.
    }
  }

  Future<bool> _confirm() async {
    final t = AppLocalizations.of(context);
    final title = t.deleteRecords, body = t.deleteMeBody, command = t.delete;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => VitalDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(command),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _run(AdultProfile person) async {
    if (_busy.contains(person.id) || !_confirming.add(person.id)) return;
    final bool confirmed;
    try {
      confirmed = await _confirm();
    } finally {
      _confirming.remove(person.id);
    }
    if (!confirmed || !mounted) return;
    final t = AppLocalizations.of(context);
    // An uncertain retry retains its id only for the same captured revision.
    // A refreshed person is a new command payload and needs a new id.
    final commandKey = 'delete:${person.revision}';
    final command = _commands[commandKey] ??= newCommandId();
    setState(() {
      _busy.add(person.id);
      _notice = null;
      _failed = false;
    });
    try {
      final gateway = ref.read(profilePrivacyActionsProvider);
      await gateway.delete(
        commandId: command,
        personId: meId,
        expectedRevision: person.revision,
      );
      _commands.remove(commandKey);
      if (mounted) {
        setState(() {
          _failed = false;
          _notice = t.privacyMeDeleted;
        });
      }
    } catch (_) {
      await _recordFailure(DiagnosticCode.profileDelete);
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = t.privacyNotSaved;
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final peopleState = ref.watch(profilesProvider);
    if (peopleState.hasError && !_recordedLoadFailure) {
      _recordedLoadFailure = true;
      Future<void>.microtask(() => _recordFailure(DiagnosticCode.dataLoad));
    }
    return EntryPage(
      children: [
        Heading(t.privacy),
        Text(t.privacyBody),
        const SizedBox(height: 8),
        Text(t.privacyOperator),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          SettingsNotice(message: _notice!, isError: _failed),
        ],
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            t.copies,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Text(t.privacyCopies),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: Text(
            t.deleteRecords,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        peopleState.when(
          data: (people) {
            final person = people.where((p) => p.isMe).firstOrNull;
            if (person == null) return Text(t.profileUnavailable);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsCommandButton(
                  key: const ValueKey('privacy-delete-me'),
                  label: t.delete,
                  destructive: true,
                  semanticLabel: t.deleteRecords,
                  onPressed: _busy.contains(meId) ? null : () => _run(person),
                ),
                if (_busy.contains(meId))
                  Semantics(liveRegion: true, child: Text(t.saving)),
              ],
            );
          },
          error: (_, _) =>
              LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
          loading: () => Text(t.loadingRecords),
        ),
      ],
    );
  }
}
