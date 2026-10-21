import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Semantic timing shared by all current and future Vital screens.
abstract final class VitalMotion {
  static const press = Duration(milliseconds: 100);
  static const release = Duration(milliseconds: 180);
  static const choice = Duration(milliseconds: 220);
  static const root = Duration(milliseconds: 280);
  static const detail = Duration(milliseconds: 380);
  static const returning = Duration(milliseconds: 300);
  static const expand = Duration(milliseconds: 420);
  static const collapse = Duration(milliseconds: 300);
  static const sheet = Duration(milliseconds: 440);
  static const sheetClose = Duration(milliseconds: 300);
  static const dialog = Duration(milliseconds: 320);
  static const dialogClose = Duration(milliseconds: 220);
  static const row = Duration(milliseconds: 340);
  static const calendar = Duration(milliseconds: 340);
  static const filter = Duration(milliseconds: 220);
  static const progress = Duration(milliseconds: 480);
  static const theme = Duration(milliseconds: 280);
  static const arrival = Cubic(.22, 1, .36, 1);
  static const geometry = Cubic(.65, 0, .35, 1);
  static const departure = Cubic(.4, 0, 1, 1);

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

/// Visual feedback around the existing shadcn control. Its hit box never moves.
class VitalPress extends StatefulWidget {
  const VitalPress({super.key, required this.child});
  final Widget child;
  @override
  State<VitalPress> createState() => _VitalPressState();
}

class _VitalPressState extends State<VitalPress> {
  final _pointers = <int>{};
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => setState(() => _pointers.add(event.pointer)),
    onPointerUp: (event) => setState(() => _pointers.remove(event.pointer)),
    onPointerCancel: (event) => setState(() => _pointers.remove(event.pointer)),
    child: TweenAnimationBuilder<double>(
      tween: Tween(
        end: _pointers.isEmpty || VitalMotion.reduced(context) ? 1 : .985,
      ),
      duration: VitalMotion.duration(
        context,
        _pointers.isEmpty ? VitalMotion.release : VitalMotion.press,
      ),
      curve: VitalMotion.arrival,
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, transformHitTests: false, child: child),
      child: widget.child,
    ),
  );
}

/// Interruptible bounds reveal that preserves forms and excludes hidden focus.
class VitalReveal extends StatelessWidget {
  const VitalReveal({super.key, required this.expanded, required this.child});
  final bool expanded;
  final Widget child;
  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !expanded,
    child: ExcludeSemantics(
      excluding: !expanded,
      child: TickerMode(
        enabled: expanded,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: expanded ? 1 : 0),
          duration: VitalMotion.duration(
            context,
            expanded ? VitalMotion.expand : VitalMotion.collapse,
          ),
          curve: VitalMotion.geometry,
          child: child,
          builder: (_, value, child) => ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: value,
              child: Offstage(offstage: value == 0, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A controlled pager with retained children and explicit hidden-page semantics.
class VitalPager extends StatefulWidget {
  const VitalPager({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
    required this.onChanged,
    this.duration = VitalMotion.root,
    this.retainPages = true,
  });
  final int index, itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onChanged;
  final Duration duration;
  final bool retainPages;
  @override
  State<VitalPager> createState() => _VitalPagerState();
}

class _VitalPagerState extends State<VitalPager> {
  late final _controller = PageController(initialPage: widget.index);
  int _generation = 0;
  bool _programmed = false;
  int? _gestureSelection;
  bool _moving = false;
  @override
  void didUpdateWidget(VitalPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (widget.index == _gestureSelection) {
        _gestureSelection = null;
      } else {
        _move();
      }
    }
  }

  void _move() {
    final generation = ++_generation;
    // Fence stale scroll callbacks as soon as the destination changes.
    _programmed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _generation || !_controller.hasClients) {
        return;
      }
      final target = widget.index;
      final page = _controller.page ?? target.toDouble();
      if ((page - target).abs() < .001) {
        // A previous activity can still be running even at the target pixel.
        _controller.jumpToPage(target);
        _programmed = false;
        return;
      }
      if (VitalMotion.reduced(context)) {
        _controller.jumpToPage(target);
      } else {
        // Long destination jumps reveal only the final neighbouring page.
        if ((page - target).abs() > 1) {
          _controller.jumpToPage(target > page ? target - 1 : target + 1);
        }
        await _controller.animateToPage(
          target,
          duration: widget.duration,
          curve: VitalMotion.arrival,
        );
      }
      if (mounted && generation == _generation) _programmed = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VitalMotion.reduced(context)) _move();
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification && !_moving) {
            setState(() => _moving = true);
          }
          if (notification is ScrollEndNotification && _moving) {
            setState(() => _moving = false);
          }
          return false;
        },
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.itemCount,
          onPageChanged: (index) {
            if (!_programmed) {
              _gestureSelection = index;
              widget.onChanged(index);
            }
          },
          itemBuilder: (context, index) => _RetainedPage(
            key: ValueKey(index),
            active: index == widget.index,
            visible: _moving || index == widget.index,
            retain: widget.retainPages,
            child: widget.itemBuilder(context, index),
          ),
        ),
      );
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({
    super.key,
    required this.active,
    required this.visible,
    required this.child,
    required this.retain,
  });
  final bool active, visible, retain;
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.retain;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      enabled: widget.active,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: ExcludeSemantics(
          excluding: !widget.active,
          child: Offstage(offstage: !widget.visible, child: widget.child),
        ),
      ),
    );
  }
}
