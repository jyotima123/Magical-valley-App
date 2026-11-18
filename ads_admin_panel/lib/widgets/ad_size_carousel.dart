import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ads_admin_panel/app_theme.dart';
import 'package:ads_admin_panel/models/ad_size_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Static descriptions for common ad sizes
class AdSizeDescriptions {
  static const Map<String, String> descriptions = {
    'Billboard': 'Large format ad ideal for maximum visibility. Best for brand awareness campaigns and homepage placements.',
    'Leaderboard': 'Wide horizontal banner typically placed at the top or bottom of pages. Great for high-traffic areas.',
    'Medium Rectangle': 'Versatile ad format that fits well within content. Popular for sidebar and in-article placements.',
    'Wide Skyscraper': 'Tall vertical ad perfect for sidebar placements. Stays visible as users scroll through content.',
    'Half Page': 'Large format offering significant screen real estate. Excellent for rich media and interactive ads.',
    'Large Rectangle': 'Expanded rectangle format with more impact. Ideal for video ads and detailed messaging.',
    'Banner': 'Classic horizontal format suitable for various placements. Good balance of visibility and content space.',
    'Square': 'Compact format that works well in grids and feeds. Popular for social media style layouts.',
    'Skyscraper': 'Narrow vertical format for tight sidebar spaces. Maintains presence without overwhelming content.',
    'Small Square': 'Minimal footprint for subtle ad placements. Best for unobtrusive reminder ads.',
  };

  static String getDescription(String name) {
    return descriptions[name] ?? 'Standard ad format for displaying your promotional content across the platform.';
  }
}

/// Ad size names that are currently available for purchase.
/// Others can still be browsed/previewed but their Select button is greyed out.
const Set<String> _enabledAdSizeNames = {'Mobile Banner', 'Half Page', 'Medium Rectangle'};

/// A carousel widget for selecting ad sizes with PSVita-style animation
class AdSizeCarousel extends StatefulWidget {
  final List<AdSizeModel> adSizes;
  final AdSizeModel? selectedSize;
  final ValueChanged<AdSizeModel> onSizeSelected;
  /// Called whenever the visible carousel page changes (for live preview).
  final ValueChanged<AdSizeModel>? onSizeViewed;
  final String? imageUrl;
  final File? imageFile;
  final Uint8List? imageBytes;

  const AdSizeCarousel({
    super.key,
    required this.adSizes,
    required this.onSizeSelected,
    this.onSizeViewed,
    this.selectedSize,
    this.imageUrl,
    this.imageFile,
    this.imageBytes,
  });

  @override
  State<AdSizeCarousel> createState() => _AdSizeCarouselState();
}

class _AdSizeCarouselState extends State<AdSizeCarousel>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  double _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedSize != null
        ? widget.adSizes.indexWhere((s) => s.id == widget.selectedSize!.id)
        : 0;
    if (_currentIndex < 0) _currentIndex = 0;
    _currentPage = _currentIndex.toDouble();

    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 0.55,
    );
    _pageController.addListener(_onPageScroll);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _onPageScroll() {
    setState(() {
      _currentPage = _pageController.page ?? _currentIndex.toDouble();
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.adSizes.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectCurrentSize() {
    if (_currentIndex >= 0 && _currentIndex < widget.adSizes.length) {
      widget.onSizeSelected(widget.adSizes[_currentIndex]);
    }
  }

  Widget _buildImagePreview(AdSizeModel size, double scale) {
    final maxPreviewWidth = 200.0 * scale;
    final maxPreviewHeight = 180.0 * scale;

    // Calculate scaled dimensions maintaining aspect ratio
    double previewWidth = size.width.toDouble();
    double previewHeight = size.height.toDouble();

    if (previewWidth > maxPreviewWidth) {
      final ratio = maxPreviewWidth / previewWidth;
      previewWidth = maxPreviewWidth;
      previewHeight *= ratio;
    }
    if (previewHeight > maxPreviewHeight) {
      final ratio = maxPreviewHeight / previewHeight;
      previewHeight = maxPreviewHeight;
      previewWidth *= ratio;
    }

    // Minimum size for visibility
    previewWidth = previewWidth.clamp(60.0, maxPreviewWidth);
    previewHeight = previewHeight.clamp(40.0, maxPreviewHeight);

    final hasImage = widget.imageUrl != null ||
        widget.imageFile != null ||
        widget.imageBytes != null;

    return Container(
      width: previewWidth,
      height: previewHeight,
      decoration: BoxDecoration(
        color: hasImage ? null : AppTheme.searchBarBackground,
        border: Border.all(
          color: AppTheme.accentPrimary.withAlpha((100 * scale).toInt()),
          width: 2 * scale,
        ),
        borderRadius: BorderRadius.circular(8 * scale),
        boxShadow: [
          BoxShadow(
            color: AppTheme.black.withAlpha((30 * scale).toInt()),
            blurRadius: 10 * scale,
            offset: Offset(0, 4 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6 * scale),
        child: hasImage
            ? _buildImage()
            : Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 40 * scale,
                  color: AppTheme.secondaryHeadingColor,
                ),
              ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageBytes != null) {
      return Image.memory(widget.imageBytes!, fit: BoxFit.cover);
    } else if (widget.imageFile != null) {
      return Image.file(widget.imageFile!, fit: BoxFit.cover);
    } else if (widget.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppTheme.searchBarBackground,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: AppTheme.searchBarBackground,
          child: const Icon(Icons.error, color: AppTheme.error),
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildCarouselItem(int index, AdSizeModel size) {
    final distance = (_currentPage - index).abs();
    final scale = (1 - (distance * 0.25)).clamp(0.6, 1.0);
    final opacity = (1 - (distance * 0.4)).clamp(0.3, 1.0);

    // 3D rotation effect
    final rotationY = (index - _currentPage) * 0.3;

    final isSelected = widget.selectedSize?.id == size.id;
    final isCurrent = index == _currentPage.round();

    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
        if (isCurrent) {
          widget.onSizeSelected(size);
        }
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateY(rotationY)
            ..multiply(Matrix4.diagonal3Values(scale, scale, scale)),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentPrimary
                    : isCurrent
                        ? AppTheme.accentPrimary.withAlpha(128)
                        : AppTheme.searchBarBackground,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppTheme.accentPrimary.withAlpha(50)
                      : AppTheme.black.withAlpha(20),
                  blurRadius: 15 * scale,
                  offset: Offset(0, 8 * scale),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Size name
                Padding(
                  padding: EdgeInsets.all(12 * scale),
                  child: Text(
                    size.name,
                    style: AppTheme.chatTitle.copyWith(
                      fontSize: 14 * scale,
                      color: isSelected
                          ? AppTheme.accentPrimary
                          : AppTheme.primaryHeadingColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Image preview
                Expanded(
                  child: Center(
                    child: _buildImagePreview(size, scale),
                  ),
                ),
                // Dimensions
                Padding(
                  padding: EdgeInsets.all(12 * scale),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12 * scale,
                      vertical: 6 * scale,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accentPrimary.withAlpha(25)
                          : AppTheme.searchBarBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      size.displaySize,
                      style: AppTheme.chatMessage.copyWith(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppTheme.accentPrimary
                            : AppTheme.secondaryHeadingColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isEnabled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isEnabled
                ? AppTheme.accentPrimary.withAlpha(25)
                : AppTheme.searchBarBackground.withAlpha(128),
            border: Border.all(
              color: isEnabled
                  ? AppTheme.accentPrimary.withAlpha(76)
                  : AppTheme.searchBarBackground,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            color: isEnabled
                ? AppTheme.accentPrimary
                : AppTheme.secondaryHeadingColor.withAlpha(128),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionPanel() {
    if (widget.adSizes.isEmpty) return const SizedBox();

    final currentSize = widget.adSizes[_currentPage.round().clamp(0, widget.adSizes.length - 1)];
    final description = AdSizeDescriptions.getDescription(currentSize.name);
    final isSelected = widget.selectedSize?.id == currentSize.id;
    final isEnabled = _enabledAdSizeNames.contains(currentSize.name);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(currentSize.id),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentPrimary.withAlpha(76)
                : AppTheme.searchBarBackground,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with size name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPrimary.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.aspect_ratio,
                    color: AppTheme.accentPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSize.name,
                        style: AppTheme.chatTitle.copyWith(
                          color: AppTheme.primaryHeadingColor,
                        ),
                      ),
                      Text(
                        currentSize.displaySize,
                        style: AppTheme.chatMessage.copyWith(
                          color: AppTheme.secondaryHeadingColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Description
            Text(
              description,
              style: AppTheme.chatMessage.copyWith(
                color: AppTheme.primaryHeadingColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // Aspect ratio info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.searchBarBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.crop,
                    size: 16,
                    color: AppTheme.secondaryHeadingColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Aspect Ratio: ${currentSize.aspectRatio.toStringAsFixed(2)}',
                    style: AppTheme.chatMessage.copyWith(
                      fontSize: 12,
                      color: AppTheme.secondaryHeadingColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Price info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.attach_money,
                    size: 16,
                    color: AppTheme.accentPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentSize.priceDisplay,
                    style: AppTheme.chatMessage.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Select button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isEnabled ? _selectCurrentSize : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: !isEnabled
                      ? AppTheme.searchBarBackground
                      : isSelected
                          ? AppTheme.success
                          : AppTheme.accentPrimary,
                  foregroundColor: !isEnabled
                      ? AppTheme.secondaryHeadingColor
                      : AppTheme.white,
                  disabledBackgroundColor: AppTheme.searchBarBackground,
                  disabledForegroundColor: AppTheme.secondaryHeadingColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isEnabled
                          ? (isSelected ? Icons.check_circle : Icons.check)
                          : Icons.lock_outline,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEnabled
                          ? (isSelected ? 'Selected' : 'Select This Size')
                          : 'Coming Soon',
                      style: AppTheme.chatMessage.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isEnabled
                            ? AppTheme.white
                            : AppTheme.secondaryHeadingColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adSizes.isEmpty) {
      return Center(
        child: Text(
          'No ad sizes available',
          style: AppTheme.chatMessage.copyWith(
            color: AppTheme.error,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        if (isWide) {
          // Wide layout: carousel on left, description on right
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carousel section
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Page indicator
                    _buildPageIndicator(),
                    const SizedBox(height: 8),
                    // Carousel
                    SizedBox(
                      height: 320,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            itemCount: widget.adSizes.length,
                            onPageChanged: (index) {
                              setState(() {
                                _currentIndex = index;
                              });
                              if (index < widget.adSizes.length) {
                                widget.onSizeViewed?.call(widget.adSizes[index]);
                              }
                            },
                            itemBuilder: (context, index) {
                              return _buildCarouselItem(
                                index,
                                widget.adSizes[index],
                              );
                            },
                          ),
                          // Navigation buttons
                          Positioned(
                            left: 8,
                            child: _buildNavigationButton(
                              icon: Icons.chevron_left,
                              onPressed: _goToPrevious,
                              isEnabled: _currentIndex > 0,
                            ),
                          ),
                          Positioned(
                            right: 8,
                            child: _buildNavigationButton(
                              icon: Icons.chevron_right,
                              onPressed: _goToNext,
                              isEnabled: _currentIndex < widget.adSizes.length - 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Description panel
              Expanded(
                flex: 2,
                child: _buildDescriptionPanel(),
              ),
            ],
          );
        } else {
          // Narrow layout: carousel on top, description below
          return Column(
            children: [
              // Page indicator
              _buildPageIndicator(),
              const SizedBox(height: 8),
              // Carousel
              SizedBox(
                height: 280,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: widget.adSizes.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildCarouselItem(
                          index,
                          widget.adSizes[index],
                        );
                      },
                    ),
                    // Navigation buttons
                    Positioned(
                      left: 0,
                      child: _buildNavigationButton(
                        icon: Icons.chevron_left,
                        onPressed: _goToPrevious,
                        isEnabled: _currentIndex > 0,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: _buildNavigationButton(
                        icon: Icons.chevron_right,
                        onPressed: _goToNext,
                        isEnabled: _currentIndex < widget.adSizes.length - 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Description panel
              _buildDescriptionPanel(),
            ],
          );
        }
      },
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${_currentPage.round() + 1}',
          style: AppTheme.chatTitle.copyWith(
            color: AppTheme.accentPrimary,
            fontSize: 18,
          ),
        ),
        Text(
          ' / ${widget.adSizes.length}',
          style: AppTheme.chatMessage.copyWith(
            color: AppTheme.secondaryHeadingColor,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 16),
        // Dot indicators
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            math.min(widget.adSizes.length, 7),
            (index) {
              // Show limited dots for many items
              int displayIndex = index;
              if (widget.adSizes.length > 7) {
                if (_currentIndex < 3) {
                  displayIndex = index;
                } else if (_currentIndex >= widget.adSizes.length - 3) {
                  displayIndex = widget.adSizes.length - 7 + index;
                } else {
                  displayIndex = _currentIndex - 3 + index;
                }
              }

              final isActive = displayIndex == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.accentPrimary
                      : AppTheme.searchBarBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
