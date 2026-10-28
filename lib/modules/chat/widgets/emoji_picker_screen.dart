// lib/modules/chat/widgets/emoji_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';

class EmojiPickerScreen extends StatefulWidget {
  final AppThemeMode theme;
  final List<String> initialSelectedEmojis;
  final Function(List<String>) onEmojisSelected;

  const EmojiPickerScreen({
    super.key,
    required this.theme,
    this.initialSelectedEmojis = const [],
    required this.onEmojisSelected,
  });

  @override
  State<EmojiPickerScreen> createState() => _EmojiPickerScreenState();
}

class _EmojiPickerScreenState extends State<EmojiPickerScreen> {
  late Set<String> selectedEmojis;
  bool get _isDarkTheme => widget.theme == AppThemeMode.dark;

  // Popular emoji categories
  static const Map<String, List<String>> emojiCategories = {
    'Smileys': [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
    ],
    'Gestures': [
      '👍',
      '👎',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '🖕',
      '👇',
      '☝️',
      '👋',
      '🤚',
      '🖐️',
      '✋',
      '🖖',
      '👏',
      '🙌',
      '🤝',
      '👐',
      '🤲',
      '🙏',
      '✊',
      '👊',
      '🤛',
      '🤜',
      '💪',
      '🦾',
      '🖤',
      '🤍',
      '🤎',
      '💜',
      '💙',
      '💚',
      '💛',
    ],
    'Hearts': [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
    ],
    'Objects': [
      '🔥',
      '⭐',
      '🌟',
      '✨',
      '💫',
      '💥',
      '💢',
      '💦',
      '💨',
      '🕳️',
      '💣',
      '💤',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
      '🎀',
      '🎗️',
      '🎟️',
      '🎫',
      '🏆',
      '🏅',
      '🥇',
      '🥈',
      '🥉',
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🥎',
      '🎾',
      '🏐',
      '🏉',
      '🥏',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🏒',
      '🏑',
    ],
    'Food': [
      '🍎',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌶️',
      '🫑',
      '🌽',
      '🥕',
      '🫒',
      '🧄',
      '🧅',
      '🥔',
      '🍠',
      '🥐',
      '🥖',
      '🍞',
      '🥨',
      '🥯',
      '🧀',
      '🥚',
      '🍳',
      '🧈',
      '🥞',
    ],
    'Animals': [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐽',
      '🐸',
      '🐵',
      '🙈',
      '🙉',
      '🙊',
      '🐒',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🐣',
      '🐥',
      '🦆',
      '🦅',
      '🦉',
      '🦇',
      '🐺',
      '🐗',
      '🐴',
      '🦄',
      '🐝',
      '🪱',
      '🐛',
      '🦋',
      '🐌',
      '🐞',
    ],
  };

  @override
  void initState() {
    super.initState();
    selectedEmojis = Set.from(widget.initialSelectedEmojis);
  }

  void _toggleEmoji(String emoji) {
    setState(() {
      if (selectedEmojis.contains(emoji)) {
        selectedEmojis.remove(emoji);
      } else {
        selectedEmojis.add(emoji);
      }
    });
  }

  void _saveReactions() {
    widget.onEmojisSelected(selectedEmojis.toList());
    Navigator.pop(context);
  }

  void _clearAll() {
    setState(() {
      selectedEmojis.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDarkTheme ? AppTheme.darkBackground : AppTheme.white,
      appBar: AppBar(
        backgroundColor: _isDarkTheme ? AppTheme.darkSurface : AppTheme.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Reactions',
          style: TextStyle(
            color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (selectedEmojis.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: Text(
                'Clear All',
                style: TextStyle(
                  color: _isDarkTheme
                      ? AppTheme.darkTextSecondary
                      : AppTheme.secondaryHeadingColor,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Selected emojis preview
          if (selectedEmojis.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isDarkTheme
                    ? AppTheme.darkSurface
                    : AppTheme.cardGreyBackground,
                border: Border(
                  bottom: BorderSide(
                    color: _isDarkTheme
                        ? AppTheme.darkBorder
                        : AppTheme.dividerBackground,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Reactions (${selectedEmojis.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedEmojis.map((emoji) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accentPrimary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _toggleEmoji(emoji),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.accentPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // Emoji categories
          Expanded(
            child: DefaultTabController(
              length: emojiCategories.length,
              child: Column(
                children: [
                  // Category tabs
                  Container(
                    decoration: BoxDecoration(
                      color: _isDarkTheme
                          ? AppTheme.darkSurface
                          : AppTheme.white,
                      border: Border(
                        bottom: BorderSide(
                          color: _isDarkTheme
                              ? AppTheme.darkBorder
                              : AppTheme.dividerBackground,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: TabBar(
                      isScrollable: true,
                      labelColor: AppTheme.accentPrimary,
                      unselectedLabelColor: _isDarkTheme
                          ? AppTheme.darkTextSecondary
                          : AppTheme.secondaryHeadingColor,
                      indicatorColor: AppTheme.accentPrimary,
                      tabs: emojiCategories.keys.map((category) {
                        return Tab(text: category);
                      }).toList(),
                    ),
                  ),

                  // Emoji grids
                  Expanded(
                    child: TabBarView(
                      children: emojiCategories.entries.map((entry) {
                        return _buildEmojiGrid(entry.value);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Save button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isDarkTheme ? AppTheme.darkSurface : AppTheme.white,
              border: Border(
                top: BorderSide(
                  color: _isDarkTheme
                      ? AppTheme.darkBorder
                      : AppTheme.dividerBackground,
                  width: 0.5,
                ),
              ),
            ),
            child: ElevatedButton(
              onPressed: selectedEmojis.isNotEmpty ? _saveReactions : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: _isDarkTheme
                    ? AppTheme.darkTextSecondary.withOpacity(0.3)
                    : AppTheme.secondaryHeadingColor.withOpacity(0.3),
              ),
              child: Text(
                selectedEmojis.isEmpty
                    ? 'Select reactions to continue'
                    : 'Save Reactions (${selectedEmojis.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) {
          final emoji = emojis[index];
          final isSelected = selectedEmojis.contains(emoji);

          return GestureDetector(
            onTap: () => _toggleEmoji(emoji),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accentPrimary.withOpacity(0.1)
                    : (_isDarkTheme
                          ? AppTheme.darkSurface
                          : AppTheme.cardGreyBackground),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.accentPrimary
                      : (_isDarkTheme
                            ? AppTheme.darkBorder
                            : AppTheme.dividerBackground),
                  width: isSelected ? 2 : 0.5,
                ),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
          );
        },
      ),
    );
  }
}
