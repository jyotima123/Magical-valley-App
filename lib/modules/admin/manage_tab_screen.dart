import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/admin/categories_management_screen.dart';
import 'package:mvc_app/modules/admin/organizations_management_screen.dart';
import 'package:mvc_app/modules/admin/users_management_screen.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/widgets/management_button.dart';

class ManageTabScreen extends StatelessWidget {
  const ManageTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Manage'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManagementButton(
              icon: Icon(
                Icons.people_outline,
                color: AppTheme.iconBackground,
                size: AppTheme.iconSize,
              ),
              title: 'Users',
              subtitle: 'Manage user accounts and permissions',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const UsersManagementScreen(),
                ),
              ),
            ),
            ManagementButton(
              icon: Icon(
                Icons.business_outlined,
                color: AppTheme.iconBackground,
                size: AppTheme.iconSize,
              ),
              title: 'Channels',
              subtitle: 'Create and manage channels',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) => OrganizationsManagementScreen(),
                  ))
                  .then((_) {
                if (!context.mounted) return;
                context.read<ChatBloc>().add(LoadChannelsEvent());
              }),
            ),
            ManagementButton(
              icon: Icon(
                Icons.category_outlined,
                color: AppTheme.iconBackground,
                size: AppTheme.iconSize,
              ),
              title: 'Categories',
              subtitle: 'Manage content categories',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CategoriesManagementScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
