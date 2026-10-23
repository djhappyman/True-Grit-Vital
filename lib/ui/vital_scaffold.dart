import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_glass.dart';

/// shadcn still owns layout, keyboard avoidance and overlay hosting. Its bars
/// overlay the viewport; scroll padding lives inside the scrolling content.
class VitalScaffold extends StatefulWidget {
  const VitalScaffold({
    super.key,
    required this.child,
    this.headers = const [],
    this.footers = const [],
    this.scrollKey,
    this.backgroundColor,
  });
  final Widget child;
  final List<Widget> headers, footers;
  final Object? scrollKey;
  final Color? backgroundColor;
  @override
  State<VitalScaffold> createState() => _VitalScaffoldState();
}

class _VitalScaffoldState extends State<VitalScaffold> {
  final _progress = ValueNotifier<double>(0);
  final _header = GlobalKey();
  final _footer = GlobalKey();
  final _savedProgress = <Object?, double>{};
  @override
  void didUpdateWidget(VitalScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollKey != widget.scrollKey) {
      _savedProgress[oldWidget.scrollKey] = _progress.value;
      _progress.value = _savedProgress[widget.scrollKey] ?? 0;
    }
  }

  bool _scroll(ScrollNotification notification) {
    final source = notification.context;
    if (notification.metrics.axis != Axis.vertical ||
        (source != null && !TickerMode.valuesOf(source).enabled)) {
      return false;
    }
    final next =
        ((notification.metrics.pixels - notification.metrics.minScrollExtent) /
                21)
            .clamp(0.0, 1.0);
    if ((_progress.value - next).abs() >= .02 || next == 0 || next == 1) {
      _progress.value = next;
    }
    return false;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollNotification>(
    onNotification: _scroll,
    child: Scaffold(
      backgroundColor: widget.backgroundColor ?? Colors.transparent,
      headerBackgroundColor: Colors.transparent,
      footerBackgroundColor: Colors.transparent,
      floatingHeader: widget.headers.isNotEmpty,
      floatingFooter: widget.footers.isNotEmpty,
      headers: [
        if (widget.headers.isNotEmpty)
          ValueListenableBuilder<double>(
            valueListenable: _progress,
            child: SafeArea(
              key: _header,
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.headers,
              ),
            ),
            builder: (context, progress, child) => VitalGlassSurface(
              key: const ValueKey('vital-glass-app-bar'),
              role: VitalGlassRole.appBar,
              borderRadius: BorderRadius.zero,
              progress: Curves.easeInOutCubicEmphasized.transform(progress),
              child: child!,
            ),
          ),
      ],
      footers: [
        if (widget.footers.isNotEmpty)
          Column(
            key: _footer,
            mainAxisSize: MainAxisSize.min,
            children: widget.footers,
          ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          // shadcn lays its bars out before its body. Read their actual
          // current geometry here; Navigator may replace MediaQuery.padding.
          double height(GlobalKey key) {
            final box = key.currentContext?.findRenderObject();
            return box is RenderBox && box.hasSize ? box.size.height : 0;
          }

          final safe = MediaQuery.paddingOf(context);
          return VitalChromeInsets(
            padding: EdgeInsets.fromLTRB(
              safe.left,
              widget.headers.isEmpty ? safe.top : height(_header),
              safe.right,
              widget.footers.isEmpty ? safe.bottom : height(_footer),
            ),
            child: widget.child,
          );
        },
      ),
    ),
  );
}

/// Explicit insets survive nested branch Navigators, which own MediaQuery.
class VitalChromeInsets extends InheritedWidget {
  const VitalChromeInsets({
    super.key,
    required this.padding,
    required super.child,
  });
  final EdgeInsets padding;
  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<VitalChromeInsets>()
          ?.padding ??
      MediaQuery.paddingOf(context);
  @override
  bool updateShouldNotify(VitalChromeInsets oldWidget) =>
      padding != oldWidget.padding;
}

/// A pinned, transparent sliver tells Flutter's viewport how much fixed chrome
/// obstructs its leading edge. ensureVisible/keyboard reveal then stop below
/// the app bar, while ordinary scrolling can still paint underneath the glass.
class VitalInsetScrollView extends StatelessWidget {
  const VitalInsetScrollView({super.key, required this.child, this.controller});
  final Widget child;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    final insets = VitalChromeInsets.of(context);
    return CustomScrollView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (insets.top > 0)
          SliverPersistentHeader(
            pinned: true,
            delegate: _ChromeObstruction(insets.top),
          ),
        SliverPadding(
          padding: EdgeInsets.only(
            left: insets.left,
            right: insets.right,
            bottom: insets.bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              removeLeft: true,
              removeRight: true,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChromeObstruction extends SliverPersistentHeaderDelegate {
  _ChromeObstruction(this.extent);
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => const IgnorePointer(child: SizedBox.expand());
  @override
  bool shouldRebuild(_ChromeObstruction oldDelegate) =>
      extent != oldDelegate.extent;
}

/// The root pager and its full-width navigation share one page position.
class VitalRootPagerScope extends InheritedWidget {
  const VitalRootPagerScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final PageController controller;
  static PageController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VitalRootPagerScope>()
      ?.controller;
  @override
  bool updateShouldNotify(VitalRootPagerScope oldWidget) =>
      controller != oldWidget.controller;
}
