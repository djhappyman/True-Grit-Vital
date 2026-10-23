import 'dart:math' as math;

import 'package:flutter/material.dart' as material show MaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import 'vital_foundation.dart';
import 'vital_motion.dart';
import 'vital_glass.dart';

/// Route-backed tasks retain the feature's existing draft and PopScope engine.
class VitalTaskScope extends InheritedWidget {
  const VitalTaskScope({super.key, required super.child});
  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VitalTaskScope>() != null;
  @override
  bool updateShouldNotify(VitalTaskScope oldWidget) => false;
}

/// One bounded, keyboard-aware scrolling owner inside a modal task route.
class VitalTaskBody extends StatelessWidget {
  const VitalTaskBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    child: DefaultTextStyle.merge(
      style: VitalType.body.copyWith(color: VitalColors(context).ink),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Only the handle owns dismissal dragging. Scroll gestures stay with fields.
/// Every exit requests maybePop, allowing the route's durable guard to decide.
class VitalTaskFrame extends StatefulWidget {
  const VitalTaskFrame({super.key, required this.child, this.dialog = false});
  final Widget child;
  final bool dialog;
  @override
  State<VitalTaskFrame> createState() => _VitalTaskFrameState();
}

class _VitalTaskFrameState extends State<VitalTaskFrame> {
  double _drag = 0;
  void _dismiss() => requestVitalTaskDismiss(context);
  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    final text = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
      child: AnimatedPadding(
        duration: VitalMotion.duration(context, VitalMotion.choice),
        curve: VitalMotion.arrival,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: widget.dialog
                  ? Alignment.center
                  : Alignment.bottomCenter,
              child: AnimatedSlide(
                offset: Offset(0, _drag / math.max(constraints.maxHeight, 1)),
                duration: _drag == 0
                    ? VitalMotion.duration(context, VitalMotion.sheetClose)
                    : Duration.zero,
                curve: VitalMotion.arrival,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: widget.dialog ? 560 : VitalLayout.contentWidth,
                    maxHeight: math.max(48, constraints.maxHeight * .94),
                  ),
                  margin: widget.dialog
                      ? const EdgeInsets.all(16)
                      : EdgeInsets.zero,
                  child: VitalGlassSurface(
                    role: widget.dialog
                        ? VitalGlassRole.dialog
                        : VitalGlassRole.sheet,
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(28),
                      bottom: Radius.circular(widget.dialog ? 28 : 0),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: widget.dialog
                              ? null
                              : (details) => setState(
                                  () => _drag = math.max(
                                    0,
                                    _drag + details.delta.dy,
                                  ),
                                ),
                          onVerticalDragEnd: widget.dialog
                              ? null
                              : (details) {
                                  if (_drag > 72 ||
                                      (details.primaryVelocity ?? 0) > 650) {
                                    _dismiss();
                                  }
                                  setState(() => _drag = 0);
                                },
                          onVerticalDragCancel: () => setState(() => _drag = 0),
                          child: Semantics(
                            label: text.cancel,
                            button: true,
                            onTap: _dismiss,
                            child: ExcludeSemantics(
                              child: Button(
                                style: ButtonVariance.ghost,
                                onPressed: _dismiss,
                                child: SizedBox(
                                  height: 36,
                                  width: 80,
                                  child: Center(
                                    child: Container(
                                      width: 40,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: c.muted,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Flexible(child: widget.child),
                        SizedBox(height: MediaQuery.paddingOf(context).bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared decision transition, with the existing shadcn dialog as content.
Future<T?> showVitalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final content = InheritedTheme.captureAll(context, Builder(builder: builder));
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _VitalDecisionRoute<T>(
      settings: routeSettings,
      barrierDismissible: barrierDismissible,
      barrierLabel: material.MaterialLocalizations.of(context)
          .modalBarrierDismissLabel,
      transitionDuration: VitalMotion.duration(context, VitalMotion.dialog),
      closeDuration: VitalMotion.duration(context, VitalMotion.dialogClose),
      pageBuilder: (context, _, _) => SafeArea(child: content),
      transitionBuilder: (context, animation, secondary, child) {
        if (VitalMotion.reduced(context)) return child;
        final curved = animation.drive(
          CurveTween(
            curve: animation.status == AnimationStatus.reverse
                ? VitalMotion.departure
                : VitalMotion.arrival,
          ),
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: curved.drive(Tween(begin: .96, end: 1)),
            child: child,
          ),
        );
      },
    ),
  );
}

class _VitalDecisionRoute<T> extends RawDialogRoute<T> {
  _VitalDecisionRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    required super.transitionDuration,
    required this.closeDuration,
    required super.barrierDismissible,
    required super.barrierLabel,
    super.settings,
  }) : super(barrierColor: const Color(0x99000000));
  final Duration closeDuration;
  @override
  Duration get reverseTransitionDuration => closeDuration;
}

/// A shared live anchored filter. Overlay content rebuilds with its owner,
/// without copying the collection's query state into a second form.
class VitalLocalOptions extends StatefulWidget {
  const VitalLocalOptions({
    super.key,
    required this.label,
    required this.content,
    this.icon = LucideIcons.listFilter,
  });
  final String label;
  final Widget content;
  final IconData icon;
  @override
  State<VitalLocalOptions> createState() => _VitalLocalOptionsState();
}

class _VitalLocalOptionsState extends State<VitalLocalOptions>
    with SingleTickerProviderStateMixin {
  OverlayCompleter<dynamic>? _overlay;
  bool _open = false;
  final _triggerFocus = FocusNode();
  final _optionsFocus = FocusNode();
  late final _animation = AnimationController(
    vsync: this,
    duration: VitalMotion.sheet,
    reverseDuration: VitalMotion.sheetClose,
  );
  late final _content = ValueNotifier(widget.content);
  @override
  void didUpdateWidget(VitalLocalOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _content.value = widget.content;
    });
  }

  @override
  void dispose() {
    final overlay = _overlay;
    if (overlay != null && !overlay.isCompleted) overlay.remove();
    _animation.dispose();
    _content.dispose();
    _triggerFocus.dispose();
    _optionsFocus.dispose();
    super.dispose();
  }

  void _show(BuildContext anchor) {
    if (_overlay != null && !_overlay!.isCompleted) {
      _overlay!.close();
      return;
    }
    final media = MediaQuery.of(anchor);
    _animation.duration = VitalMotion.duration(anchor, VitalMotion.sheet);
    _animation.reverseDuration = VitalMotion.duration(
      anchor,
      VitalMotion.sheetClose,
    );
    final narrow = media.size.width < 360 || media.textScaler.scale(14) > 21;
    Widget body(BuildContext context) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _overlay?.close(),
      },
      child: Focus(
        focusNode: _optionsFocus,
        autofocus: true,
        child: ValueListenableBuilder<Widget>(
          valueListenable: _content,
          builder: (_, child, _) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(440, media.size.width - 32),
              maxHeight: math.max(
                48,
                media.size.height - media.viewInsets.bottom - 96,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  const SizedBox(height: 12),
                  VitalControlStyle(
                    child: Button(
                      style: ButtonVariance.secondary,
                      onPressed: () => _overlay?.close(),
                      child: Text(AppLocalizations.of(context).done),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (narrow) {
      _animation.value = 0;
      _overlay = openRawDrawer<void>(
        anchor: ContextAnchor(anchor),
        transformBackdrop: false,
        animationController: _animation,
        position: OverlayPosition.bottom,
        useSafeArea: false,
        autoOpen: false,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (context, extraSize, size, padding, stackIndex) =>
            VitalGlassSurface(
              role: VitalGlassRole.sheet,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: SafeArea(top: false, child: body(context)),
            ),
      );
      // shadcn leaves custom controllers with their owner, including opening.
      _animation.animateTo(1, curve: VitalMotion.arrival);
    } else {
      _overlay =
          PopoverConfiguration(
            follow: false,
            alignment: Alignment.topRight,
            anchorAlignment: Alignment.bottomRight,
            showDuration: VitalMotion.duration(anchor, VitalMotion.filter),
            dismissDuration: VitalMotion.duration(
              anchor,
              VitalMotion.dialogClose,
            ),
          ).show<void>(
            anchor,
            (context) => VitalGlassSurface(
              role: VitalGlassRole.menu,
              borderRadius: BorderRadius.circular(18),
              child: body(context),
            ),
          );
    }
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _optionsFocus.requestFocus();
    });
    _overlay!.future.whenComplete(() {
      if (mounted) {
        setState(() => _open = false);
        if (ModalRoute.of(context)?.isCurrent != false) {
          _triggerFocus.requestFocus();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => MergeSemantics(
      child: Semantics(
        label: widget.label,
        expanded: _open,
        button: true,
        child: Button(
          focusNode: _triggerFocus,
          style: ButtonVariance.ghost,
          onPressed: () => _show(anchor),
          child: SizedBox(
            width: 40,
            height: 36,
            child: Center(child: Icon(widget.icon, size: 20)),
          ),
        ),
      ),
    ),
  );
}

Future<void> requestVitalTaskDismiss(BuildContext context) async {
  if (ModalRoute.of(context)?.isCurrent == false) return;
  final navigator = Navigator.of(context);
  if (!await navigator.maybePop() && context.mounted) {
    final router = GoRouter.of(context);
    final current = GoRouterState.of(context).uri;
    final back = Uri.tryParse(current.queryParameters['return'] ?? '');
    final valid =
        back != null &&
        !back.hasScheme &&
        !back.hasAuthority &&
        back.path.startsWith('/') &&
        back != current &&
        !router.configuration.findMatch(back).isError;
    context.go(valid ? back.toString() : '/today');
  }
}

class VitalMenuAction {
  const VitalMenuAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
}

/// Native shadcn menu keyboard traversal and adaptive presentation.
class VitalOverflow extends StatelessWidget {
  const VitalOverflow({super.key, required this.label, required this.actions});
  final String label;
  final List<VitalMenuAction> actions;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => Semantics(
      label: label,
      button: true,
      child: Button(
        style: ButtonVariance.ghost,
        onPressed: () => showDropdown<void>(
          context: anchor,
          follow: false,
          showDuration: VitalMotion.duration(anchor, VitalMotion.filter),
          dismissDuration: VitalMotion.duration(
            anchor,
            VitalMotion.dialogClose,
          ),
          builder: (_) => VitalGlassSurface(
            role: VitalGlassRole.menu,
            borderRadius: BorderRadius.circular(18),
            child: ComponentTheme<MenuPopupTheme>(
              data: const MenuPopupTheme(
                fillColor: Colors.transparent,
                borderColor: Colors.transparent,
                surfaceBlur: 0,
                surfaceOpacity: 0,
              ),
              child: DropdownMenu(
                surfaceBlur: 0,
                surfaceOpacity: 0,
                children: [
                  for (final action in actions)
                    MenuButton(
                      leading: action.icon == null ? null : Icon(action.icon),
                      onPressed: (_) => action.onPressed(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          minWidth: 48,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(action.label),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        child: const SizedBox(
          width: 40,
          height: 36,
          child: Center(child: Icon(LucideIcons.ellipsis, size: 20)),
        ),
      ),
    ),
  );
}

abstract interface class VitalTaskContent {
  Widget? get taskFooter;
}

class VitalTaskActions extends StatelessWidget implements VitalTaskContent {
  const VitalTaskActions({super.key, required this.child});
  final Widget child;
  @override
  Widget get taskFooter => child;
  @override
  Widget build(BuildContext context) => child;
}
