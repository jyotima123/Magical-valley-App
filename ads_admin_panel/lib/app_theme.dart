import 'package:flutter/material.dart';

/// Theme mode enum
enum AppThemeMode { light, dark }

/// App theme and styling configuration
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  // Light Theme Color Constants
  static const Color logoColor = Color(0xFFF58868);
  static const Color headerBackground = Color(0xFFEFEDEE);
  static const Color searchBarBackground = Color(0xFFE6E3DF);
  static const Color hamburgerMenu = Color(0xFFD9D9D9);
  static const Color secondaryHeadingColor = Color(0xFFA6A6A6);
  static const Color primaryHeadingColor = Color(0xFF716D62);
  static const Color accentPrimary = Color(0xFFF48867);
  static const Color accentSecondary = Color(0xBFF58868); // 75% opacity
  static const Color cardGreyBackground = Color(0xFFF2F2F2);
  static const Color dividerBackground = Color(0xFFEFEDEE);
  static const Color messageBackground = Color(0xFFF1F1F1);

  static const Color iconBackground = Color.fromRGBO(117, 117, 117, 1);
  static const double iconSize = 24.0;

  // Dark Theme Color Constants
  static const Color darkBackground = Color(0xFF1A1A1A);
  static const Color darkSurface = Color(0xFF2D2D2D);
  static const Color darkCardBackground = Color(0xFF2D2D2D);
  static const Color darkInputBackground = Color(0xFF424242); // grey[800]
  static const Color darkBottomBarBackground = Color(0xFF212121); // grey[900]
  static const Color darkBorder = Color(0xFF424242); // grey[800]
  static const Color darkText = Colors.white;
  static const Color darkTextSecondary = Color(0xB3FFFFFF); // white70
  static const Color darkTextHint = Color(0x61FFFFFF); // white38
  static const Color darkTextTertiary = Color(0x99FFFFFF); // grey[600]
  static const Color darkDisabledButton = Color(0xFF757575); // grey[600]

  // Pinned Posts Colors - Light Theme
  static const Color pinnedPostsBackgroundLight = Color(
    0xFFFDF8F6,
  ); // Very light orange tint
  static const Color pinnedPostsBorderLight = Color(
    0xFFE8D5CF,
  ); // Light brown border
  static const Color pinnedPostsHeaderLight = Color(
    0xFF8B6B47,
  ); // Warm brown for headers
  static const Color pinnedPostsPreviewLight = Color(
    0xFF9E7B5A,
  ); // Medium brown for preview text
  static const Color pinnedIconColorLight = Color(
    0xFFF48867,
  ); // Match accent primary

  // Pinned Posts Colors - Dark Theme
  static const Color pinnedPostsBackgroundDark = Color(
    0xFF2A1F1A,
  ); // Dark warm background
  static const Color pinnedPostsBorderDark = Color(
    0xFF4A3529,
  ); // Dark brown border
  static const Color pinnedPostsHeaderDark = Color(
    0xFFD4B89E,
  ); // Light brown for dark headers
  static const Color pinnedPostsPreviewDark = Color(
    0xFFB89A7D,
  ); // Medium brown for dark preview
  static const Color pinnedIconColorDark = Color(
    0xFFF58868,
  ); // Match logo color

  // Additional common colors
  static const Color white = Colors.white;
  static const Color black = Color.fromARGB(255, 28, 28, 28);
  static const Color transparent = Colors.transparent;
  static const Color success = Colors.green;
  static const Color error = Colors.red;

  // Management screen colors
  static const Color managementCardBackground = Colors.white;
  static const Color managementCardBorder = Color(
    0xFFE5E5E5,
  ); // Colors.grey.shade200
  static const Color managementCardShadow = Color(
    0xFFF5F5F5,
  ); // Colors.grey.shade100
  static const Color managementIconContainer = Color(
    0xFFF5F5F5,
  ); // Colors.grey.shade100
  static const Color managementSubtitle = Color(
    0xFF757575,
  ); // Colors.grey.shade600
  static const Color managementChevron = Color(
    0xFFBDBDBD,
  ); // Colors.grey.shade400
  static const Color managementScreenSubtitle = Colors.grey;

  // Message and Reaction Colors - Light Theme
  static const Color messageAuthorColor = Color(
    0xFF716D62,
  ); // Same as primaryHeadingColor
  static const Color messageContentColor = Color(
    0xFF2C2C2C,
  ); // Dark grey for readability
  static const Color messageTimestampColor = Color(
    0xFFA6A6A6,
  ); // Same as secondaryHeadingColor

  // Reaction Colors - Light Theme
  static const Color reactionBackgroundNormal = Color(
    0xFFF8F9FE,
  ); // Same as searchBarBackground
  static const Color reactionBackgroundActive = Color(
    0xFFFFE4DE,
  ); // Light orange tint
  static const Color reactionBorderNormal = Color(
    0xFFE0E0E0,
  ); // Light grey border
  static const Color reactionBorderActive = Color(
    0xFFF48867,
  ); // Same as accentPrimary
  static const Color reactionTextNormal = Color(0xFF757575); // Medium grey
  static const Color reactionTextActive = Color(
    0xFFF48867,
  ); // Same as accentPrimary
  static const Color reactionCountColor = Color(
    0xFF616161,
  ); // Darker grey for count

  // Message and Reaction Colors - Dark Theme
  static const Color darkMessageAuthorColor = Color(
    0xFFE0E0E0,
  ); // Light grey for dark theme
  static const Color darkMessageContentColor = Color(
    0xFFFFFFFF,
  ); // Pure white for content
  static const Color darkMessageTimestampColor = Color(
    0xFFB3B3B3,
  ); // Same as darkTextSecondary

  // Reaction Colors - Dark Theme
  static const Color darkReactionBackgroundNormal = Color(
    0xFF424242,
  ); // Same as darkInputBackground
  static const Color darkReactionBackgroundActive = Color(
    0xFF4A2C1A,
  ); // Dark orange tint
  static const Color darkReactionBorderNormal = Color(
    0xFF616161,
  ); // Medium grey border
  static const Color darkReactionBorderActive = Color(
    0xFFF58868,
  ); // Same as logoColor
  static const Color darkReactionTextNormal = Color(
    0xFFB3B3B3,
  ); // Same as darkTextSecondary
  static const Color darkReactionTextActive = Color(
    0xFFF58868,
  ); // Same as logoColor
  static const Color darkReactionCountColor = Color(
    0xFFE0E0E0,
  ); // Light grey for count

  // Action Button Colors
  static const Color actionButtonColor = Color(0xFF9E9E9E); // Neutral grey
  static const Color darkActionButtonColor = Color(
    0xFFB3B3B3,
  ); // Lighter grey for dark theme

  static const double actionButtonRadius = 25;

  // Light Theme Text Styles
  static TextStyle get primaryHeading => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: primaryHeadingColor,
  );

  static TextStyle get secondaryHeading => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: secondaryHeadingColor,
  );

  static TextStyle get chatTitle => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: black,
  );

  static TextStyle get chatMessage => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: black,
  );

  static TextStyle get chatTimestamp => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: secondaryHeadingColor,
  );

  static TextStyle get searchInput => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: black,
  );

  static TextStyle get notificationBubble => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: white,
  );

  // Dark Theme Text Styles
  static TextStyle get darkAppBarTitle => const TextStyle(
    fontFamily: 'Poppins',
    color: darkText,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get darkFieldLabel => const TextStyle(
    fontFamily: 'Poppins',
    color: darkTextSecondary,
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );

  static TextStyle managementHeading = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppTheme.primaryHeadingColor,
  );

  static TextStyle managementSubHeading = const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 16,
    color: Colors.grey,
  );

  static TextStyle managementSubtitleText = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppTheme.primaryHeadingColor,
  );

  static TextStyle managementTitleText = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    color: Colors.grey.shade600,
  );

  static TextStyle get darkFieldText => const TextStyle(
    fontFamily: 'Poppins',
    color: darkText,
  );

  static TextStyle get darkFieldHint => const TextStyle(
    fontFamily: 'Poppins',
    color: darkTextHint,
  );

  static TextStyle get darkAttachmentOption => const TextStyle(
    fontFamily: 'Poppins',
    color: darkText,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  // Chat specific text styles
  static TextStyle get chatEmptyMessage => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: secondaryHeadingColor,
  );

  static TextStyle get chatDateDivider => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.black, // grey[600]
  );

  // Dark theme chat styles
  static TextStyle get darkChatEmptyMessage => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: darkTextSecondary,
  );

  static TextStyle get darkChatDateDivider => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: darkTextTertiary,
  );

  static TextStyle get pinnedPostsHeaderLightText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: pinnedPostsHeaderLight,
  );

  static TextStyle get pinnedPostsHeaderDarkText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: pinnedPostsHeaderDark,
  );

  // Message Text Styles - Light Theme
  static TextStyle get messageAuthor => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: messageAuthorColor,
  );

  static TextStyle get messageContent => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: messageContentColor,
    height: 1.4, // Better line height for readability
  );

  static TextStyle get messageTimestamp => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: messageTimestampColor,
  );

  // Reaction Text Styles - Light Theme
  static TextStyle get reactionText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: reactionTextNormal,
  );

  static TextStyle get reactionCount => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: reactionCountColor,
  );

  // Message Text Styles - Dark Theme
  static TextStyle get darkMessageAuthor => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: darkMessageAuthorColor,
  );

  static TextStyle get darkMessageContent => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: darkMessageContentColor,
    height: 1.4,
  );

  static TextStyle get darkMessageTimestamp => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: darkMessageTimestampColor,
  );

  // Reaction Text Styles - Dark Theme
  static TextStyle get darkReactionText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: darkReactionTextNormal,
  );

  static TextStyle get darkReactionCount => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: darkReactionCountColor,
  );

  // Body text style that was missing
  static TextStyle get bodyText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: messageContentColor,
    height: 1.4,
  );

  static TextStyle get darkBodyText => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: darkMessageContentColor,
    height: 1.4,
  );

  // Text tertiary style that was missing
  static TextStyle get textTertiary => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: secondaryHeadingColor,
  );

  static TextStyle get textSecondaryStyle => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: Color(0xFF757575),
  );

  static TextStyle get darkTextSecondaryStyle => const TextStyle(
    fontFamily: 'Poppins',
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: darkTextSecondary,
  );

  // Theme Data
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: accentPrimary,
      scaffoldBackgroundColor: white,
      appBarTheme: const AppBarTheme(
        backgroundColor: headerBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: black),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: searchBarBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        hintStyle: searchInput.copyWith(color: secondaryHeadingColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentPrimary,
          foregroundColor: white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
      cardTheme: CardTheme(
        color: cardGreyBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).data,
      colorScheme: ColorScheme.light(
        primary: accentPrimary,
        secondary: accentSecondary,
        surface: cardGreyBackground,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      primaryColor: accentPrimary,
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: darkText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputBackground,
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
          borderSide: const BorderSide(color: accentPrimary, width: 1),
        ),
        hintStyle: darkFieldHint,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentPrimary,
          foregroundColor: white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
      cardTheme: CardTheme(
        color: darkCardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).data,
      colorScheme: ColorScheme.dark(
        primary: accentPrimary,
        secondary: accentSecondary,
        surface: darkCardBackground,
      ),
    );
  }

  // Pinned Posts Getters
  static Color get pinnedPostsBorder => pinnedPostsBorderLight;
  static Color get pinnedPostsBackground => pinnedPostsBackgroundLight;
  static Color get pinnedPostsHeader => pinnedPostsHeaderLight;
  static Color get darkPinnedPostsHeader => pinnedPostsHeaderDark;
  static Color get pinnedIconColor => pinnedIconColorLight;
  static Color get darkPinnedPostsPreview => pinnedPostsPreviewDark;
  static Color get pinnedPostsPreview => pinnedPostsPreviewLight;

  // Corrected text style getters
  static TextStyle get pinnedPostsHeaderText => pinnedPostsHeaderLightText;
  static TextStyle get darkPinnedPostsHeaderText => pinnedPostsHeaderDarkText;
}

/// Extension methods for commonly used styles
extension ThemeExtension on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;

  // Light theme colors
  Color get logoColor => AppTheme.logoColor;
  Color get headerBackground => AppTheme.headerBackground;
  Color get searchBarBackground => AppTheme.searchBarBackground;
  Color get hamburgerMenu => AppTheme.hamburgerMenu;
  Color get secondaryHeadingColor => AppTheme.secondaryHeadingColor;
  Color get primaryHeadingColor => AppTheme.primaryHeadingColor;
  Color get accentPrimary => AppTheme.accentPrimary;
  Color get accentSecondary => AppTheme.accentSecondary;
  Color get cardGreyBackground => AppTheme.cardGreyBackground;

  // Dark theme colors
  Color get darkBackground => AppTheme.darkBackground;
  Color get darkSurface => AppTheme.darkSurface;
  Color get darkCardBackground => AppTheme.darkCardBackground;
  Color get darkInputBackground => AppTheme.darkInputBackground;
  Color get darkBottomBarBackground => AppTheme.darkBottomBarBackground;
  Color get darkBorder => AppTheme.darkBorder;
  Color get darkText => AppTheme.darkText;
  Color get darkTextSecondary => AppTheme.darkTextSecondary;
  Color get darkTextHint => AppTheme.darkTextHint;
  Color get darkTextTertiary => AppTheme.darkTextTertiary;
  Color get darkDisabledButton => AppTheme.darkDisabledButton;

  // Common colors
  Color get success => AppTheme.success;
  Color get error => AppTheme.error;

  // Pinned posts colors
  Color get pinnedPostsBackground => AppTheme.pinnedPostsBackground;
  Color get pinnedPostsBorder => AppTheme.pinnedPostsBorder;
  Color get pinnedPostsHeader => AppTheme.pinnedPostsHeader;
  Color get darkPinnedPostsHeader => AppTheme.darkPinnedPostsHeader;
  Color get pinnedIconColor => AppTheme.pinnedIconColor;
  Color get pinnedPostsPreview => AppTheme.pinnedPostsPreview;
  Color get darkPinnedPostsPreview => AppTheme.darkPinnedPostsPreview;

  // Light theme text styles
  TextStyle get primaryHeading => AppTheme.primaryHeading;
  TextStyle get secondaryHeading => AppTheme.secondaryHeading;
  TextStyle get chatTitle => AppTheme.chatTitle;
  TextStyle get chatMessage => AppTheme.chatMessage;
  TextStyle get chatTimestamp => AppTheme.chatTimestamp;
  TextStyle get searchInput => AppTheme.searchInput;
  TextStyle get notificationBubble => AppTheme.notificationBubble;

  // Dark theme text styles
  TextStyle get darkAppBarTitle => AppTheme.darkAppBarTitle;
  TextStyle get darkFieldLabel => AppTheme.darkFieldLabel;
  TextStyle get darkFieldText => AppTheme.darkFieldText;
  TextStyle get darkFieldHint => AppTheme.darkFieldHint;
  TextStyle get darkAttachmentOption => AppTheme.darkAttachmentOption;
  // Chat text styles
  TextStyle get chatEmptyMessage => AppTheme.chatEmptyMessage;
  TextStyle get chatDateDivider => AppTheme.chatDateDivider;
  TextStyle get darkChatEmptyMessage => AppTheme.darkChatEmptyMessage;
  TextStyle get darkChatDateDivider => AppTheme.darkChatDateDivider;

  // Message colors - Light theme
  Color get messageAuthorColor => AppTheme.messageAuthorColor;
  Color get messageContentColor => AppTheme.messageContentColor;
  Color get messageTimestampColor => AppTheme.messageTimestampColor;

  // Reaction colors - Light theme
  Color get reactionBackgroundNormal => AppTheme.reactionBackgroundNormal;
  Color get reactionBackgroundActive => AppTheme.reactionBackgroundActive;
  Color get reactionBorderNormal => AppTheme.reactionBorderNormal;
  Color get reactionBorderActive => AppTheme.reactionBorderActive;
  Color get reactionTextNormal => AppTheme.reactionTextNormal;
  Color get reactionTextActive => AppTheme.reactionTextActive;
  Color get reactionCountColor => AppTheme.reactionCountColor;

  // Message colors - Dark theme
  Color get darkMessageAuthorColor => AppTheme.darkMessageAuthorColor;
  Color get darkMessageContentColor => AppTheme.darkMessageContentColor;
  Color get darkMessageTimestampColor => AppTheme.darkMessageTimestampColor;

  // Reaction colors - Dark theme
  Color get darkReactionBackgroundNormal =>
      AppTheme.darkReactionBackgroundNormal;
  Color get darkReactionBackgroundActive =>
      AppTheme.darkReactionBackgroundActive;
  Color get darkReactionBorderNormal => AppTheme.darkReactionBorderNormal;
  Color get darkReactionBorderActive => AppTheme.darkReactionBorderActive;
  Color get darkReactionTextNormal => AppTheme.darkReactionTextNormal;
  Color get darkReactionTextActive => AppTheme.darkReactionTextActive;
  Color get darkReactionCountColor => AppTheme.darkReactionCountColor;

  // Action button colors
  Color get actionButtonColor => AppTheme.actionButtonColor;
  Color get darkActionButtonColor => AppTheme.darkActionButtonColor;

  // Message text styles - Light theme
  TextStyle get messageAuthor => AppTheme.messageAuthor;
  TextStyle get messageContent => AppTheme.messageContent;
  TextStyle get messageTimestamp => AppTheme.messageTimestamp;
  TextStyle get bodyText => AppTheme.bodyText;
  TextStyle get textTertiary => AppTheme.textTertiary;
  TextStyle get textSecondary => AppTheme.textSecondaryStyle;

  // Reaction text styles - Light theme
  TextStyle get reactionText => AppTheme.reactionText;
  TextStyle get reactionCount => AppTheme.reactionCount;

  // Message text styles - Dark theme
  TextStyle get darkMessageAuthor => AppTheme.darkMessageAuthor;
  TextStyle get darkMessageContent => AppTheme.darkMessageContent;
  TextStyle get darkMessageTimestamp => AppTheme.darkMessageTimestamp;
  TextStyle get darkBodyText => AppTheme.darkBodyText;
  TextStyle get darkTextSecondaryStyle => AppTheme.darkTextSecondaryStyle;

  // Reaction text styles - Dark theme
  TextStyle get darkReactionText => AppTheme.darkReactionText;
  TextStyle get darkReactionCount => AppTheme.darkReactionCount;
}
