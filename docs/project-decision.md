# Create Post Redesign — Proposed Decisions

**Status: proposed, awaiting your approval.** Nothing below has been implemented. Once you confirm (and once the items in `open-questions.md` are answered), this file becomes the record of what was actually agreed, and any answer that changes a decision below will be updated here before implementation starts.

## Architecture

- The Update/Event/Deal tabs are a redesign of the **existing, single, tab-less `CreatePostScreen`** — not a new screen replacing an existing tabbed one (the current app has no tabs here at all; both existing composer files, `create_post_screen.dart` and `create_post_screen_no_animation.dart`, are flat forms). See Open Question #7 on which of the two is actually live before either is changed.
- No new BLoC/state-management layer is introduced. The screen stays a `StatefulWidget`; each tab's fields live in their own extracted sub-form widget (`UpdatePostForm` / `EventPostForm` / `DealPostForm`), following the same extraction pattern already used in `lib/modules/market/widgets/listing_form_fields.dart`.
- The existing attachment system (paperclip → image/PDF/link/paste) is reused unchanged and shared across all three tabs.
- The write path stays the existing generic one: `ApiRepository.create<T>('posts', data)`. No dedicated "create post" REST/RPC endpoint is introduced, because none exists today and the generic insert already handles arbitrary columns.

## Database

- **One table, extended — not three new tables.** The existing `posts` table gets new, nullable, type-scoped columns for Deal (`deal_offer_type`, `deal_amount`, `deal_starts_at`, `deal_ends_at`, `promo_code`) and Event (`event_starts_at`, `event_ends_at`, `event_location_text`), gated by `CHECK` constraints so they can only be set on rows of the matching `post_type`. This mirrors how this codebase already extended a shared table for vehicle listings, market items, and shelter animals rather than introducing parallel tables.
- `posts.post_type`'s `CHECK` constraint is widened to add `'event'` and `'deal'` to the existing `'text'`/`'image'`/`'pdf'`/`'message'` values.
- `posts.file_required_for_media` is widened so `'event'`/`'deal'` behave like `'text'`/`'message'` — an attached photo is optional on every post type.
- **One new table**: `post_event_interests` (`post_id`, `user_id`, `created_at`, unique per pair) — needed because "who is interested in this event" is a relationship, not an attribute of a single post, and it directly parallels the existing `post_reactions` table's shape and RLS policy structure.
- All new columns are nullable and all new constraints are satisfied trivially by every existing row — **no backfill or data migration is required**.
- Reused without any change: `organizations`, `user_profiles`, `admin_organizations`, `post_views` (+ its view-count trigger), `post_reactions`, `notification_logs`, the `notify_post_created()` push-notification trigger, and the `uploads` storage bucket.
- The migration is applied to the **QA Supabase project first**, verified there against the `development` build flavor, then applied identically to the **production Supabase project** — following the existing qa/prod split already used throughout this app's migration history.

## API / Backend

- `ChatService.sendMessage()`, `SendMessageEvent`, and the `ChatMessage` model are extended with new **optional** fields for the Deal/Event columns above — additive changes, no existing caller breaks.
- Two small new methods are added, directly mirroring the existing reaction methods: one to toggle a user's row in `post_event_interests`, one to read the interest count (via a new `post_interest_counts` view, mirroring `post_reaction_summary`).
- No change to the generic `create<T>`/`update<T>` methods themselves — they remain table-agnostic.

## Explicitly rejected

- A separate `deals` table and/or `events` table, each FK'd to `posts`. Rejected as unnecessary indirection for a small, mutually-exclusive set of fields that a `CHECK` constraint can police on the shared table.
- A `post_channels` join table for multi-channel posting, **unless** Open Question #1 comes back wanting one logical post shared live across channels. The default (one independent post row per selected channel) needs no new table at all.

## What is intentionally *not* decided yet

Everything listed in `open-questions.md` — most importantly, the multi-channel "channels you pick next" behavior (#1), what the Event reminder mechanism actually requires (#3), and which of the two existing composer screens is live (#7). Implementation will not start until those are answered, per your instruction.
