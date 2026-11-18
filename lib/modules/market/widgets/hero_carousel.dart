import 'package:flutter/material.dart';

/// The rolling hero shared by the Market's Cars card and a channel's profile:
/// one photo at a time, each holding the stage for [dwell] while it drifts
/// slowly closer, then the next one slides in.
///
/// A swipe moves through them by hand and holds the timer until the finger
/// lifts. The carousel only fills the space it is given; the card around it
/// (shape, shadow, what a tap does) belongs to the caller.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.itemCount,
    required this.photoBuilder,
    required this.captionBuilder,
    this.topBar,
    this.onIndexChanged,
    this.dwell = const Duration(milliseconds: 5000),
  }) : assert(itemCount > 0);

  /// How many photos the rotation runs through before coming back round.
  final int itemCount;

  /// The photo for item [index], in `[0, itemCount)`. It is laid out to fill
  /// the card and should cover it.
  final Widget Function(BuildContext context, int index) photoBuilder;

  /// The words over the bottom of the photo for item [index]. They change in
  /// place, a beat behind the photo, as it slides.
  final Widget Function(BuildContext context, int index) captionBuilder;

  /// Labels pinned over the top of the photo, the same for every item.
  final Widget? topBar;

  /// Told the item on stage each time it changes, so a tap can open the photo
  /// the user is looking at.
  final ValueChanged<int>? onIndexChanged;

  /// How long each item is shown before the next slides in: long enough to
  /// read the caption, short enough that the card still feels alive.
  final Duration dwell;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with SingleTickerProviderStateMixin {
  static const Duration _slide = Duration(milliseconds: 750);

  /// How much closer each photo drifts while it is on stage.
  static const double _zoom = 0.08;

  /// Runs 0→1 over each item's turn. It times the advance, drives the zoom and
  /// fills the active dot, so all three always agree. Being a ticker, it is
  /// muted with the rest of the screen when the screen is hidden.
  late final AnimationController _turn;

  final PageController _pages = PageController();

  /// Index into the endless PageView; the item is `_page % itemCount`.
  int _page = 0;
  bool _dragging = false;

  /// One item has nowhere to go, so it stays and only drifts.
  bool get _rotates => widget.itemCount > 1;

  int get _index => _page % widget.itemCount;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: widget.dwell)
      ..addStatusListener(_onTurnStatus)
      ..forward();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload can change what there is to show; keep the clock running.
    if (!_turn.isAnimating && !_dragging) _turn.forward(from: 0);
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
    widget.onIndexChanged?.call(_index);
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: _onPageChanged,
            // Builds the next page ahead of time, so its photo is decoded
            // before it slides in rather than popping in halfway.
            allowImplicitScrolling: true,
            physics: _rotates
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            // No itemCount: the rotation runs on, coming back round to the
            // first item each time it runs out.
            itemBuilder: (context, index) => _buildPhoto(context, index),
          ),
        ),
        // Shade at both ends so the white text holds up over a pale photo.
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
        if (widget.topBar != null)
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: IgnorePointer(child: widget.topBar!),
          ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 16,
          child: IgnorePointer(child: _buildCaption(context)),
        ),
      ],
    );
  }

  /// One photo, drifting closer while it is on stage and sliding at a slower
  /// pace than the page itself, which reads as depth.
  Widget _buildPhoto(BuildContext context, int index) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([_turn, _pages]),
        builder: (context, child) {
          // The photo on stage zooms with the clock; the one leaving keeps the
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
          child: widget.photoBuilder(context, index % widget.itemCount),
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
          child: KeyedSubtree(
            key: ValueKey(_page),
            child: widget.captionBuilder(context, _index),
          ),
        ),
        if (_rotates) ...[
          const SizedBox(height: 14),
          _ProgressDots(
            count: widget.itemCount,
            active: _index,
            progress: _turn,
          ),
        ],
      ],
    );
  }
}

/// A frosted pill for labels laid over a photo.
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child});

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

/// One dot per item; the current one stretches into a bar that fills as its
/// turn runs out, so the user can see the next one coming.
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

  /// Past this many, a row of dots no longer fits a phone; a counter does.
  static const int _maxDots = 12;

  @override
  Widget build(BuildContext context) {
    if (count > _maxDots) {
      return Row(
        children: [
          Container(
            width: _bar * 2,
            height: _dot,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(_dot),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: progress,
              builder: (_, __) => FractionallySizedBox(
                widthFactor: progress.value,
                heightFactor: 1,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${active + 1} / $count',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      );
    }
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
