import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';

/// The Cars category, as the one entry that is not a tile in the grid: a
/// full-width hero showing the newest cars one at a time.
///
/// Each car holds the stage for [_dwell] while its photo drifts slowly closer,
/// then the next one slides in. A swipe moves through them by hand and holds
/// the timer until the finger lifts; a tap anywhere opens the Cars screen. It
/// is a window onto the Cars screen, not a second way to browse.
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

class _CarsCarouselCardState extends State<CarsCarouselCard>
    with SingleTickerProviderStateMixin {
  /// How long each car is shown before the next slides in: long enough to read
  /// the title and price, short enough that the card still feels alive.
  static const Duration _dwell = Duration(milliseconds: 5000);
  static const Duration _slide = Duration(milliseconds: 750);

  /// How much closer each photo drifts while it is on stage.
  static const double _zoom = 0.08;

  static const double _radius = 22;

  /// Runs 0→1 over each car's turn. It times the advance, drives the zoom and
  /// fills the active dot, so all three always agree. Being a ticker, it is
  /// muted with the rest of the Market tab when the tab is hidden.
  ///
  /// Created in [initState] rather than lazily: a card that never had cars to
  /// show would otherwise create its ticker inside [dispose], where looking up
  /// TickerMode is no longer allowed.
  late final AnimationController _turn;

  final PageController _pages = PageController();

  /// Index into the endless PageView; the car is `cars[_page % length]`.
  int _page = 0;
  bool _dragging = false;

  bool get _hasCars => widget.cars.isNotEmpty;

  /// One car has nowhere to go, so it stays and only drifts.
  bool get _rotates => widget.cars.length > 1;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: _dwell)
      ..addStatusListener(_onTurnStatus);
    if (_hasCars) _turn.forward();
  }

  @override
  void didUpdateWidget(CarsCarouselCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Inventory arrives after the first build, and a failed reload can take it
    // away again.
    if (_hasCars && !_turn.isAnimating && !_dragging) {
      _turn.forward(from: 0);
    } else if (!_hasCars) {
      _turn.stop();
    }
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (!_rotates || !_pages.hasClients) {
      _turn.forward(from: 0);
      return;
    }
    _pages.nextPage(duration: _slide, curve: Curves.easeInOutCubic);
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    if (!_dragging) _turn.forward(from: 0);
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging = true;
      _turn.stop();
    } else if (n is ScrollEndNotification && _dragging) {
      _dragging = false;
      _turn.forward(from: 0);
    }
    return false;
  }

  @override
  void dispose() {
    _turn.dispose();
    _pages.dispose();
    super.dispose();
  }

  VehicleListing get _current => widget.cars[_page % widget.cars.length];

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
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: _onPageChanged,
            // Builds the next car's page ahead of time, so its photo is decoded
            // before it slides in rather than popping in halfway.
            allowImplicitScrolling: true,
            physics: _rotates
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            // No itemCount: the rotation runs on, coming back round to the
            // newest car each time it runs out.
            itemBuilder: (_, index) => _buildPhoto(index),
          ),
        ),
        // Shade at both ends so the white text holds up over a pale car.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x73000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.32, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: IgnorePointer(child: _buildTopBar()),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 16,
          child: IgnorePointer(child: _buildCaption()),
        ),
      ],
    );
  }

  /// One car's photo, drifting closer while it is on stage and sliding at a
  /// slower pace than the page itself, which reads as depth.
  Widget _buildPhoto(int index) {
    final url = widget.cars[index % widget.cars.length].firstImageUrl;
    return ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([_turn, _pages]),
        builder: (context, child) {
          // The car on stage zooms with the clock; the one leaving keeps the
          // zoom it reached, so nothing snaps back as it slides out.
          final double zoom;
          if (index == _page) {
            zoom = 1 + _zoom * Curves.easeOut.transform(_turn.value);
          } else {
            zoom = index < _page ? 1 + _zoom : 1;
          }
          var offset = 0.0;
          if (_pages.hasClients && _pages.position.haveDimensions) {
            final page = _pages.page ?? _page.toDouble();
            offset = (page - index) * _pages.position.viewportDimension * 0.35;
          }
          return Transform.translate(
            offset: Offset(offset, 0),
            child: Transform.scale(scale: zoom, child: child),
          );
        },
        child: ColoredBox(
          color: const Color(0xFF2A2A2A),
          child: url == null
              ? null
              : VehicleImage(
                  url: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  // Full card width on a large phone, without a dealer's
                  // full-size photo decoded into memory.
                  decodeWidth: 1080,
                ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _GlassPill(
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
        const _GlassPill(
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

  Widget _buildCaption() {
    final car = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The words change in place while the photo slides, a beat behind it.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomLeft,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Column(
            key: ValueKey(_page),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          ),
        ),
        if (_rotates) ...[
          const SizedBox(height: 14),
          _ProgressDots(
            count: widget.cars.length,
            active: _page % widget.cars.length,
            progress: _turn,
          ),
        ],
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

/// A frosted pill for labels laid over the photo.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: child,
    );
  }
}

/// One dot per car; the current one stretches into a bar that fills as its
/// turn runs out, so the user can see the next car coming.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.count,
    required this.active,
    required this.progress,
  });

  static const double _dot = 6;
  static const double _bar = 22;

  final int count;
  final int active;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            width: i == active ? _bar : _dot,
            height: _dot,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(_dot),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: i == active
                ? AnimatedBuilder(
                    animation: progress,
                    builder: (_, __) => FractionallySizedBox(
                      widthFactor: progress.value,
                      heightFactor: 1,
                      child: const ColoredBox(color: Colors.white),
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}
