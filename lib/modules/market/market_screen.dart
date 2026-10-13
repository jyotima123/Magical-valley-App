import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/add_vehicle_screen.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_providers.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/cars/vehicles_screen.dart';
import 'package:mvc_app/modules/market/add_market_item_screen.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_category_screen.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/my_listings_screen.dart';
import 'package:mvc_app/modules/market/widgets/cars_carousel_card.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';
import 'package:mvc_app/services/first_run_service.dart';

/// Root of the Market tab: Cars as a card of its own, with the newest inventory
/// rolling across it, then one tile per remaining category. Cars opens the Cars
/// screen with its dealer feeds and car filters; every other category opens a
/// [MarketCategoryScreen].
class MarketScreen extends StatefulWidget {
  final MarketRepository? repository;

  /// The cars the Cars card rolls through, newest first. Defaults to every
  /// provider's inventory; injectable so a test needs no provider fan-out.
  final Future<List<VehicleListing>> Function()? carsLoader;

  const MarketScreen({super.key, this.repository, this.carsLoader});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  /// How many cars the strip on the Cars card rolls through before repeating.
  static const int _carouselCars = 12;

  late final MarketRepository _repo = widget.repository ?? MarketRepository();

  List<MarketCategory> _categories = [];
  bool _loading = true;
  bool _failed = false;

  List<VehicleListing> _cars = [];
  bool _loadingCars = true;

  /// Plays once, the first time the categories arrive: the heading, the Cars
  /// card and the tiles rise into place one after another. Created in
  /// [initState], not lazily, so a screen that never loaded does not create
  /// its ticker inside [dispose].
  late final AnimationController _entrance;

  /// Cars is the one category not backed by `market_items`, and the one shown
  /// as a full-width card rather than a tile in the grid.
  MarketCategory? get _carsCategory {
    for (final category in _categories) {
      if (category.isCars) return category;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadCategories();
    _loadCars();
    // The Market tab is built the first time its icon is tapped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirstRunService.instance.maybeShowHint(
        context,
        key: FirstRunHintKeys.market,
        icon: Icons.storefront,
      );
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loading = _categories.isEmpty;
      _failed = false;
    });
    try {
      final categories = await _repo.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
      if (_entrance.isDismissed) _entrance.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _categories.isEmpty;
      });
    }
  }

  /// Pull to refresh takes in the whole screen: the categories and the cars
  /// rolling past on the Cars card.
  Future<void> _refresh() => (_loadCategories(), _loadCars()).wait;

  /// The Cars card is a window onto the Cars screen, so a failure to load
  /// inventory costs the strip and nothing else: the card still opens the list,
  /// which reports its own errors.
  Future<void> _loadCars() async {
    try {
      final cars = await (widget.carsLoader ?? _loadNewestCars)();
      if (!mounted) return;
      setState(() {
        _cars = cars;
        _loadingCars = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCars = false);
    }
  }

  /// The head of the list the Cars screen shows, cut to what a card can hold:
  /// every provider's inventory merged newest first, still for sale, and only
  /// cars with a photo to show.
  static Future<List<VehicleListing>> _loadNewestCars() async {
    final results = await VehicleProviders.loadAll();
    return VehicleProviders.mergeNewestFirst(results)
        .where((car) => !car.isSold && car.firstImageUrl != null)
        .take(_carouselCars)
        .toList();
  }

  void _openCategory(MarketCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => category.isCars
            ? CarsVehiclesScreen(title: category.name)
            : MarketCategoryScreen(category: category, repository: _repo),
      ),
    );
  }

  /// "What are you listing?" — then the form for that category, then the
  /// category itself, so the seller sees their new listing in place.
  Future<void> _openAddListing() async {
    final category = await showModalBottomSheet<MarketCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _CategoryPickerSheet(categories: _categories),
    );
    if (category == null || !mounted) return;

    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => category.isCars
            ? const AddVehicleScreen()
            : AddMarketItemScreen(initialCategory: category, repository: _repo),
      ),
    );
    if (added == true && mounted) _openCategory(category);
  }

  void _openMyListings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MyListingsScreen(repository: _repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: AppTheme.black,
        elevation: 0,
        title: Image.asset('assets/logo.png', height: 32),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.accentPrimary,
            iconSize: 28,
            tooltip: 'Add listing',
            onPressed: _categories.isEmpty ? null : _openAddListing,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'my_listings') _openMyListings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'my_listings',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('My Listings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: KeyedSubtree(
          key: ValueKey(_loading ? 'loading' : (_failed ? 'failed' : 'ready')),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _MarketSkeleton();
    if (_failed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            const Text(
              'Failed to load the Market',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: AppTheme.black,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadCategories,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: AppTheme.accentPrimary,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final cars = _carsCategory;
    final tiled = _categories.where((c) => !c.isCars).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.accentPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _Entrance(
                animation: _entrance,
                index: 0,
                child: const _Heading(),
              ),
            ),
          ),
          if (cars != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _Entrance(
                  animation: _entrance,
                  index: 1,
                  child: CarsCarouselCard(
                    name: cars.name,
                    cars: _cars,
                    loading: _loadingCars,
                    onTap: () => _openCategory(cars),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 2),
            sliver: SliverToBoxAdapter(
              child: _Entrance(
                animation: _entrance,
                index: 2,
                child: const Text(
                  'Browse categories',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.black,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.92,
              ),
              // Cars has its own card above, so the grid is everything else.
              itemCount: tiled.length,
              itemBuilder: (_, i) => _Entrance(
                animation: _entrance,
                index: 3 + i,
                child: _CategoryTile(
                  category: tiled[i],
                  onTap: () => _openCategory(tiled[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warm off-white, so the photo cards and their shadows have something to sit
/// on without the starkness of pure white.
const Color _background = Color(0xFFF7F5F3);

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppTheme.black,
            ),
            children: [
              TextSpan(
                text: 'Magic ',
                style: TextStyle(color: AppTheme.accentPrimary),
              ),
              TextSpan(text: 'Market'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Buy and sell with your neighbors',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

/// Fades and lifts a section into place, each [index] a beat after the one
/// before, so the screen assembles itself top to bottom instead of popping in.
class _Entrance extends StatelessWidget {
  const _Entrance({
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

/// A category as a photo card, the way a bookstore shelves its genres: the
/// picture says what is inside before the name does.
class _CategoryTile extends StatelessWidget {
  final MarketCategory category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: category.name,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFFDDD8D3),
                child: Image.asset(
                  category.photo,
                  fit: BoxFit.cover,
                  // Tiles are at most 220pt wide; no need to decode more.
                  cacheWidth: 600,
                  // Fades in rather than snapping, on the rare frame the
                  // bundled photo is not decoded yet.
                  frameBuilder: (_, child, frame, sync) => sync
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 300),
                          child: child,
                        ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x14000000),
                      Color(0x00000000),
                      Color(0xB3000000),
                    ],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(category.icon, color: Colors.white, size: 18),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Color(0x66000000), blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screen's shape in shimmering placeholders, shown while the categories
/// load so the real thing lands where the eye already is.
class _MarketSkeleton extends StatelessWidget {
  const _MarketSkeleton();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 200, height: 30, borderRadius: 8),
                SizedBox(height: 10),
                ShimmerBox(width: 230, height: 14, borderRadius: 6),
              ],
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverToBoxAdapter(
            child: ShimmerBox(
              height: CarsCarouselCard.height,
              borderRadius: 22,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 30, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShimmerBox(width: 170, height: 20, borderRadius: 6),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.92,
            ),
            itemCount: 4,
            itemBuilder: (_, __) => const ShimmerBox(borderRadius: 18),
          ),
        ),
      ],
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  final List<MarketCategory> categories;

  const _CategoryPickerSheet({required this.categories});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'What are you listing?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in categories)
                    ListTile(
                      leading: Icon(
                        category.icon,
                        color: AppTheme.accentPrimary,
                      ),
                      title: Text(
                        category.name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(category),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
