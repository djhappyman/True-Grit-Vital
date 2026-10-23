import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/privacy.dart';
import '../../app/storage.dart';
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
    final previousFocus = FocusManager.instance.primaryFocus;
    // Destructive dialogs start on the safe action, not on Delete.
    final cancelFocus = FocusNode(debugLabel: 'privacy-delete-cancel');
    var requestedCancelFocus = false;
    try {
      final yes = await showVitalDialog<bool>(
        context: context,
        builder: (context) {
          if (!requestedCancelFocus) {
            requestedCancelFocus = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (cancelFocus.context != null) cancelFocus.requestFocus();
            });
          }
          return VitalDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              VitalButton.secondary(
                focusNode: cancelFocus,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.cancel),
              ),
              VitalButton.destructive(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(command),
              ),
            ],
          );
        },
      );
      return yes == true;
    } finally {
      // Return focus to the surviving control that opened the decision.
      if (previousFocus?.context?.mounted ?? false) {
        previousFocus!.requestFocus();
      }
      cancelFocus.dispose();
    }
  }

  void _result(String message, {required bool failed}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _failed = failed;
    });
  }

  Future<void> _run(AdultProfile person) async {
    if (_busy.contains(person.id) || !_confirming.add(person.id)) return;
    final t = AppLocalizations.of(context);
    final initialLock = ref.read(appLockProvider);
    final route = ModalRoute.of(context);
    final router = GoRouter.maybeOf(context);
    final location = router?.routeInformationProvider.value.uri;
    var leftRoute = false;
    void navigationChanged() {
      if (router?.routeInformationProvider.value.uri != location) {
        leftRoute = true;
      }
    }

    router?.routeInformationProvider.addListener(navigationChanged);
    ProviderSubscription<AppLockState>? lockWatch;
    try {
      final RecordStore store;
      try {
        store = await ref.read(recordStoreProvider.future);
      } catch (_) {
        await _recordFailure(DiagnosticCode.profileDelete);
        _result(t.privacyNotSaved, failed: true);
        return;
      }
      if (!mounted) return;
      if (route != null && !route.isCurrent) {
        _result(t.privacyNotSaved, failed: true);
        return;
      }
      if (ref.read(appLockProvider).locked) {
        _result(t.batch15T13PrivacyLocked, failed: true);
        return;
      }
      // The button can outlive the profile revision it was rendered from.
      final AdultProfile? shown;
      try {
        shown = await store.profileById(meId);
      } catch (_) {
        await _recordFailure(DiagnosticCode.profileDelete);
        _result(t.privacyNotSaved, failed: true);
        return;
      }
      if (!mounted) return;
      if (leftRoute ||
          !identical(ref.read(appLockProvider), initialLock) ||
          initialLock.locked ||
          ModalRoute.of(context)?.isCurrent == false) {
        _result(t.batch15T13PrivacyLocked, failed: true);
        return;
      }
      if (shown == null || shown.revision != person.revision) {
        _result(t.batch15T13PrivacyChanged, failed: true);
        return;
      }
      final captured = ProfileDeleteAuthority(
        generation: store.generation,
        personRevision: shown.revision,
      );
      // A lock or unlock while the dialog is open invalidates the decision,
      // even if the app is open again by the time Delete returns.
      var lockEpoch = 0;
      lockWatch = ref.listenManual<AppLockState>(appLockProvider, (
        previous,
        next,
      ) {
        if (previous?.locked != next.locked) lockEpoch++;
      });
      setState(() {
        _notice = null;
        _failed = false;
      });
      final confirmed = await _confirm();
      if (!confirmed || !mounted) return;

      // The dialog can outlive the dataset it was opened for. Resolve the live
      // store and review the same captured authority before any writer starts.
      final RecordStore currentStore;
      final AdultProfile? currentProfile;
      try {
        currentStore = await ref.read(recordStoreProvider.future);
        currentProfile = await currentStore.profileById(meId);
      } catch (_) {
        await _recordFailure(DiagnosticCode.profileDelete);
        _result(t.privacyNotSaved, failed: true);
        return;
      }
      if (!mounted) return;
      final currentRoute = ModalRoute.of(context);
      if (leftRoute ||
          (route != null &&
              (currentRoute == null ||
                  !identical(currentRoute, route) ||
                  !currentRoute.isCurrent))) {
        _result(t.privacyNotSaved, failed: true);
        return;
      }
      if (!identical(currentStore, store) ||
          !captured.matches(
            generation: currentStore.generation,
            personRevision: currentProfile?.revision,
          )) {
        _result(t.batch15T13PrivacyChanged, failed: true);
        return;
      }
      if (lockEpoch != 0 || ref.read(appLockProvider).locked) {
        _result(t.batch15T13PrivacyLocked, failed: true);
        return;
      }

      // An uncertain retry retains its id only for this exact captured payload:
      // the same dataset generation and the same owner revision.
      final commandKey =
          'delete:${captured.generation}:${captured.personRevision}';
      final command = _commands[commandKey] ??= newCommandId();
      setState(() {
        _busy.add(person.id);
        _notice = null;
        _failed = false;
      });
      _confirming.remove(person.id);
      try {
        final gateway = ref.read(profilePrivacyActionsProvider);
        await gateway.delete(
          commandId: command,
          personId: meId,
          expectedRevision: captured.personRevision,
          expectedGeneration: captured.generation,
          actionCurrent: () =>
              mounted &&
              !leftRoute &&
              lockEpoch == 0 &&
              !ref.read(appLockProvider).locked &&
              identical(ref.read(recordStoreProvider).value, store) &&
              ModalRoute.of(context)?.isCurrent != false,
        );
        _commands.remove(commandKey);
        _result(t.privacyMeDeleted, failed: false);
      } on CommandConflict catch (error) {
        // A lock refusal can be retried with the identical payload. Changed
        // datasets or revisions cannot, so their stale identity is dropped.
        if (error.code != 'app_locked') _commands.remove(commandKey);
        await _recordFailure(DiagnosticCode.profileDelete);
        _result(switch (error.code) {
          'app_locked' => t.batch15T13PrivacyLocked,
          'generation' || 'person_context' => t.batch15T13PrivacyChanged,
          _ => t.privacyNotSaved,
        }, failed: true);
      } catch (_) {
        await _recordFailure(DiagnosticCode.profileDelete);
        _result(t.privacyNotSaved, failed: true);
      } finally {
        if (mounted) setState(() => _busy.remove(person.id));
      }
    } finally {
      router?.routeInformationProvider.removeListener(navigationChanged);
      lockWatch?.close();
      _confirming.remove(person.id);
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
        VitalSettingsLabel(t.copies),
        const SizedBox(height: 8),
        Text(t.privacyCopies),
        const SizedBox(height: 28),
        VitalSettingsLabel(t.deleteRecords),
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
