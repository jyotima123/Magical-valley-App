// Add this to your main.dart file or create a separate qa_badge_widget.dart file
import 'package:flutter/material.dart';
import 'package:mvc_app/flavour_config.dart';

class QABadgeOverlay extends StatelessWidget {
  final Widget child;

  const QABadgeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (_shouldShowQABadge())
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: MediaQuery.of(context).size.width / 2,
            child: const _QABadge(),
          ),
      ],
    );
  }

  bool _shouldShowQABadge() {
    // Check if current environment is QA
    return FlavorConfig.supabaseEnvironment == 'qa';
  }
}

class _QABadge extends StatelessWidget {
  const _QABadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'QA',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Alternative approach - wrap each screen individually
class QABadgeWrapper extends StatelessWidget {
  final Widget child;

  const QABadgeWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (FlavorConfig.supabaseEnvironment != 'qa') {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 10,
          child: const _QABadge(),
        ),
      ],
    );
  }
}
