# Persistent Bottom Navigation Implementation

## Summary
Implemented persistent bottom navigation tabs that remain visible across all screens after user authentication.

## Changes Made

### 1. Created `/lib/main_scaffold.dart`
- **New file**: Main wrapper widget that provides persistent bottom navigation
- **Features**:
  - Uses `BottomNavigationBar` with 3 tabs: Channels, Manage (admin only), Explore
  - Uses nested `Navigator` for each tab to enable deep navigation while keeping tabs visible
  - Supports role-based tab visibility (Manage tab only shows for admin/superadmin users)
  - Handles back button properly with `WillPopScope`
  - Uses `Offstage` widgets to preserve state when switching tabs

### 2. Modified `/lib/main.dart`
- **Line 30**: Added import for `main_scaffold.dart`
- **Line 329**: Changed `_getHomeScreen()` to return `MainScaffold()` instead of `RealChatScreen()`
  - This ensures the persistent navigation wrapper is the root authenticated screen

### 3. Modified `/lib/modules/chat/real_chat_scree.dart`
- **Simplified**:
  - Now focuses only on displaying Channels content
  - Removed `TickerProviderStateMixin` since TabController is no longer needed
  - Removed unused methods `_isAdminUser()`, `_refreshChatChannels()`, helper methods for tab indices

### 4. Architecture

```
Before:
AuthFlow -> RealChatScreen (with internal TabBar for Channels/Manage/Explore)

After:
AuthFlow -> MainScaffold (persistent BottomNavigationBar)
            ├── Tab 0: RealChatScreen (Channels only)
            ├── Tab 1: ManageScreen (admin only)
            └── Tab 2: CategoriesGridScreen (Explore)
```

## Benefits

1. **Persistent Navigation**: Bottom tabs are now visible across ALL screens, including:
   - Settings/Profile screens
   - Individual chat messages
   - Create organization screens
   - User management screens
   - Any other navigation within the app

2. **Better UX**: Users can quickly switch between main sections without navigating back

3. **Role-Based UI**: Manage tab automatically shows/hides based on user role

4. **State Preservation**: Each tab maintains its navigation stack independently using nested navigators

## How It Works

The `MainScaffold` widget:
1. Creates 3 separate `Navigator` instances (one for each tab)
2. Wraps each navigator in an `Offstage` widget
3. Shows/hides navigators based on selected tab
4. Each tab can have its own navigation stack (push/pop screens)
5. Bottom navigation bar remains fixed regardless of navigation depth

## Testing

After logging in or signing up:
1. Navigate to any screen (Settings, individual chats, etc.)
2. Bottom tabs should remain visible
3. Tap any bottom tab to switch between sections
4. Each tab should maintain its navigation state
5. **Navigate from Explore to Channels**: 
   - Go to Explore tab
   - Tap a category
   - Tap an organization/channel
   - Should switch to Channels tab and open that channel ✨

## Additional Fix: Cross-Tab Navigation

### Problem
When tapping a channel from the Explore tab (Categories → Organizations → Channel), the app would just go back to the categories screen instead of switching to the Channels tab and opening the selected channel.

### Solution
Added a **global key mechanism** to enable cross-tab navigation:

1. **Created `mainScaffoldKey`**: Global key exported from `main_scaffold.dart` to access MainScaffold from anywhere
2. **Added `switchToChannelsTab()` method**: Public method in MainScaffold that:
   - Switches to Channels tab (index 0)
   - Optionally selects a channel by organization ID
   - Uses ChatBloc to trigger channel selection
3. **Updated `organizations_screen.dart`**: 
   - When tapping a channel, pops back to root of Explore navigator
   - Uses global key to call `switchToChannelsTab(organizationId: ...)`
   - This triggers tab switch and channel selection

### Files Modified for Fix
- `lib/main_scaffold.dart`: Added global key and `switchToChannelsTab()` method
- `lib/main.dart`: Pass global key to MainScaffold
- `lib/modules/chat/organizations_screen.dart`: Updated `_navigateToChat()` to use new mechanism

## Notes

- The Manage tab only appears for users with 'admin' or 'superadmin' roles
- All existing functionality remains the same
- Cross-tab navigation now works seamlessly between Explore → Channels
- The global key pattern allows any screen to trigger tab switches when needed

