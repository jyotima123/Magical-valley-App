import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/add_vehicle_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiries_list_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_chat_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/listing_contact.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class VehicleDetailScreen extends StatefulWidget {
  final VehicleListing listing;
  const VehicleDetailScreen({super.key, required this.listing});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late final PageController _pageCtrl;
  late VehicleListing _listing;
  int _currentPage = 0;
  bool _updatingSold = false;
  bool _startingDealerChat = false;
  bool _deletingListing = false;
  String? _sellerName;

  VehicleListing get v => _listing;

  bool get _isOwner =>
      v.createdBy != null &&
      v.createdBy == Supabase.instance.client.auth.currentUser?.id;

  /// Dealership name for feed inventory, or the poster's name for a
  /// community listing. Best-effort: the row simply stays blank if it fails.
  Future<void> _loadSellerName() async {
    if (v.isFromDealerFeed) {
      try {
        final row = await Supabase.instance.client
            .from('dealer_sources')
            .select('display_name, organizations(name)')
            .eq('source', v.source)
            .maybeSingle();
        if (!mounted) return;
        // The organization is the dealership itself; display_name is only the
        // integration's label (e.g. "LiftKit") and the fallback when no
        // organization is linked yet.
        final orgName =
            (row?['organizations'] as Map<String, dynamic>?)?['name'] as String?;
        final name = (orgName != null && orgName.isNotEmpty)
            ? orgName
            : row?['display_name'] as String?;
        if (name != null && name.isNotEmpty) setState(() => _sellerName = name);
      } catch (_) {}
      return;
    }

    final creatorId = v.createdBy;
    if (creatorId == null) return;
    final result = await context.read<ApiRepository>().getUserProfile(creatorId);
    if (!mounted || !result.isSuccess || result.data == null) return;
    final profile = result.data!;
    final name = (profile.fullName?.isNotEmpty ?? false)
        ? profile.fullName
        : profile.username;
    if (name != null && name.isNotEmpty) setState(() => _sellerName = name);
  }

  Future<void> _reload() async {
    // Dealer inventory has no row in our table to re-read.
    if (v.isFromDealerFeed) return;
    try {
      final row = await Supabase.instance.client
          .from('vehicle_listings')
          .select()
          .eq('id', v.id)
          .single();
      if (!mounted) return;
      setState(() {
        _listing = VehicleListing.fromJson(row);
      });
    } catch (_) {
      // Keep showing the last known data if the refresh fails.
    }
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddVehicleScreen(existing: v)),
    );
    if (updated == true) _reload();
  }

  Future<void> _toggleSold() async {
    final markingSold = !v.isSold;
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

    setState(() => _updatingSold = true);
    try {
      await Supabase.instance.client
          .from('vehicle_listings')
          .update({'is_sold': markingSold})
          .eq('id', v.id);
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

  /// Soft delete: a real DELETE would cascade away the buyers' conversations
  /// about this car (vehicle_inquiry_conversations.vehicle_id, migrations
  /// 073/085), so this just marks it removed and pops back — every list query
  /// filters deleted_at out from here on.
  Future<void> _deleteListing() async {
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

    setState(() => _deletingListing = true);
    try {
      await Supabase.instance.client
          .from('vehicle_listings')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', v.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingListing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openInquiriesList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleInquiriesListScreen(listing: v),
      ),
    );
  }

  /// Dealer inventory has no in-app owner, so the receiving account is
  /// resolved server-side from the feed the vehicle came from.
  Future<void> _openDealerChat() async {
    setState(() => _startingDealerChat = true);

    final api = context.read<ApiRepository>();
    final result = await api.createOrGetDealerInquiry(v);

    if (!mounted) return;
    setState(() => _startingDealerChat = false);

    if (result.isSuccess && result.data != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              VehicleInquiryChatScreen(conversation: result.data!),
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

  Future<void> _openInquiryChat() async {
    final api = context.read<ApiRepository>();
    // No seller id: the RPC resolves who answers from the listing itself.
    final result = await api.createOrGetVehicleInquiry(v.id);

    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              VehicleInquiryChatScreen(conversation: result.data!),
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
  void initState() {
    super.initState();
    _listing = widget.listing;
    _pageCtrl = PageController();
    // The carousel only builds the current page, so pull the rest of the
    // gallery onto disk up front and swiping is instant.
    VehicleImageCache.prefetch(_listing.images);
    _loadSellerName();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
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
    final hasImages = v.images.isNotEmpty;
    return SliverAppBar(
      expandedHeight: hasImages ? 280 : 200,
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
          if (_deletingListing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete listing',
              onPressed: _deleteListing,
            ),
        ],
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: hasImages
            ? Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: v.images.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => VehicleImage(
                      url: v.images[i],
                      fit: BoxFit.cover,
                      placeholder: (_) => _imagePlaceholder(),
                    ),
                  ),
                  if (v.images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          v.images.length,
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
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentPage + 1}/${v.images.length}',
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            v.make,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  /// Dealer listings are a read-only mirror of the dealership's inventory, but
  /// the conversation still happens here: buyers list and talk to dealers in
  /// the app rather than being handed off to the dealership's own site.
  Widget _buildDealerActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startingDealerChat ? null : _openDealerChat,
            icon: _startingDealerChat
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(_startingDealerChat ? 'Opening…' : 'Message Dealer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppTheme.accentPrimary.withValues(alpha: 0.6),
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
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.storefront_outlined,
                size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Dealer inventory — details come from the dealership and may '
                'change without notice.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent() {
    final hasPromo = v.promotion != null && v.promotion! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header card
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (v.isSold) ...[
                    const _SoldBadge(),
                    const SizedBox(width: 8),
                  ],
                  _StatusBadge(status: v.status),
                  const Spacer(),
                  if (v.location != null)
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 2),
                        Text(
                          v.location!,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                v.displayTitle,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              ),
              const SizedBox(height: 8),
              if (hasPromo) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      v.displayPrice,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: Colors.grey.shade400,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      v.displayPromoPrice,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentPrimary,
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  v.displayPrice,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.black,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Stock #${v.stock}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  if (_sellerName != null)
                    Text(
                      _sellerName!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              if (v.contactPhone != null && v.contactPhone!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.phone_outlined,
                        size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      shortenedPhone(v.contactPhone!),
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
              if (v.isSold && !_isOwner)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sell, size: 16, color: Colors.red.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'This vehicle has been sold',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              else if (v.isFromDealerFeed)
                _buildDealerActions()
              else
              Row(
                children: [
                  // Owners get "Mark as Sold" in the slot a buyer would see
                  // Call in — better flow than burying it in the app bar, and
                  // it would otherwise dial the owner's own number.
                  if (_isOwner) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _updatingSold ? null : _toggleSold,
                        icon: _updatingSold
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accentPrimary,
                                ),
                              )
                            : Icon(
                                v.isSold ? Icons.undo : Icons.sell_outlined,
                                size: 18,
                              ),
                        label: Text(
                          v.isSold ? 'Mark as Available' : 'Mark as Sold',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentPrimary,
                          side: const BorderSide(color: AppTheme.accentPrimary),
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
                  ] else if (kShowListingCallButton &&
                      v.contactPhone != null &&
                      v.contactPhone!.isNotEmpty) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: v.contactPhone),
                        ),
                        icon: const Icon(Icons.phone, size: 18),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentPrimary,
                          side: const BorderSide(color: AppTheme.accentPrimary),
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
                      onPressed: _isOwner ? _openInquiriesList : _openInquiryChat,
                      icon: Icon(
                        _isOwner ? Icons.forum_outlined : Icons.chat_bubble_outline,
                        size: 18,
                      ),
                      label: Text(_isOwner ? 'View Messages' : 'Message Seller'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentPrimary,
                        foregroundColor: Colors.white,
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

        // Quick specs
        _SectionCard(
          title: 'Overview',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SpecChip(icon: Icons.speed, label: v.displayMileage),
              if (v.fuel != null)
                _SpecChip(icon: Icons.local_gas_station, label: v.fuel!),
              if (v.transmission != null)
                _SpecChip(icon: Icons.settings, label: v.transmission!),
              if (v.body != null)
                _SpecChip(icon: Icons.directions_car, label: v.body!),
              if (v.color != null)
                _SpecChip(icon: Icons.palette_outlined, label: v.color!),
              if (v.doors != null)
                _SpecChip(
                    icon: Icons.door_front_door_outlined,
                    label: '${v.doors} doors'),
            ],
          ),
        ),

        // Detailed specs
        _SectionCard(
          title: 'Specifications',
          child: Column(
            children: [
              _DetailRow('Year', '${v.year}'),
              _DetailRow('Make', v.make),
              _DetailRow('Model', v.model),
              if (v.trim != null && v.trim!.isNotEmpty)
                _DetailRow('Trim', v.trim!),
              if (v.body != null) _DetailRow('Body Type', v.body!),
              _DetailRow('Mileage', v.displayMileage),
              if (v.fuel != null) _DetailRow('Fuel', v.fuel!),
              if (v.transmission != null)
                _DetailRow('Transmission', v.transmission!),
              if (v.speed != null) _DetailRow('Speeds', v.speed!),
              if (v.engineType != null)
                _DetailRow('Engine Type', v.engineType!),
              if (v.doors != null) _DetailRow('Doors', v.doors!),
              if (v.vin != null && v.vin!.isNotEmpty)
                _DetailRow('VIN', v.vin!),
            ],
          ),
        ),

        // Appearance
        if (v.color != null || (v.interior != null && v.interior!.isNotEmpty))
          _SectionCard(
            title: 'Appearance',
            child: Column(
              children: [
                if (v.color != null) _DetailRow('Exterior Color', v.color!),
                if (v.interior != null && v.interior!.isNotEmpty)
                  _DetailRow('Interior Color', v.interior!),
              ],
            ),
          ),

        // Description
        if (v.description != null && v.description!.isNotEmpty)
          _SectionCard(
            title: 'Description',
            child: Text(
              v.description!,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: AppTheme.black,
                height: 1.5,
              ),
            ),
          ),

        // Options & Packages
        if (_hasOptions)
          _SectionCard(
            title: 'Options & Packages',
            child: Column(
              children: [
                if (v.engineOptions != null && v.engineOptions!.isNotEmpty)
                  _DetailRow('Engine Options', v.engineOptions!),
                if (v.packageOptions != null && v.packageOptions!.isNotEmpty && v.packageOptions! != "[]")
                  _DetailRow('Package Options', v.packageOptions!),
                if (v.transmissionOptions != null &&
                    v.transmissionOptions!.isNotEmpty)
                  _DetailRow('Transmission Options', v.transmissionOptions!),
                if (v.addonsDescription != null &&
                    v.addonsDescription!.isNotEmpty)
                  _DetailRow('Add-ons', v.addonsDescription!),
              ],
            ),
          ),

        const SizedBox(height: 32),
      ],
    );
  }

  bool get _hasOptions =>
      (v.engineOptions != null && v.engineOptions!.isNotEmpty) ||
      (v.packageOptions != null && v.packageOptions!.isNotEmpty) ||
      (v.transmissionOptions != null && v.transmissionOptions!.isNotEmpty) ||
      (v.addonsDescription != null && v.addonsDescription!.isNotEmpty);
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SoldBadge extends StatelessWidget {
  const _SoldBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Sold',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.red.shade600,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isNew
            ? AppTheme.accentPrimary.withValues(alpha: 0.12)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isNew ? AppTheme.accentPrimary : Colors.blue.shade700,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SpecChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.accentPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
