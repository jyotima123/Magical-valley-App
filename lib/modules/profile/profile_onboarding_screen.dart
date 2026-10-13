import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/chat/image_picker_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({super.key});

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameFocusNode = FocusNode();
  final _firstNameFocusNode = FocusNode();
  final _lastNameScrollController = ScrollController();
  final _firstNameScrollController = ScrollController();

  int _currentPage = 0;
  String? _profileImageUrl;
  bool _isUploadingImage = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isKeyboardVisible = false;

  final ApiService _apiService = SupabaseApiService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _lastNameFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _lastNameScrollController.dispose();
    _firstNameScrollController.dispose();
    super.dispose();
  }

  // Auto-scroll the active text field page to reveal its field when the
  // keyboard appears, and back to the top when the keyboard is dismissed.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;
    if (keyboardVisible == _isKeyboardVisible) return;
    _isKeyboardVisible = keyboardVisible;

    final controller = _scrollControllerForPage(_currentPage);
    if (controller == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.animateTo(
        keyboardVisible ? controller.position.maxScrollExtent : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  ScrollController? _scrollControllerForPage(int page) {
    switch (page) {
      case 1:
        return _lastNameScrollController;
      case 2:
        return _firstNameScrollController;
      default:
        return null;
    }
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // Request focus on text fields when navigating to their pages
      Future.delayed(const Duration(milliseconds: 350), () {
        if (_currentPage == 0) {
          // About to navigate to page 1 (last name)
          _lastNameFocusNode.requestFocus();
        } else if (_currentPage == 1) {
          // About to navigate to page 2 (first name)
          _firstNameFocusNode.requestFocus();
        }
      });
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveProfile() async {
    final currentState = context.read<AuthBloc>().state;
    if (currentState is! AuthAuthenticatedState) return;

    final userProfile = currentState.userProfile;
    if (userProfile == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final apiRepository = context.read<ApiRepository>();

      // Combine first and last name into full name
      final fullName =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';

      final updateData = <String, dynamic>{
        'full_name': fullName,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Only update profile picture if one was uploaded
      if (_profileImageUrl != null) {
        updateData['profile_picture_url'] = _profileImageUrl;
      }

      final result = await apiRepository.updateUserProfile(
        userProfile.id,
        updateData,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        // Refresh auth state with updated profile and wait for it to complete
        final authBloc = context.read<AuthBloc>();
        authBloc.add(CheckAuthStatusEvent());

        // Wait for the auth state to update with the new profile
        await authBloc.stream.firstWhere(
          (state) {
            if (state is AuthAuthenticatedState && state.userProfile != null) {
              // Check if the profile has been updated (no '@privaterelay.appleid.com' in full_name)
              final fullName = state.userProfile!.fullName ?? '';
              return !fullName.contains('@privaterelay.appleid.com');
            }
            return false;
          },
          orElse: () => authBloc.state,
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () => authBloc.state,
        );

        // Navigate to completion page
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          _nextPage();
        }
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Failed to update profile';
          _isSaving = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'An error occurred while updating profile';
        _isSaving = false;
      });
    }
  }

  Future<void> _uploadProfilePicture(ImageSource source) async {
    final currentState = context.read<AuthBloc>().state;
    if (currentState is! AuthAuthenticatedState) return;

    setState(() {
      _isUploadingImage = true;
      _errorMessage = null;
    });

    try {
      // Pick image
      final imageBytes = await ImagePickerService.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (imageBytes != null) {
        // Upload image to your API
        final result = await _apiService.uploadProfilePicture(
          imageBytes,
          fileName: "profile.png",
          userId: currentState.userProfile?.id ?? "unknown_user",
          fileBytes: imageBytes,
        );

        if (result.isSuccess) {
          setState(() {
            _profileImageUrl = result.data;
          });
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to upload image';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload image. Please try again.';
      });
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Profile Picture',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFF28C6A)),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _uploadProfilePicture(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFF28C6A),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _uploadProfilePicture(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _currentPage > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: _previousPage,
              )
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
      ),
      body: Column(
        children: [
          // Progress indicator (only show on steps 1-3, hide on welcome and completion)
          if (_currentPage > 0 && _currentPage < 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: index < _currentPage
                            ? const Color(0xFFF28C6A)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildWelcomePage(),
                _buildLastNamePage(),
                _buildFirstNamePage(),
                _buildProfilePicturePage(),
                _buildCompletionPage(),
              ],
            ),
          ),

          // Error message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleContinueButton,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF28C6A),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _getButtonText(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.waving_hand,
                  size: 100,
                  color: Color(0xFFF28C6A),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Hey there!',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'We\'d love to get to know you better.\nLet\'s set up your profile in just a few steps.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLastNamePage() {
    return SingleChildScrollView(
      controller: _lastNameScrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'What\'s your last name?',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This will appear on your profile',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _lastNameController,
            focusNode: _lastNameFocusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Enter your last name',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFF28C6A), width: 2),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirstNamePage() {
    return SingleChildScrollView(
      controller: _firstNameScrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'And your first name?',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your full name helps people recognize you',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _firstNameController,
            focusNode: _firstNameFocusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Enter your first name',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFF28C6A), width: 2),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePicturePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Add a profile picture',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Show people who you are',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 60),
          Center(
            child: GestureDetector(
              onTap: _isUploadingImage ? null : _showImageSourceDialog,
              child: Stack(
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      image: _profileImageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_profileImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _profileImageUrl == null
                        ? Icon(Icons.person, size: 80, color: Colors.grey[400])
                        : null,
                  ),
                  if (_isUploadingImage)
                    Positioned.fill(
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF28C6A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: TextButton(
              onPressed: _isUploadingImage ? null : _showImageSourceDialog,
              child: const Text(
                'Add Photo',
                style: TextStyle(
                  color: Color(0xFFF28C6A),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionPage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF28C6A).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 80,
                    color: Color(0xFFF28C6A),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'You\'re all set!',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                    children: const [
                      TextSpan(text: 'Welcome to the community!\n\n'),
                      TextSpan(
                        text:
                            'You can edit your profile anytime tapping the hamburger menu ',
                      ),
                      WidgetSpan(
                        child: Icon(Icons.menu, size: 20, color: Colors.grey),
                        alignment: PlaceholderAlignment.bottom,
                      ),
                      TextSpan(
                        text: ' at the top right, then tap on Edit Profile.',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getButtonText() {
    if (_currentPage == 0) {
      return 'Get Started';
    } else if (_currentPage == 4) {
      return 'Done';
    } else if (_currentPage == 3) {
      return 'Continue';
    }
    return 'Continue';
  }

  void _handleContinueButton() {
    if (_currentPage == 0) {
      // Welcome page - just continue
      setState(() {
        _errorMessage = null;
      });
      _nextPage();
    } else if (_currentPage == 1) {
      // Validate last name
      if (_lastNameController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your last name';
        });
        return;
      }
      setState(() {
        _errorMessage = null;
      });
      _nextPage();
    } else if (_currentPage == 2) {
      // Validate first name
      if (_firstNameController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your first name';
        });
        return;
      }
      setState(() {
        _errorMessage = null;
      });
      // Hide keyboard before moving to next page
      FocusScope.of(context).unfocus();
      _nextPage();
    } else if (_currentPage == 3) {
      // Save profile (profile picture is optional) and move to completion
      _saveProfile();
    } else if (_currentPage == 4) {
      // Completion page - close the screen
      Navigator.of(context).pop();
    }
  }
}
