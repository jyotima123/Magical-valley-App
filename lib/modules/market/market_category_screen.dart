import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/market/add_market_item_screen.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_item_detail_screen.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/pets/petango_api_service.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal_detail_screen.dart';
import 'package:mvc_app/modules/market/pets/pets_list_merge.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal_card.dart';
import 'package:mvc_app/modules/market/pets/shelter_source.dart';
import 'package:mvc_app/modules/market/widgets/fit_toggle_photo.dart';
import 'package:mvc_app/modules/market/widgets/promoted_listings_strip.dart';
import 'package:mvc_app/modules/market/widgets/listing_row_card.dart';
import 'package:mvc_app/modules/market/widgets/market_price_line.dart';

/// Every item listed in one Market category, newest first.
///
/// Unlike the Cars screen, which holds all of its inventory in memory, a
/// category is paged from the server: it has no upper bound, and search runs
/// in the database for the same reason.
///
/// Promoted listings (migration 089) also appear in a strip above the list.
///
/// Pets mixes the shelter's adoptable animals into the list by date. That
/// feed is small and live, so it is held in memory and searched here.
class MarketCategoryScreen extends StatefulWidget {
  final MarketCategory category;
  final MarketRepository? repository;

  const MarketCategoryScreen({
    super.key,
    required this.category,
    this.repository,
  });

  @override
  State<MarketCategoryScreen> createState() => _MarketCategoryScreenState();
}

class _MarketCategoryScreenState extends State<MarketCategoryScreen> {
  static const int _pageSize = 20;

  /// How close to the end of the list the next page is requested, so it
  /// arrives before the user actually hits the bottom.
  static const double _loadMoreThreshold = 400;

  static const Duration _searchDebounce = Duration(milliseconds: 350);

  late final MarketRepository _repo = widget.repository ?? MarketRepository();

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<MarketItem> _items = [];
  String _query = '';

  /// Nothing to show yet: the first load, or a new search.
  bool _loading = true;
  bool _firstPageInFlight = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _loadMoreFailed = false;

  /// Pets only: show each photo whole, letterboxed, instead of cropped.
  bool _showWholePhotos = false;
  String? _error;

  /// Bumped on every first-page load. A response that comes back for an older
  /// generation — the user typed again meanwhile — is dropped rather than
  /// shown under the newer search.
  int _generation = 0;

  final _petango = PetangoApiService();

  /// Null until loaded, and whenever the shelter feed is off.
  ShelterSource? _shelter;
  List<ShelterAnimal> _shelterAnimals = const [];

  List<MarketItem> _promoted = const [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFirstPage();
    _loadPromoted();
    if (widget.category.isPets) _loadShelter();
  }

  /// A failure only leaves the strip out; the list itself is unaffected.
  Future<void> _loadPromoted() async {
    try {
      final promoted = await _repo.fetchPromoted(
        category: widget.category.slug,
      );
      if (!mounted) return;
      setState(() => _promoted = promoted);
      VehicleImageCache.prefetch(
        promoted.map((i) => i.firstImageUrl).whereType<String>(),
      );
    } catch (_) {
      if (mounted) setState(() => _promoted = const []);
    }
  }

  /// Failures leave the animals out and nothing else: the shelter being
  /// unreachable is not a reason to report the community listings as broken.
  Future<void> _loadShelter({bool forceRefresh = false}) async {
    try {
      final shelter = await ShelterSource.load();
      final animals = shelter == null
          ? const <ShelterAnimal>[]
          : await _petango.fetchAnimals(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _shelter = shelter;
        _shelterAnimals = animals;
      });
      VehicleImageCache.prefetch(
        animals.map((a) => a.firstPhotoUrl).whereType<String>(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _shelterAnimals = const []);
    }
  }

  Future<void> _refresh() => Future.wait([
    _loadFirstPage(),
    _loadPromoted(),
    if (widget.category.isPets) _loadShelter(forceRefresh: true),
  ]);

  /// The shelter animals matching the search box, by name, species or breed.
  List<ShelterAnimal> get _visibleShelterAnimals {
    if (_shelter == null) return const [];
    final term = _query.toLowerCase();
    if (term.isEmpty) return _shelterAnimals;
    return _shelterAnimals
        .where(
          (a) => [
            a.name,
            a.species,
            a.breedLabel,
          ].any((field) => field.toLowerCase().contains(term)),
        )
        .toList();
  }

  void _openShelterAnimal(ShelterAnimal animal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ShelterAnimalDetailScreen(animal: animal, service: _petango),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Loads (or reloads) from the top. With rows already on screen — a pull to
  /// refresh — they stay visible until the new page replaces them.
  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    setState(() {
      _firstPageInFlight = true;
      _loading = _items.isEmpty;
      // Any page still arriving belongs to the old generation and will be
      // dropped, so it must not keep blocking the next one.
      _loadingMore = false;
      _loadMoreFailed = false;
      _error = null;
    });

    try {
      final page = await _repo.fetchItems(
        category: widget.category.slug,
        search: _query,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page;
        _hasMore = page.length == _pageSize;
      });
      VehicleImageCache.prefetch(
        page.map((i) => i.firstImageUrl).whereType<String>(),
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (_items.isEmpty) {
        setState(() => _error = '$e');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh listings'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _firstPageInFlight = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    // While the first page is being replaced, `_items.length` is about to
    // change, so an offset taken from it now would skip or repeat rows.
    if (_firstPageInFlight || _loadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });

    try {
      final page = await _repo.fetchItems(
        category: widget.category.slug,
        search: _query,
        offset: _items.length,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        // An item listed since the first page shifts every offset by one, so
        // the boundary row can come back twice.
        final seen = _items.map((i) => i.id).toSet();
        _items = [..._items, ...page.where((i) => !seen.contains(i.id))];
        _hasMore = page.length == _pageSize;
      });
      VehicleImageCache.prefetch(
        page.map((i) => i.firstImageUrl).whereType<String>(),
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadMoreFailed) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  void _onSearchChanged(String _) {
    // Rebuild now so the clear button tracks the field; query after a pause.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      final query = _searchCtrl.text.trim();
      if (query == _query) return;
      _query = query;
      _items = [];
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
      _loadFirstPage();
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearchChanged('');
  }

  Future<void> _openAddListing() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddMarketItemScreen(
          initialCategory: widget.category,
          repository: _repo,
        ),
      ),
    );
    if (added == true) _loadFirstPage();
  }

  Future<void> _openItem(MarketItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketItemDetailScreen(
          item: item,
          category: widget.category,
          repository: _repo,
        ),
      ),
    );
    // It may have been sold or had its promotion changed meanwhile.
    _loadPromoted();
    // Reloading the whole list would throw away how far the user had paged,
    // so refresh just the row they may have edited or marked sold.
    try {
      final fresh = await _repo.fetchItem(item.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final i in _items)
            if (i.id != item.id)
              i
            // Moved to another category while being edited.
            else if (fresh.isInCategory(widget.category.slug))
              fresh,
        ];
      });
    } catch (_) {
      // Keep the row as it was.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
        title: Text(
          widget.category.name,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.black,
          ),
        ),
        actions: [
          if (widget.category.isPets)
            IconButton(
              icon: Icon(
                _showWholePhotos
                    ? Icons.zoom_in_map_rounded
                    : Icons.zoom_out_map_rounded,
              ),
              color: AppTheme.accentPrimary,
              iconSize: 26,
              tooltip: _showWholePhotos ? 'Fill photos' : 'Show whole photos',
              onPressed: () =>
                  setState(() => _showWholePhotos = !_showWholePhotos),
            ),
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
          _SearchField(
            controller: _searchCtrl,
            hint: 'Search ${widget.category.name}…',
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// What the list shows, in order: community items, interleaved with the
  /// shelter's animals in Pets. A failed first page counts as complete, so the
  /// animals still show beside the retry.
  List<Object> get _rows {
    final animals = _visibleShelterAnimals;
    if (animals.isEmpty) return _items;
    return mergePetsList(
      items: _items,
      animals: animals,
      itemsComplete: !_hasMore,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPrimary),
      );
    }
    final rows = _rows;
    // With shelter animals on screen, a community-listing failure is reported
    // in the footer instead of replacing them.
    if (rows.isNotEmpty) return _buildList(rows);
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        iconColor: Colors.red.shade300,
        title: 'Failed to load listings',
        actionLabel: 'Retry',
        onAction: _loadFirstPage,
      );
    }
    if (_query.isNotEmpty) {
      return _MessageState(
        icon: Icons.search_off,
        title: 'Nothing matches "$_query"',
        subtitle: 'Try a different search',
        actionLabel: 'Clear search',
        onAction: _clearSearch,
      );
    }
    return _MessageState(
      icon: widget.category.icon,
      title: 'Nothing listed in ${widget.category.name} yet',
      subtitle: 'Be the first to add one!',
      actionLabel: 'Add Listing',
      onAction: _openAddListing,
      filledAction: true,
    );
  }

  Widget _buildList(List<Object> rows) {
    final currentUserId = _repo.currentUserId;
    // Promoted items are a browse aid; while searching the list itself is
    // the answer.
    final hasStrip = _promoted.isNotEmpty && _query.isEmpty;
    final leading = hasStrip ? 1 : 0;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.accentPrimary,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        // Horizontal padding goes on each row, so the promoted strip can run
        // edge to edge.
        padding: const EdgeInsets.symmetric(vertical: 16),
        // The strip, then the rows, then one row for the next page arriving
        // or the end.
        itemCount: leading + rows.length + 1,
        itemBuilder: (_, i) {
          if (hasStrip && i == 0) {
            return PromotedListingsStrip(items: _promoted, onOpen: _openItem);
          }
          final index = i - leading;
          final Widget row;
          if (index == rows.length) {
            row = _buildFooter(rows.length);
          } else {
            row = switch (rows[index]) {
              final ShelterAnimal animal => GestureDetector(
                onTap: () => _openShelterAnimal(animal),
                child: ShelterAnimalCard(
                  animal: animal,
                  shelterName: _shelter!.displayName,
                  showWholePhoto: _showWholePhotos,
                ),
              ),
              final MarketItem item => GestureDetector(
                // Sold items are view-only for everyone except their seller.
                onTap: !item.isSold || item.isOwnedBy(currentUserId)
                    ? () => _openItem(item)
                    : null,
                child: MarketItemCard(
                  item: item,
                  showWholePhoto: _showWholePhotos,
                ),
              ),
              _ => const SizedBox.shrink(),
            };
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: row,
          );
        },
      ),
    );
  }

  Widget _buildFooter(int shown) {
    final Widget child;
    if (_error != null) {
      child = TextButton(
        onPressed: _loadFirstPage,
        child: const Text(
          "Couldn't load listings. Tap to retry",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: AppTheme.accentPrimary,
          ),
        ),
      );
    } else if (_loadMoreFailed) {
      child = TextButton(
        onPressed: _loadMore,
        child: const Text(
          "Couldn't load more. Tap to retry",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: AppTheme.accentPrimary,
          ),
        ),
      );
    } else if (_hasMore) {
      child = const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.accentPrimary,
        ),
      );
    } else {
      child = Text(
        shown == 1 ? 'Showing 1 listing' : 'Showing all $shown listings',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: Colors.grey.shade500,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Center(child: child),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppTheme.black,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, color: Colors.grey.shade500, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// Empty, no-results and error states: an icon, a line or two, one action.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool filledAction;

  const _MessageState({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.filledAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonText = TextStyle(
      fontFamily: 'Poppins',
      fontWeight: FontWeight.w600,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: iconColor ?? Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (filledAction)
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionLabel, style: buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              )
            else
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentPrimary,
                  side: const BorderSide(color: AppTheme.accentPrimary),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                ),
                child: Text(actionLabel, style: buttonText),
              ),
          ],
        ),
      ),
    );
  }
}

/// One item in a category list. Sold items stay in the list, dimmed and
/// stamped, as on the Cars screen.
class MarketItemCard extends StatelessWidget {
  final MarketItem item;

  /// Show the whole photo (zoomed out) instead of cropping it to the width.
  final bool showWholePhoto;
  const MarketItemCard({
    super.key,
    required this.item,
    this.showWholePhoto = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasTags =
        item.isSold || item.isPromoted || item.conditionLabel != null;
    final card = ListingRowCard(
      thumbnail: _buildImage(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTags) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (item.isPromoted && !item.isSold)
                  _Tag(
                    'Promoted',
                    background: AppTheme.accentPrimary.withValues(alpha: 0.14),
                    foreground: AppTheme.accentPrimary,
                  ),
                if (item.isSold)
                  _Tag(
                    'Sold',
                    background: Colors.red.withValues(alpha: 0.12),
                    foreground: Colors.red.shade600,
                  ),
                if (item.conditionLabel != null)
                  _Tag(
                    item.conditionLabel!,
                    background: Colors.blue.withValues(alpha: 0.1),
                    foreground: Colors.blue.shade700,
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MarketPriceLine(item: item),
          ),
          if (item.location != null) ...[
            const SizedBox(height: 4),
            ListingLocationLine(item.location!),
          ],
        ],
      ),
    );

    // Sold items are dimmed so they read as inactive in the list.
    return item.isSold ? Opacity(opacity: 0.6, child: card) : card;
  }

  Widget _buildImage() {
    final url = item.firstImageUrl;
    final image = url != null
        ? FitTogglePhoto(
            url: url,
            height: kListingThumbSize,
            showWhole: showWholePhoto,
            decodeWidth: 400,
            coverAlignment: item.isInCategory(kPetsCategory)
                ? Alignment.topCenter
                : Alignment.center,
            placeholder: (_) => _placeholder(),
          )
        : _placeholder();
    return item.isSold ? SoldThumbStamp(child: image) : image;
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      alignment: Alignment.center,
      child: Icon(
        MarketCategory.iconFor(item.category),
        size: 40,
        color: Colors.grey.shade300,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Tag(this.label, {required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
