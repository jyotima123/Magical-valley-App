import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/add_vehicle_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_detail_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/add_market_item_screen.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_item_detail_screen.dart';
import 'package:mvc_app/modules/market/market_repository.dart';

/// Everything the signed-in user has listed in the Market — their cars and
/// their items in every other category, sold ones included — each one a tap
/// away from being edited or marked sold.
///
/// Dealer inventory never appears: it belongs to the dealership, arrives from
/// its feed, and has no author in the app.
class MyListingsScreen extends StatefulWidget {
  final MarketRepository? repository;

  const MyListingsScreen({super.key, this.repository});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late final MarketRepository _repo = widget.repository ?? MarketRepository();

  List<_MyListing> _listings = [];
  Map<String, MarketCategory> _categories = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _repo.currentUserId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to see your listings';
      });
      return;
    }

    setState(() {
      _loading = _listings.isEmpty;
      _error = null;
    });

    try {
      final (items, vehicles, categories) = await (
        _repo.fetchItemsBy(userId),
        _repo.fetchVehiclesBy(userId),
        // Only for display names; the list is still usable without them.
        _repo.fetchCategories().catchError((_) => <MarketCategory>[]),
      ).wait;
      if (!mounted) return;

      setState(() {
        _categories = {for (final c in categories) c.slug: c};
        _listings = [
          for (final v in vehicles) _MyListing.vehicle(v),
          for (final i in items) _MyListing.item(i),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_listings.isEmpty) _error = 'Failed to load your listings';
      });
    }
  }

  /// A category's display name, falling back to its slug if the category
  /// list could not be loaded (or the category has since been hidden).
  MarketCategory _categoryOf(_MyListing listing) =>
      _categories[listing.category] ??
      MarketCategory(
        slug: listing.category,
        name: listing.isVehicle ? 'Cars & Trucks' : listing.category,
      );

  Future<void> _open(_MyListing listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => listing.vehicle != null
            ? VehicleDetailScreen(listing: listing.vehicle!)
            : MarketItemDetailScreen(
                item: listing.item!,
                category: _categoryOf(listing),
                repository: _repo,
              ),
      ),
    );
    _load();
  }

  Future<void> _edit(_MyListing listing) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => listing.vehicle != null
            ? AddVehicleScreen(existing: listing.vehicle)
            : AddMarketItemScreen(
                existing: listing.item,
                initialCategory: _categoryOf(listing),
                repository: _repo,
              ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleSold(_MyListing listing) async {
    final markingSold = !listing.isSold;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          markingSold ? 'Mark as Sold?' : 'Mark as Available?',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          markingSold
              ? 'The listing will show as Sold and buyers will no longer be able to contact you about it.'
              : 'The listing will become active again and buyers will be able to contact you.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text(markingSold ? 'Mark as Sold' : 'Mark as Available'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (listing.vehicle != null) {
        await _repo.setVehicleSold(listing.id, sold: markingSold);
      } else {
        await _repo.setSold(listing.id, sold: markingSold);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Vehicle listings only for now — deleting a Market item isn't part of
  /// this pass.
  Future<void> _delete(_MyListing listing) async {
    if (listing.vehicle == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete this listing?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'This removes the listing for everyone. Buyers who already '
          'messaged you will keep their conversation.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.deleteVehicle(listing.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        title: const Text(
          'My Listings',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.black,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPrimary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: AppTheme.black,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
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
    if (_listings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 72,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                "You haven't listed anything yet",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap + on the Market screen to list something',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentPrimary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _listings.length,
        itemBuilder: (_, i) {
          final listing = _listings[i];
          return _MyListingTile(
            listing: listing,
            categoryName: _categoryOf(listing).name,
            onTap: () => _open(listing),
            onEdit: () => _edit(listing),
            onToggleSold: () => _toggleSold(listing),
            onDelete: listing.isVehicle ? () => _delete(listing) : null,
          );
        },
      ),
    );
  }
}

/// A car or a Market item, as one row of My Listings.
class _MyListing {
  final VehicleListing? vehicle;
  final MarketItem? item;

  _MyListing.vehicle(VehicleListing this.vehicle) : item = null;
  _MyListing.item(MarketItem this.item) : vehicle = null;

  bool get isVehicle => vehicle != null;

  String get id => vehicle?.id ?? item!.id;

  String get category => isVehicle ? kCarsCategory : item!.category;

  String get title => vehicle?.displayTitle ?? item!.title;

  bool get isSold => vehicle?.isSold ?? item!.isSold;

  DateTime get createdAt => vehicle?.createdAt ?? item!.createdAt;

  String? get imageUrl => vehicle?.firstImageUrl ?? item?.firstImageUrl;

  /// The price a buyer would pay: the promotional one when there is one.
  String get priceLabel {
    final v = vehicle;
    if (v != null) {
      return (v.promotion ?? 0) > 0 ? v.displayPromoPrice : v.displayPrice;
    }
    return item!.hasPromo ? item!.displayPromoPrice : item!.displayPrice;
  }
}

class _MyListingTile extends StatelessWidget {
  final _MyListing listing;
  final String categoryName;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleSold;
  final VoidCallback? onDelete;

  const _MyListingTile({
    required this.listing,
    required this.categoryName,
    required this.onTap,
    required this.onEdit,
    required this.onToggleSold,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = listing.imageUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: imageUrl != null
                        ? VehicleImage(
                            url: imageUrl,
                            fit: BoxFit.cover,
                            decodeWidth: 200,
                            placeholder: (_) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            listing.priceLabel,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentPrimary,
                            ),
                          ),
                          if (listing.isSold) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
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
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Listing actions',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'toggle_sold') onToggleSold();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    _menuItem('edit', Icons.edit_outlined, 'Edit'),
                    _menuItem(
                      'toggle_sold',
                      listing.isSold ? Icons.undo : Icons.sell_outlined,
                      listing.isSold ? 'Mark as Available' : 'Mark as Sold',
                    ),
                    if (onDelete != null)
                      _menuItem(
                        'delete',
                        Icons.delete_outline,
                        'Delete',
                        color: Colors.red.shade600,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color color = AppTheme.black,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          // A menu is capped in width; large accessibility text must wrap
          // rather than overflow it.
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: Icon(
        MarketCategory.iconFor(listing.category),
        size: 28,
        color: Colors.grey.shade300,
      ),
    );
  }
}
