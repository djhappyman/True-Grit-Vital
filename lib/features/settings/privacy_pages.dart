import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/privacy.dart';
import '../../data/record_store.dart';
import '../../domain/privacy/diagnostics.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart' show personLabel, profilesProvider;
import '../recording/record_pages.dart' show EntryPage, Heading, LoadFailure;
import 'settings_widgets.dart';

enum _PrivacyAction { archive, reactivate, delete }

/// Scoped archive, reactivation and deletion with explicit consequences.
///
/// Every action carries the captured person id and revision. The store rejects
/// a stale context, and a reused command id makes an uncertain retry idempotent
/// instead of creating a second action.
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

  Future<bool> _confirm(AdultProfile person, _PrivacyAction action) async {
    final t = AppLocalizations.of(context);
    final name = personLabel(
      t,
      ref.read(profilesProvider).value ?? [],
      person.id,
    );
    final (title, body, command) = switch (action) {
      _PrivacyAction.archive => (
        t.archivePerson,
        t.archiveBody(name),
        t.archive,
      ),
      _PrivacyAction.reactivate => (
        t.reactivate,
        t.reactivateBody(name),
        t.reactivate,
      ),
      _PrivacyAction.delete => (
        person.isMe ? t.deleteRecords : t.deletePerson,
        person.isMe ? t.deleteMeBody : t.deleteProfileBody(name),
        t.delete,
      ),
    };
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
          action == _PrivacyAction.delete
              ? VitalButton.destructive(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(command),
                )
              : VitalButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(command),
                ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _run(AdultProfile person, _PrivacyAction action) async {
    if (_busy.contains(person.id) || !_confirming.add(person.id)) return;
    final bool confirmed;
    try {
      confirmed = await _confirm(person, action);
    } finally {
      _confirming.remove(person.id);
    }
    if (!confirmed || !mounted) return;
    final t = AppLocalizations.of(context);
    final label = personLabel(
      t,
      ref.read(profilesProvider).value ?? [],
      person.id,
    );
    // An uncertain retry retains its id only for the same captured revision.
    // A refreshed person is a new command payload and needs a new id.
    final commandKey = '${action.name}:${person.id}:${person.revision}';
    final command = _commands[commandKey] ??= newCommandId();
    setState(() {
      _busy.add(person.id);
      _notice = null;
      _failed = false;
    });
    try {
      final gateway = ref.read(profilePrivacyActionsProvider);
      switch (action) {
        case _PrivacyAction.archive:
          await gateway.archive(
            commandId: command,
            personId: person.id,
            expectedRevision: person.revision,
          );
        case _PrivacyAction.reactivate:
          await gateway.reactivate(
            commandId: command,
            personId: person.id,
            expectedRevision: person.revision,
          );
        case _PrivacyAction.delete:
          await gateway.delete(
            commandId: command,
            personId: person.id,
            expectedRevision: person.revision,
          );
      }
      _commands.remove(commandKey);
      if (mounted) {
        setState(() {
          _failed = false;
          _notice = switch (action) {
            _PrivacyAction.archive => t.privacyArchived(label),
            _PrivacyAction.reactivate => t.privacyReactivated(label),
            _PrivacyAction.delete =>
              person.isMe ? t.privacyMeDeleted : t.privacyDeleted(label),
          };
        });
      }
    } catch (_) {
      await _recordFailure(
        action == _PrivacyAction.delete
            ? DiagnosticCode.profileDelete
            : DiagnosticCode.profileArchive,
      );
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
        const SizedBox(height: 8),
        Text(t.privacyArchiveHelp),
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
            t.people,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        peopleState.when(
          data: (people) {
            final active = people.where((person) => !person.isArchived);
            final archived = people.where((person) => person.isArchived);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final person in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PersonCard(
                      name: personLabel(t, people, person.id),
                      isMe: person.isMe,
                      busy: _busy.contains(person.id),
                      actions: [
                        if (!person.isMe)
                          SettingsCommandButton(
                            key: ValueKey('privacy-archive-${person.id}'),
                            label: t.archive,
                            semanticLabel: t.privacyArchiveSemantic(
                              personLabel(t, people, person.id),
                            ),
                            onPressed: _busy.contains(person.id)
                                ? null
                                : () => _run(person, _PrivacyAction.archive),
                          ),
                        SettingsCommandButton(
                          key: ValueKey('privacy-delete-${person.id}'),
                          label: t.delete,
                          destructive: true,
                          semanticLabel: person.isMe
                              ? t.privacyDeleteRecordsSemantic(
                                  personLabel(t, people, person.id),
                                )
                              : t.privacyDeleteSemantic(
                                  personLabel(t, people, person.id),
                                ),
                          onPressed: _busy.contains(person.id)
                              ? null
                              : () => _run(person, _PrivacyAction.delete),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    t.archivedPeople,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Text(t.privacyArchivedHelp),
                const SizedBox(height: 12),
                if (archived.isEmpty)
                  Text(t.privacyNoneArchived)
                else
                  for (final person in archived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PersonCard(
                        name: personLabel(t, people, person.id),
                        archived: true,
                        busy: _busy.contains(person.id),
                        actions: [
                          SettingsCommandButton(
                            key: ValueKey('privacy-reactivate-${person.id}'),
                            label: t.reactivate,
                            semanticLabel: t.privacyReactivateSemantic(
                              personLabel(t, people, person.id),
                            ),
                            onPressed: _busy.contains(person.id)
                                ? null
                                : () => _run(person, _PrivacyAction.reactivate),
                          ),
                          SettingsCommandButton(
                            key: ValueKey('privacy-delete-${person.id}'),
                            label: t.delete,
                            destructive: true,
                            semanticLabel: t.privacyDeleteSemantic(
                              personLabel(t, people, person.id),
                            ),
                            onPressed: _busy.contains(person.id)
                                ? null
                                : () => _run(person, _PrivacyAction.delete),
                          ),
                        ],
                      ),
                    ),
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.name,
    required this.actions,
    required this.busy,
    this.isMe = false,
    this.archived = false,
  });

  final String name;
  final List<Widget> actions;
  final bool busy, isMe, archived;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            isMe
                ? t.privacyMeOwner
                : archived
                ? t.archived
                : t.privacyOtherOwner,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
          if (busy) ...[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(t.saving)),
          ],
        ],
      ),
    );
  }
}
