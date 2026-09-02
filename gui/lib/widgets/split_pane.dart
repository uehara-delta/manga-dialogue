import 'package:flutter/material.dart';

/// 2 つの領域を境界のドラッグで分割するペイン。
/// [fraction] は最初の領域が占める割合（0〜1）。ドラッグ中は [onFractionChanged]、
/// 離したときに [onFractionCommitted] を呼ぶので、後者で設定に保存するとよい。
class SplitPane extends StatefulWidget {
  const SplitPane({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.fraction,
    required this.onFractionChanged,
    this.onFractionCommitted,
    this.minFirst = 160,
    this.minSecond = 160,
  });

  final Axis axis;
  final Widget first;
  final Widget second;
  final double fraction;
  final ValueChanged<double> onFractionChanged;
  final ValueChanged<double>? onFractionCommitted;

  /// 各領域の最小サイズ（論理ピクセル）
  final double minFirst;
  final double minSecond;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  static const _handleThickness = 6.0;
  bool _hover = false;
  bool _dragging = false;

  double _clamp(double fraction, double total) {
    final available = total - _handleThickness;
    if (available <= widget.minFirst + widget.minSecond) return fraction.clamp(0.0, 1.0);
    return fraction.clamp(widget.minFirst / available, 1 - widget.minSecond / available);
  }

  void _move(double delta, double fraction, double total) =>
      widget.onFractionChanged(_clamp(fraction + delta / (total - _handleThickness), total));

  void _commit(double total) {
    setState(() => _dragging = false);
    widget.onFractionCommitted?.call(_clamp(widget.fraction, total));
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final fraction = _clamp(widget.fraction, total);
        final firstSize = (total - _handleThickness) * fraction;
        final color = Theme.of(context).colorScheme;
        final active = _hover || _dragging;
        final handle = MouseRegion(
          cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 軸専用の認識器にすると、隣のリストのスクロールなどとの競合で負けない
            onHorizontalDragStart: horizontal ? (_) => setState(() => _dragging = true) : null,
            onHorizontalDragUpdate: horizontal ? (d) => _move(d.delta.dx, fraction, total) : null,
            onHorizontalDragEnd: horizontal ? (_) => _commit(total) : null,
            onHorizontalDragCancel: horizontal ? () => setState(() => _dragging = false) : null,
            onVerticalDragStart: horizontal ? null : (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: horizontal ? null : (d) => _move(d.delta.dy, fraction, total),
            onVerticalDragEnd: horizontal ? null : (_) => _commit(total),
            onVerticalDragCancel: horizontal ? null : () => setState(() => _dragging = false),
            child: Container(
              width: horizontal ? _handleThickness : null,
              height: horizontal ? null : _handleThickness,
              color: active ? color.primary.withValues(alpha: 0.35) : Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: horizontal ? 1 : null,
                height: horizontal ? null : 1,
                color: active ? color.primary : color.outlineVariant,
              ),
            ),
          ),
        );
        final children = [
          SizedBox(width: horizontal ? firstSize : null, height: horizontal ? null : firstSize, child: widget.first),
          handle,
          Expanded(child: widget.second),
        ];
        return horizontal
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}
