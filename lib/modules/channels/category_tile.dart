// lib/widgets/category_tile.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/organizations_screen.dart';
import 'package:mvc_app/utils/profile_utils.dart';

class CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasContent;
  final String? categoryId;
  final VoidCallback? onOrganizationFollowChanged; // Add callback

  const CategoryTile({
    super.key,
    required this.icon,
    required this.label,
    this.hasContent = false,
    this.categoryId,
    this.onOrganizationFollowChanged, // Add callback parameter
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (hasContent) {
          // Check if profile needs completion before accessing explore categories
          final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
            context,
            message: 'Please complete your profile to explore and discover channels.',
          );

          if (canContinue && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OrganizationsScreen(
                  categoryId: categoryId,
                  categoryName: label,
                  onOrganizationFollowChanged:
                      onOrganizationFollowChanged, // Pass callback
                ),
              ),
            );
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: hasContent ? AppTheme.white : AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: hasContent
              ? Border.all(
                  color: AppTheme.accentSecondary.withOpacity(0.1),
                  width: 1,
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: hasContent ? AppTheme.accentPrimary : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: hasContent ? FontWeight.w600 : FontWeight.normal,
                  color: hasContent ? Colors.black : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
