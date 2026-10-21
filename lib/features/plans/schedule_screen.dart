import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';

/// Page chrome for the schedule editor.
///
/// This is composition only: it keeps the canonical secondary-editor back
/// action and the shared Stitch scroll body without introducing a shell or a
/// second set of colours, type sizes or surface decoration.
class SchedulePageScaffold extends StatelessWidget {
  const SchedulePageScaffold({
    super.key,
    required this.onBack,
    required this.children,
    this.badge,
  });

  final VoidCallback onBack;
  final List<Widget> children;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Scaffold(
        headers: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                StitchButton(
                  icon: LucideIcons.arrowLeft,
                  onPressed: onBack,
                  child: Text(t.back),
                ),
                ?badge,
              ],
            ),
          ),
        ],
        child: StitchScrollBody(children: children),
      ),
    );
  }
}

/// A title block that follows the export's authored hierarchy without
/// repeating page chrome.
class ScheduleTitleBlock extends StatelessWidget {
  const ScheduleTitleBlock({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: StitchType.title.copyWith(color: c.ink)),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: StitchType.body.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}

/// Uppercase section label with an optional, wrapping right-hand meta line.
class ScheduleSectionHeader extends StatelessWidget {
  const ScheduleSectionHeader({super.key, required this.title, this.meta});

  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        label: meta == null ? title : '$title. $meta',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: StitchType.small.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .9,
                  ),
                ),
              ),
              if (meta case final value?) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: StitchType.caption.copyWith(color: c.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A 48px choice pill with explicit selection semantics.
class ScheduleChoiceChip extends StatelessWidget {
  const ScheduleChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onPressed,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: StitchButton(
        primary: selected,
        icon: icon,
        onPressed: onPressed,
        child: Text(label),
      ),
    ),
  );
}

/// Complete substance identity. The name is never truncated; it wraps and the
/// supporting line keeps the original form and unit.
class ScheduleIdentityCard extends StatelessWidget {
  const ScheduleIdentityCard({
    super.key,
    required this.name,
    required this.detail,
    this.badge,
    this.icon = LucideIcons.pill,
  });

  final String name, detail;
  final Widget? badge;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return StitchSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchIcon(icon, size: 40, selected: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: StitchType.heading.copyWith(color: c.ink)),
                const SizedBox(height: 4),
                Text(detail, style: StitchType.body.copyWith(color: c.muted)),
                if (badge case final value?) ...[
                  const SizedBox(height: 8),
                  value,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled, explicitly unavailable reference surface. The badge and copy
/// state that nothing here is saved or sent.
class SchedulePreviewNote extends StatelessWidget {
  const SchedulePreviewNote({
    super.key,
    required this.body,
    this.label,
    this.icon = LucideIcons.slidersHorizontal,
  });

  final String body;
  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return StitchSurface(
      inset: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label case final value?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  ExcludeSemantics(
                    child: Icon(icon, size: 16, color: c.accent),
                  ),
                  StitchBadge(value),
                ],
              ),
            ),
          Text(body, style: StitchType.caption.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}
