import 'package:flutter/material.dart';

/// Fades and lifts a section into place, each [index] a beat after the one
/// before, so a screen assembles itself top to bottom instead of popping in.
/// One [animation] drives every section on the screen.
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    super.key,
    required this.animation,
    required this.index,
    required this.child,
  });

  /// Sections past this many all arrive together; a long grid would otherwise
  /// keep the last tiles waiting.
  static const int _staggered = 10;

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index.clamp(0, _staggered) * 0.06).clamp(0.0, 0.6);
    final curve = Interval(start, start + 0.4, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final t = curve.transform(animation.value);
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(0, 0.12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
