// Sample conversation data
import 'package:mvc_app/modules/chat/models/chat_model.dart';

final List<ConversationItem> demoConversations = [
  ConversationItem(
    name: 'John Smith',
    lastMessage: 'Are we still meeting today?',
    time: '10:30 AM',
    unreadCount: 2,
  ),
  ConversationItem(
    name: 'Design Team',
    lastMessage: 'New mockups are ready for review',
    time: 'Yesterday',
    unreadCount: 0,
  ),
  ConversationItem(
    name: 'Sarah Johnson',
    lastMessage: 'Thanks for your help!',
    time: 'Yesterday',
    unreadCount: 0,
  ),
  ConversationItem(
    name: 'Project X Group',
    lastMessage: 'Alex: Let\'s discuss this tomorrow',
    time: 'Wednesday',
    unreadCount: 5,
  ),
  ConversationItem(
    name: 'Mom',
    lastMessage: 'Call me when you get a chance',
    time: 'Tuesday',
    unreadCount: 1,
  ),
  ConversationItem(
    name: 'Tech Support',
    lastMessage: 'Your ticket #45678 has been resolved',
    time: 'Monday',
    unreadCount: 0,
  ),
  ConversationItem(
    name: 'Jessica Miller',
    lastMessage: 'Are you coming to the event?',
    time: '5/10/25',
    unreadCount: 0,
  ),
  ConversationItem(
    name: 'David Wilson',
    lastMessage: 'Check out this new restaurant',
    time: '5/5/25',
    unreadCount: 0,
  ),
];
