import 'package:flutter/material.dart' as m;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as s;

import '../../app/display_preferences.dart';
import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../vital_dialog.dart';
import '../vital_foundation.dart';
import '../vital_motion.dart';
import '../vital_presenters.dart' show showVitalDialog;

/// Palette/type bridge for the owner's canonical picker geometry and painter.
/// It supplies no Material buttons, dialogs, or theme selection of its own.
abstract final class VitalPickerTheme {
  static m.ThemeData of(m.BuildContext context) {
    final theme = s.Theme.of(context);
    final c = VitalColors(context);
    final scheme =
        m.ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: theme.brightness == s.Brightness.dark
              ? m.Brightness.dark
              : m.Brightness.light,
        ).copyWith(
          primary: c.accent,
          onPrimary: c.accentInk,
          surface: theme.colorScheme.popover,
          onSurface: c.ink,
          onSurfaceVariant: c.muted,
          outlineVariant: c.line,
          surfaceContainerHighest: theme.colorScheme.secondary,
        );
    return m.ThemeData(
      colorScheme: scheme,
      fontFamily: VitalType.uiFontFamily,
      textTheme: m.TextTheme(
        headlineSmall: VitalType.detailTitle,
        headlineMedium: VitalType.metric,
        titleLarge: VitalType.dialogTitle,
        titleSmall: VitalType.control,
        bodyLarge: VitalType.body,
        bodyMedium: VitalType.body,
        bodySmall: VitalType.metadata,
        labelLarge: VitalType.control,
        labelMedium: VitalType.label,
        labelSmall: VitalType.micro,
      ),
    );
  }
}

bool vitalPickerUses24Hour(m.BuildContext context) => displayFormatter(
  context,
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(displayPreferencesProvider).timeFormat,
).use24Hour;

class VitalPickerHandle<T> {
  VitalPickerHandle(this.context);
  final m.BuildContext context;
  void complete(T? value) {
    if (!context.mounted || m.ModalRoute.of(context)?.isCurrent != true) return;
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(appLockProvider).locked) return;
    m.Navigator.of(context).pop(value);
  }

  void cancel() {
    if (context.mounted && m.ModalRoute.of(context)?.isCurrent == true) {
      m.Navigator.of(context).pop();
    }
  }
}

Future<T?> showVitalPickerDialog<T>({
  required m.BuildContext context,
  required m.Widget Function(m.BuildContext, VitalPickerHandle<T>) builder,
}) => showVitalDialog<T>(
  context: context,
  builder: (context) => _PickerSession<T>(builder: builder),
);

enum VitalPickerScrollMode { bounded }

class VitalPickerFrame extends m.StatelessWidget {
  const VitalPickerFrame({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
    this.footer,
    this.titleTextStyle,
    this.scrollMode,
    this.headerBodySpacing,
    this.footerSpacing,
    this.maxWidth = 440,
  });
  final String title;
  final m.Widget body;
  final m.Widget? trailing, footer;
  final m.TextStyle? titleTextStyle;
  final VitalPickerScrollMode? scrollMode;
  final double? headerBodySpacing, footerSpacing;
  final double maxWidth;
  @override
  m.Widget build(m.BuildContext context) => VitalDialog(
    title: m.Text(title, style: titleTextStyle),
    headerAlignment: m.CrossAxisAlignment.center,
    trailing: trailing,
    maxWidth: maxWidth,
    content: body,
    contentPadding: maxWidth == 360
        ? const m.EdgeInsets.fromLTRB(18, 18, 18, 16)
        : const m.EdgeInsets.fromLTRB(20, 18, 20, 18),
    surfaceRadius: maxWidth == 360 ? 24 : 28,
    headerBodySpacing: headerBodySpacing ?? 14,
    footerSpacing: footerSpacing ?? 16,
    actions: footer == null ? null : [footer!],
  );
}

class VitalPickerAction {
  const VitalPickerAction.primary({
    required this.label,
    required this.onPressed,
  }) : primary = true;
  const VitalPickerAction.secondary({
    required this.label,
    required this.onPressed,
  }) : primary = false;
  final String label;
  final m.VoidCallback? onPressed;
  final bool primary;
}

class VitalPickerActionBar extends m.StatelessWidget {
  const VitalPickerActionBar({super.key, required this.actions});
  final List<VitalPickerAction> actions;
  @override
  m.Widget build(m.BuildContext context) => VitalDialogActions(
    children: [
      for (final action in actions)
        VitalControlStyle(
          tone: action.primary
              ? VitalControlTone.primary
              : VitalControlTone.secondary,
          child: s.Button(
            style: s.ButtonVariance.secondary,
            onPressed: action.onPressed,
            child: m.Text(action.label),
          ),
        ),
    ],
  );
}

class VitalPickerTap extends m.StatelessWidget {
  const VitalPickerTap({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.radius,
  });
  final m.Widget child;
  final m.VoidCallback? onTap;
  final m.BorderRadius? borderRadius;
  final double? radius;
  @override
  m.Widget build(m.BuildContext context) => VitalPress(
    enabled: onTap != null,
    child: s.Clickable(
      onPressed: onTap,
      disableTransition: VitalMotion.reduced(context),
      decoration: m.WidgetStateProperty.resolveWith(
        (states) => m.BoxDecoration(
          borderRadius: borderRadius ?? m.BorderRadius.circular(radius ?? 18),
          color:
              states.contains(m.WidgetState.hovered) ||
                  states.contains(m.WidgetState.pressed)
              ? VitalColors(context).accent.withValues(alpha: .08)
              : m.Colors.transparent,
        ),
      ),
      child: child,
    ),
  );
}

class VitalPickerIconButton extends m.StatelessWidget {
  const VitalPickerIconButton({
    super.key,
    this.tooltip,
    required this.icon,
    this.onPressed,
    this.visualDensity,
  });
  final String? tooltip;
  final m.Widget icon;
  final m.VoidCallback? onPressed;
  final m.VisualDensity? visualDensity;
  @override
  m.Widget build(m.BuildContext context) => m.Semantics(
    label: tooltip,
    child: VitalControlStyle(
      quiet: true,
      padding: const m.EdgeInsets.all(12),
      child: s.Button(
        style: s.ButtonVariance.ghost,
        onPressed: onPressed,
        child: m.ExcludeSemantics(child: icon),
      ),
    ),
  );
}

class VitalPickerTextButton extends m.StatelessWidget {
  const VitalPickerTextButton.icon({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final m.Widget icon, label;
  final m.VoidCallback? onPressed;
  @override
  m.Widget build(m.BuildContext context) => VitalControlStyle(
    quiet: true,
    padding: const m.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: s.Button(
      style: s.ButtonVariance.ghost,
      onPressed: onPressed,
      child: m.Row(
        mainAxisSize: m.MainAxisSize.min,
        crossAxisAlignment: m.CrossAxisAlignment.center,
        children: [
          m.ExcludeSemantics(
            child: m.SizedBox(
              width: 18,
              height: 18,
              child: m.Center(child: icon),
            ),
          ),
          const m.SizedBox(width: 8),
          m.DefaultTextStyle.merge(
            style: const m.TextStyle(height: 1),
            child: label,
          ),
        ],
      ),
    ),
  );
}

abstract final class VitalPickerMotion {
  static Duration page(m.BuildContext c) =>
      VitalMotion.duration(c, const Duration(milliseconds: 240));
  static Duration leave(m.BuildContext c) =>
      VitalMotion.duration(c, const Duration(milliseconds: 210));
  static Duration bounds(m.BuildContext c) =>
      VitalMotion.duration(c, const Duration(milliseconds: 260));
  static Duration header(m.BuildContext c) =>
      VitalMotion.duration(c, const Duration(milliseconds: 140));
}

class _PickerSession<T> extends ConsumerStatefulWidget {
  const _PickerSession({required this.builder});
  final m.Widget Function(m.BuildContext, VitalPickerHandle<T>) builder;
  @override
  ConsumerState<_PickerSession<T>> createState() => _PickerSessionState<T>();
}

class _PickerSessionState<T> extends ConsumerState<_PickerSession<T>> {
  void _invalidate() {
    final route = m.ModalRoute.of(context);
    if (route != null && route.isActive) {
      m.Navigator.of(context).removeRoute(route);
    }
  }

  @override
  m.Widget build(m.BuildContext context) {
    ref.listen(appLockProvider, (previous, next) {
      if (next.locked && previous?.locked != true) _invalidate();
    });
    ref.listen(recordStoreProvider.select((v) => v.value?.generation), (
      previous,
      next,
    ) {
      if (previous != null && next != previous) _invalidate();
    });
    if (ref.watch(appLockProvider.select((v) => v.locked))) {
      m.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _invalidate();
      });
      return const m.SizedBox.shrink();
    }
    return widget.builder(context, VitalPickerHandle<T>(context));
  }
}
