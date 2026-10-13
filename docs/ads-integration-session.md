# Ads Integration Session Documentation

**Date:** 2026-01-13
**Session Focus:** Adding ad size management and integrating ads into the chat feed

**Status:** ✅ Complete and Working

---

## Table of Contents

1. [Overview](#overview)
2. [Admin Panel Changes](#admin-panel-changes)
3. [Main App Changes](#main-app-changes)
4. [Database Changes](#database-changes)
5. [Testing and Debugging](#testing-and-debugging)
6. [Usage Instructions](#usage-instructions)

---

## Overview

This session implemented a complete ad system with two main components:
1. **Admin Panel**: Ad size management and ad preview functionality
2. **Main App**: Ad display integration within the chat message feed

### Key Features Implemented

- Ad size selection with predefined IAB standard sizes (300x250, 728x90, etc.)
- Live preview of ads in exact dimensions during creation/editing
- Automatic ad insertion in chat feed (1 ad per 3 messages)
- Medium Rectangle (300x250) ads displayed in chat
- Click-through functionality for ads
- Full dark mode support

---

## Admin Panel Changes

### 1. Database Migration: `049_ad_sizes.sql`

**Location:** `migrations/049_ad_sizes.sql`

**Purpose:** Creates ad size management system

**Tables Created:**
- `ad_sizes`: Stores available ad sizes with dimensions

**Fields:**
```sql
- id (UUID, primary key)
- name (VARCHAR, unique - e.g., "Medium Rectangle")
- width (INTEGER - pixel width)
- height (INTEGER - pixel height)
- is_active (BOOLEAN - for enabling/disabling sizes)
- display_order (INTEGER - for sorting in dropdowns)
- created_at (TIMESTAMP)
- updated_at (TIMESTAMP)
```

**Pre-populated Sizes:**

Desktop/Tablet:
- Medium Rectangle: 300x250
- Leaderboard: 728x90
- Half-Page: 300x600
- Large Rectangle: 336x280
- Wide Skyscraper: 160x600
- Billboard: 970x250
- Portrait: 300x1050

Mobile:
- Mobile Banner: 300x50
- Large Mobile Banner: 320x100
- Mobile Leaderboard: 320x50

**Modifications to Existing Tables:**
- Added `ad_size_id` foreign key to `ads` table

**RLS Policies:**
- Anyone can view active ad sizes
- Super admins have full CRUD access
- Cascading delete prevention for sizes in use

**Views Created:**
- `ad_sizes_with_usage`: Shows ad sizes with usage count

### 2. Ad Size Model

**Location:** `ads_admin_panel/lib/models/ad_size_model.dart`

**Purpose:** Dart representation of ad sizes

**Key Features:**
```dart
class AdSizeModel {
  final String id;
  final String name;          // "Medium Rectangle"
  final int width;            // 300
  final int height;           // 250
  final bool isActive;
  final int displayOrder;

  // Computed properties
  String get displaySize;           // "300 x 250"
  String get displayNameWithSize;   // "Medium Rectangle (300 x 250)"
  double get aspectRatio;           // width / height
}
```

### 3. Ad Size Service

**Location:** `ads_admin_panel/lib/services/ad_size_service.dart`

**Purpose:** Fetch ad sizes from Supabase

**Methods:**
```dart
Future<List<AdSizeModel>> getAdSizes()
Future<AdSizeModel?> getAdSizeById(String id)
```

**Features:**
- Fetches only active sizes
- Sorted by display_order and name
- Error handling with exception messages

### 4. Updated Ad Model

**Location:** `ads_admin_panel/lib/models/ad_model.dart`

**Changes:**
- Added `adSizeId` field (nullable String)
- Updated constructor, fromJson, toJson, copyWith
- Added to equality comparison (props)

### 5. Ad Form Screen Updates

**Location:** `ads_admin_panel/lib/screens/ad_form_screen.dart`

**Major Changes:**

#### New State Variables:
```dart
List<AdSizeModel> _adSizes = [];
AdSizeModel? _selectedAdSize;
bool _isLoadingSizes = true;
```

#### New Methods:
```dart
Future<void> _loadAdSizes()  // Loads available ad sizes on init
```

#### UI Components Added:

**Ad Size Dropdown:**
```dart
DropdownButtonFormField<AdSizeModel>(
  items: _adSizes.map((size) => DropdownMenuItem(
    value: size,
    child: Text(size.displayNameWithSize),
  )).toList(),
  validator: (value) => value == null ? 'Please select ad size' : null,
)
```

**Live Preview Section:**
- Shows ad at exact pixel dimensions (e.g., 300x250)
- Updates dynamically when size or image changes
- Displays actual size label
- Includes helpful text: "This is how your ad will appear at actual size"
- Maintains aspect ratio with BoxFit.cover
- Bordered container with theme-aware styling

**Layout Structure:**
1. Ad Image section (existing)
2. Image picker button
3. **NEW:** Ad Size dropdown
4. **NEW:** Live preview at selected dimensions
5. Ad Details section (existing)
6. Schedule section (existing)

### 6. Ad Service Update

**Location:** `ads_admin_panel/lib/services/ad_service.dart`

**Changes:**
- No changes needed
- `ad_size_id` automatically handled by updated AdModel.toJson()

---

## Main App Changes

### 1. Ad Model (Main App)

**Location:** `lib/models/ad_model.dart`

**Purpose:** Lightweight ad representation for displaying in chat

**Fields:**
```dart
class AdModel {
  final String id;
  final String title;
  final String? description;
  final String imageUrl;
  final String linkUrl;
  final DateTime startDate;
  final DateTime endDate;
  final String? adSizeId;
  final int? width;
  final int? height;

  bool get isActive;  // Checks if ad is currently in date range
}
```

**Key Difference from Admin Model:**
- Simpler model with only display-relevant fields
- No payment/status fields
- Includes dimensions directly (no need to join ad_sizes)

### 2. Ad Service (Main App)

**Location:** `lib/services/ad_service.dart`

**Purpose:** Fetch active Medium Rectangle ads from Supabase

**Key Design Decision:** Uses **hardcoded ad size IDs** instead of querying `ad_sizes` table, since these IDs are fixed and seeded in the database. This eliminates an extra query and improves performance.

**Hardcoded Constants:**
```dart
static const String mediumRectangleId = 'f4e532a9-2102-4a19-b0ab-b59e87d70479'; // 300x250
static const String leaderboardId = '18ef3f86-c86e-4bf2-91ba-e2129c461b2b'; // 728x90
// ... all other ad sizes
```

**Methods:**

#### `getRandomMediumRectangleAd()`
Returns a single random Medium Rectangle ad.

#### `getRandomMediumRectangleAds({int count = 5})`
Returns multiple ads for variety. Used by chat view to pre-load ad pool.

**Query Pattern:**
```dart
_client.from('ads')
  .select('*, ad_sizes!ad_size_id(id, name, width, height)')
  .eq('ad_size_id', mediumRectangleId)
  .eq('status', 'active')
  .eq('payment_status', 'succeeded')
  .lte('start_date', now)
  .gte('end_date', now)
```

**Important:** The join syntax `ad_sizes!ad_size_id` explicitly specifies the foreign key relationship: `ads.ad_size_id` → `ad_sizes.id`.

**Debug Logging:** Comprehensive logging with emoji prefixes (🎯, 📊, ✅, ⚠️, ❌) for easy filtering in console.

### 3. Ad Widget

**Location:** `lib/modules/chat/widgets/ad_widget.dart`

**Purpose:** Display ad in chat feed with proper styling

**Features:**

#### Visual Elements:
1. "SPONSORED" label (top, uppercase, small font)
2. 300x250 image container
3. "Ad" badge overlay (top-right corner)
4. Optional ad title below image

#### Styling:
- Rounded corners (12px border radius)
- Border matching theme
- Box shadow for depth
- Dark mode support
- Semi-transparent black badge background

#### Interaction:
- Entire ad is clickable
- Opens `linkUrl` in external browser
- Uses `url_launcher` package

#### Error Handling:
- Loading placeholder with spinner
- Error state with broken image icon
- "Ad not available" fallback message

#### Performance:
- Cached network images
- Specific cache dimensions (300x250)
- Memory and disk cache optimization

### 4. Chat View Integration

**Location:** `lib/modules/chat/widgets/chat_view.dart`

**Major Changes:**

#### Updated `_MessageListItem` Class:
```dart
class _MessageListItem {
  final ChatMessage? message;
  final String? dateDivider;
  final bool isAd;  // NEW

  bool get isMessage => message != null && !isAd;
  bool get isDateDivider => dateDivider != null;
  bool get isAdItem => isAd;  // NEW
}
```

#### New State Variables:
```dart
List<AdModel> _availableAds = [];
bool _isLoadingAds = false;
```

#### New Methods:

**`_loadAds()`:**
```dart
Future<void> _loadAds() async {
  final ads = await AdService.instance.getRandomMediumRectangleAds(count: 10);
  setState(() {
    _availableAds = ads;
  });
}
```
- Called in `initState()`
- Loads 10 ads for variety
- Stores in state for message list building
- Debug logging for troubleshooting

**Updated `_buildMessageListItems()`:**
```dart
List<_MessageListItem> _buildMessageListItems(List<ChatMessage> messages) {
  List<_MessageListItem> items = [];
  int messagesSinceLastAd = 0;

  for (final message in messages) {
    // Add date divider if needed
    // Add message
    items.add(_MessageListItem(message: message));
    messagesSinceLastAd++;

    // Insert ad every 3 messages
    if (messagesSinceLastAd >= 3 && _availableAds.isNotEmpty) {
      items.add(_MessageListItem(isAd: true));
      messagesSinceLastAd = 0;
    }
  }

  return items;
}
```

**Ad Insertion Logic:**
- Tracks message count since last ad
- Inserts ad after every 3 messages
- Resets counter after ad insertion
- Only inserts if ads are available
- Maintains date dividers properly

#### Updated `_buildOptimizedMessageList()` ListView Builder:

**Ad Rendering:**
```dart
if (item.isAdItem && _availableAds.isNotEmpty) {
  final adIndex = (adjustedIndex ~/ 4) % _availableAds.length;
  final ad = _availableAds[adIndex];

  return RepaintBoundary(
    key: ValueKey('ad_$adjustedIndex'),
    child: AdWidget(ad: ad, theme: widget.theme),
  );
}
```

**Ad Rotation:**
- Uses modulo to cycle through available ads
- Different ads shown at different positions
- Prevents repetition with 10-ad pool

**Performance:**
- Wrapped in `RepaintBoundary` for isolation
- Unique `ValueKey` for proper recycling
- Efficient rendering with cached images

#### Import Additions:
```dart
import 'package:mvc_app/models/ad_model.dart';
import 'package:mvc_app/services/ad_service.dart';
import 'ad_widget.dart';
```

---

## Database Changes

### Schema Updates

#### New Table: `ad_sizes` (Migration 049)
Stores predefined ad sizes with IAB standard dimensions.

**Key Fields:**
- `id` (UUID): Unique identifier - **Fixed IDs seeded in migration**
- `name` (VARCHAR): Display name (e.g., "Medium Rectangle")
- `width`, `height` (INTEGER): Pixel dimensions
- `is_active` (BOOLEAN): Enable/disable sizes
- `display_order` (INTEGER): Sort order in dropdowns

**Important:** The ad size IDs are **fixed and constant** - they're seeded in the migration and never change. This allows hardcoding them in the app for better performance.

#### Modified Table: `ads` (Migration 049)
```sql
ALTER TABLE ads ADD COLUMN ad_size_id UUID REFERENCES ad_sizes(id);
```

**Relationship:** `ads.ad_size_id` → `ad_sizes.id` (many-to-one)

### RLS Policies

#### `ad_sizes` table (Migration 049):
- ✅ Anyone can view active ad sizes (for dropdown selection)
- ✅ Super admins have full CRUD access

#### `ads` table (Migration 050 - Critical Fix):
- ✅ **Anyone can view active ads** (status='active', payment='succeeded', within date range)
- ✅ Super admins can view all ads
- ✅ Advertisers can view their own ads

**Important:** The public access policy for ads was added in migration 050 to fix a 401 unauthorized error when fetching ads in the main app.

### Indexes

#### Performance Indexes:
```sql
CREATE INDEX idx_ad_sizes_active ON ad_sizes(is_active, display_order);
CREATE INDEX idx_ad_sizes_dimensions ON ad_sizes(width, height);
CREATE INDEX idx_ads_size ON ads(ad_size_id);
```

### Views

#### `ad_sizes_with_usage`
```sql
CREATE VIEW ad_sizes_with_usage AS
SELECT
    ads.id, ads.name, ads.width, ads.height,
    ads.is_active, ads.display_order,
    COUNT(a.id) AS ads_count
FROM ad_sizes ads
LEFT JOIN ads a ON a.ad_size_id = ads.id
GROUP BY ads.id
ORDER BY ads.display_order, ads.name;
```

---

## Testing and Debugging

### Debug Logging Added

All logging uses emoji prefixes for easy filtering:

**Ad Service:**
- 🎯 Query initiation
- 📊 Query results
- ✅ Success messages
- ⚠️ Warnings (no ads found)
- ❌ Error messages

**Chat View:**
- 🚀 Ad loading start
- 💾 Ads loaded into state
- 🎬 Message list building
- 📺 Ad insertion/rendering
- 📋 List build summary

### How to Test

#### 1. Database Setup
```bash
# Run the migration
psql -d your_database -f migrations/049_ad_sizes.sql
```

#### 2. Create Test Ad in Admin Panel
1. Open admin panel
2. Create new ad
3. Select "Medium Rectangle (300 x 250)" from dropdown
4. Upload image
5. Preview shows at exact 300x250 dimensions
6. Set dates (ensure ad is currently active)
7. Set status to "active" and payment_status to "succeeded"
8. Save ad

#### 3. View Ads in Main App
1. Open main app
2. Navigate to chat
3. Check console logs for:
   - `🚀 ChatView: Starting to load ads...`
   - `🎯 Fetching 10 ads for time: ...`
   - `📊 Ads query response length: X`
   - `✅ Loaded X ads successfully`
   - `💾 ChatView: Loaded X ads into state`
4. Scroll through messages
5. Look for:
   - `🎬 Building message list with X messages and Y available ads`
   - `📺 Inserting ad at position X`
   - `📺 Rendering ad at index X`

#### 4. Verify Ad Display
- Check for "SPONSORED" label
- Verify 300x250 dimensions
- Check "Ad" badge overlay
- Test click functionality
- Verify dark mode appearance

### Common Issues and Solutions

#### Issue: 401 Unauthorized Error (CRITICAL - FIXED)

**Symptom:**
```
GET | 401 | /rest/v1/ads?select=*%2Cad_sizes...
```

**Root Cause:** The `ads` table had RLS policies that only allowed:
- Super admins to view all ads
- Advertisers to view their own ads

But there was **no policy** allowing public/anonymous users to view active ads!

**Solution:** Run migration `050_public_ads_access.sql`
```sql
CREATE POLICY "Anyone can view active ads" ON ads FOR SELECT
USING (status = 'active' AND payment_status = 'succeeded'
       AND start_date <= NOW() AND end_date >= NOW());
```

**Status:** ✅ Fixed in migration 050

---

#### Issue: "No ads found in database"

**Possible Causes:**
- Migrations 049 and 050 not run
- No ads created with Medium Rectangle size
- Ads not active or payment not succeeded
- Ads outside date range

**Quick Check:**
```sql
-- Verify ad exists with correct size
SELECT a.id, a.title, a.status, a.payment_status,
       a.ad_size_id, s.name, s.width, s.height
FROM ads a
JOIN ad_sizes s ON a.ad_size_id = s.id
WHERE s.width = 300 AND s.height = 250;
```

---

#### Issue: Ads not appearing in chat

**Possible Causes:**
- Less than 3 messages in channel (ads appear every 3 messages)
- Console shows `⚠️ No ads found in database`
- RLS policy issue (check for 401 errors)

**Debug Steps:**
1. Check console: `💾 ChatView: Loaded X ads` - should be > 0
2. Check console: `📺 Inserting ad at position X` - confirms ad insertion
3. Verify at least 6+ messages in chat
4. Run SQL query above to verify ads exist

---

#### Issue: Wrong ad size ID

**Symptom:** Query returns 0 ads even though ads exist

**Cause:** Using wrong ad size ID or incorrect relationship direction

**Solution:** Use the correct hardcoded ID from `AdService`:
```dart
static const String mediumRectangleId = 'f4e532a9-2102-4a19-b0ab-b59e87d70479';
```

Ensure join uses correct relationship: `ad_sizes!ad_size_id` (ads.ad_size_id → ad_sizes.id)

---

## Usage Instructions

### For Admin Panel Users

#### Creating an Ad with Size Selection:

1. **Navigate to Create Ad page**
2. **Upload ad image** (any dimension initially)
3. **Select Ad Size** from dropdown
   - Choose from predefined sizes
   - Example: "Medium Rectangle (300 x 250)"
4. **View Live Preview**
   - Preview shows image at exact selected dimensions
   - Helps ensure image looks good at actual size
5. **Fill in remaining details** (title, link, dates, amount)
6. **Save ad**

#### Best Practices:

- **Image Quality:** Upload images at or above the target dimensions
- **Aspect Ratio:** Match image aspect ratio to selected size when possible
- **Preview Check:** Always review the live preview before saving
- **Multiple Sizes:** Create different versions of ads for different sizes
- **Testing:** Check ad appearance in main app after creation

### For End Users (Main App)

#### Viewing Ads:

- Ads appear automatically in chat feed
- 1 ad per 3 messages
- Labeled as "SPONSORED"
- "Ad" badge for clear identification
- Fully clickable

#### Interacting with Ads:

- **Click:** Opens advertiser's website in external browser
- **Scroll past:** Ads don't interrupt reading flow
- **Dark mode:** Ads adapt to theme automatically

---

## File Structure

### Admin Panel Files:
```
ads_admin_panel/
├── lib/
│   ├── models/
│   │   ├── ad_size_model.dart          (NEW)
│   │   └── ad_model.dart                (MODIFIED - added adSizeId)
│   ├── services/
│   │   └── ad_size_service.dart        (NEW)
│   └── screens/
│       └── ad_form_screen.dart          (MODIFIED - size selector & preview)
```

### Main App Files:
```
mvc_app/
├── lib/
│   ├── models/
│   │   └── ad_model.dart                (NEW)
│   ├── services/
│   │   └── ad_service.dart              (NEW - with hardcoded size IDs)
│   └── modules/chat/widgets/
│       ├── ad_widget.dart               (NEW)
│       └── chat_view.dart               (MODIFIED - ad integration)
├── migrations/
│   ├── 049_ad_sizes.sql                (NEW - ad sizes table)
│   └── 050_public_ads_access.sql       (NEW - CRITICAL: fixes 401 error)
└── docs/
    └── ads-integration-session.md       (NEW - this file)
```

---

## Performance Considerations

### Optimization Strategies Implemented:

1. **Ad Pre-loading:**
   - Loads 10 ads on chat view init
   - Prevents per-message queries
   - Uses singleton pattern for service

2. **Image Caching:**
   - `cached_network_image` package
   - Memory cache: 300x250 dimensions
   - Disk cache for persistence
   - Reduces network requests

3. **RepaintBoundary:**
   - Isolates ad widgets
   - Prevents unnecessary repaints
   - Improves scroll performance

4. **Ad Rotation:**
   - Modulo-based cycling
   - Prevents same ad repetition
   - Distributes impressions evenly

5. **ListView Optimization:**
   - Only visible items rendered
   - Efficient recycling with ValueKey
   - Minimal rebuild on scroll

### Performance Metrics to Monitor:

- Ad load time (should be < 1 second)
- Chat scroll FPS (should maintain 60fps)
- Memory usage with 10 cached ads
- Network bandwidth for ad images

---

## Future Enhancements

### Potential Improvements:

1. **Ad Analytics:**
   - Track impressions (views)
   - Track clicks
   - Calculate CTR (Click-Through Rate)
   - Revenue reporting

2. **Ad Targeting:**
   - User demographics
   - Interest-based targeting
   - Location-based ads
   - Time-of-day targeting

3. **More Ad Sizes:**
   - Support all IAB standard sizes
   - Dynamic size selection in chat
   - Responsive ads

4. **Ad Frequency Control:**
   - Configurable ads per X messages
   - Time-based frequency capping
   - User preference for ad density

5. **A/B Testing:**
   - Test different ad positions
   - Test different ad creatives
   - Optimize for performance

6. **Ad Blocking Detection:**
   - Detect if ads are hidden
   - Alternative monetization strategies
   - User feedback for hidden ads

---

## Troubleshooting Guide

### Console Log Analysis

#### Expected Log Sequence:
```
🚀 ChatView: Starting to load ads...
🎯 Fetching 10 ads for time: 2026-01-12T10:30:00.000Z
📊 Ads query response length: 3
✅ Loaded 3 ads successfully
💾 ChatView: Loaded 3 ads into state
🎬 Building message list with 15 messages and 3 available ads
📺 Inserting ad at position 4
📺 Inserting ad at position 8
📺 Inserting ad at position 12
📋 Built 18 list items (15 messages, 3 ads)
📺 Rendering ad at index 4 (ad 1/3)
📺 Rendering ad at index 8 (ad 2/3)
📺 Rendering ad at index 12 (ad 3/3)
```

#### If you see "⚠️ No ads found in database":
1. Check migration was run successfully
2. Verify ads exist with Medium Rectangle size
3. Check ad dates are valid
4. Verify status='active' and payment_status='succeeded'

#### If you see "❌ Error fetching ads":
1. Check Supabase connection
2. Verify RLS policies
3. Check network connectivity
4. Review Supabase logs for detailed error

### SQL Debugging Queries

```sql
-- Check ad_sizes table
SELECT * FROM ad_sizes ORDER BY display_order;

-- Check ads with sizes
SELECT
    a.id, a.title, a.status, a.payment_status,
    a.start_date, a.end_date,
    s.name as size_name, s.width, s.height
FROM ads a
LEFT JOIN ad_sizes s ON a.ad_size_id = s.id
ORDER BY a.created_at DESC;

-- Check active ads in date range
SELECT
    a.id, a.title,
    a.start_date <= NOW() as started,
    a.end_date >= NOW() as not_expired,
    s.width, s.height
FROM ads a
JOIN ad_sizes s ON a.ad_size_id = s.id
WHERE a.status = 'active'
  AND a.payment_status = 'succeeded';

-- Find ads that should be showing
SELECT
    a.id, a.title,
    s.name as size_name
FROM ads a
JOIN ad_sizes s ON a.ad_size_id = s.id
WHERE a.status = 'active'
  AND a.payment_status = 'succeeded'
  AND a.start_date <= NOW()
  AND a.end_date >= NOW()
  AND s.width = 300
  AND s.height = 250;
```

---

## Migration Rollback

If you need to rollback the changes:

```sql
-- Rollback migration 050 (public ads access)
DROP POLICY IF EXISTS "Anyone can view active ads" ON ads;

-- Rollback migration 049 (ad sizes)
ALTER TABLE ads DROP COLUMN IF EXISTS ad_size_id;
DROP INDEX IF EXISTS idx_ads_size;
DROP INDEX IF EXISTS idx_ad_sizes_active;
DROP INDEX IF EXISTS idx_ad_sizes_dimensions;
DROP VIEW IF EXISTS ad_sizes_with_usage;
DROP POLICY IF EXISTS "Anyone can view active ad sizes" ON ad_sizes;
DROP POLICY IF EXISTS "Super admins can view all ad sizes" ON ad_sizes;
DROP POLICY IF EXISTS "Super admins can insert ad sizes" ON ad_sizes;
DROP POLICY IF EXISTS "Super admins can update ad sizes" ON ad_sizes;
DROP POLICY IF EXISTS "Super admins can delete ad sizes" ON ad_sizes;
DROP TABLE IF EXISTS ad_sizes CASCADE;
```

---

## Summary

This session successfully implemented:

✅ **Admin Panel:** Ad size management with live preview at exact dimensions
✅ **Main App:** Ad integration in chat feed (1 ad per 3 messages)
✅ **Database:** Ad sizes table with fixed IAB standard IDs
✅ **Services:** Optimized ad fetching with hardcoded size IDs
✅ **UI Components:** Responsive ad widget with dark mode support
✅ **Performance:** Single-query fetching, RepaintBoundary, cached images
✅ **RLS Policies:** Public access to active ads (fixed 401 error)
✅ **Debug Tools:** Comprehensive emoji-tagged logging

**Files Created:** 7 new files
**Files Modified:** 3 files
**Database Objects:** 1 table, 3 indexes, 6 policies, 1 view
**Migrations:** 2 (049_ad_sizes.sql, 050_public_ads_access.sql)

### Key Technical Decisions:

1. **Hardcoded Ad Size IDs:** Since ad sizes are seeded with fixed UUIDs, we hardcode them in the service for better performance (no extra query needed).

2. **Relationship Direction:** `ads.ad_size_id` → `ad_sizes.id` (many-to-one). The ad references a predefined size, not the other way around.

3. **Public RLS Policy:** Critical for allowing anonymous users to view active ads in the main app. Without this, all ad queries return 401.

4. **Ad Frequency:** 1 ad per 3 messages. Configurable by changing the counter in `_buildMessageListItems()`.

5. **Medium Rectangle Only:** Currently only 300x250 ads are shown in chat, but the system supports all IAB sizes for future expansion.

---

**Status:** ✅ **COMPLETE AND TESTED**

**End of Documentation**
