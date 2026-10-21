import '../features/supporting/supporting_pages.dart';
import '../features/supporting/supporting_form.dart';
import '../features/supporting/supporting_trends.dart';
import '../features/backup/backup_pages.dart';
import '../ui/vital_ui.dart';
import '../ui/stitch_ui.dart';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import '../domain/records.dart' show meId;
import 'appearance.dart';
import 'backup.dart';
import 'display_preferences.dart';
import '../features/history/history_pages.dart';
import '../features/charts/chart_pages.dart';
import '../features/exports/export_pages.dart';
import '../features/history/history_source.dart';
import '../domain/history/history.dart';
import 'attachments.dart';
import 'artifact_transfer.dart';
import '../features/attachments/attachment_pages.dart';
import '../domain/attachments.dart';
import 'reminders.dart';
import '../features/plans/plan_form.dart';
import '../features/events/event_pages.dart';
import '../features/events/event_review.dart';
import '../features/plans/pause_editor.dart';
import '../features/plans/phase_editor.dart';
import '../features/reminders/reminder_pages.dart';
import '../features/stock/stock_pages.dart';
import '../features/products/product_pages.dart';
import '../features/catalogue/item_types.dart';
import '../features/lock/lock_gate.dart';
import '../features/profiles/profile_pages.dart';
import '../features/recording/record_pages.dart';
import '../features/recording/combined_pages.dart';
import '../features/substances/substance_overview.dart';
import '../features/settings/diagnostic_pages.dart';
import '../features/settings/help_pages.dart';
import '../features/settings/privacy_pages.dart';
import '../features/settings/settings_pages.dart';
import '../features/reports/reports_page.dart';
import '../features/reports/report_preview_page.dart';
import '../features/restore/restore_pages.dart';
import '../features/restore/restore_recovery_banner.dart';
import 'settings_toggle_row.dart';
import 'vital_theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/today',
    redirect: (_, state) {
      final person =
          state.pathParameters['person'] ?? state.uri.queryParameters['person'];
      if (person != null && person != meId) return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/supporting',
        builder: (_, state) => StorageGate(
          child: SupportingRecordsPage(
            key: ValueKey(state.uri.toString()),
            location: state.uri.toString(),
          ),
        ),
      ),
      GoRoute(
        path: '/reports/preview',
        builder: (_, _) => const StorageGate(child: ReportPreviewPage()),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, state) => StorageGate(
          child: ReportsPage(
            key: ValueKey(state.uri.toString()),
            from: state.uri.queryParameters['from'],
            before: state.uri.queryParameters['before'],
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/supporting/:person/add-panel',
        builder: (_, state) => StorageGate(
          child: SupportingForm(
            key: ValueKey(state.uri.toString()),
            personId: meId,
            itemId: state.uri.queryParameters['item'],
            eventId: state.uri.queryParameters['event'],
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/supporting/:person/add-observation',
        builder: (_, state) => StorageGate(
          child: SupportingForm(
            key: ValueKey(state.uri.toString()),
            personId: meId,
            observation: true,
            itemId: state.uri.queryParameters['item'],
            eventId: state.uri.queryParameters['event'],
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/supporting/:person/trends',
        builder: (_, state) => StorageGate(
          child: SupportingTrendsPage(
            key: ValueKey(state.uri.toString()),
            personId: meId,
            metricId: state.uri.queryParameters['metric'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/supporting/:person/:id/edit',
        builder: (_, state) => StorageGate(
          child: SupportingForm(
            key: ValueKey(state.uri.toString()),
            personId: meId,
            id: state.pathParameters['id']!,
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/supporting/:person/:id',
        builder: (_, state) => StorageGate(
          child: SupportingDetailPage(
            key: ValueKey(state.uri.toString()),
            personId: meId,
            id: state.pathParameters['id']!,
            returnLocation: state.uri.queryParameters['return'],
            revision: int.tryParse(state.uri.queryParameters['revision'] ?? ''),
          ),
        ),
      ),

      GoRoute(
        path: '/charts',
        builder: (_, state) => StorageGate(
          child: ChartsPage(
            key: ValueKey(state.uri.toString()),
            location: state.uri.toString(),
          ),
        ),
      ),
      GoRoute(
        path: '/exports',
        builder: (_, state) => StorageGate(
          child: ExportPage(
            key: ValueKey(state.uri.toString()),
            location: state.uri.toString(),
          ),
        ),
      ),
      GoRoute(
        path: '/history-source/:kind/:id',
        builder: (_, state) {
          final kind = state.pathParameters['kind'];
          final prefix = kind == 'record'
              ? 'r'
              : kind == 'combined'
              ? 'c'
              : 's';
          return StorageGate(
            child: HistorySourcePage(
              id: TimelineEntryId.parse(
                '$prefix:${state.pathParameters['id']}',
              ),
              personId: meId,
              returnLocation: state.uri.queryParameters['return'] ?? '/history',
            ),
          );
        },
      ),
      GoRoute(
        path: '/files/:person/:kind/:target',
        builder: (context, state) {
          final kind = AttachmentTargetKind.values
              .where((value) => value.name == state.pathParameters['kind'])
              .firstOrNull;
          return StorageGate(
            child: kind == null
                ? EntryPage(
                    children: [
                      Text(AppLocalizations.of(context).attachmentStale),
                    ],
                  )
                : AttachmentListPage(
                    personId: meId,
                    kind: kind,
                    targetId: state.pathParameters['target']!,
                    restoreFocus:
                        state.uri.queryParameters['focus'] == 'choose',
                  ),
          );
        },
      ),
      GoRoute(
        path: '/attachment/:id/rename',
        builder: (_, state) => StorageGate(
          child: AttachmentRenameForm(
            attachmentId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/attachment/:id',
        builder: (_, state) => StorageGate(
          child: AttachmentViewerPage(
            attachmentId: state.pathParameters['id']!,
            focusRename: state.uri.queryParameters['focus'] == 'rename',
          ),
        ),
      ),
      GoRoute(
        path: '/supporting-source/:person/:id',
        builder: (_, state) => StorageGate(
          child: SupportingSourceViewerPage(
            personId: meId,
            attachmentId: state.pathParameters['id']!,
            revision:
                int.tryParse(state.uri.queryParameters['revision'] ?? '') ?? 0,
            contentVersionId: state.uri.queryParameters['version'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/event-create',
        builder: (_, state) => const StorageGate(child: EventForm()),
      ),
      GoRoute(
        path: '/event/:id/revisions',
        builder: (_, state) => StorageGate(
          child: EventRevisionsPage(eventId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/period-revisions/:id',
        builder: (_, state) => StorageGate(
          child: UsePeriodRevisionsPage(periodId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/event/:id/edit',
        builder: (_, state) =>
            StorageGate(child: EventForm(eventId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/event/:id/decision',
        builder: (_, state) => StorageGate(
          child: EventDecisionForm(
            eventId: state.pathParameters['id']!,
            itemId: state.uri.queryParameters['item'],
            envelopeId: state.uri.queryParameters['envelope'],
          ),
        ),
      ),
      GoRoute(
        path: '/event/:id/review',
        builder: (_, state) => StorageGate(
          child: EventEndReviewPage(
            eventId: state.pathParameters['id']!,
            envelopeId: state.uri.queryParameters['envelope'],
          ),
        ),
      ),
      GoRoute(
        path: '/event/:id',
        builder: (_, state) => StorageGate(
          child: EventDetailPage(eventId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/use/:person/:item/edit',
        builder: (_, state) => StorageGate(
          child: UsePeriodForm(
            personId: meId,
            itemId: state.pathParameters['item']!,
            periodId: state.uri.queryParameters['period'],
          ),
        ),
      ),
      GoRoute(
        path: '/use/:person/:item',
        builder: (_, state) => StorageGate(
          child: UseHistoryPage(
            personId: meId,
            itemId: state.pathParameters['item']!,
          ),
        ),
      ),
      GoRoute(
        path: '/reminders',
        builder: (_, _) => const StorageGate(child: RemindersPage()),
      ),
      GoRoute(
        path: '/reminders/action/:id',
        builder: (_, state) => StorageGate(
          child: ReminderActionPage(envelopeId: state.pathParameters['id']!),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            VitalShell(path: state.uri.path, child: child),
        routes: [
          for (final destination in Destination.values)
            GoRoute(
              path: destination.path,
              pageBuilder: (context, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: StorageGate(
                  child: destination == Destination.events
                      ? const EventsPage()
                      : destination == Destination.history
                      ? HistoryPage(location: state.uri.toString())
                      : RecordCollection(destination: destination),
                ),
              ),
            ),
        ],
      ),
      GoRoute(
        path: '/products/:person/label/:item',
        builder: (_, state) => StorageGate(
          child: ProductLabelForm(
            personId: meId,
            itemId: state.pathParameters['item']!,
          ),
        ),
      ),
      GoRoute(
        path: '/stock/:person/create',
        builder: (_, state) => StorageGate(
          child: StockContainerForm(
            personId: meId,
            itemId: state.uri.queryParameters['item'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/stock/:person/adjust/:container',
        builder: (_, state) {
          // The raw container plus the route's surface key the form state: an
          // in-place switch between the adjustment and notices route must not
          // reuse the other surface's editor state.
          final containerId = state.pathParameters['container']!;
          final notices = state.uri.queryParameters['notices'] == 'true';
          return StorageGate(
            child: StockAdjustmentForm(
              key: ValueKey(
                'stockAdjust:$containerId:${notices ? 'notices' : 'quantity'}',
              ),
              personId: meId,
              containerId: containerId,
              notices: notices,
            ),
          );
        },
      ),
      GoRoute(
        path: '/stock/:person',
        builder: (_, state) => StorageGate(
          child: StockPage(
            personId: meId,
            itemId: state.uri.queryParameters['item'],
          ),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const StorageGate(child: ProfileForm()),
      ),
      // Safe exits for bookmarks from the earlier multi-person prototype.
      GoRoute(
        path: '/recorded',
        builder: (_, _) => const StorageGate(child: RecordedDosesPage()),
      ),
      GoRoute(path: '/person-history/:id', redirect: (_, _) => '/recorded'),
      GoRoute(path: '/people', redirect: (_, _) => '/profile'),
      GoRoute(path: '/people/add', redirect: (_, _) => '/profile'),
      GoRoute(path: '/people/:id', redirect: (_, _) => '/profile'),
      GoRoute(
        path: '/scope',
        redirect: (_, state) => state.uri.queryParameters['create'] == 'true'
            ? '/create'
            : '/today',
      ),
      GoRoute(
        path: '/backup',
        builder: (_, _) => const StorageGate(child: BackupPage()),
      ),
      GoRoute(
        path: '/appearance',
        builder: (_, _) => const StorageGate(child: AppearancePage()),
      ),
      GoRoute(path: '/restore', builder: (_, _) => const RestorePage()),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const StorageGate(child: SettingsPage()),
      ),
      GoRoute(
        path: '/settings/privacy',
        builder: (_, _) => const StorageGate(child: PrivacyPage()),
      ),
      GoRoute(
        path: '/settings/diagnostics',
        builder: (_, _) => const StorageGate(child: DiagnosticsPage()),
      ),
      GoRoute(
        path: '/settings/help',
        builder: (_, _) => const StorageGate(child: HelpPage()),
      ),
      GoRoute(
        path: '/settings/licences',
        builder: (_, _) => const StorageGate(child: LicencesPage()),
      ),
      GoRoute(
        path: '/settings/licences/app',
        builder: (_, _) => const StorageGate(child: ApplicationLicencePage()),
      ),
      GoRoute(
        path: '/settings/licences/:index',
        builder: (_, state) => StorageGate(
          child: LicenceDetailPage(
            index: int.tryParse(state.pathParameters['index'] ?? '') ?? -1,
          ),
        ),
      ),
      GoRoute(
        path: '/revisions/:id',
        builder: (_, state) => StorageGate(
          child: RevisionHistory(
            recordId: state.pathParameters['id']!,
            personId: meId,
          ),
        ),
      ),
      GoRoute(
        path: '/types/:person/edit',
        builder: (_, state) => StorageGate(
          child: ItemTypeForm(
            personId: meId,
            typeId: state.uri.queryParameters['type'],
          ),
        ),
      ),
      GoRoute(
        path: '/types/:person',
        builder: (_, state) =>
            StorageGate(child: ItemTypesPage(personId: meId)),
      ),
      GoRoute(
        path: '/create',
        builder: (_, state) => const StorageGate(child: ItemForm()),
      ),
      GoRoute(
        path: '/site/:person/:record',
        builder: (_, state) => StorageGate(
          child: SiteForm(
            personId: meId,
            recordId: state.pathParameters['record']!,
          ),
        ),
      ),
      GoRoute(
        path: '/combined/:person/edit/:action',
        builder: (_, state) => StorageGate(
          child: CombinedForm(
            personId: meId,
            actionId: state.pathParameters['action']!,
            undo: state.uri.queryParameters['undo'] == 'true',
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/combined/:person',
        builder: (_, state) => StorageGate(
          child: CombinedForm(
            personId: meId,
            initialItemId: state.uri.queryParameters['item'],
          ),
        ),
      ),
      GoRoute(
        path: '/record/:id',
        builder: (_, state) =>
            StorageGate(child: DoseForm(itemId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/correct/:id',
        builder: (_, state) => StorageGate(
          child: DoseForm(
            recordId: state.pathParameters['id']!,
            personId: meId,
            returnLocation: state.uri.queryParameters['return'],
          ),
        ),
      ),
      GoRoute(
        path: '/phases/:id',
        builder: (_, state) => StorageGate(
          child: PhasePlanForm(
            itemId: state.pathParameters['id']!,
            planId: state.uri.queryParameters['plan'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/pause/:id',
        builder: (_, state) => StorageGate(
          child: PausePlanForm(
            itemId: state.pathParameters['id']!,
            planId: state.uri.queryParameters['plan'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/schedule/:id',
        builder: (_, state) => StorageGate(
          child: DailyPlanForm(
            itemId: state.pathParameters['id']!,
            planId: state.uri.queryParameters['plan'],
          ),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (_, state) => StorageGate(
          child: ItemHistory(itemId: state.pathParameters['id']!),
        ),
      ),
      // One reachable overview per substance. The `/item/:id` route above
      // stays the preserved full-history surface.
      GoRoute(
        path: '/substance/:id',
        builder: (_, state) => StorageGate(
          child: SubstanceOverviewPage(itemId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class VitalApp extends ConsumerWidget {
  const VitalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appearanceProvider);
    return ShadcnApp.router(
      title: 'True Grit: Vital',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: vitalTheme(Brightness.light),
      darkTheme: vitalTheme(Brightness.dark),
      themeMode: preferences.mode,
      enableThemeAnimation: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      builder: (context, child) {
        final data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            disableAnimations:
                preferences.reduceMotion ||
                data.disableAnimations ||
                data.accessibleNavigation,
          ),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: const Color(0x00000000),
                    systemNavigationBarColor: const Color(0x00000000),
                  )
                : SystemUiOverlayStyle.dark.copyWith(
                    statusBarColor: const Color(0x00000000),
                    systemNavigationBarColor: const Color(0x00000000),
                  ),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.background,
              child: SafeArea(
                child: ReminderRuntime(
                  child: BackupRuntime(
                    child: ArtifactTransferRuntime(
                      child: AttachmentRuntime(
                        child: VitalComponentThemes(
                          child: LockGate(child: ReminderHost(child: child!)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum Destination {
  today('/today', LucideIcons.calendarCheck),
  substances('/substances', LucideIcons.pill),
  events('/events', LucideIcons.calendarRange),
  history('/history', LucideIcons.history);

  const Destination(this.path, this.icon);
  final String path;
  final IconData icon;

  String label(AppLocalizations text) => switch (this) {
    today => text.today,
    substances => text.substances,
    events => text.events,
    history => text.history,
  };
}

/// App chrome remains fixed while feature content scrolls.
class VitalShell extends StatelessWidget {
  const VitalShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final c = StitchColors(context);
    final destination = Destination.values
        .where((d) => d.path == path)
        .firstOrNull;
    return Scaffold(
      headers: [
        const RestoreRecoveryBanner(),
        SafeArea(
          bottom: false,
          child: VitalPageBody(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const StitchMark(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              text.appTitle.toUpperCase(),
                              style: StitchType.small.copyWith(color: c.muted),
                            ),
                            Text(
                              destination?.label(text) ?? text.today,
                              style: StitchType.name.copyWith(color: c.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  tooltip: (_) => TooltipContainer(child: Text(text.settings)),
                  child: Semantics(
                    label: text.settings,
                    button: true,
                    child: StitchButton(
                      onPressed: () => context.push('/settings'),
                      quiet: true,
                      compact: true,
                      child: ExcludeSemantics(
                        child: Icon(
                          LucideIcons.settings,
                          size: 22,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: text.profile,
                  button: true,
                  child: StitchButton(
                    onPressed: () => context.push('/profile'),
                    compact: true,
                    child: ExcludeSemantics(
                      child: Icon(
                        LucideIcons.userRound,
                        size: 18,
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: Column(
        children: [
          Expanded(child: child),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ShellNavigation(path: path, vertical: false),
            ),
          ),
        ],
      ),
    );
  }
}

class ShellNavigation extends StatelessWidget {
  const ShellNavigation({
    super.key,
    required this.path,
    required this.vertical,
  });
  final String path;
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    if (largeText) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: VitalChrome(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final destination in Destination.values)
                  Semantics(
                    selected: path == destination.path,
                    child: VitalButton.secondary(
                      onPressed: () => context.go(destination.path),
                      child: Text(destination.label(text)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final items = <Widget>[
      for (final destination in Destination.values)
        Semantics(
          selected: path == destination.path,
          child: ButtonStyleOverride(
            decoration: (context, states, decoration) =>
                decoration is BoxDecoration
                ? decoration.copyWith(
                    color: path == destination.path
                        ? colors.accent
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: path == destination.path
                          ? colors.primary.withValues(alpha: 0.25)
                          : const Color(0x00000000),
                    ),
                  )
                : decoration,
            padding: (context, states, padding) =>
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Button(
              style: ButtonVariance.ghost,
              onPressed: () => context.go(destination.path),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        destination.icon,
                        size: 20,
                        color: path == destination.path
                            ? colors.accentForeground
                            : colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.label(text),
                      style: StitchType.small.copyWith(
                        color: path == destination.path
                            ? colors.accentForeground
                            : colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VitalLayout.contentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: VitalChrome(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: largeText || vertical
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: items,
                    )
                  : Row(
                      children: [
                        for (final item in items) Expanded(child: item),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selected glass surface with a complete opaque accessibility fallback.
class VitalChrome extends ConsumerWidget {
  const VitalChrome({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final effective = EffectiveAppearance.compose(
      preferences: ref.watch(appearanceProvider),
      systemReduceMotion:
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context),
      systemReduceTransparency: MediaQuery.highContrastOf(context),
      glassValidated: ref.watch(glassValidatedProvider),
    );
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: effective.opaque
            ? colors.card
            : colors.card.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
    if (effective.opaque) return surface;
    return glass.AdaptiveGlass(
      shape: const glass.LiquidRoundedSuperellipse(borderRadius: 48),
      settings: const glass.LiquidGlassSettings(),
      child: surface,
    );
  }
}

/// One scrolling, keyboard-aware body for primary and secondary screens.
/// Compatibility adapter; new screens can use VitalPage or VitalScrollBody.
class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.children, this.panelled = false});
  final List<Widget> children;
  final bool panelled;
  @override
  Widget build(BuildContext context) {
    final hasTitle = children.isNotEmpty && children.first is Heading;
    return VitalScrollBody(
      children: [
        if (hasTitle) VitalPageHeader(title: (children.first as Heading).text),
        if (panelled)
          VitalPanel(
            gap: 0,
            children: hasTitle ? children.skip(1).toList() : children,
          )
        else
          ...hasTitle ? children.skip(1) : children,
      ],
    );
  }
}

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppLocalizations.of(context);
    final preferences = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final saveError = ref.watch(appearanceErrorProvider);
    final saving = ref.watch(appearanceBusyProvider);
    final effective = EffectiveAppearance.compose(
      preferences: preferences,
      systemReduceMotion:
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context),
      // Flutter has no portable reduced-transparency MediaQuery field. The
      // explicit preference and unvalidated-renderer fallback remain available.
      systemReduceTransparency: false,
      glassValidated: ref.watch(glassValidatedProvider),
    );
    return EntryPage(
      children: [
        Heading(text.appearance),
        const SizedBox(height: 8),
        Text(text.appearanceBody),
        if (saveError)
          Semantics(liveRegion: true, child: Text(text.appearanceFailure)),
        const SizedBox(height: 24),
        const AppLockSettings(),
        const SizedBox(height: 24),
        const TimeFormatSettings(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VitalButton.secondary(
              onPressed: () => context.push('/reminders'),
              child: Text(text.reminders),
            ),
            VitalButton.secondary(
              onPressed: () => context.push('/backup'),
              child: Text(text.backup),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Semantics(
          header: true,
          child: Text(
            text.colourMode,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (mode, label) in [
              (ThemeMode.system, text.system),
              (ThemeMode.light, text.light),
              (ThemeMode.dark, text.dark),
            ])
              Semantics(
                selected: preferences.mode == mode,
                child: VitalButton.secondary(
                  onPressed: saving ? null : () => controller.setMode(mode),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preferences.mode == mode) ...[
                        const ExcludeSemantics(
                          child: Icon(LucideIcons.check, size: 16),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(label),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsToggleRow(
          label: text.opaqueSurfaces,
          description: text.opaqueHelper,
          value: preferences.opaque,
          enabled: !saving,
          onChanged: controller.setOpaque,
          reduceMotion: effective.reduceMotion,
        ),
        SettingsToggleRow(
          label: text.reduceMotion,
          description: text.motionHelper,
          value: preferences.reduceMotion,
          enabled: !saving,
          onChanged: controller.setReduceMotion,
          reduceMotion: effective.reduceMotion,
        ),
        const SizedBox(height: 24),
        SurfaceSample(effective: effective, opaqueChosen: preferences.opaque),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            text.formSamples,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final (icon, label) in [
              (LucideIcons.pill, text.tablet),
              (LucideIcons.syringe, text.injection),
              (LucideIcons.droplets, text.liquid),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Icon(icon)),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(text.formHelper),
      ],
    );
  }
}

class SurfaceSample extends StatelessWidget {
  const SurfaceSample({
    super.key,
    required this.effective,
    required this.opaqueChosen,
  });
  final EffectiveAppearance effective;
  final bool opaqueChosen;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final child = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text.surfaceSample,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            effective.opaque
                ? (opaqueChosen ? text.opaqueChosen : text.opaqueActive)
                : text.glassActive,
          ),
          const SizedBox(height: 8),
          Text(
            effective.reduceMotion ? text.motionReduced : text.motionStandard,
          ),
        ],
      ),
    );
    if (effective.opaque) {
      return Container(
        key: const ValueKey('opaque-sample'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
    }
    return glass.AdaptiveGlass(
      key: const ValueKey('glass-sample'),
      shape: const glass.LiquidRoundedSuperellipse(borderRadius: 20),
      settings: const glass.LiquidGlassSettings(),
      child: child,
    );
  }
}
