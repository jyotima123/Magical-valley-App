import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main.dart';

class SignUpOtpExplanationScreen extends StatelessWidget {
  const SignUpOtpExplanationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: "We need to confirm your email address",
          body: "You will receive an email \nwith a 6-digit code",
          image: const Center(
            child: Icon(Icons.mail, size: 100.0, color: AppTheme.accentPrimary),
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
          title: "Can't find the email?",
          body:
              "Please check your spam folder as well, \nwe will need this code in the next step",
          image: const Center(
            child: Icon(
              Icons.password,
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
      onDone: () => _onIntroEnd(context),
      onSkip: () => _onIntroEnd(context),
      showSkipButton: true,
      showNextButton: true,
      showBackButton: true,
      skip: const Text(
        'Skip',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.accentPrimary,
        ),
      ),
      next: const Icon(Icons.arrow_forward, color: AppTheme.accentPrimary),
      back: const Icon(Icons.arrow_back, color: AppTheme.accentPrimary),
      done: const Text(
        'I have my code',
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
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool('has_seen_intro', true);

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AppRouter()),
        // MaterialPageRoute(
        //   builder: (context) =>
        //       const OtpVerificationScreen(email: 'alisson+4@fullpond.co'),
        // ),
      );
    }
  }
}
