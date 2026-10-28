import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';

/// A single step in the app tour.
class TourStep {
  final String title;
  final String body;
  final IconData icon;

  /// Returns the [Rect] to spotlight, or null for a centered card with no spotlight.
  final Rect? Function()? anchorProvider;

  const TourStep({
    required this.title,
    required this.body,
    required this.icon,
    this.anchorProvider,
  });
}

/// Full-screen overlay that guides the user through [steps] one by one.
///
/// Place this widget in the topmost [Stack] of your scaffold so it renders
/// above all content. Remove it (or set [visible] = false) when done.
class AppTourOverlay extends StatefulWidget {
  final List<TourStep> steps;

  /// Called with the 0-based index of the step that just became visible.
  final void Function(int stepIndex) onStepShown;

  /// Called when the user taps "Done" on the last step.
  final VoidCallback onFinish;

  /// Called when the user taps "Skip".
  final VoidCallback onSkip;

  const AppTourOverlay({
    super.key,
    required this.steps,
    required this.onStepShown,
    required this.onFinish,
    required this.onSkip,
  });

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onStepShown(0),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _advance() {
    if (_currentStep + 1 >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    setState(() => _currentStep++);
    widget.onStepShown(_currentStep);
    _ctrl
      ..reset()
      ..forward();
  }

  Rect? _anchor() {
    final step = widget.steps[_currentStep];
    return step.anchorProvider?.call();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final anchor = _anchor();

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Dark overlay with optional spotlight hole
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSkip,
            child: CustomPaint(
              painter: _SpotlightPainter(anchor: anchor),
              size: size,
            ),
          ),
          // Tooltip card
          _positionedCard(size, anchor),
        ],
      ),
    );
  }

  Widget _positionedCard(Size screen, Rect? anchor) {
    const hPad = 20.0;
    double? top, bottom;

    if (anchor == null) {
      // Centered on screen
      top = screen.height / 2 - 110;
    } else if (anchor.bottom < screen.height * 0.55) {
      // Target is in the upper half → show card below
      top = anchor.bottom + 20;
    } else {
      // Target is in the lower half → show card above
      bottom = screen.height - anchor.top + 20;
    }

    return Positioned(
      left: hPad,
      right: hPad,
      top: top,
      bottom: bottom,
      child: _TourCard(
        step: widget.steps[_currentStep],
        stepIndex: _currentStep,
        totalSteps: widget.steps.length,
        onNext: _advance,
        onSkip: widget.onSkip,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spotlight painter — fills the screen with a dark overlay except for a
// rounded-rect "hole" around [anchor].
// ---------------------------------------------------------------------------
class _SpotlightPainter extends CustomPainter {
  final Rect? anchor;
  _SpotlightPainter({this.anchor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xB8000000);

    if (anchor == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(anchor!.inflate(10), const Radius.circular(16)),
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.anchor != anchor;
}

// ---------------------------------------------------------------------------
// Tour card
// ---------------------------------------------------------------------------
class _TourCard extends StatelessWidget {
  final TourStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = stepIndex == totalSteps - 1;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.headerBackground,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    step.icon,
                    color: AppTheme.accentPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryHeadingColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onSkip,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppTheme.secondaryHeadingColor.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Body text
            Text(
              step.body,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: AppTheme.primaryHeadingColor.withValues(alpha: 0.85),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            // Progress dots + Next/Done button
            Row(
              children: [
                _ProgressDots(
                  current: stepIndex,
                  total: totalSteps,
                ),
                const Spacer(),
                _NextButton(
                  label: isLast ? 'Done' : 'Next',
                  onTap: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;

  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 5),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accentPrimary
                : AppTheme.secondaryHeadingColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accentPrimary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
