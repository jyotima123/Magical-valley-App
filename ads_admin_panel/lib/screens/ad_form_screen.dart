import 'dart:io';

import 'package:ads_admin_panel/app_theme.dart';
import 'package:ads_admin_panel/config/supabase_config.dart';
import 'package:ads_admin_panel/models/ad_model.dart';
import 'package:ads_admin_panel/models/ad_size_model.dart';
import 'package:ads_admin_panel/services/ad_service.dart';
import 'package:ads_admin_panel/services/ad_size_service.dart';
import 'package:ads_admin_panel/widgets/ad_size_carousel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class AdFormScreen extends StatefulWidget {
  final AdModel? ad;

  const AdFormScreen({super.key, this.ad});

  @override
  State<AdFormScreen> createState() => _AdFormScreenState();
}

class _AdFormScreenState extends State<AdFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdService _adService = AdService();
  final AdSizeService _adSizeService = AdSizeService();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _linkUrlController;

  String? _imageUrl;
  File? _imageFile;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _errorMessage;

  List<AdSizeModel> _adSizes = [];
  AdSizeModel? _selectedAdSize;
  AdSizeModel? _previewAdSize; // tracks carousel page for live preview
  bool _isLoadingSizes = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.ad?.title);
    _descriptionController = TextEditingController(text: widget.ad?.description);
    _linkUrlController = TextEditingController(text: widget.ad?.linkUrl);
    _imageUrl = widget.ad?.imageUrl;
    _loadAdSizes();
  }

  Future<void> _loadAdSizes() async {
    try {
      final sizes = await _adSizeService.getAdSizes();
      setState(() {
        _adSizes = sizes;
        _isLoadingSizes = false;

        if (widget.ad?.adSizeId != null) {
          _selectedAdSize = sizes.firstWhere(
            (size) => size.id == widget.ad!.adSizeId,
            orElse: () => sizes.isNotEmpty ? sizes.first : sizes.first,
          );
        } else if (sizes.isNotEmpty) {
          _selectedAdSize = sizes.first;
        }
        _previewAdSize = _selectedAdSize;
      });
    } catch (e) {
      setState(() {
        _isLoadingSizes = false;
        _errorMessage = 'Failed to load ad sizes: $e';
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (kIsWeb) {
          setState(() {
            _imageBytes = file.bytes;
            _imageUrl = null;
          });
        } else {
          setState(() {
            _imageFile = File(file.path!);
            _imageUrl = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  DateTime? _getNextPaymentDueDate() {
    // If editing an existing ad, calculate next payment due date
    // Start date will be when latest purchase was made, end date is 30 days after
    if (widget.ad != null && widget.ad!.startDate != null) {
      return widget.ad!.startDate.add(const Duration(days: 30));
    }
    // For new ads, show 30 days from now
    return DateTime.now().add(const Duration(days: 30));
  }

  Widget _buildAdPreview() {
    final imageUrl = _imageUrl;
    final imageFile = _imageFile;
    final imageBytes = _imageBytes;
    final title = _titleController.text.trim();

    // Scale the selected ad size to fit within the preview area
    const double maxPreviewWidth = 300.0;
    const double maxPreviewHeight = 250.0;

    double previewWidth = (_previewAdSize?.width ?? 300).toDouble();
    double previewHeight = (_previewAdSize?.height ?? 250).toDouble();

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar placeholder space (32px avatar + 8px gap = 40px, matching post layout)
          const SizedBox(width: 40),

          // Ad content
          Column(
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
                    color: AppTheme.secondaryHeadingColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Ad container
              Container(
                width: previewWidth,
                height: previewHeight,
                decoration: BoxDecoration(
                  color: AppTheme.messageBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.dividerBackground,
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
                        width: previewWidth,
                        height: previewHeight,
                        child: imageBytes != null
                            ? Image.memory(imageBytes!, fit: BoxFit.cover)
                            : imageFile != null
                                ? Image.file(imageFile!, fit: BoxFit.cover)
                                : imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Container(
                                          color: AppTheme.cardGreyBackground,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                AppTheme.accentPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          color: AppTheme.cardGreyBackground,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.broken_image_outlined,
                                                size: 48,
                                                color: AppTheme.secondaryHeadingColor,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Ad not available',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.secondaryHeadingColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        memCacheWidth: previewWidth.toInt(),
                                        memCacheHeight: previewHeight.toInt(),
                                        maxWidthDiskCache: previewWidth.toInt(),
                                        maxHeightDiskCache: previewHeight.toInt(),
                                      )
                                    : Container(
                                        color: AppTheme.cardGreyBackground,
                                        child: Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            size: 48,
                                            color: AppTheme.secondaryHeadingColor,
                                          ),
                                        ),
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

              // Ad title (optional)
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDueCalendar() {
    final nextPaymentDate = _getNextPaymentDueDate();
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.searchBarBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            color: AppTheme.accentPrimary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Payment Due',
                  style: AppTheme.chatMessage.copyWith(
                    fontSize: 12,
                    color: AppTheme.secondaryHeadingColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextPaymentDate != null
                      ? dateFormat.format(nextPaymentDate)
                      : 'Not available',
                  style: AppTheme.chatTitle.copyWith(
                    fontSize: 14,
                    color: AppTheme.primaryHeadingColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _uploadImage() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      if (kIsWeb && _imageBytes != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'ad_$timestamp.jpg';
        final filePath = '$userId/$fileName';

        await SupabaseConfig.client.storage.from('ads').uploadBinary(
              filePath,
              _imageBytes!,
            );

        return SupabaseConfig.client.storage.from('ads').getPublicUrl(filePath);
      } else if (_imageFile != null) {
        return await _adService.uploadAdImage(_imageFile!, userId);
      }

      return _imageUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<void> _saveAd() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_imageUrl == null && _imageFile == null && _imageBytes == null) {
      setState(() {
        _errorMessage = 'Please select an image for the ad';
      });
      return;
    }

    if (_selectedAdSize == null) {
      setState(() {
        _errorMessage = 'Please select an ad size';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? uploadedImageUrl = _imageUrl;

      if (_imageFile != null || _imageBytes != null) {
        uploadedImageUrl = await _uploadImage();
      }

      if (uploadedImageUrl == null) {
        throw Exception('Failed to get image URL');
      }

      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Start date will be when latest purchase was made (now for new ads)
      // End date will be 30 days after start date
      final startDate = widget.ad?.startDate ?? DateTime.now();
      final endDate = startDate.add(const Duration(days: 30));

      final ad = AdModel(
        id: widget.ad?.id,
        creatorId: userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        imageUrl: uploadedImageUrl,
        linkUrl: _linkUrlController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        adSizeId: _selectedAdSize?.id,
        amountPaidCents: _selectedAdSize!.currentPrice,
        currency: 'USD',
        paymentStatus: widget.ad?.paymentStatus ?? PaymentStatus.pending,
        status: widget.ad?.status ?? AdStatus.draft,
      );

      if (widget.ad == null) {
        await _adService.createAd(ad);
      } else {
        await _adService.updateAd(ad);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.primaryHeadingColor),
        title: Text(
          widget.ad == null ? 'Create Ad' : 'Edit Ad',
          style: AppTheme.primaryHeading.copyWith(fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.error.withAlpha(76)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: AppTheme.chatMessage.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                Card(
                  color: AppTheme.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ad Image',
                          style: AppTheme.primaryHeading,
                        ),
                        const SizedBox(height: 12),
                        if (_imageUrl != null || _imageBytes != null || _imageFile != null)
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _imageBytes != null
                                  ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                                  : _imageFile != null
                                      ? Image.file(_imageFile!, fit: BoxFit.cover)
                                      : CachedNetworkImage(
                                          imageUrl: _imageUrl!,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                          errorWidget: (context, url, error) => const Center(
                                            child: Icon(Icons.error),
                                          ),
                                        ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.image),
                          label: Text(
                            _imageUrl != null || _imageBytes != null || _imageFile != null
                                ? 'Change Image'
                                : 'Select Image',
                            style: AppTheme.chatMessage.copyWith(
                              color: AppTheme.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentPrimary,
                            foregroundColor: AppTheme.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Ad Size',
                          style: AppTheme.primaryHeading,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Swipe or use arrows to browse sizes. Tap to select.',
                          style: AppTheme.chatMessage.copyWith(
                            fontSize: 12,
                            color: AppTheme.secondaryHeadingColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isLoadingSizes)
                          const SizedBox(
                            height: 320,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          AdSizeCarousel(
                            adSizes: _adSizes,
                            selectedSize: _selectedAdSize,
                            onSizeSelected: (size) {
                              setState(() {
                                _selectedAdSize = size;
                                _previewAdSize = size;
                              });
                            },
                            onSizeViewed: (size) {
                              setState(() {
                                _previewAdSize = size;
                              });
                            },
                            imageUrl: _imageUrl,
                            imageFile: _imageFile,
                            imageBytes: _imageBytes,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: AppTheme.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ad Details',
                          style: AppTheme.primaryHeading,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            // border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a title';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Displayed below the ad image.',
                          style: AppTheme.chatMessage.copyWith(
                            fontSize: 11,
                            color: AppTheme.secondaryHeadingColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            // border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Shown as a popup when the user taps the ad.',
                          style: AppTheme.chatMessage.copyWith(
                            fontSize: 11,
                            color: AppTheme.secondaryHeadingColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _linkUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Link URL',
                            // border: OutlineInputBorder(),
                            hintText: 'https://example.com',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a link URL';
                            }
                            if (!value.startsWith('http://') && !value.startsWith('https://')) {
                              return 'URL must start with http:// or https://';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The page that opens when the user clicks the ad.',
                          style: AppTheme.chatMessage.copyWith(
                            fontSize: 11,
                            color: AppTheme.secondaryHeadingColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: AppTheme.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: AppTheme.primaryHeading,
                        ),
                        const SizedBox(height: 16),
                        if (_imageUrl != null || _imageBytes != null || _imageFile != null)
                          _buildAdPreview()
                        else
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppTheme.searchBarBackground,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.image_outlined,
                                    size: 48,
                                    color: AppTheme.secondaryHeadingColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Upload an image to see preview',
                                    style: AppTheme.chatMessage.copyWith(
                                      color: AppTheme.secondaryHeadingColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        _buildPaymentDueCalendar(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveAd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPrimary,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.white,
                            ),
                          ),
                        )
                      : Text(
                          widget.ad == null ? 'Create Ad' : 'Update Ad',
                          style: AppTheme.chatTitle.copyWith(
                            fontSize: 16,
                            color: AppTheme.white,
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
}
