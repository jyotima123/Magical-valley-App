// lib/modules/chat/widgets/message_reactions_widget.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';

class MessageReactionsWidget extends StatelessWidget {
  final String messageId;
  final AppThemeMode theme;
  final bool isAdmin;
  final List<PostReaction> reactions;
  final Map<String, int> emojiCounts;
  final String currentUserId;
  final Function(String messageId, List<String> emojis)? onReactionTap;

  const MessageReactionsWidget({
    super.key,
    required this.messageId,
    required this.theme,
    required this.isAdmin,
    required this.reactions,
    required this.emojiCounts,
    required this.currentUserId,
    this.onReactionTap,
  });

  bool get _isDarkTheme => theme == AppThemeMode.dark;

  // Map emoji names to actual emojis
  static const Map<String, String> _emojiMap = {
    'heart': '❤️',
    'thumbsup': '👍',
    'laugh': '😁',
    'claps': '👏',
  };

  String _getEmojiDisplay(String emojiName) {
    return _emojiMap[emojiName] ?? emojiName;
  }

  // Get unique emojis with their counts
  Map<String, int> get _uniqueEmojiCounts {
    final Map<String, int> counts = {};
    for (final reaction in reactions) {
      for (final emoji in reaction.emojiReactions) {
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }
    return counts;
  }

  // Get current user's reactions
  List<String> get _currentUserReactions {
    final currentUserReaction = reactions.firstWhere(
      (reaction) => reaction.userId == currentUserId,
      orElse: () => PostReaction(
        id: '',
        postId: messageId,
        userId: currentUserId,
        emojiReactions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return currentUserReaction.emojiReactions;
  }

  void _showReactionDetails(BuildContext context, String emoji, int count) {
    if (!isAdmin) return;

    // Get users who reacted with this emoji
    final usersWithEmoji = reactions
        .where((reaction) => reaction.emojiReactions.contains(emoji))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkTheme ? AppTheme.white : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(_getEmojiDisplay(emoji), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              '$count reaction${count > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: usersWithEmoji.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final reaction = usersWithEmoji[index];
              final user = reaction.userProfile;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.accentPrimary.withOpacity(0.1),
                  child: user?.profilePictureUrl != null
                      ? ClipOval(
                          child: Image.network(
                            user!.profilePictureUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Text(user.fullName?[0].toUpperCase() ?? 'U'),
                          ),
                        )
                      : Text(
                          user?.fullName?[0].toUpperCase() ?? 'U',
                          style: TextStyle(
                            color: AppTheme.accentPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                title: Text(
                  user?.fullName ?? 'Unknown User',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isDarkTheme ? AppTheme.darkText : AppTheme.black,
                  ),
                ),
                subtitle: reaction.emojiReactions.length > 1
                    ? Text(
                        'Also reacted with: ${reaction.emojiReactions.where((e) => e != emoji).map((e) => _getEmojiDisplay(e)).join(' ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isDarkTheme
                              ? AppTheme.darkTextSecondary
                              : AppTheme.secondaryHeadingColor,
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: AppTheme.accentPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uniqueEmojis = _uniqueEmojiCounts;

    if (uniqueEmojis.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: uniqueEmojis.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final isCurrentUserReaction = _currentUserReactions.contains(emoji);

          return GestureDetector(
            onTap: () {
              if (isAdmin) {
                _showReactionDetails(context, emoji, count);
              } else {
                // Toggle emoji in the current user's reactions without overwriting others
                final List<String> updated = List<String>.from(
                  _currentUserReactions,
                );
                if (isCurrentUserReaction) {
                  updated.remove(emoji);
                } else {
                  updated.add(emoji);
                }
                onReactionTap?.call(messageId, updated);
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: (count > 1) ? 8 : 6,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isCurrentUserReaction
                    ? AppTheme.accentPrimary.withOpacity(0.3)
                    : (_isDarkTheme
                          ? AppTheme.white.withOpacity(0.8)
                          : AppTheme.white.withOpacity(0.8)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrentUserReaction
                      ? AppTheme.accentPrimary.withOpacity(0.3)
                      : (_isDarkTheme
                            ? AppTheme.darkBorder.withOpacity(0.5)
                            : AppTheme.dividerBackground),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getEmojiDisplay(emoji),
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isCurrentUserReaction
                            ? AppTheme.accentPrimary
                            : (_isDarkTheme
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.secondaryHeadingColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Helper widget for loading state
class MessageReactionsLoading extends StatelessWidget {
  final AppThemeMode theme;

  const MessageReactionsLoading({super.key, required this.theme});

  bool get _isDarkTheme => theme == AppThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 20,
            decoration: BoxDecoration(
              color: _isDarkTheme
                  ? AppTheme.darkSurface.withOpacity(0.5)
                  : AppTheme.cardGreyBackground.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 24,
            height: 20,
            decoration: BoxDecoration(
              color: _isDarkTheme
                  ? AppTheme.darkSurface.withOpacity(0.5)
                  : AppTheme.cardGreyBackground.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget for empty state
class MessageReactionsEmpty extends StatelessWidget {
  const MessageReactionsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
