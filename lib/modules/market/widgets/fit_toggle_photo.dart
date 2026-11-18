import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';

/// A card photo that can switch between filling its box (cropped, the default)
/// and showing the whole picture (fit to the height) over a blurred, enlarged,
/// semi-transparent copy of itself.
///
/// Both modes read the same cached file, so toggling costs no download. The
/// switch cross-fades rather than tweening the fit, because [BoxFit] itself
/// is not animatable and the picture's size is unknown until it decodes.
class FitTogglePhoto extends StatelessWidget {
  const FitTogglePhoto({
    super.key,
    required this.url,
    required this.showWhole,
    required this.height,
    this.coverAlignment = Alignment.center,
    this.decodeWidth = 800,
    this.placeholder,
  });

  final String url;

  /// True shows the whole photo; false fills the box and crops.
  final bool showWhole;
  final double height;

  /// Which part survives the crop in the filled mode.
  final Alignment coverAlignment;
  final int? decodeWidth;
  final WidgetBuilder? placeholder;

  static const Duration duration = Duration(milliseconds: 280);
  static const Color backdrop = Color(0xFFE4E4E4);

  /// The backdrop copy: how far it is enlarged, blurred and faded.
  static const double _backdropScale = 1.6;
  static const double _backdropBlur = 22;
  static const double _backdropOpacity = 0.55;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOut,
      height: height,
      width: double.infinity,
      color: showWhole ? backdrop : Colors.transparent,
      // The enlarged, blurred copy bleeds past the box, so trim it.
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Built only while zoomed out, so the list pays for the blur only
          // when it is on screen.
          AnimatedSwitcher(
            duration: duration,
            child: showWhole
                ? _blurredBackdrop()
                : const SizedBox.expand(key: ValueKey('no-backdrop')),
          ),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: VehicleImage(
              // The key is what makes the switcher cross-fade between modes.
              key: ValueKey(showWhole),
              url: url,
              height: height,
              width: double.infinity,
              fit: showWhole ? BoxFit.contain : BoxFit.cover,
              alignment: showWhole ? Alignment.center : coverAlignment,
              decodeWidth: decodeWidth,
              placeholder: placeholder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurredBackdrop() {
    return ImageFiltered(
      key: const ValueKey('backdrop'),
      imageFilter: ImageFilter.blur(
        sigmaX: _backdropBlur,
        sigmaY: _backdropBlur,
        tileMode: TileMode.mirror,
      ),
      child: Transform.scale(
        scale: _backdropScale,
        child: Opacity(
          opacity: _backdropOpacity,
          child: VehicleImage(
            url: url,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            alignment: coverAlignment,
            // It is blurred beyond recognition, so a small decode is plenty.
            decodeWidth: 160,
            placeholder: (_) => const SizedBox.shrink(),
            errorWidget: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
