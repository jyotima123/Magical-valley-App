import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/image_picker_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';

enum FeedbackType {
  issue('issue', 'Issue'),
  suggestion('suggestion', 'Suggestion');

  final String value;
  final String label;

  const FeedbackType(this.value, this.label);
}

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  FeedbackType? _selectedFeedbackType;
  Uint8List? _screenshotBytes;
  String? _screenshotUrl;
  bool _isUploadingScreenshot = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot(ImageSource source) async {
    setState(() {
      _isUploadingScreenshot = true;
      _errorMessage = null;
    });

    try {
      final imageBytes = await ImagePickerService.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        quality: 85,
      );

      if (imageBytes != null) {
        // Compress the image for feedback screenshots
        final compressedBytes = await ImagePickerService.compressImage(
          imageBytes: imageBytes,
          quality: 80,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        setState(() {
          _screenshotBytes = compressedBytes ?? imageBytes;
        });

        // Upload screenshot to storage
        await _uploadScreenshot();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image. Please try again.';
      });
    } finally {
      setState(() {
        _isUploadingScreenshot = false;
      });
    }
  }

  Future<void> _uploadScreenshot() async {
    if (_screenshotBytes == null) return;

    final currentState = context.read<AuthBloc>().state;
    if (currentState is! AuthAuthenticatedState) return;

    final userId = currentState.userProfile?.id;
    if (userId == null) return;

    setState(() {
      _isUploadingScreenshot = true;
      _errorMessage = null;
    });

    try {
      final result = await SupabaseApiService.instance.uploadGenericFile(
        userId: userId,
        fileBytes: _screenshotBytes!,
        fileName: 'feedback_screenshot.png',
        subFolder: 'feedback',
      );

      if (result.isSuccess) {
        setState(() {
          _screenshotUrl = result.data;
        });
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Failed to upload screenshot';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload screenshot. Please try again.';
      });
    } finally {
      setState(() {
        _isUploadingScreenshot = false;
      });
    }
  }

  void _removeScreenshot() {
    setState(() {
      _screenshotBytes = null;
      _screenshotUrl = null;
    });
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickScreenshot(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickScreenshot(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitFeedback() async {
    if (_formKey.currentState?.validate() != true) return;

    if (_selectedFeedbackType == null) {
      setState(() {
        _errorMessage = 'Please select a feedback type';
      });
      return;
    }

    final currentState = context.read<AuthBloc>().state;
    if (currentState is! AuthAuthenticatedState) return;

    final userProfile = currentState.userProfile;
    if (userProfile == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // If we have screenshot bytes but no URL, upload it first
      if (_screenshotBytes != null && _screenshotUrl == null) {
        await _uploadScreenshot();
        if (_screenshotUrl == null) {
          setState(() {
            _isSubmitting = false;
            _errorMessage = 'Failed to upload screenshot. Please try again.';
          });
          return;
        }
      }

      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.submitFeedback(
        userId: userProfile.id,
        feedbackType: _selectedFeedbackType!.value,
        description: _descriptionController.text.trim(),
        screenshotUrl: _screenshotUrl,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted successfully! Thank you for your input.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Wait a moment then pop
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Failed to submit feedback';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'An error occurred while submitting feedback. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Send Feedback',
          style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Feedback Type Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feedback Type',
                    style: AppTheme.managementSubtitleText.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.managementCardBorder),
                    ),
                    child: DropdownButtonFormField<FeedbackType>(
                      value: _selectedFeedbackType,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      hint: Text(
                        'Select feedback type',
                        style: AppTheme.managementTitleText,
                      ),
                      items: FeedbackType.values.map((type) {
                        return DropdownMenuItem<FeedbackType>(
                          value: type,
                          child: Text(
                            type.label,
                            style: AppTheme.managementTitleText,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedFeedbackType = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a feedback type';
                        }
                        return null;
                      },
                      style: AppTheme.managementTitleText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Description Text Area
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Description',
                    style: AppTheme.managementSubtitleText.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 8,
                    style: AppTheme.managementTitleText,
                    decoration: InputDecoration(
                      hintText: 'Please describe your ${_selectedFeedbackType?.label.toLowerCase() ?? "feedback"}...',
                      hintStyle: AppTheme.managementTitleText.copyWith(
                        color: AppTheme.managementSubtitle,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.managementCardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.managementCardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primaryHeadingColor),
                      ),
                      filled: true,
                      fillColor: AppTheme.white,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a description';
                      }
                      if (value.trim().length < 10) {
                        return 'Description must be at least 10 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Screenshot Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardGreyBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.managementCardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Screenshot (Optional)',
                      style: AppTheme.managementSubtitleText.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    if (_screenshotBytes != null || _screenshotUrl != null) ...[
                      Stack(
                        children: [
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.managementCardBorder),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _screenshotBytes != null
                                  ? Image.memory(
                                      _screenshotBytes!,
                                      fit: BoxFit.cover,
                                    )
                                  : _screenshotUrl != null
                                      ? Image.network(
                                          _screenshotUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Center(
                                              child: Icon(Icons.broken_image),
                                            );
                                          },
                                        )
                                      : const SizedBox(),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              onPressed: _removeScreenshot,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_isUploadingScreenshot)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showImageSourceDialog,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(
                            _screenshotBytes != null || _screenshotUrl != null
                                ? 'Change Screenshot'
                                : 'Add Screenshot',
                            style: AppTheme.managementTitleText.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: AppTheme.managementCardBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTheme.managementTitleText.copyWith(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Submit and Cancel Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: AppTheme.managementCardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: AppTheme.managementTitleText.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitFeedback,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryHeadingColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Submit Feedback',
                              style: AppTheme.managementTitleText.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
