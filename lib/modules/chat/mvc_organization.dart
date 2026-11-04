// lib/modules/chat/mvc_organization.dart
import 'package:mvc_app/flavour_config.dart';

/// MVC official channel organization IDs — the MVC channel is always shown
/// in the chat list and always counts toward the unread badge, regardless
/// of whether the user has actually followed it. Kept in one shared place
/// so the channel-list filter and the badge/unread-count logic can never
/// drift out of sync with each other again.
const String mvcOrganizationIdQa = '938562d2-0a56-41bb-9c55-520390f30aa4';
const String mvcOrganizationIdProduction =
    '2a2ceec6-aa41-4f0b-8954-b973fed287ac';

String get mvcOrganizationId => FlavorConfig.isProduction
    ? mvcOrganizationIdProduction
    : mvcOrganizationIdQa;

/// Whether a channel should be treated as "followed" for chat-list
/// visibility and unread-badge counting purposes: true for channels the
/// user actually follows, and also true for the MVC official channel,
/// which is always shown/counted even when the user hasn't explicitly
/// followed it.
bool isFollowedOrMvcChannel(String organizationId, bool isFollowed) =>
    isFollowed || organizationId == mvcOrganizationId;
