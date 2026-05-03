import 'package:flutter/material.dart';

enum GestureZone { left, center, right }
enum VerticalZone { leftHalf, rightHalf }

class GestureHandler extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final void Function(GestureZone zone)? onDoubleTap;
  final void Function(double delta)? onHorizontalDrag;
  final void Function(VerticalZone zone, double delta)? onVerticalDrag;
  final VoidCallback? onVerticalDragStart;
  final VoidCallback? onVerticalDragEnd;

  const GestureHandler({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onHorizontalDrag,
    this.onVerticalDrag,
    this.onVerticalDragStart,
    this.onVerticalDragEnd,
  });

  @override
  State<GestureHandler> createState() => _GestureHandlerState();
}

class _GestureHandlerState extends State<GestureHandler> {
  bool _isDragging = false;
  double _dragAccumulator = 0.0;

  GestureZone _getHorizontalZone(BuildContext context, Offset localPos) {
    final w = context.size?.width ?? 1;
    if (localPos.dx < w / 3) return GestureZone.left;
    if (localPos.dx > w * 2 / 3) return GestureZone.right;
    return GestureZone.center;
  }

  VerticalZone _getVerticalZone(BuildContext context, Offset localPos) {
    final w = context.size?.width ?? 1;
    return localPos.dx < w / 2 ? VerticalZone.leftHalf : VerticalZone.rightHalf;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSingleTap,
      onDoubleTapDown: (details) {
        final zone = _getHorizontalZone(context, details.localPosition);
        widget.onDoubleTap?.call(zone);
      },
      onHorizontalDragStart: (_) {
        _isDragging = true;
        _dragAccumulator = 0.0;
      },
      onHorizontalDragUpdate: (details) {
        if (!_isDragging) return;
        _dragAccumulator += details.delta.dx;
        widget.onHorizontalDrag?.call(details.delta.dx);
      },
      onHorizontalDragEnd: (_) {
        _isDragging = false;
        _dragAccumulator = 0.0;
      },
      onVerticalDragStart: (_) {
        _isDragging = true;
        _dragAccumulator = 0.0;
        widget.onVerticalDragStart?.call();
      },
      onVerticalDragUpdate: (details) {
        if (!_isDragging) return;
        final zone = _getVerticalZone(context, details.localPosition);
        widget.onVerticalDrag?.call(zone, details.delta.dy);
      },
      onVerticalDragEnd: (_) {
        _isDragging = false;
        widget.onVerticalDragEnd?.call();
      },
      child: widget.child,
    );
  }
}
