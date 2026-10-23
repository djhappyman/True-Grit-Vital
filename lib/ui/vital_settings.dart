import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import 'vital_foundation.dart';
import 'vital_motion.dart';
import 'vital_scaffold.dart';

/// Presentation only. Existing settings routes and durable form guards own data.
class VitalSettingsScope extends InheritedWidget {
  const VitalSettingsScope({
    super.key,
    required this.fallbackTitle,
    required super.child,
    this.hub = false,
  });
  final String fallbackTitle;
  final bool hub;
  static VitalSettingsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VitalSettingsScope>();
  @override
  bool updateShouldNotify(VitalSettingsScope oldWidget) =>
      fallbackTitle != oldWidget.fallbackTitle || hub != oldWidget.hub;
}

abstract final class VitalSettingsType {
  static const item = TextStyle(
    fontFamily: VitalType.uiFontFamily,
    fontSize: 16,
    height: 1.12,
    fontWeight: FontWeight.w600,
  );
  static const detail = TextStyle(
    fontFamily: VitalType.uiFontFamily,
    fontSize: 12.5,
    height: 1.22,
  );
  static const section = TextStyle(
    fontFamily: VitalType.uiFontFamily,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
  );
}

/// Workout's centred label app bar, with Vital's safe scrolling/glass adapter.
class VitalSettingsToolbar extends StatelessWidget {
  const VitalSettingsToolbar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backEnabled = true,
  });
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool backEnabled;
  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            VitalIconButton(
              label: AppLocalizations.of(context).back,
              icon: LucideIcons.arrowLeft,
              onPressed: !backEnabled
                  ? null
                  : onBack ??
                        () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/today');
                          }
                        },
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: VitalType.control.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.8,
                  ),
                ),
              ),
            ),
            SizedBox(width: 48, child: trailing),
          ],
        ),
      ),
    );
  }
}

class VitalSettingsPage extends StatelessWidget {
  const VitalSettingsPage({
    super.key,
    required this.title,
    this.children = const [],
    this.body,
    this.onBack,
    this.trailing,
    this.headerChildren = const [],
    this.hub = false,
  });
  final String title;
  final List<Widget> children, headerChildren;
  final Widget? body, trailing;
  final VoidCallback? onBack;
  final bool hub;

  @override
  Widget build(BuildContext context) => VitalSettingsScope(
    fallbackTitle: title,
    hub: hub,
    child: VitalScaffold(
      headers: [
        VitalSettingsToolbar(title: title, onBack: onBack, trailing: trailing),
        ...headerChildren,
      ],
      child: body ?? VitalSettingsBody(hub: hub, children: children),
    ),
  );
}

/// Shared drilldown gutters and breathing room, inside the measured viewport.
class VitalSettingsBody extends StatelessWidget {
  const VitalSettingsBody({
    super.key,
    required this.children,
    this.hub = false,
  });
  final List<Widget> children;
  final bool hub;
  @override
  Widget build(BuildContext context) => VitalInsetScrollView(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VitalLayout.contentWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(hub ? 16 : 20, 12, hub ? 16 : 20, 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class VitalSettingsLabel extends StatelessWidget {
  const VitalSettingsLabel(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            ExcludeSemantics(
              child: Icon(icon, size: 13, color: VitalColors(context).muted),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: VitalSettingsType.section.copyWith(
                color: VitalColors(context).muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class VitalSettingsSection extends StatelessWidget {
  const VitalSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.icon,
  });
  final String title;
  final List<Widget> children;
  final String? description;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      VitalSettingsLabel(title, icon: icon),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(
          description!,
          style: VitalSettingsType.detail.copyWith(
            color: VitalColors(context).muted,
          ),
        ),
      ],
      const SizedBox(height: 8),
      ...children,
    ],
  );
}

/// Flat destination row with Workout's 44px colour badge and full-size type.
class VitalSettingsRow extends StatelessWidget {
  const VitalSettingsRow({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
    this.icon,
  });
  final String label, description;
  final VoidCallback onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    final hub = VitalSettingsScope.maybeOf(context)?.hub ?? false;
    return Semantics(
      label: label,
      hint: description,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: VitalControlStyle(
          quiet: true,
          radius: 14,
          padding: EdgeInsets.symmetric(horizontal: hub ? 16 : 2, vertical: 14),
          child: Button(
            style: ButtonVariance.ghost,
            disableTransition: VitalMotion.reduced(context),
            onPressed: onPressed,
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.accentSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: c.accent, size: 22),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: VitalSettingsType.item.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: VitalSettingsType.detail.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(LucideIcons.chevronRight, size: 20, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Used for factual storage/backup summaries, rather than nesting whole pages.
class VitalSettingsCard extends StatelessWidget {
  const VitalSettingsCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      VitalSurfaceFrame(radius: 16, child: child);
}
