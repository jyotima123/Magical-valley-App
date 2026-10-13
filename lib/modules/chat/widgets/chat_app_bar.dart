// lib/modules/chat/widgets/chat_app_bar.dart
// ignore_for_file: unnecessary_type_check

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/admin/manage_tab_screen.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/profile/profile_settings_screen.dart';
import 'package:mvc_app/services/api_repository.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController searchController;
  final int selectedTabIndex;
  final VoidCallback onChannelsTabTap;
  final VoidCallback onCategoriesTabTap;
  final VoidCallback onManageTabTap;
  final VoidCallback onCreateOrganization;
  final Function(ChatChannel?, String) onCreatePost;
  final VoidCallback onLogout;
  final AppThemeMode theme;
  final bool showBottomNavigation;
  final bool showSearchBar;
  final VoidCallback onToggleSearchBar;
  final VoidCallback onLogoTap;
  final bool enableSearchToggle;
  final PreferredSizeWidget? bottom;

  const ChatAppBar({
    super.key,
    required this.searchController,
    required this.selectedTabIndex,
    required this.onChannelsTabTap,
    required this.onCategoriesTabTap,
    required this.onManageTabTap,
    required this.onCreateOrganization,
    required this.onCreatePost,
    required this.onLogout,
    required this.theme,
    required this.showBottomNavigation,
    required this.showSearchBar,
    required this.onToggleSearchBar,
    required this.onLogoTap,
    this.enableSearchToggle = true,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        return AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppTheme.headerBackground,
          flexibleSpace: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: kToolbarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                children: [
                  GestureDetector(
                    onTap: onLogoTap,
                    child: Image.asset('assets/logo.png', height: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: showSearchBar
                        ? Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.searchBarBackground,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: TextField(
                              controller: searchController,
                              style: AppTheme.searchInput,
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                hintStyle: AppTheme.searchInput.copyWith(
                                  color: AppTheme.secondaryHeadingColor,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: AppTheme.secondaryHeadingColor,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: AppTheme.secondaryHeadingColor,
                                  ),
                                  onPressed: () {
                                    searchController.clear();
                                    onToggleSearchBar();
                                  },
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: AppTheme.searchBarBackground,
                              ),
                            ),
                          )
                        : Container(),
                  ),
                  if (!showSearchBar && enableSearchToggle)
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: onToggleSearchBar,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  ChatMenuButton(
                    onCreateOrganization: onCreateOrganization,
                    onCreatePost: onCreatePost,
                    onLogout: onLogout,
                    showSearchBar: showSearchBar,
                    onToggleSearchBar: onToggleSearchBar,
                    enableSearchToggle: enableSearchToggle,
                  ),
                ],
              ),
            ),
              ),
            ),
          ),
          bottom: bottom,
        );
      },
    );
  }
}

class BottomNavigationTabs extends StatelessWidget {
  final int selectedTabIndex;
  final VoidCallback onChannelsTabTap;
  final VoidCallback onCategoriesTabTap;
  final VoidCallback onManageTabTap;
  final bool isVisible;

  const BottomNavigationTabs({
    super.key,
    required this.selectedTabIndex,
    required this.onChannelsTabTap,
    required this.onCategoriesTabTap,
    required this.onManageTabTap,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: isVisible ? 60 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isVisible ? 1.0 : 0.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.headerBackground,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _buildTabButtons(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTabButtons() {
    final List<Widget> tabs = [];

    // Always add Channels tab
    tabs.add(
      Expanded(
        child: GestureDetector(
          onTap: onChannelsTabTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum,
                  color: selectedTabIndex == 0
                      ? AppTheme.accentPrimary
                      : Colors.grey,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  'Channels',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selectedTabIndex == 0
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selectedTabIndex == 0
                        ? AppTheme.accentPrimary
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Add Categories tab
    const categoriesIndex = 1;
    tabs.add(
      Expanded(
        child: GestureDetector(
          onTap: onCategoriesTabTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.explore,
                  color: selectedTabIndex == categoriesIndex
                      ? AppTheme.accentPrimary
                      : Colors.grey,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selectedTabIndex == categoriesIndex
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selectedTabIndex == categoriesIndex
                        ? AppTheme.accentPrimary
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return tabs;
  }
}

class ChatMenuButton extends StatelessWidget {
  final VoidCallback onCreateOrganization;
  final Function(ChatChannel?, String) onCreatePost;
  final VoidCallback onLogout;
  final bool showSearchBar;
  final VoidCallback onToggleSearchBar;
  final bool enableSearchToggle;

  const ChatMenuButton({
    super.key,
    required this.onCreateOrganization,
    required this.onCreatePost,
    required this.onLogout,
    required this.showSearchBar,
    required this.onToggleSearchBar,
    this.enableSearchToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        return BlocBuilder<ChatBloc, ChatState>(
          builder: (context, chatState) {
            String currentUserId = '';
            UserRole currentUserRole = UserRole.regular;
            if (authState is AuthAuthenticatedState) {
              currentUserId = authState.userId;
              currentUserRole = authState.userProfile?.role ?? UserRole.regular;
            }

            return PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (String value) {
                switch (value) {
                  case 'toggle_search':
                    onToggleSearchBar();
                    break;
                  case 'manage':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageTabScreen(),
                      ),
                    );
                    break;
                  case 'create_organization':
                    onCreateOrganization();
                    break;
                  case 'create_post':
                    if (chatState is ChatLoadedState) {
                      onCreatePost(chatState.selectedChannel, currentUserId);
                    }
                    break;
                  case 'edit':
                    print("EDIT PROFILE");
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    break;
                  case 'logout':
                    onLogout();
                    break;
                }
              },
              itemBuilder: (BuildContext context) {
                List<PopupMenuEntry<String>> menuItems = [];

                // User options section
                menuItems.addAll([
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 10),
                        Text('Info'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 10),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ]);

                // Admin options section (only for non-regular users)
                if (currentUserRole != UserRole.regular) {
                  menuItems.addAll([
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.settings, size: 20),
                          SizedBox(width: 10),
                          Text('Manage'),
                        ],
                      ),
                    ),
                  ]);
                }
                if (chatState is ChatLoadedState &&
                    currentUserRole != UserRole.regular) {
                  menuItems.addAll([
                    PopupMenuItem<String>(
                      value: 'create_organization',
                      enabled: chatState is ChatLoadedState,
                      child: Row(
                        children: [
                          Icon(
                            Icons.business,
                            size: 20,
                            color: (currentUserRole != UserRole.regular)
                                ? null
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          const Text('Create Organization'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'create_post',
                      enabled: chatState is ChatLoadedState,
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_box,
                            size: 20,
                            color: (currentUserRole != UserRole.regular)
                                ? null
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Create Post',
                            style: TextStyle(
                              color: (chatState is ChatLoadedState)
                                  ? null
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]);
                }

                return menuItems;
              },
            );
          },
        );
      },
    );
  }
}
