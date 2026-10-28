class ConversationItem {
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;

  const ConversationItem({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
  });
}
