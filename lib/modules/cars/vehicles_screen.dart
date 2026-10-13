import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/add_vehicle_screen.dart';
import 'package:mvc_app/modules/cars/cars_search_screen.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_providers.dart';
import 'package:mvc_app/modules/cars/vehicle_detail_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/cars/vehicle_search_filters.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CarsVehiclesScreen extends StatefulWidget {
  /// App bar title — the category name when opened from the Market screen.
  /// Without one, the app logo is shown instead.
  final String? title;

  const CarsVehiclesScreen({super.key, this.title});

  @override
  State<CarsVehiclesScreen> createState() => _CarsVehiclesScreenState();
}

class _CarsVehiclesScreenState extends State<CarsVehiclesScreen> {
  /// Results are revealed a page at a time as the user scrolls. Both sources
  /// are already in memory — filtering and sorting run across the two combined
  /// — so a page here is a render window, not a round trip.
  static const int _pageSize = 20;

  /// How close to the end of the list the next page is revealed, so the list
  /// grows before the user actually hits the bottom.
  static const double _loadMoreThreshold = 400;

  String _statusFilter = 'All';
  List<VehicleListing> _listings = [];

  /// [_listings] after the search box, status chip and filter sheet, sorted.
  /// Held in a field rather than recomputed in a getter so that the pass runs
  /// when the criteria change instead of on every rebuild — including the ones
  /// scrolling triggers.
  List<VehicleListing> _matches = [];
  int _visibleCount = _pageSize;
  bool _extending = false;

  bool _loading = true;
  String? _error;

  /// Set when a provider failed but the others still have vehicles to show —
  /// surfaced as a banner instead of an empty error screen.
  String? _notice;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  VehicleSearchFilters _filters = VehicleSearchFilters();

  static const _statuses = ['All', 'New', 'Pre-Owned', 'Certified Pre-Owned'];

  bool get _hasMore => _visibleCount < _matches.length;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyCriteriaChange);
    _scrollCtrl.addListener(_onScroll);
    _loadListings();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Loads every active inventory provider side by side.
  ///
  /// Which providers exist comes from `dealer_sources`, so a vendor can be
  /// added or retired without touching this screen. They are independent: an
  /// outage in one must not blank out the others, so a failure is only fatal
  /// when nothing at all could be loaded.
  Future<void> _loadListings({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    final results = await VehicleProviders.loadAll(forceRefresh: forceRefresh);

    if (!mounted) return;

    final loaded = results.where((r) => !r.failed).toList();
    final failed = results.where((r) => r.failed).toList();

    setState(() {
      // One list, newest first, whoever the car belongs to: dealerships,
      // vendors and people who listed in the app interleave by date.
      _listings = VehicleProviders.mergeNewestFirst(results);
      // A reload is not a change of criteria: someone returning from a detail
      // screen keeps however far down the list they had already scrolled.
      _recomputeMatches(resetPage: false);
      _loading = false;

      if (results.isEmpty) {
        _error = 'No vehicle inventory is configured yet.';
        _notice = null;
      } else if (loaded.isEmpty) {
        // Everything is down, so there is nothing to show behind a banner.
        _error = failed.first.error;
        _notice = null;
      } else {
        _error = null;
        _notice = failed.isEmpty ? null : _partialLoadNotice(failed);
      }
    });
    _prefetchThumbnails();
  }

  /// One provider down is worth naming; several is worth summarising, since the
  /// banner is a single line above a list the user came here to read.
  String _partialLoadNotice(List<ProviderFetch> failed) {
    if (failed.length == 1) {
      return '${failed.first.error} Showing everything else.';
    }
    final names = failed.map((f) => f.provider.displayName).join(', ');
    return 'Could not load $names. Showing everything else.';
  }

  /// Applies the search box, status chip and filter sheet to [_listings].
  ///
  /// [resetPage] drops back to the first page: correct whenever the user
  /// changed what they are looking for, wrong for a background reload of the
  /// same criteria.
  void _recomputeMatches({required bool resetPage}) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final result = _listings.where((v) {
      if (_statusFilter != 'All' && v.status != _statusFilter) return false;
      if (!_filters.matches(v)) return false;
      if (query.isNotEmpty) {
        final haystack = [
          '${v.year}',
          v.make,
          v.model,
          v.trim ?? '',
          v.stock,
          v.color ?? '',
          v.body ?? '',
          v.location ?? '',
          v.description ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
    _filters.sort(result);

    // Cars without photos sink below the ones that have them. Stable, like the
    // partition below, so the chosen sort still holds within each group.
    final withPhotos = <VehicleListing>[];
    final withoutPhotos = <VehicleListing>[];
    for (final listing in result) {
      (listing.images.isEmpty ? withoutPhotos : withPhotos).add(listing);
    }
    result
      ..clear()
      ..addAll(withPhotos)
      ..addAll(withoutPhotos);

    // Sellers get priority placement: whatever the chosen sort, their own
    // listings come first. A stable partition rather than a comparator tweak,
    // so the sort's own order still holds within each half.
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final mine = <VehicleListing>[];
    final others = <VehicleListing>[];
    for (final listing in result) {
      final isMine =
          listing.createdBy != null && listing.createdBy == currentUserId;
      (isMine ? mine : others).add(listing);
    }
    _matches = [...mine, ...others];
    if (resetPage) _visibleCount = _pageSize;
  }

  /// Re-filters after a change to the search, chips or filters, and sends the
  /// user back to the top of a freshly paged result set.
  void _applyCriteriaChange([VoidCallback? change]) {
    setState(() {
      change?.call();
      _recomputeMatches(resetPage: true);
    });
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _prefetchThumbnails();
  }

  /// Pulls the thumbnails for the visible rows plus one page ahead onto disk,
  /// so a page revealed mid-fling paints from the cache instead of popping in.
  /// Photos already cached cost nothing.
  void _prefetchThumbnails() {
    final end = (_visibleCount + _pageSize).clamp(0, _matches.length);
    VehicleImageCache.prefetch(
      _matches.take(end).map((v) => v.firstImageUrl).whereType<String>(),
    );
  }

  void _onScroll() {
    if (_extending || !_hasMore || !_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;

    _extending = true;
    setState(() => _visibleCount += _pageSize);
    // Released once the new rows have been laid out, so that a fling — which
    // fires several scroll events against a not-yet-grown extent — reveals one
    // page rather than several.
    WidgetsBinding.instance.addPostFrameCallback((_) => _extending = false);
    _prefetchThumbnails();
  }

  Future<void> _openFilters() async {
    final updated = await Navigator.of(context).push<VehicleSearchFilters>(
      MaterialPageRoute(
        builder: (_) => CarsSearchScreen(
          initialFilters: _filters,
          listings: _listings,
        ),
      ),
    );
    if (updated != null && mounted) {
      _applyCriteriaChange(() => _filters = updated);
    }
  }

  Future<void> _openAddListing() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
    );
    if (added == true) _loadListings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      // A back button appears on its own when pushed from the Market screen.
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              )
            : Image.asset('assets/logo.png', height: 32),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.accentPrimary,
            iconSize: 28,
            tooltip: 'Add listing',
            onPressed: _openAddListing,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchCtrl,
            filterCount: _filters.activeCount,
            onFiltersTap: _openFilters,
          ),
          if (!_filters.isEmpty)
            _ActiveFiltersBar(
              count: _filters.activeCount,
              onClear: () =>
                  _applyCriteriaChange(() => _filters = VehicleSearchFilters()),
            ),
          _StatusChips(
            statuses: _statuses,
            selected: _statusFilter,
            onChanged: (s) => _applyCriteriaChange(() => _statusFilter = s),
          ),
          if (_notice != null)
            _NoticeBar(
              message: _notice!,
              onRetry: () => _loadListings(forceRefresh: true),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPrimary),
      );
    }
    if (_error != null) {
      return _ErrorState(onRetry: () => _loadListings(forceRefresh: true));
    }
    if (_matches.isEmpty) {
      final hasActiveSearch = _searchCtrl.text.trim().isNotEmpty ||
          !_filters.isEmpty ||
          _statusFilter != 'All';
      if (_listings.isNotEmpty && hasActiveSearch) {
        return _NoResultsState(
          onClear: () {
            // Clearing the field notifies its own listener; the rest of the
            // criteria are reset in one further pass.
            _searchCtrl.clear();
            _applyCriteriaChange(() {
              _filters = VehicleSearchFilters();
              _statusFilter = 'All';
            });
          },
        );
      }
      return _EmptyState(onAdd: _openAddListing);
    }
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final shown = _hasMore ? _visibleCount : _matches.length;
    return RefreshIndicator(
      onRefresh: () => _loadListings(forceRefresh: true),
      color: AppTheme.accentPrimary,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        // One row past the page: the next page arriving, or the end of results.
        itemCount: shown + 1,
        itemBuilder: (_, i) {
          if (i == shown) {
            return _ListFooter(loadingMore: _hasMore, total: _matches.length);
          }
          final listing = _matches[i];
          final isOwner = listing.createdBy != null &&
              listing.createdBy == currentUserId;
          // Sold listings are view-only for everyone except their creator.
          final canOpen = !listing.isSold || isOwner;
          return GestureDetector(
            onTap: canOpen
                ? () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VehicleDetailScreen(listing: listing),
                      ),
                    );
                    _loadListings();
                  }
                : null,
            child: _VehicleCard(listing: listing),
          );
        },
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final int filterCount;
  final VoidCallback onFiltersTap;

  const _SearchBar({
    required this.controller,
    required this.filterCount,
    required this.onFiltersTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey.shade500, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppTheme.black,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by make, model, trim…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: controller.clear,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child:
                      Icon(Icons.close, color: Colors.grey.shade500, size: 18),
                ),
              ),
            GestureDetector(
              onTap: onFiltersTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune,
                      color: AppTheme.accentPrimary, size: 20),
                  if (filterCount > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$filterCount',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
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

class _ActiveFiltersBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;

  const _ActiveFiltersBar({required this.count, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 14, color: AppTheme.accentPrimary),
          const SizedBox(width: 6),
          Text(
            '$count filter${count != 1 ? 's' : ''} applied',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClear,
            child: Text(
              'Clear all',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when one source failed while the other still returned vehicles.
class _NoticeBar extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _NoticeBar({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E5),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: Colors.orange.shade900,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tail of the results list: the next page arriving, or a count confirming the
/// user has reached the end of what matched.
class _ListFooter extends StatelessWidget {
  final bool loadingMore;
  final int total;

  const _ListFooter({required this.loadingMore, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Center(
        child: loadingMore
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentPrimary,
                ),
              )
            : Text(
                total == 1 ? 'Showing 1 vehicle' : 'Showing all $total vehicles',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final VoidCallback onClear;
  const _NoResultsState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No vehicles match your search',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting or clearing your filters',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentPrimary,
              side: const BorderSide(color: AppTheme.accentPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text(
              'Clear search & filters',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  final List<String> statuses;
  final String selected;
  final ValueChanged<String> onChanged;

  const _StatusChips({
    required this.statuses,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: statuses.map((s) {
            final active = selected == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.accentPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active
                          ? AppTheme.accentPrimary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No vehicles listed yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to add your first listing',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'Add Listing',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          const Text(
            'Failed to load listings',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
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
}

class _VehicleCard extends StatelessWidget {
  final VehicleListing listing;
  const _VehicleCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final hasPromo =
        listing.promotion != null && listing.promotion! > 0;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImage(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (listing.isSold) ...[
                      const _SoldListBadge(),
                      const SizedBox(width: 6),
                    ],
                    if (listing.isFromDealerFeed) ...[
                      const _DealerBadge(),
                      const SizedBox(width: 6),
                    ],
                    _StatusBadge(status: listing.status),
                    const Spacer(),
                    if (listing.location != null)
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Text(
                            listing.location!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  listing.displayTitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.black,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    if (listing.color != null)
                      _Detail(listing.color!),
                    if (listing.body != null)
                      _Detail(listing.body!),
                    _Detail(listing.displayMileage),
                    if (listing.fuel != null)
                      _Detail(listing.fuel!),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (hasPromo) ...[
                      Text(
                        listing.displayPrice,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.grey.shade400,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        listing.displayPromoPrice,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentPrimary,
                        ),
                      ),
                    ] else
                      Text(
                        listing.displayPrice,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.black,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      'Stock #${listing.stock}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Sold listings are dimmed so they read as inactive in the list.
    return listing.isSold ? Opacity(opacity: 0.6, child: card) : card;
  }

  Widget _buildImage() {
    final url = listing.firstImageUrl;
    final image = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: url != null
          ? VehicleImage(
              url: url,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              // Cards are at most a screen wide; decoding a full-size dealer
              // photo for a 180px-tall thumbnail is pure memory pressure.
              decodeWidth: 800,
              placeholder: (_) => _placeholder(),
            )
          : _placeholder(),
    );
    if (!listing.isSold) return image;
    return Stack(
      children: [
        image,
        Positioned.fill(
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade600.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'SOLD',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      height: 160,
      width: double.infinity,
      color: const Color(0xFFF0F0F0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 4),
          Text(
            listing.make,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String text;
  const _Detail(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 12,
        color: Colors.grey.shade600,
      ),
    );
  }
}

class _SoldListBadge extends StatelessWidget {
  const _SoldListBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Sold',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.red.shade600,
        ),
      ),
    );
  }
}

/// Marks inventory mirrored from the dealer feed, which behaves differently
/// from community listings (read-only, contact happens on the dealer site).
class _DealerBadge extends StatelessWidget {
  const _DealerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 11, color: Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(
            'Dealer',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isNew = status.toLowerCase() == 'new';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isNew
            ? AppTheme.accentPrimary.withOpacity(0.12)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isNew ? AppTheme.accentPrimary : Colors.blue.shade700,
        ),
      ),
    );
  }
}
