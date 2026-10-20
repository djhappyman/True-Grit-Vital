import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/restore.dart';
import '../../domain/restore/restore.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import 'restore_recovery_banner.dart';

/// Staged validation, explicit full-replacement confirmation and truthful
/// progress for one protected backup. The route is registered by the lead;
/// T08 owns the settings entry that links here.
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    await ref.read(restoreProvider.notifier).choose();
  }

  Future<void> _check() async {
    await ref.read(restoreProvider.notifier).check(_password.text);
    if (!mounted) return;
    if (ref.read(restoreProvider).phase == RestorePhase.preview) {
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locked = ref.watch(appLockProvider.select((state) => state.locked));
    final gateway = ref.watch(restoreGatewayProvider);
    final state = ref.watch(restoreProvider);
    final active =
        state.phase == RestorePhase.preparing ||
        state.phase == RestorePhase.replacing;
    return PopScope(
      canPop: !active,
      child: Scaffold(
        headers: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  VitalButton.secondary(
                    onPressed: active
                        ? null
                        : () => context.canPop()
                              ? context.pop()
                              : context.go('/today'),
                    child: Text(t.back),
                  ),
                ],
              ),
            ),
          ),
        ],
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: VitalPageBody(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.phase != RestorePhase.complete)
                    const RestoreRecoveryBanner(),
                  HeadingText(t.restoreTitle),
                  const SizedBox(height: 16),
                  if (locked)
                    _message(t.restoreLocked)
                  else if (gateway == null || !gateway.supported)
                    _unavailable(t)
                  else
                    ..._body(t, state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations t, RestoreState state) =>
      switch (state.phase) {
        RestorePhase.choosing ||
        RestorePhase.checking ||
        RestorePhase.preparing ||
        RestorePhase.replacing => [_working(t, state)],
        RestorePhase.preview => [_preview(t, state)],
        RestorePhase.complete => [_complete(t, state)],
        RestorePhase.failed => [_failed(t, state)],
        RestorePhase.cancelled => [_cancelled(t, state)],
        RestorePhase.idle => [_chooser(t, state)],
      };

  Widget _unavailable(AppLocalizations t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HeadingText(t.restoreUnavailable, level: 2),
      const SizedBox(height: 12),
      _message(t.restoreUnavailableBody),
    ],
  );

  Widget _chooser(AppLocalizations t, RestoreState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.restoreIntro),
      const SizedBox(height: 20),
      Text(
        t.restoreArchiveLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(state.fileName ?? t.restoreArchiveNone),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton.secondary(
          onPressed: state.busy ? null : _choose,
          child: Text(t.restoreChoose),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        t.restorePasswordLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Semantics(
        label: t.restorePasswordLabel,
        child: TextField(
          controller: _password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !state.busy,
          onChanged: (_) => setState(() {}),
        ),
      ),
      const SizedBox(height: 8),
      Text(t.restorePasswordHelp),
      if (state.errorCode != null) ...[
        const SizedBox(height: 8),
        _error(t, state.errorCode!),
      ],
      const SizedBox(height: 20),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton(
          onPressed:
              state.busy || state.fileName == null || _password.text.isEmpty
              ? null
              : _check,
          child: Text(t.restoreCheck),
        ),
      ),
    ],
  );

  Widget _preview(AppLocalizations t, RestoreState state) {
    final preview = state.preview;
    if (preview == null) return _message(t.restoreFailedBody);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeadingText(t.restorePreviewTitle, level: 2),
        const SizedBox(height: 12),
        Text(preview.fileName),
        Text(t.restoreCreated(_date(preview.createdAt))),
        if (preview.upgradesSchema) ...[
          const SizedBox(height: 8),
          Text(t.restoreOlderWarning),
        ],
        const SizedBox(height: 20),
        Text(
          t.restorePeople,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (preview.coverage.isEmpty)
          for (final person in preview.people)
            Text(
              person.archived
                  ? '${person.name} (${t.restoreArchived})'
                  : person.name,
            )
        else
          for (final coverage in preview.coverage) ...[
            Text(
              coverage.person.archived
                  ? '${coverage.person.name} (${t.restoreArchived})'
                  : coverage.person.name,
            ),
            Text(t.restoreRecords(coverage.recordCount)),
            Text(
              coverage.earliestRecord != null && coverage.latestRecord != null
                  ? t.restoreCoverageRange(
                      _date(coverage.earliestRecord!),
                      _date(coverage.latestRecord!),
                    )
                  : t.restoreCoverageEmpty,
            ),
          ],
        const SizedBox(height: 20),
        Text(
          t.restoreCoverage,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          preview.earliestRecord != null && preview.latestRecord != null
              ? t.restoreCoverageRange(
                  _date(preview.earliestRecord!),
                  _date(preview.latestRecord!),
                )
              : t.restoreCoverageEmpty,
        ),
        Text(t.restoreLocalDates),
        const SizedBox(height: 20),
        Text(t.restoreRecords(preview.recordCount)),
        Text(t.restoreSubstances(preview.itemCount)),
        Text(t.restoreSupporting(preview.supportingCount)),
        Text(t.restoreAttachments(preview.attachmentCount)),
        const SizedBox(height: 20),
        Text(t.restoreConsequence),
        const SizedBox(height: 12),
        _ReplaceConfirmation(
          label: t.restoreReplaceAll,
          description: t.restoreReplaceAllHelp,
          value: state.confirmed,
          onChanged: ref.read(restoreProvider.notifier).setConfirmed,
        ),
        if (state.errorCode != null) _error(t, state.errorCode!),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton.destructive(
              onPressed: state.confirmed
                  ? () => ref.read(restoreProvider.notifier).replace()
                  : null,
              child: Text(t.restoreReplace),
            ),
            VitalButton.secondary(
              onPressed: () => ref.read(restoreProvider.notifier).reset(),
              child: Text(t.restoreCancel),
            ),
          ],
        ),
      ],
    );
  }

  Widget _working(AppLocalizations t, RestoreState state) {
    final stage = switch (state.phase) {
      RestorePhase.checking => t.restoreChecking,
      RestorePhase.preparing => t.restorePreparing,
      RestorePhase.replacing => t.restoreReplacing,
      _ => t.restoreChecking,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: stage,
          child: Text(
            stage,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        if (state.fraction != null)
          LinearProgressIndicator(value: state.fraction)
        else
          const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(t.restoreWorking),
        if (state.canCancelCheck) ...[
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalButton.secondary(
              onPressed: ref.read(restoreProvider.notifier).cancelCheck,
              child: Text(t.restoreCancel),
            ),
          ),
        ],
      ],
    );
  }

  Widget _complete(AppLocalizations t, RestoreState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HeadingText(t.restoreCompleteTitle, level: 2),
      const SizedBox(height: 12),
      Text(
        t.restoreCompleteBody(state.preview?.fileName ?? state.fileName ?? ''),
      ),
      if (state.reminderWarning)
        Semantics(
          liveRegion: true,
          child: Text(
            t.restoreReminderWarning,
            style: TextStyle(color: Theme.of(context).colorScheme.destructive),
          ),
        )
      else
        Text(t.restoreCompleteReminder),
      const SizedBox(height: 8),
      Text(t.restoreCompleteCleared),
      const SizedBox(height: 20),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton(
          onPressed: () {
            ref.read(restoreProvider.notifier).reset();
            context.go('/today');
          },
          child: Text(t.restoreDone),
        ),
      ),
    ],
  );

  Widget _failed(AppLocalizations t, RestoreState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HeadingText(t.restoreFailedTitle, level: 2),
      const SizedBox(height: 12),
      _error(t, state.errorCode ?? RestoreCodes.failed),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          VitalButton(
            onPressed: ref.read(restoreProvider.notifier).retry,
            child: Text(t.restoreRetry),
          ),
          VitalButton.secondary(
            onPressed: () => ref.read(restoreProvider.notifier).reset(),
            child: Text(t.restoreCancel),
          ),
        ],
      ),
    ],
  );

  Widget _cancelled(AppLocalizations t, RestoreState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.restoreCancelled),
      const SizedBox(height: 20),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton(
          onPressed: ref.read(restoreProvider.notifier).retry,
          child: Text(t.restoreRetry),
        ),
      ),
    ],
  );

  Widget _message(String text) => Text(text);

  Widget _error(AppLocalizations t, String code) => Semantics(
    liveRegion: true,
    child: Text(
      _errorText(t, code),
      style: TextStyle(color: Theme.of(context).colorScheme.destructive),
    ),
  );
}

String _errorText(AppLocalizations t, String code) => switch (code) {
  RestoreCodes.unavailable => t.restoreUnavailableBody,
  RestoreCodes.chooseArchive => t.restoreChooseArchive,
  RestoreCodes.passwordRequired => t.restorePasswordRequired,
  RestoreCodes.passwordLong => t.restorePasswordLong,
  RestoreCodes.wrongPassword => t.restoreWrongPassword,
  RestoreCodes.multiplePeople => t.restoreSingleUserRequired,
  RestoreCodes.corrupt => t.restoreCorrupt,
  RestoreCodes.unsupportedVersion => t.restoreUnsupportedVersion,
  RestoreCodes.tooLarge => t.restoreTooLarge,
  RestoreCodes.confirmationRequired => t.restoreConfirmationRequired,
  RestoreCodes.busy => t.restoreBusy,
  RestoreCodes.recoveryRequired => t.restoreRecoveryRequired,
  RestoreCodes.storage => t.restoreStorage,
  RestoreCodes.archiveChanged => t.restoreArchiveChanged,
  RestoreCodes.cancelled => t.restoreCancelled,
  _ => t.restoreFailedBody,
};

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}';
}

/// Local heading keeps the authored 1-3 word rule and shared semantics without
/// importing the routing-heavy app shell.
class HeadingText extends StatelessWidget {
  const HeadingText(this.text, {super.key, this.level = 1});
  final String text;
  final int level;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: TextStyle(
        fontSize: level == 1 ? 28 : 22,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A one-time destructive acknowledgement is a checkbox, not a preference
/// switch. The whole row is one semantic control and one keyboard target.
class _ReplaceConfirmation extends StatelessWidget {
  const _ReplaceConfirmation({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  void _toggle() => onChanged(!value);

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    hint: description,
    checked: value,
    onTap: _toggle,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(description),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Checkbox(
                  state: value
                      ? CheckboxState.checked
                      : CheckboxState.unchecked,
                  onChanged: (state) =>
                      onChanged(state == CheckboxState.checked),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
