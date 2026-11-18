import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/widgets/hero_carousel.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';

/// The Cars category, as the one entry that is not a tile in the grid: a
/// full-width hero showing the newest cars one at a time.
///
/// The rotation itself is a [HeroCarousel]; a tap anywhere opens the Cars
/// screen. It is a window onto the Cars screen, not a second way to browse.
class CarsCarouselCard extends StatefulWidget {
  const CarsCarouselCard({
    super.key,
    required this.name,
    required this.cars,
    required this.onTap,
    this.loading = false,
  });

  /// The category's name as the database spells it, so renaming it again stays
  /// a row change rather than a release.
  final String name;

  /// Newest first. Cars without a photo belong to the caller to filter out: a
  /// grey hero is worse than a shorter rotation.
  final List<VehicleListing> cars;

  final VoidCallback onTap;

  /// Inventory is still loading, so the hero shimmers. Keeping the space
  /// reserved stops the screen jumping under the user's thumb when the photos
  /// arrive.
  final bool loading;

  /// Height of the hero; fixed, so loading, empty and full all take the same
  /// room.
  static const double height = 236;

  @override
  State<CarsCarouselCard> createState() => _CarsCarouselCardState();
}

class _CarsCarouselCardState extends State<CarsCarouselCard> {
  static const double _radius = 22;

  bool get _hasCars => widget.cars.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_hasCars) {
      body = _buildRotation();
    } else if (widget.loading) {
      body = const ShimmerBox(borderRadius: _radius);
    } else {
      body = _buildEmpty();
    }

    return PressableScale(
      onTap: widget.onTap,
      pressedScale: 0.98,
      semanticLabel: widget.name,
      child: Container(
        height: CarsCarouselCard.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: KeyedSubtree(
              key: ValueKey(_hasCars ? 'cars' : widget.loading),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRotation() {
    return HeroCarousel(
      itemCount: widget.cars.length,
      topBar: _buildTopBar(),
      photoBuilder: (_, index) {
        final url = widget.cars[index].firstImageUrl;
        if (url == null) return const SizedBox.expand();
        return VehicleImage(
          url: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          // Full card width on a large phone, without a dealer's full-size
          // photo decoded into memory.
          decodeWidth: 1080,
        );
      },
      captionBuilder: (_, index) => _buildCaption(widget.cars[index]),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        GlassPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_car, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                widget.name,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        const GlassPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 2),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaption(VehicleListing car) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'NEW ARRIVAL',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          car.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.accentPrimary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            car.displayPrice,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// No inventory to show — none listed, or it failed to load. The card still
  /// leads to the Cars screen, which reports its own errors.
  Widget _buildEmpty() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          MarketCategory.photoFor(kCarsCategory),
          fit: BoxFit.cover,
          cacheWidth: 1080,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x40000000), Color(0xCC000000)],
            ),
          ),
        ),
        Positioned(top: 14, left: 14, right: 14, child: _buildTopBar()),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Text(
            'Every dealership’s inventory, in one place',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ),
      ],
    );
  }
}
