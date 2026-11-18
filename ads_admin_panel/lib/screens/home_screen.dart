import 'package:ads_admin_panel/app_theme.dart';
import 'package:ads_admin_panel/config/supabase_config.dart';
import 'package:ads_admin_panel/models/ad_model.dart';
import 'package:ads_admin_panel/screens/ad_form_screen.dart';
import 'package:ads_admin_panel/screens/auth_screen.dart';
import 'package:ads_admin_panel/services/ad_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AdService _adService = AdService();
  List<AdModel> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSuperAdmin = false;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndAds();
  }

  Future<void> _loadUserRoleAndAds() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userInfo = await _adService.getUserRole();
      final role = userInfo['role'] as String?;
      _isSuperAdmin = role == 'superadmin';
      _userEmail = userInfo['email'] as String? ?? '';

      if (_isSuperAdmin) {
        _ads = await _adService.getAllAds();
      } else {
        _ads = await _adService.getMyAds();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAd(String adId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: const Text('Delete Ad'),
        content: const Text('Are you sure you want to delete this ad?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adService.deleteAd(adId);
        _loadUserRoleAndAds();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ad deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete ad: $e')),
          );
        }
      }
    }
  }

  Future<void> _approveAd(String adId) async {
    try {
      await _adService.approveAd(adId);
      _loadUserRoleAndAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad approved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve ad: $e')),
        );
      }
    }
  }

  Future<void> _rejectAd(String adId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: const Text('Reject Ad'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Rejection Reason',
            // border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.isNotEmpty) {
      try {
        await _adService.rejectAd(adId, reasonController.text);
        _loadUserRoleAndAds();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ad rejected')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reject ad: $e')),
          );
        }
      }
    }
  }

  Future<void> _signOut() async {
    await SupabaseConfig.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        title: Text(
          'Ads Management',
          style: AppTheme.primaryHeading.copyWith(fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                _userEmail,
                style: AppTheme.chatMessage.copyWith(fontSize: 14),
              ),
            ),
          ),
          if (_isSuperAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.logoColor,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'Super Admin',
                  style: AppTheme.chatMessage.copyWith(
                    fontSize: 12,
                    color: AppTheme.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.logout, color: AppTheme.primaryHeadingColor),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error: $_errorMessage',
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserRoleAndAds,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _ads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.ad_units,
                            size: 64,
                            color: AppTheme.secondaryHeadingColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No ads yet',
                            style: AppTheme.secondaryHeading.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AdFormScreen(),
                                ),
                              );
                              if (result == true) {
                                _loadUserRoleAndAds();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentPrimary,
                              foregroundColor: AppTheme.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(
                              'Create Your First Ad',
                              style: AppTheme.chatTitle.copyWith(
                                color: AppTheme.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _ads.length,
                      itemBuilder: (context, index) {
                        final ad = _ads[index];
                        return _AdCard(
                          ad: ad,
                          isSuperAdmin: _isSuperAdmin,
                          onEdit: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => AdFormScreen(ad: ad),
                              ),
                            );
                            if (result == true) {
                              _loadUserRoleAndAds();
                            }
                          },
                          onDelete: () => _deleteAd(ad.id!),
                          onApprove: () => _approveAd(ad.id!),
                          onReject: () => _rejectAd(ad.id!),
                          onPayment: () {
                            // TODO: Navigate to payment page for ad with id: ad.id
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Payment page for ad: ${ad.title}')),
                            );
                          },
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const AdFormScreen()),
          );
          if (result == true) {
            _loadUserRoleAndAds();
          }
        },
        backgroundColor: AppTheme.accentPrimary,
        foregroundColor: AppTheme.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        icon: const Icon(Icons.add),
        label: Text(
          'Create Ad',
          style: AppTheme.chatTitle.copyWith(color: AppTheme.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  final AdModel ad;
  final bool isSuperAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPayment;

  const _AdCard({
    required this.ad,
    required this.isSuperAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.onApprove,
    required this.onReject,
    required this.onPayment,
  });

  Color _getStatusColor(AdStatus status) {
    switch (status) {
      case AdStatus.draft:
        return Colors.grey;
      case AdStatus.pendingApproval:
        return Colors.orange;
      case AdStatus.approved:
        return Colors.green;
      case AdStatus.rejected:
        return Colors.red;
      case AdStatus.active:
        return Colors.blue;
      case AdStatus.expired:
        return Colors.brown;
      case AdStatus.paused:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppTheme.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ad.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              child: CachedNetworkImage(
                imageUrl: ad.imageUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(child: Icon(Icons.error)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ad.title,
                        style: AppTheme.primaryHeading.copyWith(fontSize: 20),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(ad.status),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        ad.status.displayName,
                        style: AppTheme.chatMessage.copyWith(
                          fontSize: 12,
                          color: AppTheme.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (ad.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    ad.description!,
                    style: AppTheme.chatMessage,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 16,
                      color: AppTheme.secondaryHeadingColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ad.linkUrl,
                        style: AppTheme.chatMessage.copyWith(
                          color: AppTheme.accentPrimary,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppTheme.secondaryHeadingColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${dateFormat.format(ad.startDate)} - ${dateFormat.format(ad.endDate)}',
                      style: AppTheme.chatMessage,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.payment,
                      size: 16,
                      color: AppTheme.secondaryHeadingColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '\$${(ad.amountPaidCents / 100).toStringAsFixed(2)} ${ad.currency}',
                      style: AppTheme.chatMessage,
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.searchBarBackground,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.grey.shade300, width: 1),
                      ),
                      child: Text(
                        ad.paymentStatus.displayName,
                        style: AppTheme.chatMessage.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                if (ad.rejectionReason != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.error.withAlpha(76)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error, color: AppTheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Rejection Reason: ${ad.rejectionReason}',
                            style: AppTheme.chatMessage.copyWith(
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (ad.status == AdStatus.draft || ad.status == AdStatus.rejected)
                      ElevatedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 18),
                        label: Text(
                          'Edit',
                          style: AppTheme.chatMessage.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentPrimary,
                          foregroundColor: AppTheme.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    if (ad.status == AdStatus.draft || ad.status == AdStatus.rejected)
                      ElevatedButton.icon(
                        onPressed: onPayment,
                        icon: const Icon(Icons.payment, size: 18),
                        label: Text(
                          'Payment',
                          style: AppTheme.chatMessage.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: AppTheme.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    if (ad.status == AdStatus.draft)
                      ElevatedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete, size: 18),
                        label: Text(
                          'Delete',
                          style: AppTheme.chatMessage.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: AppTheme.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    if (isSuperAdmin && ad.status == AdStatus.pendingApproval) ...[
                      ElevatedButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                          'Approve',
                          style: AppTheme.chatMessage.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: AppTheme.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(
                          'Reject',
                          style: AppTheme.chatMessage.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: AppTheme.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
