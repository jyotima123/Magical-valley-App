import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';

class AppDialog extends StatelessWidget {
  final IconData icon;
  final String heading;
  final String? subheading;
  final bool dismissible;
  final Duration? autoCloseDuration;
  final String okButtonText;
  final double? opacity;
  final VoidCallback? onOkPressed;

  const AppDialog({
    super.key,
    required this.icon,
    required this.heading,
    this.subheading,
    this.dismissible = true,
    this.autoCloseDuration,
    this.okButtonText = 'OK',
    this.opacity,
    this.onOkPressed,
  });

  static Future<void> show({
    required BuildContext context,
    required IconData icon,
    required String heading,
    String? subheading,
    bool dismissible = true,
    Duration? autoCloseDuration,
    String okButtonText = 'OK',
    double? opacity,
    VoidCallback? onOkPressed,
  }) async {
    // Auto close only when non-dismissible and a duration is provided
    if (!dismissible && autoCloseDuration != null) {
      // Schedule auto close after dialog is displayed
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(autoCloseDuration);
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          // ignore: use_build_context_synchronously
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: dismissible,
      builder: (ctx) => AppDialog(
        icon: icon,
        heading: heading,
        subheading: subheading,
        dismissible: dismissible,
        autoCloseDuration: autoCloseDuration,
        okButtonText: okButtonText,
        opacity: opacity,
        onOkPressed: onOkPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showOk = dismissible || onOkPressed != null;
    final double resolvedOpacity = opacity != null
        ? opacity!.clamp(0.0, 1.0)
        : 1.0;

    return Dialog(
      backgroundColor: Colors.white.withOpacity(resolvedOpacity),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Opacity(
            opacity: resolvedOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.accentPrimary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 48, color: AppTheme.accentPrimary),
                ),
                const SizedBox(height: 20),
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  style: AppTheme.managementTitleText.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subheading != null && subheading!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subheading!,
                    textAlign: TextAlign.center,
                    style: AppTheme.secondaryHeading.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
                if (showOk) ...[
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (onOkPressed != null) {
                          onOkPressed!();
                        }
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        okButtonText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
