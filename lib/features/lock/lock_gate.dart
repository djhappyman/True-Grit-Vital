import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_auth.dart';

class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _contentMounted = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLockProvider.notifier).lifecycle(state);
    if (state != AppLifecycleState.resumed) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Storage failures retain the existing distinct recovery screen.
    if (ref.watch(recordStoreProvider).hasError) return widget.child;
    final state = ref.watch(appLockProvider), t = AppLocalizations.of(context);
    final hidden = !state.ready || state.locked;
    if (!hidden) _contentMounted = true;
    return Stack(
      children: [
        // Keep the original operation, adult, controllers and navigation mounted.
        // Offstage also removes hit testing; explicit focus/semantics exclusions
        // prevent keyboard and assistive access to hidden private fields.
        if (_contentMounted)
          IgnorePointer(
            ignoring: hidden,
            child: ExcludeFocus(
              excluding: hidden,
              child: ExcludeSemantics(
                excluding: hidden,
                child: Offstage(
                  offstage: hidden,
                  child: TickerMode(enabled: !hidden, child: widget.child),
                ),
              ),
            ),
          ),
        if (hidden)
          VitalScaffold(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: VitalPanel(
                    children: [
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: VitalIconTile(LucideIcons.shieldCheck, size: 48),
                      ),
                      Semantics(
                        header: true,
                        child: Text(
                          t.lockHeading,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        !state.ready
                            ? (state.failed ? t.lockUnavailable : t.lockLoading)
                            : t.lockBody,
                      ),
                      if (state.failed && state.ready)
                        Semantics(
                          liveRegion: true,
                          child: Text(t.lockUnavailable),
                        ),
                      if (!state.ready && state.failed)
                        VitalButton(
                          onPressed: () => ref.invalidate(appLockProvider),
                          child: Text(t.retry),
                        ),
                      if (state.ready) ...[
                        const SizedBox(height: 24),
                        VitalButton(
                          onPressed: state.busy
                              ? null
                              : () =>
                                    ref.read(appLockProvider.notifier).unlock(),
                          child: Text(state.busy ? t.saving : t.unlock),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppLockSettings extends ConsumerWidget {
  const AppLockSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider), t = AppLocalizations.of(context);
    final supported = state.availability == AppAuthAvailability.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.appLock,
          description: supported
              ? t.appLockHelper
              : (state.availability == AppAuthAvailability.setupRequired
                    ? t.lockSetupRequired
                    : state.availability ==
                          AppAuthAvailability.temporarilyUnavailable
                    ? t.lockUnavailable
                    : t.lockUnsupported),
          value: state.enabled,
          enabled: state.ready && !state.busy && (supported || state.enabled),
          onChanged: ref.read(appLockProvider.notifier).setEnabled,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
        if (!supported)
          VitalButton.secondary(
            onPressed: state.busy
                ? null
                : ref.read(appLockProvider.notifier).refreshAvailability,
            child: Text(t.retry),
          ),
        if (state.failed)
          Semantics(liveRegion: true, child: Text(t.lockUnavailable)),
        if (state.enabled)
          VitalButton.secondary(
            onPressed: ref.read(appLockProvider.notifier).lock,
            child: Text(t.lock),
          ),
      ],
    );
  }
}
