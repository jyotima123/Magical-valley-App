// lib/testability/screen_state.dart
// Data models for the testability server. Only used in debug/profile builds.
import 'dart:convert';

/// Screen-space bounding box of a UI element.
class ElementBounds {
  final double x1, y1, x2, y2;

  const ElementBounds({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  double get centerX => (x1 + x2) / 2;
  double get centerY => (y1 + y2) / 2;

  Map<String, dynamic> toJson() => {
        'x1': x1.round(),
        'y1': y1.round(),
        'x2': x2.round(),
        'y2': y2.round(),
        'cx': centerX.round(),
        'cy': centerY.round(),
      };
}

/// A single interactive or informational element visible on screen.
class ScreenElement {
  final String id;
  final String label;

  /// 'button' | 'text_field' | 'text' | 'tab' | 'list_item'
  final String type;
  final bool enabled;
  final bool visible;
  final ElementBounds? bounds;

  /// Extra key/value pairs specific to this element (e.g. {'value': 'foo@bar.com'}).
  final Map<String, dynamic>? extra;

  const ScreenElement({
    required this.id,
    required this.label,
    required this.type,
    this.enabled = true,
    this.visible = true,
    this.bounds,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        'enabled': enabled,
        'visible': visible,
        if (bounds != null) 'bounds': bounds!.toJson(),
        if (extra != null) ...extra!,
      };
}

/// Full snapshot of the current screen, pushed by each screen into
/// [ScreenStateRegistry] after every meaningful state change.
class ScreenState {
  final String screen;
  final String subState;
  final List<ScreenElement> elements;
  final Map<String, dynamic> metadata;

  const ScreenState({
    required this.screen,
    required this.subState,
    this.elements = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'screen': screen,
        'sub_state': subState,
        'elements': elements.map((e) => e.toJson()).toList(),
        'metadata': metadata,
      };

  String toJsonString() => jsonEncode(toJson());
}
