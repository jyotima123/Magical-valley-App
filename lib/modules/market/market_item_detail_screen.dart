import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiries_list_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_chat_screen.dart';
import 'package:mvc_app/modules/market/add_market_item_screen.dart';
import 'package:mvc_app/modules/market/listing_contact.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/widgets/market_price_line.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// One Market item. Buyers message the seller from here; the seller edits it,
/// marks it sold, and reads the messages about it.
class MarketItemDetailScreen extends StatefulWidget {
  final MarketItem item;

  /// Shown under the title; the item only carries its category slug.
  final MarketCategory? category;

  final MarketRepository? repository;

  const MarketItemDetailScreen({
    super.key,
    required this.item,
    this.category,
    this.repository,
  });

  @override
  State<MarketItemDetailScreen> createState() => _MarketItemDetailScreenState();
}

class _MarketItemDetailScreenState extends State<MarketItemDetailScreen> {
  late final MarketRepository _repo = widget.repository ?? MarketRepository();
  late final PageController _pageCtrl;
  late MarketItem _item;
  int _currentPage = 0;
  bool _updatingSold = false;
  bool _startingChat = false;

  bool get _isOwner => _item.isOwnedBy(_repo.currentUserId);

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _pageCtrl = PageController();
    // The carousel only builds the current page, so pull the rest of the
    // gallery onto disk up front and swiping is instant.
    VehicleImageCache.prefetch(_item.images);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final fresh = await _repo.fetchItem(_item.id);
      if (!mounted) return;
      setState(() => _item = fresh);
    } catch (_) {
      // Keep showing the last known data if the refresh fails.
    }
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddMarketItemScreen(
          existing: _item,
          initialCategory: widget.category,
          repository: _repo,
        ),
      ),
    );
    if (updated == true) _reload();
  }

  Future<void> _toggleSold() async {
    final markingSold = !_item.isSold;
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
              ? 'The listing will show as Sold and new buyers will no longer be able to contact you about it. Existing conversations stay open.'
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

    setState(() => _updatingSold = true);
    try {
      await _repo.setSold(_item.id, sold: markingSold);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingSold = false);
    }
  }

  void _openInquiriesList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleInquiriesListScreen.forMarketItem(item: _item),
      ),
    );
  }

  Future<void> _openInquiryChat() async {
    setState(() => _startingChat = true);
    // No seller id: the RPC resolves who answers from the item itself.
    final result = await context
        .read<ApiRepository>()
        .createOrGetMarketItemInquiry(_item.id);

    if (!mounted) return;
    setState(() => _startingChat = false);

    if (result.isSuccess && result.data != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VehicleInquiryChatScreen(conversation: result.data!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to start conversation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final images = _item.images;
    return SliverAppBar(
      expandedHeight: images.isNotEmpty ? 280 : 200,
      pinned: true,
      backgroundColor: AppTheme.headerBackground,
      foregroundColor: AppTheme.black,
      actions: [
        if (_isOwner) ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit listing',
            onPressed: _openEdit,
          ),
          if (_updatingSold)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentPrimary,
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'toggle_sold') _toggleSold();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle_sold',
                  child: Row(
                    children: [
                      Icon(
                        _item.isSold ? Icons.undo : Icons.sell_outlined,
                        size: 18,
                        color: AppTheme.black,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _item.isSold ? 'Mark as Available' : 'Mark as Sold',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: images.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => VehicleImage(
                      url: images[i],
                      fit: BoxFit.cover,
                      placeholder: (_) => _imagePlaceholder(),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _currentPage == i ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? Colors.white
                                  : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentPage + 1}/${images.length}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : _imagePlaceholder(),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: Center(
        child: Icon(
          MarketCategory.iconFor(_item.category),
          size: 64,
          color: Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildContent() {
    final item = _item;
    final phone = item.contactPhone;
    final hasPhone = phone != null && phone.isNotEmpty;
    final categoryName = widget.category?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.isSold) ...[_Badge.sold(), const SizedBox(width: 8)],
                  if (item.conditionLabel != null)
                    _Badge.condition(item.conditionLabel!),
                  const Spacer(),
                  if (item.location != null)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              item.location!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              ),
              const SizedBox(height: 8),
              MarketPriceLine(item: item, large: true),
              if (categoryName != null) ...[
                const SizedBox(height: 6),
                Text(
                  categoryName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
              if (hasPhone) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 15,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      shortenedPhone(phone),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (item.isSold && !_isOwner)
                const _SoldNotice()
              else
                Row(
                  children: [
                    if (kShowListingCallButton && hasPhone && !_isOwner) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              launchUrl(Uri(scheme: 'tel', path: phone)),
                          icon: const Icon(Icons.phone, size: 18),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentPrimary,
                            side: const BorderSide(
                              color: AppTheme.accentPrimary,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isOwner
                            ? _openInquiriesList
                            : (_startingChat ? null : _openInquiryChat),
                        icon: _startingChat
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _isOwner
                                    ? Icons.forum_outlined
                                    : Icons.chat_bubble_outline,
                                size: 18,
                              ),
                        label: Text(
                          _isOwner
                              ? 'View Messages'
                              : (_startingChat ? 'Opening…' : 'Message Seller'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.accentPrimary
                              .withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (item.description != null && item.description!.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  item.description!,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppTheme.black,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

/// "Sold" or the item's condition, as a small tinted label.
class _Badge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  _Badge.sold()
    : label = 'Sold',
      background = Colors.red.withValues(alpha: 0.12),
      foreground = Colors.red.shade600;

  _Badge.condition(this.label)
    : background = Colors.blue.withValues(alpha: 0.1),
      foreground = Colors.blue.shade700;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _SoldNotice extends StatelessWidget {
  const _SoldNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sell, size: 16, color: Colors.red.shade400),
          const SizedBox(width: 8),
          Text(
            'This item has been sold',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
