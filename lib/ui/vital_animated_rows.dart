import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_motion.dart';

/// Exit content is a read-only snapshot, so callers can release removed inputs.
class VitalAnimatedRow {
  const VitalAnimatedRow({
    required this.id,
    required this.child,
    required this.exitChild,
  });
  final String id;
  final Widget child, exitChild;
}

/// Stable keyed rows with a small spring settle and coordinated bounds.
class VitalAnimatedRows extends StatefulWidget {
  const VitalAnimatedRows({super.key, required this.rows});
  final List<VitalAnimatedRow> rows;
  @override
  State<VitalAnimatedRows> createState() => _VitalAnimatedRowsState();
}

class _VitalAnimatedRowsState extends State<VitalAnimatedRows> {
  final _key = GlobalKey<AnimatedListState>();
  late final List<VitalAnimatedRow> _rows = [...widget.rows];
  @override
  void didUpdateWidget(covariant VitalAnimatedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = _key.currentState;
    if (state == null) {
      _rows
        ..clear()
        ..addAll(widget.rows);
      return;
    }
    for (var i = _rows.length - 1; i >= 0; i--) {
      if (!widget.rows.any((row) => row.id == _rows[i].id)) {
        final removed = _rows.removeAt(i);
        state.removeItem(
          i,
          (context, animation) =>
              _transition(context, removed.exitChild, animation, exiting: true),
          duration: VitalMotion.duration(context, VitalMotion.rowRemove),
        );
      }
    }
    for (var i = 0; i < widget.rows.length; i++) {
      final row = widget.rows[i];
      if (i < _rows.length && _rows[i].id == row.id) {
        _rows[i] = row;
        continue;
      }
      final oldIndex = _rows.indexWhere((old) => old.id == row.id);
      if (oldIndex >= 0) {
        final moved = _rows.removeAt(oldIndex);
        state.removeItem(
          oldIndex,
          (context, animation) =>
              _transition(context, moved.exitChild, animation, exiting: true),
          duration: VitalMotion.duration(context, VitalMotion.rowRemove),
        );
      }
      _rows.insert(i, row);
      state.insertItem(
        i,
        duration: VitalMotion.duration(context, VitalMotion.rowSpring),
      );
    }
  }

  Widget _transition(
    BuildContext context,
    Widget child,
    Animation<double> animation, {
    bool exiting = false,
  }) {
    if (VitalMotion.reduced(context)) return child;
    final body = SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.topCenter,
          scale: animation
              .drive(CurveTween(curve: Curves.easeOutBack))
              .drive(Tween(begin: .94, end: 1.0)),
          child: child,
        ),
      ),
    );
    return exiting
        ? IgnorePointer(
            child: ExcludeSemantics(child: ExcludeFocus(child: body)),
          )
        : body;
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
    key: _key,
    initialItemCount: _rows.length,
    shrinkWrap: true,
    primary: false,
    padding: EdgeInsets.zero,
    physics: const NeverScrollableScrollPhysics(),
    itemBuilder: (context, index, animation) => KeyedSubtree(
      key: ValueKey(_rows[index].id),
      child: _transition(context, _rows[index].child, animation),
    ),
  );
}
