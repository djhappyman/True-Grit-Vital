import 'package:flutter/material.dart'
    as material
    show MaterialLocalizations, TimeOfDay;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/backup.dart';
import '../../app/app_lock.dart';
import '../../domain/backup/backup_history.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final password = _password.text;
    final confirmation = _confirm.text;
    // Keep the fields visible after a validation error. Clear only once the
    // controller accepts the password, so no observable state retains it.
    if (BackupController.passwordError(password, confirmation) == null) {
      _password.clear();
      _confirm.clear();
    }
    await ref
        .read(backupProvider.notifier)
        .create(password: password, confirmation: confirmation);
  }

  Future<void> _delete() async {
    final text = AppLocalizations.of(context);
    final confirmed = await showVitalDialog<bool>(
      context: context,
      builder: (dialog) => VitalDialog(
        title: Text(text.backupDeleteHeading),
        content: Text(text.backupDeleteBody),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(text.cancel),
          ),
          VitalButton.destructive(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(text.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(backupProvider.notifier).discard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final operations = ref.watch(backupOperationsProvider);
    final state = ref.watch(backupProvider);
    final controller = ref.read(backupProvider.notifier);
    return Scaffold(
      headers: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton.secondary(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/today');
                  }
                },
                child: Text(text.back),
              ),
            ),
          ),
        ),
      ],
      child: SingleChildScrollView(
        child: VitalPageBody(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  text.backup,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (operations == null)
                _FailurePanel(
                  heading: text.backupUnavailableHeading,
                  body: text.backupUnavailableBody,
                )
              else if (!operations.destinationSupported)
                const _SaveUnavailablePanel()
              else
                switch (state.phase) {
                  BackupPhase.idle ||
                  BackupPhase.failed ||
                  BackupPhase.cancelled => _form(
                    context,
                    text,
                    state,
                    controller,
                  ),
                  BackupPhase.preparing ||
                  BackupPhase.encrypting ||
                  BackupPhase.verifying => _progress(
                    text,
                    state,
                    controller,
                    allowCancel: true,
                  ),
                  BackupPhase.saving => _progress(
                    text,
                    state,
                    controller,
                    allowCancel: false,
                  ),
                  BackupPhase.ready => _ready(context, text, state, controller),
                  BackupPhase.saved => _saved(text, state, controller),
                },
              const SizedBox(height: 24),
              const BackupHistoryPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations text,
    BackupState state,
    BackupController controller,
  ) {
    final passwordError = switch (state.errorCode) {
      'backup_password_short' => text.backupShortPassword,
      'backup_password_long' => text.backupPasswordLong,
      _ => null,
    };
    final confirmError = state.errorCode == 'backup_password_mismatch'
        ? text.backupPasswordMismatch
        : null;
    final failure =
        state.errorCode == null || passwordError != null || confirmError != null
        ? null
        : _failureCopy(text, state.errorCode!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            text.backupCreateHeading,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        _ScopeNotice(text: text),
        const SizedBox(height: 16),
        Text(text.backupPasswordLoss),
        const SizedBox(height: 20),
        if (failure != null) ...[
          _FailurePanel(heading: failure.$1, body: failure.$2),
          const SizedBox(height: 20),
        ],
        _PasswordField(
          key: const ValueKey('backup-password'),
          label: text.backupPasswordLabel,
          helper: text.backupPasswordHelper,
          controller: _password,
          error: passwordError,
        ),
        _PasswordField(
          key: const ValueKey('backup-confirm'),
          label: text.backupConfirmLabel,
          controller: _confirm,
          error: confirmError,
          last: true,
          onSubmitted: _create,
        ),
        Text(text.backupPasswordNotStored),
        const SizedBox(height: 16),
        VitalButton(
          key: const ValueKey('backup-create'),
          onPressed: controller.available ? _create : null,
          child: Text(text.create),
        ),
      ],
    );
  }

  Widget _progress(
    AppLocalizations text,
    BackupState state,
    BackupController controller, {
    required bool allowCancel,
  }) {
    final label = switch (state.phase) {
      BackupPhase.preparing => text.backupPreparing,
      BackupPhase.encrypting => text.backupEncrypting,
      BackupPhase.verifying => text.backupChecking,
      BackupPhase.saving => text.saving,
      _ => text.working,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: label,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: label,
          value: state.fraction == null
              ? null
              : '${(state.fraction! * 100).round()}%',
          child: ExcludeSemantics(
            child: LinearProgressIndicator(
              key: const ValueKey('backup-progress'),
              value: state.fraction,
            ),
          ),
        ),
        if (allowCancel) ...[
          const SizedBox(height: 20),
          VitalButton.secondary(
            key: const ValueKey('backup-cancel'),
            onPressed: controller.cancel,
            child: Text(text.cancel),
          ),
        ],
      ],
    );
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations text,
    BackupState state,
    BackupController controller,
  ) {
    final creation = state.creation!;
    final saveFailure =
        state.errorCode == null || state.errorCode == 'backup_history_failed'
        ? null
        : _failureCopy(text, state.errorCode!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorCode == 'backup_history_failed') ...[
          Text(text.featureBackupHistoryWriteFailed),
          const SizedBox(height: 12),
        ],
        if (saveFailure != null) ...[
          _FailurePanel(heading: saveFailure.$1, body: saveFailure.$2),
          const SizedBox(height: 12),
        ],
        _FailurePanel(
          heading: text.backupReadyHeading,
          body: text.backupContents(
            creation.inventory.peopleCount,
            creation.inventory.attachmentCount,
          ),
        ),
        const SizedBox(height: 12),
        Text(text.backupSize(_size(creation.byteCount))),
        Text(text.backupCreated(_created(context, creation.createdAt))),
        Text(text.backupKeepSafe),
        Text(text.backupUnsavedWarning),
        const SizedBox(height: 20),
        VitalButton(
          key: const ValueKey('backup-save'),
          onPressed: controller.canSave ? controller.save : null,
          child: Text(text.save),
        ),
        const SizedBox(height: 8),
        VitalButton.destructive(
          key: const ValueKey('backup-delete'),
          onPressed: _delete,
          child: Text(text.delete),
        ),
      ],
    );
  }

  Widget _saved(
    AppLocalizations text,
    BackupState state,
    BackupController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FailurePanel(
        heading: text.backupSavedHeading,
        body: text.backupSavedBody(state.savedName ?? ''),
      ),
      if (state.errorCode == 'backup_history_failed') ...[
        const SizedBox(height: 12),
        Text(text.featureBackupHistoryWriteFailed),
      ],
      const SizedBox(height: 20),
      VitalButton(
        key: const ValueKey('backup-done'),
        onPressed: controller.reset,
        child: Text(text.done),
      ),
    ],
  );

  static String _created(BuildContext context, DateTime value) {
    final localizations = material.MaterialLocalizations.of(context);
    final local = value.toLocal();
    final date = localizations.formatFullDate(local);
    final time = localizations.formatTimeOfDay(
      material.TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date $time';
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(1)} GiB';
  }
}

/// Read-only receipts inside the existing guarded backup workflow.
class BackupHistoryPanel extends ConsumerWidget {
  const BackupHistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appLockProvider).locked) return const SizedBox.shrink();
    final text = AppLocalizations.of(context);
    final history = ref.watch(backupHistoryProvider);
    return VitalSurface(
      child: history.when(
        skipError: false,
        skipLoadingOnReload: false,
        data: (receipts) {
          final saved = receipts
              .where((receipt) => receipt.savedAt != null)
              .firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text.featureBackupHistoryLastSave,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                saved == null
                    ? text.featureBackupHistoryNoSave
                    : text.featureBackupHistorySaved(
                        _BackupPageState._created(context, saved.savedAt!),
                      ),
              ),
              const SizedBox(height: 12),
              VitalDisclosure(
                key: const ValueKey('backup-history-disclosure'),
                title: text.featureBackupHistory,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(text.featureBackupHistoryHelp),
                    if (receipts.isEmpty) ...[
                      const SizedBox(height: 12),
                      Text(text.featureBackupHistoryEmpty),
                    ],
                    for (final receipt in receipts) ...[
                      const SizedBox(height: 16),
                      _BackupReceiptDetails(receipt: receipt),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => Text(text.featureBackupHistoryLoading),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text.featureBackupHistoryFailed),
            const SizedBox(height: 8),
            VitalButton.secondary(
              onPressed: () => ref.invalidate(backupHistoryProvider),
              child: Text(text.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupReceiptDetails extends StatelessWidget {
  const _BackupReceiptDetails({required this.receipt});
  final BackupReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return Column(
      key: ValueKey('backup-receipt-${receipt.sha256}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.featureBackupHistoryChecked(
            _BackupPageState._created(context, receipt.verifiedAt),
          ),
        ),
        Text(
          receipt.savedAt == null
              ? text.featureBackupHistoryUnsaved
              : text.featureBackupHistorySaved(
                  _BackupPageState._created(context, receipt.savedAt!),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          text.featureBackupHistoryFacts(
            receipt.byteCount,
            receipt.schemaVersion,
            receipt.recordCount,
            receipt.itemCount,
            receipt.attachmentCount,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(text.featureBackupHistoryHash(receipt.sha256)),
      ],
    );
  }
}

class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice({required this.text});
  final AppLocalizations text;
  @override
  Widget build(BuildContext context) => VitalSurface(
    role: VitalSurfaceRole.section,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.backupAllAdults,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(text.backupIncludesFiles),
      ],
    ),
  );
}

class _SaveUnavailablePanel extends StatelessWidget {
  const _SaveUnavailablePanel();
  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return _FailurePanel(
      heading: text.backupCannotSave,
      body: text.backupSavingUnavailable,
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({required this.heading, required this.body});
  final String heading, body;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: VitalSurface(
      role: VitalSurfaceRole.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              heading,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    ),
  );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.error,
    this.onSubmitted,
    this.last = false,
  });
  final String label;
  final TextEditingController controller;
  final String? helper, error;
  final VoidCallback? onSubmitted;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          textField: true,
          child: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => onSubmitted?.call(),
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
          ),
        ),
        if (helper != null) Text(helper!),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
      ],
    ),
  );
}

(String, String) _failureCopy(
  AppLocalizations text,
  String code,
) => switch (code) {
  'backup_no_space' => (text.backupNoSpaceHeading, text.backupNoSpaceBody),
  'backup_wrong_password' => (
    text.backupWrongPassword,
    text.backupWrongPasswordBody,
  ),
  'backup_unsupported_version' || 'backup_unsupported_schema' => (
    text.backupNewerHeading,
    text.backupNewerBody,
  ),
  'backup_attachment_mismatch' ||
  'backup_invalid_dataset' ||
  'backup_corrupt' => (text.backupIncompleteHeading, text.backupIncompleteBody),
  'backup_missing' ||
  'backup_staging' => (text.backupDamagedHeading, text.backupDamagedBody),
  'backup_locked' ||
  'app_locked' => (text.backupLockedHeading, text.backupLocked),
  'backup_busy' => (text.backupBusyHeading, text.backupBusyBody),
  'backup_save_failed' => (
    text.backupSaveFailedHeading,
    text.backupSaveFailedBody,
  ),
  'backup_save_limit' => (text.backupSaveFailedHeading, text.backupSaveLimit),
  'backup_cancelled' => (text.backupCancelled, text.backupCancelledBody),
  'backup_unavailable' => (
    text.backupUnavailableHeading,
    text.backupUnavailableBody,
  ),
  _ => (text.backupFailedHeading, text.backupFailedBody),
};
