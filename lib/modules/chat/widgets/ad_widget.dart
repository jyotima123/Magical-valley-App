import 'dart:math' show min;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/models/ad_model.dart';
import 'package:url_launcher/url_launcher.dart';

class AdWidget extends StatelessWidget {
  final AdModel ad;
  final AppThemeMode theme;

  /// When [true], tapping the ad immediately opens [ad.linkUrl] in the browser.
  /// When [false] (default), tapping first shows a centered preview popup with
  /// a "Visit website" button, letting the user confirm before navigating.
  final bool openDirectly;

  const AdWidget({
    super.key,
    required this.ad,
    required this.theme,
    this.openDirectly = false,
  });

  bool get _isDarkTheme => theme == AppThemeMode.dark;

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('Error opening ad link: $e');
    }
  }

  void _onAdTapped(BuildContext context) {
    if (openDirectly) {
      _launchUrl(ad.linkUrl);
    } else {
      _showAdPreview(context);
    }
  }

  Future<void> _showAdPreview(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return _AdPreviewDialog(ad: ad, isDarkTheme: _isDarkTheme);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show ads in QA environment
    if (FlavorConfig.supabaseEnvironment != 'qa') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Sponsored" label
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'SPONSORED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isDarkTheme
                    ? AppTheme.darkTextSecondary
                    : AppTheme.secondaryHeadingColor,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Ad container
          GestureDetector(
            onTap: () => _onAdTapped(context),
            child: Container(
              width: 300,
              height: 250,
              decoration: BoxDecoration(
                color: _isDarkTheme
                    ? AppTheme.darkCardBackground
                    : AppTheme.messageBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDarkTheme
                      ? AppTheme.darkTextTertiary.withOpacity(0.3)
                      : AppTheme.dividerBackground,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // Ad image
                    SizedBox(
                      width: 300,
                      height: 250,
                      child: CachedNetworkImage(
                        imageUrl: ad.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: _isDarkTheme
                              ? AppTheme.darkSurface
                              : AppTheme.cardGreyBackground,
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.accentPrimary,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: _isDarkTheme
                              ? AppTheme.darkSurface
                              : AppTheme.cardGreyBackground,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                                color: _isDarkTheme
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.secondaryHeadingColor,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ad not available',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isDarkTheme
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.secondaryHeadingColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        memCacheWidth: 300,
                        memCacheHeight: 250,
                        maxWidthDiskCache: 300,
                        maxHeightDiskCache: 250,
                      ),
                    ),

                    // Ad badge overlay
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ad',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Ad title (optional)
          if (ad.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                ad.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _AdPreviewDialog extends StatefulWidget {
  final AdModel ad;
  final bool isDarkTheme;

  const _AdPreviewDialog({required this.ad, required this.isDarkTheme});

  @override
  State<_AdPreviewDialog> createState() => _AdPreviewDialogState();
}

class _AdPreviewDialogState extends State<_AdPreviewDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('Error opening ad link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final maxAdWidth = screenWidth - 48.0;

    final adW = (widget.ad.width ?? 300).toDouble();
    final adH = (widget.ad.height ?? 250).toDouble();
    final adHeight = maxAdWidth * (adH / adW);

    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Stack(
          children: [
            // Full-screen tap-to-dismiss overlay + centered ad content
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black.withOpacity(0.65),
                width: double.infinity,
                height: double.infinity,
                child: Center(
                  child: GestureDetector(
                    // Absorb taps so the overlay doesn't dismiss
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // "Sponsored" label
                          Text(
                            'SPONSORED',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Ad image
                          Container(
                            width: maxAdWidth,
                            height: adHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: maxAdWidth,
                                    height: adHeight,
                                    child: CachedNetworkImage(
                                      imageUrl: widget.ad.imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: AppTheme.cardGreyBackground,
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: AppTheme.cardGreyBackground,
                                        child: const Center(
                                          child:
                                              Icon(Icons.broken_image_outlined),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Ad badge
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.white,
                                            size: 12,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Ad',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Ad title
                          if (widget.ad.title.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              widget.ad.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          // Ad description
                          if (widget.ad.description != null &&
                              widget.ad.description!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.ad.description!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Visit website button — pulsating with white glow
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              final glowOpacity =
                                  0.15 + _pulseAnimation.value * 0.35;
                              final scale =
                                  0.975 + _pulseAnimation.value * 0.025;
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: maxAdWidth,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.white.withOpacity(glowOpacity),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: ElevatedButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await _launchUrl(widget.ad.linkUrl);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.accentPrimary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                shape: const StadiumBorder(),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Left spacer balances the right-side icon
                                  const SizedBox(width: 28),
                                  Expanded(
                                    child: Text(
                                      'Visit website',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.accentPrimary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_outlined,
                                    size: 22,
                                    color: AppTheme.accentPrimary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // "Tap outside to close" pinned to the bottom of the screen
            Positioned(
              bottom: 20 + bottomPadding,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  'Tap outside to close',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
