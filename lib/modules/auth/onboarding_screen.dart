import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: "Welcome to MVC",
          body:
              "Connect with your community and discover amazing opportunities around you.",
          image: const Center(
            child: Icon(
              Icons.waving_hand,
              size: 100.0,
              color: AppTheme.accentPrimary,
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
            bodyTextStyle: TextStyle(fontSize: 18.0, color: Colors.black54),
            pageColor: Colors.white,
            imagePadding: EdgeInsets.only(top: 60),
          ),
        ),
        PageViewModel(
          title: "Stay Connected",
          body: "Get to know what's happening around you.",
          image: const Center(
            child: Icon(
              Icons.chat_bubble_outline,
              size: 100.0,
              color: AppTheme.accentPrimary,
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
            bodyTextStyle: TextStyle(fontSize: 18.0, color: Colors.black54),
            pageColor: Colors.white,
            imagePadding: EdgeInsets.only(top: 60),
          ),
        ),
        PageViewModel(
          title: "Discover Events",
          body:
              "Find local events, new companies, and promotions happening in your community.",
          image: const Center(
            child: Icon(
              Icons.event,
              size: 100.0,
              color: AppTheme.accentPrimary,
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
            bodyTextStyle: TextStyle(fontSize: 18.0, color: Colors.black54),
            pageColor: Colors.white,
            imagePadding: EdgeInsets.only(top: 60),
          ),
        ),
        PageViewModel(
          title: "Get Started",
          body:
              "Ready to join your community? Let's create your account and get you connected!",
          image: const Center(
            child: Icon(
              Icons.rocket_launch,
              size: 100.0,
              color: AppTheme.accentPrimary,
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
            bodyTextStyle: TextStyle(fontSize: 18.0, color: Colors.black54),
            pageColor: Colors.white,
            imagePadding: EdgeInsets.only(top: 60),
          ),
        ),
      ],
      globalHeader: Container(
        padding: EdgeInsets.only(top: 50, right: 20),
        alignment: Alignment.topRight,
        child: TextButton(
          onPressed: () => _onIntroEnd(context),
          child: Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      onDone: () => _onIntroEnd(context),
      onSkip: () => _onIntroEnd(context),
      showSkipButton: false,
      showNextButton: true,
      showBackButton: true,
      // skip: const Text(
      //   'Skip',
      //   style: TextStyle(
      //     fontWeight: FontWeight.w600,
      //     color: AppTheme.accentPrimary,
      //   ),
      // ),
      next: const Icon(Icons.arrow_forward, color: AppTheme.accentPrimary),
      back: const Icon(Icons.arrow_back, color: AppTheme.accentPrimary),
      done: const Text(
        'Get Started',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppTheme.accentPrimary,
        ),
      ),
      dotsDecorator: DotsDecorator(
        size: const Size.square(10.0),
        activeSize: const Size(20.0, 10.0),
        activeColor: AppTheme.accentPrimary,
        color: Colors.black26,
        spacing: const EdgeInsets.symmetric(horizontal: 3.0),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25.0),
        ),
      ),
    );
  }

  Future<void> _onIntroEnd(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_intro', true);

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AppRouter()),
      );
    }
  }
}
