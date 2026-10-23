import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/privacy.dart';
import '../../domain/privacy/diagnostics.dart';
import '../../domain/privacy/licences.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../catalogue/catalogue_picker.dart' show catalogueReaderProvider;
import '../recording/record_pages.dart' show EntryPage, Heading, LoadFailure;
import 'settings_widgets.dart';

/// Local recovery, privacy and source information. This page never claims a
/// remote sender, legal certification or a capability the build lacks.
class HelpPage extends ConsumerWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final catalogue = ref.watch(catalogueReaderProvider);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isLinux = defaultTargetPlatform == TargetPlatform.linux;
    return EntryPage(
      children: [
        Heading(t.help),
        Text(t.helpBody),
        const SizedBox(height: 28),
        _HelpSection(
          title: t.recovery,
          children: [
            Text(t.recoveryOpen),
            if (isLinux) Text(t.recoveryKeyring),
            Text(t.recoveryLock),
          ],
        ),
        const SizedBox(height: 28),
        _HelpSection(
          title: t.privacy,
          children: [
            Text(t.privacyLocal),
            Text(t.privacyOperator),
            Text(t.privacyNotifications),
            if (isAndroid) Text(t.privacySwitcher),
            Text(t.privacyShared),
          ],
        ),
        const SizedBox(height: 28),
        _HelpSection(
          title: t.sources,
          children: [
            catalogue.when(
              data: (reader) => reader == null
                  ? Text(t.sourcesNone)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.catalogueRelease(
                            reader.manifest.sourceId,
                            reader.manifest.version,
                            reader.manifest.releaseDate,
                          ),
                        ),
                        Text(
                          t.catalogueAttribution(reader.manifest.attribution),
                        ),
                        Text(t.catalogueLicence(reader.manifest.licence)),
                      ],
                    ),
              error: (_, _) => Text(t.sourcesUnavailable),
              loading: () => Text(t.loadingRecords),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _HelpSection(
          title: t.about,
          children: [Text(t.aboutBody), Text(t.aboutLimit)],
        ),
        const SizedBox(height: 20),
        SettingsNavigationRow(
          label: t.licences,
          description: t.settingsLicencesBody,
          onPressed: () => context.push('/settings/licences'),
        ),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => VitalSettingsSection(
    title: title,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        children[index],
      ],
    ],
  );
}

/// Lists the bundled notices plus the application licence. Each row opens a
/// readable detail page; nothing is downloaded or sent.
class LicencesPage extends ConsumerStatefulWidget {
  const LicencesPage({super.key});

  @override
  ConsumerState<LicencesPage> createState() => _LicencesPageState();
}

class _LicencesPageState extends ConsumerState<LicencesPage> {
  bool _recordedFailure = false;

  Future<void> _recordFailure() async {
    try {
      final log = await ref.read(diagnosticLogProvider.future);
      await log.record(
        DiagnosticCode.licenceNotice,
        platform: ref.read(diagnosticPlatformProvider),
      );
      ref.invalidate(diagnosticEventsProvider);
    } catch (_) {
      // The visible licence failure is the primary result.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final notices = ref.watch(licenceNoticesProvider);
    final appLicence = ref.watch(applicationLicenceProvider);
    if ((notices.hasError || appLicence.hasError) && !_recordedFailure) {
      _recordedFailure = true;
      Future<void>.microtask(_recordFailure);
    }
    return EntryPage(
      children: [
        Heading(t.licences),
        Text(t.licencesBody),
        const SizedBox(height: 24),
        SettingsNavigationRow(
          label: t.appLicence,
          description: t.appLicenceBody,
          onPressed: () => context.push('/settings/licences/app'),
        ),
        const SizedBox(height: 16),
        VitalSettingsLabel(t.packageNotices),
        const SizedBox(height: 10),
        notices.when(
          data: (items) => items.isEmpty
              ? Text(t.licencesUnavailable)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < items.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SettingsNavigationRow(
                          label: items[index].title,
                          description: t.licenceDetailBody,
                          onPressed: () =>
                              context.push('/settings/licences/$index'),
                        ),
                      ),
                  ],
                ),
          error: (_, _) => LoadFailure(
            onRetry: () {
              _recordedFailure = false;
              ref.invalidate(licenceNoticesProvider);
              ref.invalidate(applicationLicenceProvider);
            },
            message: t.licencesUnavailable,
          ),
          loading: () => Text(t.loadingRecords),
        ),
      ],
    );
  }
}

class ApplicationLicencePage extends ConsumerWidget {
  const ApplicationLicencePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.appLicence),
        Text(t.licencesBody),
        const SizedBox(height: 20),
        ref
            .watch(applicationLicenceProvider)
            .when(
              data: (text) => SelectableText(text),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(applicationLicenceProvider),
                message: t.licencesUnavailable,
              ),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}

class LicenceDetailPage extends ConsumerWidget {
  const LicenceDetailPage({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.licence),
        const SizedBox(height: 20),
        ref
            .watch(licenceNoticesProvider)
            .when(
              data: (items) {
                if (index < 0 || index >= items.length) {
                  return Text(t.licencesUnavailable);
                }
                return _LicenceText(notice: items[index]);
              },
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(licenceNoticesProvider),
                message: t.licencesUnavailable,
              ),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}

class _LicenceText extends StatelessWidget {
  const _LicenceText({required this.notice});

  final LicenceNotice notice;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(notice.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      SelectableText(notice.body),
    ],
  );
}
