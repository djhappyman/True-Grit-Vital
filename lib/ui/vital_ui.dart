import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';

/// Shared geometry for the adopted mobile layout on every platform.
abstract final class VitalLayout {
  static const double contentWidth = 640;
  static const double gutter = 16;
  static const double target = 48;
  static const double surfaceRadius = 24;
  static const double sheetRadius = 32;
  static const double gap = 12;
  static const double sectionGap = 24;
  static const double panelPadding = 20;
}

/// Semantic text roles shared by screens and contributor-built features.
abstract final class VitalType {
  static const title = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.8,
  );
  static const section = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
  );
  static const record = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const body = TextStyle(fontSize: 16, height: 1.5);
  static const metadata = TextStyle(fontSize: 14, height: 1.45);
  static const quantity = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

enum VitalButtonVariant { primary, secondary, destructive }

/// A shadcn command button. Descriptive choices can opt into start alignment.
class VitalButton extends StatelessWidget {
  const VitalButton({
    super.key,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.expand = false,
    this.alignment = Alignment.center,
    this.multiline = false,
  }) : variant = VitalButtonVariant.primary;

  const VitalButton.secondary({
    super.key,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.expand = false,
    this.alignment = Alignment.center,
    this.multiline = false,
  }) : variant = VitalButtonVariant.secondary;

  const VitalButton.destructive({
    super.key,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.expand = false,
    this.alignment = Alignment.center,
    this.multiline = false,
  }) : variant = VitalButtonVariant.destructive;

  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final Widget? leading;
  final Widget? trailing;
  final bool isLoading;
  final bool expand;
  final AlignmentGeometry alignment;
  final bool multiline;
  final VitalButtonVariant variant;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildButton(context, constraints),
  );

  Widget _buildButton(BuildContext context, BoxConstraints constraints) {
    final colors = Theme.of(context).colorScheme;
    final foreground = switch (variant) {
      VitalButtonVariant.primary => colors.primaryForeground,
      VitalButtonVariant.secondary => colors.secondaryForeground,
      VitalButtonVariant.destructive => Colors.white,
    };
    final fill = switch (variant) {
      VitalButtonVariant.primary => colors.primary,
      VitalButtonVariant.secondary => colors.secondary,
      VitalButtonVariant.destructive => colors.destructive,
    };
    final effectiveAlignment = multiline
        ? AlignmentDirectional.centerStart
        : alignment;
    final centred = effectiveAlignment == Alignment.center;
    final hasLeading = leading != null || isLoading;
    final hasTrailing = trailing != null;
    final leadingSlot = hasLeading || (centred && hasTrailing);
    final trailingSlot = hasTrailing || (centred && hasLeading);
    var horizontalPadding = 20.0;
    if (!multiline && constraints.hasBoundedWidth && child is Text) {
      final text = child as Text;
      final typography = Theme.of(context).typography;
      final painter = TextPainter(
        text: TextSpan(
          text: text.data,
          style: typography.small.merge(typography.medium).merge(text.style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final accessories = (leadingSlot ? 28 : 0) + (trailingSlot ? 28 : 0);
      horizontalPadding = math.min(
        20,
        math.max(0, (constraints.maxWidth - painter.width - accessories) / 2),
      );
      painter.dispose();
    }
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingSlot) ...[
          SizedBox(
            width: 20,
            height: 20,
            child: ExcludeSemantics(
              child: isLoading
                  ? CircularProgressIndicator(
                      theme: CircularProgressIndicatorTheme(color: foreground),
                    )
                  : leading,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            alignment: effectiveAlignment,
            child: DefaultTextStyle.merge(
              maxLines: multiline ? null : 1,
              softWrap: multiline,
              child: child,
            ),
          ),
        ),
        if (trailingSlot) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            height: 20,
            child: ExcludeSemantics(child: trailing ?? const SizedBox.shrink()),
          ),
        ],
      ],
    );
    final button = ButtonStyleOverride(
      decoration: (context, states, decoration) {
        if (decoration is! BoxDecoration) return decoration;
        final disabled = states.contains(WidgetState.disabled);
        return decoration.copyWith(
          borderRadius: BorderRadius.circular(999),
          color: isLoading
              ? fill
              : disabled
              ? colors.secondary
              : variant == VitalButtonVariant.destructive
              ? (decoration.color ?? fill).withValues(alpha: 1)
              : decoration.color,
          border: disabled && !isLoading
              ? Border.all(color: colors.mutedForeground)
              : decoration.border,
        );
      },
      textStyle: (context, states, textStyle) => textStyle.copyWith(
        color: isLoading
            ? foreground
            : states.contains(WidgetState.disabled)
            ? colors.mutedForeground
            : textStyle.color,
      ),
      iconTheme: (context, states, iconTheme) => iconTheme.copyWith(
        color: isLoading
            ? foreground
            : states.contains(WidgetState.disabled)
            ? colors.mutedForeground
            : iconTheme.color,
      ),
      padding: (context, states, padding) =>
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
      child: Button(
        style: switch (variant) {
          VitalButtonVariant.primary => ButtonVariance.primary,
          VitalButtonVariant.secondary => ButtonVariance.secondary,
          VitalButtonVariant.destructive => ButtonVariance.destructive,
        },
        onPressed: isLoading ? null : onPressed,
        focusNode: focusNode,
        disableTransition: MediaQuery.disableAnimationsOf(context),
        alignment: effectiveAlignment,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24, minWidth: 8),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            alignment: effectiveAlignment,
            child: content,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null && !isLoading,
      liveRegion: isLoading,
      value: isLoading ? AppLocalizations.of(context).working : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: VitalLayout.target,
          minWidth: VitalLayout.target,
        ),
        child: expand
            ? SizedBox(width: double.infinity, child: button)
            : button,
      ),
    );
  }
}

/// Semantic surface roles keep future material changes in one place.
enum VitalSurfaceRole { contained, section, sheet, inset }

class VitalSurface extends StatelessWidget {
  const VitalSurface({
    super.key,
    required this.child,
    this.role = VitalSurfaceRole.contained,
    this.padding = const EdgeInsets.all(VitalLayout.panelPadding),
  });

  final Widget child;
  final VitalSurfaceRole role;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: role == VitalSurfaceRole.inset ? colors.secondary : colors.card,
        borderRadius: BorderRadius.circular(
          role == VitalSurfaceRole.sheet
              ? VitalLayout.sheetRadius
              : VitalLayout.surfaceRadius,
        ),
        border: Border.all(
          color: colors.border.withValues(alpha: dark ? 0.65 : 0.85),
        ),
        boxShadow: role == VitalSurfaceRole.sheet
            ? [
                BoxShadow(
                  color: const Color(0xFF000000)
                      .withValues(alpha: dark ? 0.2 : 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class VitalSection extends StatelessWidget {
  const VitalSection({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });

  final Widget title;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: VitalType.section,
              child: Semantics(header: true, child: title),
            ),
          ),
          ?action,
        ],
      ),
      for (final child in children) ...[
        const SizedBox(height: VitalLayout.gap),
        child,
      ],
    ],
  );
}

/// Width and gutters only; the caller retains ownership of scrolling/insets.
class VitalPageBody extends StatelessWidget {
  const VitalPageBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: VitalLayout.contentWidth),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(VitalLayout.gutter),
        child: DefaultTextStyle.merge(style: VitalType.body, child: child),
      ),
    ),
  );
}

/// The standard feature page. Its chrome and scrollable body respect safe areas.
class VitalPage extends StatelessWidget {
  const VitalPage({
    super.key,
    this.title,
    this.leading,
    this.headerActions = const [],
    required this.children,
    this.panelled = false,
  });
  final String? title;
  final Widget? leading;
  final List<Widget> headerActions, children;
  final bool panelled;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Scaffold(
      headers: [
        if (leading != null || headerActions.isNotEmpty)
          VitalPageBody(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?leading, ...headerActions],
            ),
          ),
      ],
      child: VitalScrollBody(
        children: [
          if (title != null) VitalPageHeader(title: title!),
          if (panelled) VitalPanel(gap: 0, children: children) else ...children,
        ],
      ),
    ),
  );
}

/// Bounded content, keyboard-aware scrolling and device insets in one place.
class VitalScrollBody extends StatelessWidget {
  const VitalScrollBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: VitalPageBody(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// A page title with optional context and a wrapping action area.
class VitalPageHeader extends StatelessWidget {
  const VitalPageHeader({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.actions = const [],
  });
  final String title;
  final String? description;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: VitalLayout.sectionGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              VitalIconTile(icon!),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: VitalType.title),
              ),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: VitalType.metadata.copyWith(
              color: Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          VitalActions(children: actions),
        ],
      ],
    ),
  );
}

/// One opaque group for related form fields, settings or review content.
class VitalPanel extends StatelessWidget {
  const VitalPanel({
    super.key,
    this.title,
    this.description,
    this.icon,
    this.action,
    required this.children,
    this.gap = 16,
    this.inset = false,
  });
  final String? title, description;
  final IconData? icon;
  final Widget? action;
  final List<Widget> children;
  final double gap;
  final bool inset;

  @override
  Widget build(BuildContext context) => VitalSurface(
    role: inset ? VitalSurfaceRole.inset : VitalSurfaceRole.contained,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                VitalIconTile(icon!, size: 36),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title!, style: VitalType.section),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (description != null) ...[
          Text(
            description!,
            style: VitalType.metadata.copyWith(
              color: Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 && gap > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    ),
  );
}

/// An icon is always accompanied by an authored label in its parent.
class VitalIconTile extends StatelessWidget {
  const VitalIconTile(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.accent,
        borderRadius: BorderRadius.circular(size * 0.4),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * 0.48,
        color: Theme.of(context).colorScheme.accentForeground,
      ),
    ),
  );
}

class VitalRecordHeader extends StatelessWidget {
  const VitalRecordHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = LucideIcons.pill,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VitalIconTile(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VitalType.record),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: VitalType.metadata.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class VitalActions extends StatelessWidget {
  const VitalActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

enum VitalTone { neutral, positive, warning, danger }

class VitalBadge extends StatelessWidget {
  const VitalBadge(this.label, {super.key, this.tone = VitalTone.neutral});
  final String label;
  final VitalTone tone;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = switch (tone) {
      VitalTone.neutral => colors.mutedForeground,
      VitalTone.positive => colors.accentForeground,
      VitalTone.warning => Color(dark ? 0xFFE9CB85 : 0xFF765000),
      VitalTone.danger => colors.destructive,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tone == VitalTone.neutral
            ? colors.secondary
            : foreground.withValues(alpha: dark ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: VitalType.label.copyWith(color: foreground)),
    );
  }
}

/// Inline status keeps the message and its recovery action together.
class VitalNotice extends StatelessWidget {
  const VitalNotice({
    super.key,
    required this.child,
    this.icon = LucideIcons.info,
    this.action,
    this.tone = VitalTone.neutral,
  });
  final Widget child;
  final IconData icon;
  final Widget? action;
  final VitalTone tone;
  @override
  Widget build(BuildContext context) => VitalSurface(
    role: VitalSurfaceRole.inset,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: tone == VitalTone.danger
                  ? Theme.of(context).colorScheme.destructive
                  : Theme.of(context).colorScheme.accentForeground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: VitalType.metadata,
                child: child,
              ),
            ),
          ],
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

class VitalEmptyState extends StatelessWidget {
  const VitalEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = LucideIcons.inbox,
    this.action,
  });
  final String title;
  final String? description;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => VitalPanel(
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalIconTile(icon, size: 48),
      ),
      Semantics(header: true, child: Text(title, style: VitalType.section)),
      if (description != null)
        Text(
          description!,
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      if (action != null)
        Align(alignment: AlignmentDirectional.centerStart, child: action!),
    ],
  );
}

/// Visible labels and helper text around the existing shadcn input controls.
class VitalField extends StatelessWidget {
  const VitalField({
    super.key,
    required this.label,
    required this.child,
    this.description,
  });
  final String label;
  final Widget child;
  final String? description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: VitalType.label),
      const SizedBox(height: 8),
      child,
      if (description != null) ...[
        const SizedBox(height: 6),
        Text(
          description!,
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      ],
    ],
  );
}

/// Keep native shadcn input styling shared, without changing text alignment.
class VitalComponentThemes extends StatelessWidget {
  const VitalComponentThemes({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ComponentTheme<TextFieldTheme>(
    data: TextFieldTheme(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: Border.all(color: Theme.of(context).colorScheme.input),
    ),
    child: child,
  );
}

/// Shared material boundary around shadcn's dialog anatomy and behaviour.
class VitalDialog extends StatelessWidget {
  const VitalDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.leading,
    this.trailing,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? trailing;

  static bool _isScrollable(Widget? widget) =>
      widget is SingleChildScrollView || widget is ScrollView;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final largeText = media.textScaler.scale(14) >= 28;
    final padding = largeText ? 8.0 : 24.0;
    final theme = Theme.of(context);
    final maxWidth = math.min(560.0, screen.width - (largeText ? 0 : 32));
    final maxHeight = math.max(
      48.0,
      screen.height -
          media.viewInsets.bottom -
          media.padding.top -
          media.padding.bottom -
          32,
    );
    final contentMaxHeight = math.max(
      0.0,
      maxHeight - padding * 2 - 2 * theme.scaling,
    );
    final densityGap = theme.density.baseGap * theme.scaling;
    final hasHeader = title != null || leading != null || trailing != null;
    final hasActions = actions?.isNotEmpty ?? false;

    final header = hasHeader
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) leading!.iconXLarge().iconMutedForeground(),
              if (title != null)
                Flexible(child: title!.foreground().large().semiBold()),
              if (trailing != null)
                trailing!.iconXLarge().iconMutedForeground(),
            ],
          ).gap(densityGap * 2)
        : null;
    final actionRow = hasActions
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 12,
            children: actions!,
          )
        : null;

    // The header and body share a bounded, scrollable region. Actions stay
    // outside it so they remain reachable when real copy or large text exceeds
    // the available height. Callers that already supply their own scroll view
    // keep it as the single scrollable region.
    final body = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: contentMaxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isScrollable(content)) ...[
            if (header != null) ...[header, SizedBox(height: densityGap)],
            Flexible(fit: FlexFit.loose, child: content!),
          ] else if (header != null || content != null)
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                key: const ValueKey('vital-dialog-scroll'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?header,
                    if (header != null && content != null)
                      SizedBox(height: densityGap),
                    ?content,
                  ],
                ),
              ),
            ),
          if (actionRow != null) ...[const SizedBox(height: 20), actionRow],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: AlertDialog(
            content: body,
            padding: EdgeInsets.all(padding),
            surfaceBlur: 0,
            surfaceOpacity: 1,
          ),
        ),
      ),
    );
  }
}

/// Short section choices with shadcn focus, keyboard and button behaviour.
///
/// Choices wrap at large text sizes rather than shrinking their labels. This is
/// for section labels, not descriptive dropdowns or multiline record choices.
class VitalSegments<T> extends StatelessWidget {
  const VitalSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.label,
    this.expand = true,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) label;
  final bool expand;

  Widget _option(T value) {
    final isSelected = value == selected;
    final text = Text(label(value));
    void action() => onChanged(value);
    return MergeSemantics(
      child: Semantics(
        selected: isSelected,
        inMutuallyExclusiveGroup: true,
        child: isSelected
            ? VitalButton(onPressed: action, child: text)
            : VitalButton.secondary(onPressed: action, child: text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.typography.small.merge(theme.typography.medium);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final widths = values.map((value) {
      final painter = TextPainter(
        text: TextSpan(text: label(value), style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width + 40;
      painter.dispose();
      return width < VitalLayout.target ? VitalLayout.target : width;
    }).toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final equalWidth = values.isEmpty
              ? 0.0
              : (constraints.maxWidth - (values.length - 1) * 4) /
                    values.length;
          final fitsRow =
              constraints.hasBoundedWidth &&
              widths.every((width) => width <= equalWidth);
          if (expand && fitsRow) {
            return Row(
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _option(values[i])),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final value in values) _option(value)],
          );
        },
      ),
    );
  }
}
