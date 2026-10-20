import '../../app/supporting.dart';
import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/attachments.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/attachments.dart';
import '../profiles/profile_pages.dart';
import '../stock/stock_widgets.dart' show stockRecordAmountNumber;
import '../recording/record_pages.dart';

final attachmentJobsProvider = StreamProvider.autoDispose<List<AttachmentJob>>(
  retry: (_, _) => null,
  (ref) async* {
    if (!ref.watch(appLockProvider.select((s) => s.ready && !s.locked))) {
      yield [];
      return;
    }
    yield* (await ref.watch(recordStoreProvider.future)).watchAttachmentJobs();
  },
);
final attachmentLookupProvider = StreamProvider.autoDispose
    .family<AttachmentRecord?, String>(retry: (_, _) => null, (ref, id) async* {
      if (!ref.watch(appLockProvider.select((s) => s.ready && !s.locked))) {
        yield null;
        return;
      }
      yield* (await ref.watch(recordStoreProvider.future))
          .watchAttachmentById(id);
    });
typedef AttachmentQuery = ({
  String personId,
  AttachmentTargetKind targetKind,
  String targetId,
  int offset,
});
final attachmentListProvider = StreamProvider.autoDispose
    .family<List<AttachmentRecord>, AttachmentQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) async* {
      if (!ref.watch(appLockProvider.select((s) => s.ready && !s.locked))) {
        yield [];
        return;
      }
      yield* (await ref.watch(recordStoreProvider.future)).watchAttachments(
        personId: query.personId,
        targetKind: query.targetKind,
        targetId: query.targetId,
        limit: 51,
        offset: query.offset,
      );
    });
String attachmentRoute(AttachmentRecord record) =>
    '/files/${record.personId}/${record.targetKind.name}/${record.targetId}';

String attachmentFailureText(AppLocalizations t, String? code) =>
    switch (code) {
      'app_locked' => t.attachmentLocked,
      'attachment_byte_limit' || 'attachment_empty' => t.attachmentByteError,
      'attachment_image_required' ||
      'attachment_image_limit' ||
      'attachment_image_invalid' ||
      'attachment_frame_limit' => t.attachmentImageError,
      'attachment_page_limit' ||
      'attachment_pdf_invalid' ||
      'attachment_pdf_password' ||
      'attachment_pdf_unavailable' => t.attachmentPdfError,
      'attachment_job_capacity' => t.attachmentBusy,
      'attachment_handoff_capacity' => t.attachmentShareBusy,
      'attachment_name' => t.attachmentNameError,
      'attachment_picker_unavailable' ||
      'attachment_camera_unavailable' ||
      'attachment_save_unavailable' ||
      'attachment_handoff_unavailable' => t.attachmentUnavailable,
      'attachment_target_revision' ||
      'attachment_revision' ||
      'person_context' ||
      'ownership' ||
      'generation' ||
      'deleted_context' ||
      'attachment_picker_context' => t.attachmentStale,
      _ => t.attachmentFailed,
    };
String? attachmentNoticeText(AppLocalizations t, String? notice) =>
    switch (notice) {
      'saved' => t.attachmentSaved,
      'cancelled' => t.attachmentCancelled,
      'interrupted' => t.attachmentInterrupted,
      'shared' => t.attachmentShared,
      'copySaved' => t.attachmentCopySaved,
      _ => null,
    };
String attachmentPreviewHelpCopy(
  AppLocalizations t,
  AttachmentCapabilities capabilities,
) => capabilities.share && capabilities.save
    ? t.attachmentPreviewHelp
    : capabilities.share
    ? t.attachmentPreviewHelpShare
    : capabilities.save
    ? t.attachmentPreviewHelpSave
    : t.attachmentPreviewHelpNone;
String attachmentNoPreviewCopy(
  AppLocalizations t,
  AttachmentCapabilities capabilities,
) => capabilities.share && capabilities.save
    ? t.attachmentNoPreviewShareSave
    : capabilities.share
    ? t.attachmentNoPreviewShare
    : capabilities.save
    ? t.attachmentNoPreviewSave
    : t.attachmentNoPreview;
String attachmentPreviewFailureCopy(
  AppLocalizations t,
  AttachmentCapabilities capabilities,
) => capabilities.share && capabilities.save
    ? t.attachmentPreviewFailureShareSave
    : capabilities.share
    ? t.attachmentPreviewFailureShare
    : capabilities.save
    ? t.attachmentPreviewFailureSave
    : t.attachmentPreviewFailure;

class AttachmentTargetSummary extends ConsumerWidget {
  const AttachmentTargetSummary({
    super.key,
    required this.personId,
    required this.kind,
    required this.targetId,
  });
  final String personId, targetId;
  final AttachmentTargetKind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (kind == AttachmentTargetKind.item) {
      final item = ref.watch(itemLookupProvider(targetId)).value;
      return Text(
        item == null || item.personId != personId
            ? t.noItem
            : t.attachmentTargetItem(item.name),
      );
    }
    if (kind == AttachmentTargetKind.supporting) {
      final supporting = ref
          .watch(
            supportingLookupProvider((
              personId: personId,
              id: targetId,
              revision: null,
            )),
          )
          .value;
      return Text(
        supporting == null
            ? t.supportingUnavailable
            : t.supportingTarget(supporting.snapshot.title),
      );
    }
    final record = ref
        .watch(recordLookupProvider((recordId: targetId, personId: personId)))
        .value;
    return Text(
      record == null
          ? t.noItem
          : t.attachmentTargetDose(
              record.name,
              stockRecordAmountNumber(t, record),
              record.actualUnit,
              displayStamp(context, ref, record.actualAt),
            ),
    );
  }
}

class AttachmentJobs extends ConsumerWidget {
  const AttachmentJobs({super.key, this.personId, this.targetId});
  final String? personId, targetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        runtime = ref.watch(attachmentsControllerProvider),
        jobs = ref.watch(attachmentJobsProvider);
    return jobs.when(
      data: (all) {
        final selected = all
            .where(
              (job) =>
                  (personId == null || job.personId == personId) &&
                  (targetId == null || job.targetId == targetId),
            )
            .toList();
        if (selected.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(t.attachmentJobs),
            for (final job in selected)
              Padding(
                key: ValueKey(job.id),
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.profileOwner(ownerLabel(ref, t, job.personId))),
                    AttachmentTargetSummary(
                      personId: job.personId,
                      kind: job.targetKind,
                      targetId: job.targetId,
                    ),
                    Text(t.attachmentRecordRevision(job.targetRevision)),
                    Text(switch (job.state) {
                      AttachmentJobState.awaitingPicker => t.attachmentAwaiting,
                      AttachmentJobState.importing => t.attachmentStaging,
                      _ => t.attachmentInterrupted,
                    }),
                    if (job.receivedBytes > 0)
                      Text(t.attachmentImportAmount(job.receivedBytes)),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        VitalButton.secondary(
                          onPressed: runtime.busy
                              ? null
                              : () => ref
                                    .read(
                                      attachmentsControllerProvider.notifier,
                                    )
                                    .resume(job),
                          child: Text(t.attachmentResume),
                        ),
                        VitalButton.secondary(
                          onPressed: runtime.busy
                              ? null
                              : () => ref
                                    .read(
                                      attachmentsControllerProvider.notifier,
                                    )
                                    .cancel(job),
                          child: Text(t.cancel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      error: (_, _) =>
          LoadFailure(onRetry: () => ref.invalidate(attachmentJobsProvider)),
      loading: () => Text(t.loadingRecords),
    );
  }
}

class AttachmentListPage extends ConsumerStatefulWidget {
  const AttachmentListPage({
    super.key,
    required this.personId,
    required this.targetId,
    required this.kind,
    this.restoreFocus = false,
  });
  final String personId, targetId;
  final AttachmentTargetKind kind;
  final bool restoreFocus;
  @override
  ConsumerState<AttachmentListPage> createState() => _AttachmentListPageState();
}

class _AttachmentListPageState extends ConsumerState<AttachmentListPage> {
  final chooseFocus = FocusNode();
  int offset = 0;
  bool focused = false;
  @override
  void dispose() {
    chooseFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        runtime = ref.watch(attachmentsControllerProvider),
        capabilities = ref.watch(attachmentGatewayProvider).capabilities;
    final owner = people.value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    final item = widget.kind == AttachmentTargetKind.item
        ? ref.watch(itemLookupProvider(widget.targetId)).value
        : null;
    final actual = widget.kind == AttachmentTargetKind.record
        ? ref
              .watch(
                recordLookupProvider((
                  recordId: widget.targetId,
                  personId: widget.personId,
                )),
              )
              .value
        : null;
    final supporting = widget.kind == AttachmentTargetKind.supporting
        ? ref
              .watch(
                supportingLookupProvider((
                  personId: widget.personId,
                  id: widget.targetId,
                  revision: null,
                )),
              )
              .value
        : null;
    final revision = item?.personId == widget.personId
        ? item!.revision
        : actual?.revision ?? supporting?.revision;
    final query = (
      personId: widget.personId,
      targetKind: widget.kind,
      targetId: widget.targetId,
      offset: offset,
    );
    final result = ref.watch(attachmentListProvider(query)),
        jobs = ref.watch(attachmentJobsProvider);
    if (!focused && widget.restoreFocus) {
      focused = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chooseFocus.requestFocus();
      });
    }
    final enabled =
        owner != null &&
        !owner.isArchived &&
        revision != null &&
        actual?.isVoided != true &&
        supporting?.isVoided != true &&
        !runtime.busy &&
        (jobs.value?.isEmpty ?? false);
    void begin(AttachmentPickerKind picker) {
      ref
          .read(attachmentsControllerProvider.notifier)
          .begin(
            personId: widget.personId,
            personRevision: owner!.revision,
            targetKind: widget.kind,
            targetId: widget.targetId,
            targetRevision: revision!,
            pickerKind: picker,
          );
    }

    final notice = attachmentNoticeText(t, runtime.notice);
    return EntryPage(
      children: [
        Heading(t.attachments),
        Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
        AttachmentTargetSummary(
          personId: widget.personId,
          kind: widget.kind,
          targetId: widget.targetId,
        ),
        Text(
          widget.kind == AttachmentTargetKind.supporting
              ? t.attachmentSupportingHelp
              : t.attachmentHelp,
        ),
        if (owner == null || revision == null) Text(t.attachmentStale),
        if (owner != null && owner.isArchived)
          Text(t.attachmentArchivedProfile),
        if (actual?.isVoided == true) Text(t.attachmentVoidedRecord),
        if (supporting?.isVoided == true) Text(t.attachmentSupportingVoided),
        const SizedBox(height: 16),
        if (!capabilities.pickFile && !capabilities.photo)
          Text(t.attachmentUnavailable),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (capabilities.pickFile)
              VitalButton(
                focusNode: chooseFocus,
                onPressed: enabled
                    ? () => begin(AttachmentPickerKind.file)
                    : null,
                child: Text(t.attachmentChoose),
              ),
            if (capabilities.photo)
              VitalButton.secondary(
                onPressed: enabled
                    ? () => begin(AttachmentPickerKind.photo)
                    : null,
                child: Text(t.attachmentPhotos),
              ),
            if (capabilities.camera)
              VitalButton.secondary(
                onPressed: enabled
                    ? () => begin(AttachmentPickerKind.camera)
                    : null,
                child: Text(t.attachmentCapture),
              ),
          ],
        ),
        if (capabilities.photo && !capabilities.camera)
          Text(t.attachmentCameraUnavailable),
        const SizedBox(height: 16),
        if (runtime.failureCode != null)
          Semantics(
            liveRegion: true,
            child: Text(attachmentFailureText(t, runtime.failureCode)),
          ),
        if (notice != null) Semantics(liveRegion: true, child: Text(notice)),
        const AttachmentJobs(),
        result.when(
          data: (records) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (records.isEmpty && (jobs.value?.isEmpty ?? false))
                Text(t.attachmentEmpty),
              for (final record in records.take(50))
                AttachmentTile(
                  key: ValueKey(record.id),
                  attachment: record,
                  fallbackFocus: chooseFocus,
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (offset > 0)
                    VitalButton.secondary(
                      onPressed: () => setState(() => offset -= 50),
                      child: Text(t.previous),
                    ),
                  if (records.length > 50)
                    VitalButton.secondary(
                      onPressed: () => setState(() => offset += 50),
                      child: Text(t.next),
                    ),
                ],
              ),
            ],
          ),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(attachmentListProvider(query)),
          ),
          loading: () => Text(t.loadingRecords),
        ),
      ],
    );
  }
}

class AttachmentTile extends ConsumerStatefulWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.fallbackFocus,
  });
  final AttachmentRecord attachment;
  final FocusNode fallbackFocus;
  @override
  ConsumerState<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<AttachmentTile> {
  final focus = FocusNode();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), record = widget.attachment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(t.attachmentBytes(record.inspection!.byteCount)),
          Text(t.attachmentRecordRevision(record.targetRevision)),
          Semantics(
            label: t.attachmentViewFor(
              record.name,
              ownerLabel(ref, t, record.personId),
            ),
            child: VitalButton.secondary(
              focusNode: focus,
              onPressed: () async {
                await context.push('/attachment/${record.id}');
                if (mounted) focus.requestFocus();
              },
              child: Text(t.attachmentReopen),
            ),
          ),
        ],
      ),
    );
  }
}

/// One confirmed removal. Tests override this seam to model a reply that is
/// lost after the store committed, which a widget cannot otherwise observe.
typedef AttachmentDeleteRequest = ({
  String commandId,
  AttachmentRecord attachment,
  int expectedPersonRevision,
});
final attachmentDeleteProvider =
    Provider<Future<void> Function(AttachmentDeleteRequest)>(
      (ref) =>
          (request) async =>
              (await ref.read(recordStoreProvider.future)).deleteAttachment(
                commandId: request.commandId,
                attachment: request.attachment,
                expectedPersonRevision: request.expectedPersonRevision,
              ),
    );

/// Resolves a possibly committed removal before resubmitting its command, so an
/// uncertain reply is never repeated under a different identity.
Future<void> replayAttachmentDelete({
  required RecordStore store,
  required String commandId,
  required Future<void> Function() delete,
}) async {
  if (!await store.operationCommitted(commandId)) await delete();
}

class AttachmentViewerPage extends ConsumerStatefulWidget {
  const AttachmentViewerPage({
    super.key,
    required this.attachmentId,
    this.focusRename = false,
  });
  final String attachmentId;
  final bool focusRename;
  @override
  ConsumerState<AttachmentViewerPage> createState() =>
      _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends ConsumerState<AttachmentViewerPage> {
  final renameFocus = FocusNode(),
      deleteFocus = FocusNode(),
      shareFocus = FocusNode(),
      saveFocus = FocusNode();
  FocusNode? pendingFocus;
  bool deleting = false, focusRestored = false;
  String? completedDeletionRoute;
  // The file and owner revision reviewed for the first confirmation attempt.
  // They are released only once the store has definitively rejected that
  // attempt; see remove.
  String? error, deleteCommand;
  AttachmentRecord? deleteTarget;
  int? deleteOwnerRevision;
  @override
  void dispose() {
    renameFocus.dispose();
    deleteFocus.dispose();
    shareFocus.dispose();
    saveFocus.dispose();
    super.dispose();
  }

  void clearDeleteAttempt() {
    deleteCommand = null;
    deleteTarget = null;
    deleteOwnerRevision = null;
  }

  void restoreFocus(FocusNode node) {
    pendingFocus = node;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(appLockProvider).locked) return;
      pendingFocus?.requestFocus();
      pendingFocus = null;
    });
  }

  Future<void> remove(AttachmentRecord record, int ownerRevision) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => VitalDialog(
        title: Text(t.attachmentDelete),
        content: Text(
          t.attachmentDeleteHelp(
            record.name,
            ownerLabel(ref, t, record.personId),
          ),
        ),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      restoreFocus(deleteFocus);
      return;
    }
    setState(() {
      deleting = true;
      error = null;
    });
    // The first confirmation freezes the file and owner revision the person
    // actually reviewed. A possibly uncertain outcome (a lost acknowledgement
    // or an interrupted write) keeps that identity so the retry can first
    // resolve whether the store already committed instead of removing under a
    // new identity. Only a conflict the store rejected inside its transaction
    // proves nothing was applied; the next confirmation then captures the
    // revisions currently shown, never the stale ones that failed.
    deleteTarget ??= record;
    deleteOwnerRevision ??= ownerRevision;
    final command = deleteCommand ??= newCommandId(),
        target = deleteTarget!,
        expectedPersonRevision = deleteOwnerRevision!;
    try {
      final store = await ref.read(recordStoreProvider.future);
      await replayAttachmentDelete(
        store: store,
        commandId: command,
        delete: () => ref.read(attachmentDeleteProvider)((
          commandId: command,
          attachment: target,
          expectedPersonRevision: expectedPersonRevision,
        )),
      );
      clearDeleteAttempt();
      completedDeletionRoute = '${attachmentRoute(target)}?focus=choose';
      if (mounted && !ref.read(appLockProvider).locked) {
        context.go(completedDeletionRoute!);
      }
    } on CommandConflict catch (failure) {
      // _command refuses inside its transaction, so a conflict means this
      // attempt applied nothing. An app lock only blocked the resolution read,
      // so keep the identity and let the next confirmation resolve it.
      if (failure.code != 'app_locked') clearDeleteAttempt();
      if (mounted) {
        setState(() => error = attachmentFailureText(t, failure.code));
      }
    } catch (_) {
      // The outcome may be committed but unacknowledged. Keep the identity so
      // the next explicit confirmation resolves it before resubmitting.
      if (mounted) {
        setState(() => error = attachmentFailureText(t, null));
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Future<void> handoff(AttachmentRecord record, {required bool save}) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => VitalDialog(
        title: Text(save ? t.attachmentSaveHeading : t.attachmentShareHeading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              save
                  ? t.attachmentSaveFor(
                      record.name,
                      ownerLabel(ref, t, record.personId),
                    )
                  : t.attachmentShareHelp(
                      record.name,
                      ownerLabel(ref, t, record.personId),
                    ),
            ),
            if (!save) Text(t.attachmentShareLifetime),
          ],
        ),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(save ? t.save : t.attachmentShare),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(attachmentsControllerProvider.notifier)
          .handoff(record, save: save);
    }
    if (mounted) restoreFocus(save ? saveFocus : shareFocus);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        result = ref.watch(attachmentLookupProvider(widget.attachmentId)),
        runtime = ref.watch(attachmentsControllerProvider),
        capabilities = ref.watch(attachmentGatewayProvider).capabilities,
        people = ref.watch(profilesProvider);
    ref.listen(appLockProvider, (_, next) {
      if (!next.locked && completedDeletionRoute != null) {
        context.go(completedDeletionRoute!);
      } else if (!next.locked && pendingFocus != null) {
        restoreFocus(pendingFocus!);
      }
    });
    if (widget.focusRename && !focusRestored) {
      focusRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !renameFocus.hasFocus) renameFocus.requestFocus();
      });
    }
    return result.when(
      data: (record) {
        if (record == null) {
          return EntryPage(
            children: [Heading(t.attachments), Text(t.attachmentStale)],
          );
        }
        final owner = people.value
            ?.where((p) => p.id == record.personId)
            .firstOrNull;
        final enabled =
            owner != null && !owner.isArchived && !runtime.busy && !deleting;
        final notice = attachmentNoticeText(t, runtime.notice);
        return EntryPage(
          onBack: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(attachmentRoute(record));
            }
          },
          children: [
            Heading(t.attachmentOriginal),
            Text(record.name),
            Text(t.profileOwner(ownerLabel(ref, t, record.personId))),
            AttachmentTargetSummary(
              personId: record.personId,
              kind: record.targetKind,
              targetId: record.targetId,
            ),
            Text(t.attachmentRecordRevision(record.targetRevision)),
            Text(t.attachmentBytes(record.inspection!.byteCount)),
            if (record.inspection!.mediaKind != AttachmentMediaKind.other)
              Text(attachmentPreviewHelpCopy(t, capabilities)),
            AttachmentPreviewSurface(attachment: record),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            if (runtime.failureCode != null)
              Semantics(
                liveRegion: true,
                child: Text(attachmentFailureText(t, runtime.failureCode)),
              ),
            if (notice != null)
              Semantics(liveRegion: true, child: Text(notice)),
            if (people.hasValue && owner == null) Text(t.attachmentStale),
            if (owner != null && owner.isArchived)
              Text(t.attachmentArchivedProfile),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                VitalButton.secondary(
                  focusNode: renameFocus,
                  onPressed: !enabled
                      ? null
                      : () => context.push('/attachment/${record.id}/rename'),
                  child: Text(t.attachmentRename),
                ),
                VitalButton.secondary(
                  focusNode: deleteFocus,
                  onPressed: !enabled
                      ? null
                      : () => remove(record, owner.revision),
                  child: Text(t.delete),
                ),
                if (capabilities.share)
                  VitalButton.secondary(
                    focusNode: shareFocus,
                    onPressed: !enabled
                        ? null
                        : () => handoff(record, save: false),
                    child: Text(t.attachmentShare),
                  ),
                if (capabilities.save)
                  VitalButton.secondary(
                    focusNode: saveFocus,
                    onPressed: !enabled
                        ? null
                        : () => handoff(record, save: true),
                    child: Text(t.save),
                  ),
              ],
            ),
          ],
        );
      },
      error: (_, _) => EntryPage(
        children: [
          LoadFailure(
            onRetry: () =>
                ref.invalidate(attachmentLookupProvider(widget.attachmentId)),
          ),
        ],
      ),
      loading: () => EntryPage(children: [Text(t.loadingRecords)]),
    );
  }
}

enum SupportingSourceAvailability { available, changed, unavailable }

/// The saved source must match the captured owner, attachment revision and
/// content version. A renamed or current attachment never substitutes for it.
SupportingSourceAvailability supportingSourceAvailability({
  required AttachmentRecord? attachment,
  required String personId,
  required int revision,
  required String contentVersionId,
}) {
  if (attachment == null ||
      attachment.personId != personId ||
      attachment.targetKind != AttachmentTargetKind.supporting) {
    return SupportingSourceAvailability.unavailable;
  }
  if (attachment.revision != revision ||
      attachment.versionId != contentVersionId) {
    return SupportingSourceAvailability.changed;
  }
  if (attachment.state != AttachmentState.ready ||
      attachment.inspection == null) {
    return SupportingSourceAvailability.unavailable;
  }
  return SupportingSourceAvailability.available;
}

class SupportingSourceViewerPage extends ConsumerWidget {
  const SupportingSourceViewerPage({
    super.key,
    required this.personId,
    required this.attachmentId,
    required this.revision,
    required this.contentVersionId,
  });
  final String personId, attachmentId, contentVersionId;
  final int revision;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (ref.watch(appLockProvider.select((s) => s.locked))) {
      return EntryPage(
        children: [Heading(t.supportingSource), Text(t.supportingLocked)],
      );
    }
    final result = ref.watch(attachmentLookupProvider(attachmentId));
    return result.when(
      data: (record) {
        final availability = supportingSourceAvailability(
          attachment: record,
          personId: personId,
          revision: revision,
          contentVersionId: contentVersionId,
        );
        return EntryPage(
          onBack: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(
                Uri(
                  path: '/supporting',
                  queryParameters: {'person': personId},
                ).toString(),
              );
            }
          },
          children: [
            Heading(t.supportingSource),
            if (availability == SupportingSourceAvailability.available) ...[
              Text(t.profileOwner(ownerLabel(ref, t, personId))),
              Text(record!.name),
              Text(t.supportingSourceViewing(record.revision)),
              Text(t.attachmentBytes(record.inspection!.byteCount)),
              AttachmentPreviewSurface(attachment: record),
            ] else if (availability == SupportingSourceAvailability.changed)
              // Do not show the current name or bytes: they are not the saved
              // source the record points at.
              Text(t.supportingSourceChanged)
            else
              Text(t.supportingSourceUnavailable),
          ],
        );
      },
      error: (_, _) => EntryPage(
        children: [
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () =>
                ref.invalidate(attachmentLookupProvider(attachmentId)),
          ),
        ],
      ),
      loading: () => EntryPage(children: [Text(t.loadingRecords)]),
    );
  }
}

class AttachmentPreviewSurface extends ConsumerStatefulWidget {
  const AttachmentPreviewSurface({super.key, required this.attachment});
  final AttachmentRecord attachment;
  @override
  ConsumerState<AttachmentPreviewSurface> createState() =>
      _AttachmentPreviewSurfaceState();
}

class _AttachmentPreviewSurfaceState
    extends ConsumerState<AttachmentPreviewSurface> {
  AttachmentPin? pin;
  AttachmentPreview? preview;
  Uint8List? bytes;
  RecordStore? store;
  final transform = TransformationController();
  int page = 1, epoch = 0;
  bool loading = false, failed = false;
  double zoom = 1;
  void clear() {
    epoch++;
    loading = false;
    preview?.dispose();
    preview = null;
    bytes?.fillRange(0, bytes!.length, 0);
    bytes = null;
    final oldPin = pin, oldStore = store;
    pin = null;
    if (oldPin != null && oldStore != null) {
      unawaited(
        oldStore.releaseAttachmentPin(oldPin).catchError((Object _) {
          /* Durable startup recovery releases an interrupted preview pin. */
        }),
      );
    }
  }

  @override
  void dispose() {
    clear();
    transform.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AttachmentPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.versionId != widget.attachment.versionId ||
        oldWidget.attachment.revision != widget.attachment.revision) {
      clear();
    }
  }

  Future<void> load() async {
    if (loading ||
        ref.read(appLockProvider).locked ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final token = ++epoch;
    setState(() {
      loading = true;
      failed = false;
    });
    AttachmentPreview? rendered;
    try {
      store ??= await ref.read(recordStoreProvider.future);
      if (pin == null) {
        final captured = await store!.pinAttachment(
          id: widget.attachment.id,
          generation: widget.attachment.generation,
          expectedRevision: widget.attachment.revision,
          sessionId: ref.read(attachmentSessionProvider),
        );
        if (!mounted || token != epoch || ref.read(appLockProvider).locked) {
          await store!.releaseAttachmentPin(captured);
          return;
        }
        pin = captured;
      }
      if (bytes == null) {
        final captured = await readAttachmentBytes(
          store!.readAttachmentPin(pin!),
        );
        if (!mounted || token != epoch || ref.read(appLockProvider).locked) {
          captured.fillRange(0, captured.length, 0);
          return;
        }
        bytes = captured;
      }
      if (!mounted || token != epoch || ref.read(appLockProvider).locked) {
        return;
      }
      final size = MediaQuery.sizeOf(context),
          edge = (size.width * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(1, AttachmentLimits.maxDisplayEdge);
      rendered = await ref
          .read(attachmentMediaProvider)
          .preview(
            bytes!,
            inspection: pin!.attachment.inspection!,
            page: page,
            maxEdge: edge,
          );
      if (!mounted || token != epoch || ref.read(appLockProvider).locked) {
        rendered.dispose();
        return;
      }
      setState(() {
        preview?.dispose();
        preview = rendered;
        loading = false;
      });
    } catch (_) {
      rendered?.dispose();
      if (mounted && token == epoch) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        capabilities = ref.watch(attachmentGatewayProvider).capabilities,
        locked = ref.watch(appLockProvider.select((s) => s.locked));
    ref.listen(appLockProvider, (_, next) {
      if (next.locked) {
        clear();
        if (mounted) setState(() {});
      }
    });
    if (locked) return const SizedBox.shrink();
    if (ModalRoute.of(context)?.isCurrent == false) {
      clear();
      return const SizedBox.shrink();
    }
    if (widget.attachment.inspection!.mediaKind == AttachmentMediaKind.other) {
      return Text(attachmentNoPreviewCopy(t, capabilities));
    }
    if (preview == null &&
        !loading &&
        !failed &&
        ModalRoute.of(context)?.isCurrent != false) {
      scheduleMicrotask(load);
    }
    final pages = widget.attachment.inspection!.pageCount ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) Text(t.loadingRecords),
        if (failed) ...[
          Text(attachmentPreviewFailureCopy(t, capabilities)),
          VitalButton.secondary(onPressed: load, child: Text(t.retry)),
        ],
        if (preview != null)
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * .55).clamp(200, 600),
            child: ClipRect(
              child: Semantics(
                label: t.attachmentPreview,
                image: true,
                child: InteractiveViewer(
                  transformationController: transform,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: RawImage(image: preview!.image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        Text(t.attachmentPage(page, pages)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (pages > 1)
              VitalButton.secondary(
                onPressed: loading || page <= 1
                    ? null
                    : () {
                        setState(() {
                          page--;
                          preview?.dispose();
                          preview = null;
                        });
                        load();
                      },
                child: Text(t.previous),
              ),
            if (pages > 1)
              VitalButton.secondary(
                onPressed: loading || page >= pages
                    ? null
                    : () {
                        setState(() {
                          page++;
                          preview?.dispose();
                          preview = null;
                        });
                        load();
                      },
                child: Text(t.next),
              ),
            VitalButton.secondary(
              onPressed: preview == null || zoom >= 4
                  ? null
                  : () {
                      zoom = (zoom * 1.5).clamp(1, 4);
                      transform.value = transform.value.clone()
                        ..setIdentity()
                        ..scaleByDouble(zoom, zoom, 1, 1);
                    },
              child: Text(t.attachmentZoom),
            ),
            VitalButton.secondary(
              onPressed: preview == null
                  ? null
                  : () {
                      zoom = 1;
                      transform.value = transform.value.clone()..setIdentity();
                    },
              child: Text(t.attachmentReset),
            ),
          ],
        ),
      ],
    );
  }
}

class AttachmentRenameForm extends ConsumerStatefulWidget {
  const AttachmentRenameForm({super.key, required this.attachmentId});
  final String attachmentId;
  @override
  ConsumerState<AttachmentRenameForm> createState() =>
      _AttachmentRenameFormState();
}

class _AttachmentRenameFormState
    extends DurableFormState<AttachmentRenameForm> {
  final name = TextEditingController();
  AttachmentRecord? original, frozen;
  AdultProfile? owner;
  bool initialised = false;
  @override
  DraftKind get entryKind => DraftKind.attachmentRename;
  @override
  String? get entryPerson => original?.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String get entryTarget => widget.attachmentId;
  @override
  int? get entryTargetRevision => original?.revision;
  @override
  Map<String, String> captureEntry() => {
    'name': name.text,
    'frozen': frozen == null ? '' : jsonEncode(frozen!.toJson()),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    name.text = fields['name'] ?? '';
    if ((fields['frozen'] ?? '').isNotEmpty) {
      frozen = AttachmentRecord.fromJson(
        Map<String, Object?>.from(jsonDecode(fields['frozen']!) as Map),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    name.addListener(entryChanged);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (name.text.trim().isEmpty || name.text.length > 255) {
      setState(() => error = t.attachmentNameError);
      return;
    }
    frozen ??= original;
    await commit((command) async {
      await (await ref.read(recordStoreProvider.future)).renameAttachment(
        commandId: command,
        attachment: frozen!,
        expectedPersonRevision: capturedPersonRevision!,
        name: name.text.trim(),
      );
    }, successPath: '/attachment/${widget.attachmentId}?focus=rename');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        result = ref.watch(attachmentLookupProvider(widget.attachmentId)),
        people = ref.watch(profilesProvider);
    if (!result.hasValue || !people.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final current = result.value;
    if (current == null) return EntryPage(children: [Text(t.attachmentStale)]);
    if (!initialised) {
      initialised = true;
      original = current;
      name.text = current.name;
      owner = people.value!.where((p) => p.id == current.personId).firstOrNull;
    }
    if (owner == null) return EntryPage(children: [Text(t.attachmentStale)]);
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        current.revision == capturedTargetRevision &&
        people.value!.any(
          (p) =>
              p.id == owner!.id &&
              p.revision == capturedPersonRevision &&
              !p.isArchived,
        );
    return wrap([
      Heading(t.attachmentRename),
      Text(t.profileOwner(ownerLabel(ref, t, original!.personId))),
      Text(original!.name),
      if (!valid) Text(t.conflictFailure),
      LabelledInput(
        label: t.attachmentName,
        controller: name,
        enabled: valid && !busy && !uncertain,
        error: error == t.attachmentNameError ? error : null,
      ),
      ?failure(),
      VitalButton(
        onPressed: busy || conflict || (!valid && !uncertain) ? null : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
    ]);
  }
}
