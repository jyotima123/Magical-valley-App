import 'package:flutter/material.dart';

/// Holds shared [GlobalKey]s used to locate widgets that the app tour
/// highlights. Widgets attach their render objects to these keys so that
/// the tour overlay can compute spotlight positions.
///
/// Usage:
///   - Bottom navigation container: wrap with `KeyedSubtree(key: AppTourService.instance.bottomNavKey, …)`
class AppTourService {
  AppTourService._();
  static final AppTourService instance = AppTourService._();

  /// Key attached to the bottom navigation bar container in [MainScaffold].
  final GlobalKey bottomNavKey = GlobalKey(debugLabel: 'tour_bottom_nav');

  // -------------------------------------------------------------------------
  // Convenience: compute the Rect for a specific nav-bar item index.
  // -------------------------------------------------------------------------

  /// Returns the [Rect] (in global coordinates) of bottom-nav item [itemIndex]
  /// assuming [totalItems] tabs spread evenly across the nav bar.
  Rect? navItemRect(int itemIndex, int totalItems) {
    final ctx = bottomNavKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    final itemW = box.size.width / totalItems;
    return Rect.fromLTWH(
      origin.dx + itemW * itemIndex,
      origin.dy,
      itemW,
      box.size.height,
    );
  }
}
