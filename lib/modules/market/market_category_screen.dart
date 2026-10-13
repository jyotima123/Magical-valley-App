import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/market/add_market_item_screen.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_item_detail_screen.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/widgets/market_price_line.dart';

/// Every item listed in one Market category, newest first.
///
/// Unlike the Cars screen, which holds all of its inventory in memory, a
/// category is paged from the server: it has no upper bound, and search runs
/// in the database for the same reason.
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
  String? _error;

  /// Bumped on every first-page load. A response that comes back for an older
  /// generation — the user typed again meanwhile — is dropped rather than
  /// shown under the newer search.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFirstPage();
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPrimary),
      );
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        iconColor: Colors.red.shade300,
        title: 'Failed to load listings',
        actionLabel: 'Retry',
        onAction: _loadFirstPage,
      );
    }
    if (_items.isEmpty) {
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

    final currentUserId = _repo.currentUserId;
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      color: AppTheme.accentPrimary,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        // One row past the items: the next page arriving, or the end.
        itemCount: _items.length + 1,
        itemBuilder: (_, i) {
          if (i == _items.length) return _buildFooter();
          final item = _items[i];
          // Sold items are view-only for everyone except their seller.
          final canOpen = !item.isSold || item.isOwnedBy(currentUserId);
          return GestureDetector(
            onTap: canOpen ? () => _openItem(item) : null,
            child: MarketItemCard(item: item),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final Widget child;
    if (_loadMoreFailed) {
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
        _items.length == 1
            ? 'Showing 1 listing'
            : 'Showing all ${_items.length} listings',
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
  const MarketItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
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
                if (item.isSold ||
                    item.conditionLabel != null ||
                    item.location != null) ...[
                  Row(
                    children: [
                      if (item.isSold) ...[
                        _Tag(
                          'Sold',
                          background: Colors.red.withValues(alpha: 0.12),
                          foreground: Colors.red.shade600,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (item.conditionLabel != null)
                        _Tag(
                          item.conditionLabel!,
                          background: Colors.blue.withValues(alpha: 0.1),
                          foreground: Colors.blue.shade700,
                        ),
                      const Spacer(),
                      if (item.location != null)
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  item.location!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.black,
                  ),
                ),
                const SizedBox(height: 8),
                MarketPriceLine(item: item),
              ],
            ),
          ),
        ],
      ),
    );

    // Sold items are dimmed so they read as inactive in the list.
    return item.isSold ? Opacity(opacity: 0.6, child: card) : card;
  }

  Widget _buildImage() {
    final url = item.firstImageUrl;
    final image = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: url != null
          ? VehicleImage(
              url: url,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              // A card is at most a screen wide; no need to decode more.
              decodeWidth: 800,
              placeholder: (_) => _placeholder(),
            )
          : _placeholder(),
    );
    if (!item.isSold) return image;
    return Stack(
      children: [
        image,
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade600.withValues(alpha: 0.9),
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
      child: Icon(
        MarketCategory.iconFor(item.category),
        size: 48,
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
