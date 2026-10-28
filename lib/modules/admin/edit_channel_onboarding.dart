import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:mvc_app/app_theme.dart';

class EditChannelOnboarding extends StatelessWidget {
  const EditChannelOnboarding({super.key});

  static PageDecoration get _decoration => const PageDecoration(
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 22.0,
          fontWeight: FontWeight.w700,
          color: AppTheme.black,
        ),
        bodyTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15.0,
          color: Colors.black54,
          height: 1.5,
        ),
        pageColor: Colors.white,
        imagePadding: EdgeInsets.only(top: 48),
        bodyPadding: EdgeInsets.symmetric(horizontal: 24),
      );

  Widget _icon(IconData icon, Color color) => Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 60, color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: 'Logo & Channel Name',
          body:
              'Tap the profile picture to upload your logo from the gallery or camera.\n\n'
              'The channel name is what followers see everywhere in the app.\n\n'
              'Example name: "City Bakery" or "Downtown Gym"',
          image: _icon(Icons.store_outlined, AppTheme.accentPrimary),
          decoration: _decoration,
        ),
        PageViewModel(
          title: 'Bio / Description',
          body:
              'Tell followers what your channel is about in a few sentences. '
              'This appears on your public profile.\n\n'
              'Example:\n"The best artisan bread in town, baked fresh every morning. '
              'Visit us Mon–Sat 7 am–6 pm."',
          image: _icon(Icons.info_outline, Colors.blue.shade600),
          decoration: _decoration,
        ),
        PageViewModel(
          title: 'Website & Maps Link',
          body:
              'Website — paste your main URL, e.g. "https://mybusiness.com".\n\n'
              'Google Maps Link — open Google Maps, find your location, '
              'tap Share → Copy link, then paste it here.\n\n'
              'Example: "https://maps.app.goo.gl/SdvggNr..."',
          image: _icon(Icons.language_outlined, Colors.teal.shade600),
          decoration: _decoration,
        ),
        PageViewModel(
          title: 'Photos',
          body:
              'Add photos of your place so followers can see what to expect '
              'before they visit.\n\n'
              'Tap "Add" to pick multiple photos from your gallery. '
              'Tap the × on any photo to remove it.\n\n'
              'Tip: use bright, well-lit photos for the best impression.',
          image: _icon(Icons.photo_library_outlined, Colors.orange.shade700),
          decoration: _decoration,
        ),
        PageViewModel(
          title: 'Categories',
          body:
              'Pick the categories that best describe your channel. '
              'Followers use these when browsing the Explore tab.\n\n'
              'You must select at least one. You can choose multiple '
              'if your channel spans more than one area.\n\n'
              'Example: "Food" + "Hospitality" for a café.',
          image: _icon(Icons.category_outlined, Colors.purple.shade600),
          decoration: _decoration,
        ),
      ],
      onDone: () => Navigator.of(context).pop(),
      onSkip: () => Navigator.of(context).pop(),
      showSkipButton: true,
      showNextButton: true,
      showBackButton: true,
      skip: Text(
        'Close',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          color: AppTheme.secondaryHeadingColor,
        ),
      ),
      next: const Icon(Icons.arrow_forward, color: AppTheme.accentPrimary),
      back: const Icon(Icons.arrow_back, color: AppTheme.accentPrimary),
      done: Text(
        'Got it',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          color: AppTheme.accentPrimary,
        ),
      ),
      dotsDecorator: DotsDecorator(
        size: const Size.square(8),
        activeSize: const Size(20, 8),
        activeColor: AppTheme.accentPrimary,
        color: Colors.black26,
        spacing: const EdgeInsets.symmetric(horizontal: 3),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
      ),
    );
  }
}
