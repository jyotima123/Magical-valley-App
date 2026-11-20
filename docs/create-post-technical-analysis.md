# Create Post Redesign — Technical Analysis

Status: **analysis only — no code or database changes have been made.**
Scope: the "Create Post" composer (`lib/modules/posts/`), its write path into Supabase, and the schema changes needed to support the new Update / Event / Deal tab designs.

---

## 1. Existing Implementation — As-Built Today

### 1.1 Frontend entry points

There are **two separate composer screens** in the codebase, and they are not equivalent:

| File | Status | Notes |
|---|---|---|
| `lib/modules/posts/create_post_screen.dart` (`CreatePostScreen`) | Animated, full-featured | Dispatches `SendMessageEvent` to `ChatBloc`, which goes through `ChatService.sendMessage()`. Supports image/PDF/link/paste attachments, clipboard paste, HEIC conversion, a first-run hint dialog. |
| `lib/modules/posts/create_post_screen_no_animation.dart` (`CreatePostScreenNoAnimation`) | Simpler, no animation | Calls `ApiRepository.create('posts', ...)` **directly**, bypassing `ChatBloc` entirely (so it does not trigger the channel-list refresh or the notification-badge update that happens after a normal send). Its attachment menu options are all `// TODO` stubs except the post_type toggle. |

**I could not find a navigation call to either screen inside the files examined this session** (it is not referenced from `main_scaffold.dart`). The call site is presumably in a channel/chat screen not yet opened. **This needs to be confirmed before implementation** — see Open Questions.

**Neither screen currently has tabs.** Both are a single flat form: a `TITLE` field, a `CONTENT` textarea, and a paperclip button that opens a bottom sheet with Insert Photo / Attach PDF / Add Link / Paste. There is no Update/Event/Deal switcher anywhere in the current code. The three reference images describe a composer that does not exist yet — this is new UI, not a re-skin of existing tabs.

### 1.2 Supporting frontend files

- **`attachment_floating_card.dart`** (`AttachmentFloatingCard`) — a modal overlay used for the `link` and `paste` attachment types (image/PDF go straight to the native picker instead). Shows a preview + confirm/cancel step.
- **`models/attachment_data.dart`** (`AttachmentData`) — a generic attachment value object: `type` (`image`/`pdf`/`link`/`paste`), `filePath`, `url`, `fileName`, `fileBytes`, `textContent`. It is a transient, in-memory UI model only — it is never itself persisted; only the resulting `file_url` (and for link/paste, text folded into `content`) reaches the database.
- **`chat/models/post_reactions_model.dart`** — `PostReaction`, `PostReactionSummary`, `EmojiCount` — models for the existing emoji-reaction feature on posts (read-side; not part of creation).
- **`chat/models/chat_message.dart`** (`ChatMessage`) — the Dart model a created post round-trips through. Fields: `id`, `organizationId`, `createdBy`, `title`, `content`, `postType`, `fileUrl`, `status`, `viewCount`, `createdAt`, `updatedAt`, `author`. **This model has no fields for anything Deal- or Event-specific** — it will need to be extended.
- **`channels/widgets/explore_feed_post_card.dart`** — renders a post in the Explore feed, and also hosts **inline editing**: admins/superadmins can edit a post's `title`/`content` directly on the card (same permission rule as the chat screen: superadmin always, admin only for organizations they manage). Edits go through the same generic update path as creation. It does **not** currently branch its rendering on `post_type` beyond showing the attached image/PDF.
- **`chat/select_organization_screen.dart`** (`SelectOrganizationScreen`) — a **single-select** channel picker (pops with one `Organization`), used elsewhere in the app (e.g. starting a DM). It is not a multi-select "choose which channels this goes to" screen, and `CreatePostScreen` does not call it — the screen is always bound to one `organizationId` passed in by its caller. This matters for the "channels you pick next" line in the Update tab reference image (see Open Questions).

### 1.3 Write path (how a post actually gets created today)

```
CreatePostScreen
  → ChatBloc.add(SendMessageEvent(organizationId, userId, title, content, postType, fileUrl))
    → ChatBloc._onSendMessage()
      → ChatService.sendMessage(organizationId, userId, title, content, postType, fileUrl)
        → builds postData map: {organization_id, created_by, title, content, post_type, file_url, status:'active'}
        → ApiRepository.create<Map<String,dynamic>>('posts', postData)
          → ApiService.create<T>('posts', data)   // generic Supabase insert, defined once, reused everywhere
        → wraps the inserted row back into a ChatMessage, attaches the author's UserProfile
    → ChatBloc.add(RefreshChannelsEvent())   // refreshes channel list's last-message + triggers notification badge recompute
```

`CreatePostScreenNoAnimation` shortcuts straight to the `ApiRepository.create('posts', ...)` step, skipping the `ChatBloc` dispatch (and therefore the channel refresh / badge update).

There is **no dedicated REST/RPC endpoint for "create a post."** `ApiRepository.create<T>(table, data)` → `ApiService.create<T>(table, data)` is a fully generic Supabase-table insert used for many tables across the app, not something specific to posts. This has an important consequence for the redesign: **adding new, nullable columns to the `posts` table requires no backend code change at all** — the generic insert will happily write whatever keys are in the map, as long as they're valid columns.

`post_type` is **not** chosen by the user via a selector today — it's inferred client-side in `_createPost()`: image/PDF attachment present → `'image'`/`'pdf'`; title present → `'text'`; content-only → `'message'`. The reference-image tabs would be the first place `post_type` is ever a direct, explicit user choice.

### 1.4 Image/file upload

Both image and PDF attachments go through `SupabaseApiService.uploadGenericFile(fileBytes, fileName, userId)`, which uploads to the **`uploads` storage bucket** and returns a public URL, stored as `posts.file_url`. HEIC images are converted to PNG client-side first (`ImageConverterService`). The `uploads` bucket (migration `044_fix_storage_rls_policies.sql`) allows any authenticated user to INSERT, allows admins/superadmins to UPDATE/DELETE any file, and is publicly readable. This upload path is generic and reusable as-is for any new post type that needs a photo.

### 1.5 Post lifecycle: create / edit / delete / retrieve / notifications

- **Create**: as above.
- **Edit**: `ExploreFeedPostCard`'s inline edit calls the same generic `update<T>('posts', id, data)` path (title/content only, in the code examined).
- **Delete**: not examined directly this session (not required for the Create Post task), but `posts.status` supports `'archived'`, suggesting soft-delete is the pattern rather than a hard `DELETE`.
- **Retrieve**: posts are read as part of channel/message queries (`ChatService`) and the cross-organization Explore feed (`explore_feed_bloc.dart` / `ExploreFeedItem`).
- **View tracking**: `post_views` table + `trigger_update_post_view_count` trigger increments `posts.view_count` on every insert into `post_views`. A `batchInsertPostViews` API method exists to record multiple views at once, de-duplicating against views the user already has.
- **Reactions**: `post_reactions` table (one row per user per post, `emoji_reactions text[]`), with `upsert_post_reaction`/`remove_post_reaction` RPC functions and `post_reaction_summary`/`post_emoji_counts` views for aggregated display.
- **Push notifications**: a database trigger, `post_created_notification` (`AFTER INSERT ON posts ... WHEN (NEW.status = 'active')`), calls `notify_post_created()`, which does an HTTP POST (via `pg_net`) to a Supabase Edge Function (`send-fcm-notification`) with the post's title/content and the organization name, which then fans out FCM notifications to the organization's followers. **This fires automatically for every post insert regardless of `post_type`** — a Deal or Event post created through the normal insert path will already trigger a push notification with no extra work, though the notification text (currently just "New post in `<channel>`" / the post title or content, truncated) does not currently say anything specific like "New deal" or "Event: ...".

---

## 2. Analysis of the Three New Design References

All three screens share: a back arrow + "Create Post" title; a `POST TYPE` segmented control with three pill buttons (**Update** / **Event** / **Deal**, in that left-to-right order, with the active one filled in the accent orange and the inactive ones outlined); a `TITLE` field; a `CONTENT` textarea at the bottom; and a bottom bar with a paperclip (attach) button on the left and a send button (circular, orange) on the right. This is an evolution of the existing composer, not a different screen entirely — the chrome (app bar, bottom bar, title/content fields, attach button) is unchanged; what's new is the segmented control and the type-specific fields that appear between them.

### 2.1 Update tab (image 3 — "Update_default")

- **Purpose**: the general-purpose post, equivalent to today's only post type.
- **Elements**: `POST TYPE` selector (Update active); a caption under it, *"Shows in the Home feed of the channels you pick next."*; `TITLE` (placeholder "What's this about?"); `CONTENT` (placeholder "Share your thoughts...", multi-line).
- **Behavior implication**: the phrase *"the channels you pick next"* describes a step that **does not exist in the current app** — today a post always belongs to the single `organizationId` the screen was opened with. This phrasing implies tapping Send on the Update tab leads to (or the flow otherwise includes) a multi-channel selection step, which is a materially new capability. **Flagged as Open Question #1** — the image shows the *composer*, not the channel-picker step it refers to, so its UI and exact behavior (does it post one copy per channel? can you post to channels you don't admin?) are not specified by the references and must not be guessed.
- **Validation (inferred)**: same as today — at least one of title/content/attachment.
- No conditional fields; no dynamic behavior beyond the existing attachment bar.

### 2.2 Event tab (image 2 — "Create_Post_-_Event")

- **Elements**: `POST TYPE` selector (Event active); `TITLE` ("Latte art night" in the sample); a row of three fields — `DATE` ("Sat, Nov 21"), `STARTS` ("6:00 PM"), `ENDS` ("8:00 PM"); `LOCATION` — a text field ("210 Main Ave, Twin Falls") with a separate small map-icon button beside it; `CONTENT` textarea; and a static info box (star icon) reading *"Members can tap **Interested** to save it to their calendar and get a reminder. You'll see how many are interested."*
- **Field behavior (inferred, not shown interactively in a static mock)**:
  - `DATE` — a date picker, almost certainly `showDatePicker`.
  - `STARTS`/`ENDS` — time pickers (`showTimePicker`), displayed as two side-by-side boxes under one `STARTS`/`ENDS` pair of labels, same row as `DATE`.
  - `LOCATION` — free-text address entry; the map icon's behavior is not shown mid-interaction. The most consistent reading, given it's a plain text field rather than an autocomplete/search box, is that it opens the typed address in a maps app (a launch-URL action), **not** a map picker/autocomplete widget — but this is inference, not something the static image proves. **Open Question #2.**
  - The "Interested" feature described in the info box is **purely explanatory text in this screen** — there is no "Interested" button *on the composer itself* (that button would appear later, on the published post card, which is not one of the three reference images). This means: (a) the composer itself needs no new interactive element for this, just the static info box; but (b) a `post_event_interests`-style table, a toggle action, a count, and a reminder-delivery mechanism are all required *downstream*, outside the Create Post screen proper, to make the promise in that info box true. **Open Question #3** covers what "get a reminder" actually requires (local device calendar/reminder only, vs. a server-sent push close to the event).
- **Validation (inferred)**: Title, Date, Starts likely required; whether Ends and Location are required or optional cannot be determined from a filled-in sample screenshot — placeholders are not shown for any Event field because the mock has sample data in every field. **Open Question #4.**

### 2.3 Deal tab (image 1 — "Create_Post_-_Deal")

- **Elements**: `POST TYPE` selector (Deal active); `TITLE` ("20% off any bag of beans"); `OFFER` — four selectable pill chips: **% off** (selected, filled orange), **$ off**, **Buy 1 get 1**, **Freebie** (all four outlined/unselected states shown via their styling, only one selected at a time); a row of three fields — `AMOUNT` ("20%"), `STARTS` ("Nov 18"), `ENDS` ("Nov 29"); `PROMO CODE (optional)` — explicitly marked optional, placeholder "Leave blank to redeem in store"; `CONTENT` textarea (used here for fine print, e.g. "One per customer. Show this post at the counter.").
- **Field behavior (inferred)**:
  - `OFFER` is a single-select chip group (one active at a time), driving what `AMOUNT` means (a percentage for "% off", a currency amount for "$ off"). For "Buy 1 get 1" and "Freebie" it is unclear whether `AMOUNT` is hidden, disabled, or stays a free-text field with no particular meaning — the reference image only shows the "% off" state. **Open Question #5.**
  - `STARTS`/`ENDS` here are **dates**, not times (unlike Event's date-plus-time triplet) — this is a promotion validity window, a different concept from Event's single-day schedule, even though the field labels are reused.
  - `PROMO CODE` is explicitly optional; its placeholder text ("Leave blank to redeem in store") implies it's meant for an online/digital code, with an in-store redemption path when left blank — purely informational copy, no special validation beyond "optional."
- **Validation (inferred)**: Title, Offer type, Amount (when applicable), Starts, Ends likely required; Promo Code and Content optional.

### 2.4 Mobile vs. desktop behavior

All three references are phone-width mockups (390–430px-class screens) with a bottom-pinned action bar, standard for this app (the existing `CreatePostScreen` already works this way, with `resizeToAvoidBottomInset: true`). **Nothing in the three images indicates desktop/tablet-specific behavior**, and no other screen examined this session shows an existing desktop breakpoint pattern to follow. The safest default — centering the form in a max-width column on wide screens, scrolling as today otherwise — is proposed in §6, but is explicitly a guess, not something derived from the references. **Open Question #6.**

### 2.5 What the images do *not* show (and this analysis will not invent)

- The resulting feed/card appearance of a published Deal or Event post (badges, countdown, "Interested" button placement, offer styling).
- The multi-channel picker screen implied by the Update tab's caption.
- Error/validation states (empty required field, invalid date range, etc.).
- Whether editing an existing Deal/Event post reuses this same screen pre-filled, or a different one.
- Whether attachments (photo) are supported identically across all three tabs — the paperclip icon is present in the bottom bar on all three screenshots, suggesting yes, but this is also inference.

---

## 3. Existing Database Schema — As Found in the Migrations

This project is **Flutter + Supabase (Postgres)**, with hand-written, sequentially numbered SQL migration files under `/migrations` (not Prisma — there is no ORM schema file in this codebase; the "Prisma models" framing in a generic brief does not apply here). The tables relevant to posts, reconstructed from migrations `001.sql` through `090_market_item_sold_expiry.sql`:

### 3.1 `posts` (defined in `001.sql`; evolved by `032.sql`, `062_add_message_post_type.sql`)

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | `uuid_generate_v4()` |
| `organization_id` | `uuid` FK → `organizations(id)` | `ON DELETE CASCADE`. **Single channel per post — no many-to-many today.** |
| `created_by` | `uuid` FK → `user_profiles(id)` | |
| `title` | `varchar(255)` | nullable |
| `content` | `text` | nullable |
| `post_type` | `varchar(20)` NOT NULL | `CHECK IN ('text','image','pdf','message')` — note **no `'event'`/`'deal'` today** |
| `file_url` | `text` | nullable; required (`CHECK`) when `post_type IN ('image','pdf')` |
| `status` | `varchar(20)` | `CHECK IN ('active','archived','fixated')`, default `'active'` |
| `view_count` | `integer` | default 0, maintained by trigger |
| `created_at`, `updated_at` | `timestamptz` | default `NOW()`, `updated_at` maintained by `update_updated_at_column()` trigger |

Indexes: `organization_id`, `status`, `created_at DESC`. RLS: followers (or admin/superadmin) can `SELECT` posts with `status IN ('active','fixated')`; org admins (via `admin_organizations`) and superadmins can do `ALL` on posts in their org(s).

**Used by**: `ChatService.sendMessage()` (insert), `ExploreFeedPostCard` inline edit (update), `explore_feed_bloc.dart` / channel message queries (select), `post_views` trigger & RPCs, `post_reactions` FK, the `notify_post_created()` trigger.

**Can it support the new design?** Partially. It already holds everything the Update tab needs. It has **no columns at all** for Deal's offer type/amount/dates/promo code, or Event's date/time/location — those are entirely new. It also enforces a strict one-organization-per-post relationship, which conflicts with the Update tab's "channels you pick next" copy unless that's handled client-side as multiple inserts (see §4).

### 3.2 `post_views` (defined in `001.sql`; admin-read RPC added in `060_post_views_admin_rpc.sql`)

`id`, `user_id` (FK, `ON DELETE SET NULL`), `post_id` (FK, `ON DELETE CASCADE`), `viewed_at`. A trigger increments `posts.view_count` on insert. RLS has no general `SELECT` policy (by design — a QA debug screen uses the `get_post_views()` `SECURITY DEFINER` RPC instead, gated to admins/superadmins of the post's org). **Reused as-is** — nothing about Deal/Event changes view tracking.

### 3.3 `post_reactions` (defined in `032.sql`)

`id`, `post_id` (FK, cascade), `user_id` (FK, cascade), `emoji_reactions text[]`, `created_at`/`updated_at`. Unique `(post_id, user_id)`. RPCs `upsert_post_reaction`/`remove_post_reaction`; views `post_reaction_summary`, `post_emoji_counts`. **Reused as-is**, and is the direct structural template for the new "Interested" feature (see §4.3) — same one-row-per-user-per-post shape.

### 3.4 `notification_logs` + `notify_post_created()` trigger (defined in `041_notify_post_created_without_username.sql`, refined in `038.sql`, `039.sql`)

`notification_logs` records push-fan-out attempts (`post_id`, `channel_id`, counts). `notify_post_created()` is an `AFTER INSERT ON posts ... WHEN (NEW.status = 'active')` trigger that calls the `send-fcm-notification` Edge Function with the post's title/content and the organization's name. **Reused as-is for Deal/Event** — any new `post_type` value still fires this trigger on insert, since it keys off `status`, not `post_type`. Only the notification *text* might optionally be customized per type later (cosmetic, not structural).

### 3.5 Storage: the `uploads` bucket (`044_fix_storage_rls_policies.sql`)

Public-read, authenticated-write bucket already used for post image/PDF attachments via `uploadGenericFile()`. **Reused as-is** for any photo attached to a Deal or Event post.

### 3.6 Prior art for structured, type-specific fields on a shared table

Two existing features already solve "one table, several shapes of row" the same way this redesign will need to:

- **Vehicle listings** (`071_vehicle_listings.sql` onward) and **market items** (`080_market_items.sql`, `083_market_categories_v2.sql`, `086_market_secondary_category.sql`) both use a single wide table with mostly-nullable columns rather than per-category tables.
- **Shelter/adoption animals** (`088_shelter_animal_listings.sql`) and **promoted market items** (`089_promoted_market_items.sql`) — the most recent schema work in this codebase — extend an existing items table with nullable nullable nullable additions rather than new parallel tables, and `shelter_animal.dart`'s `toInquirySnapshot()` builds a "shadow" row in an existing table rather than creating a new relationship. This is the same pattern recommended in §4 below, so it is consistent with how this codebase has already chosen to evolve similar problems twice.

### 3.7 Complete existing flow, end to end

```
User fills Title/Content (+ optional attachment)
  → CreatePostScreen._createPost()
    → infers post_type from attachment/title/content
    → ChatBloc.add(SendMessageEvent(...))
      → ChatService.sendMessage(...) builds {organization_id, created_by, title, content, post_type, file_url, status:'active'}
        → ApiRepository.create('posts', data) → Supabase INSERT
          → trigger: post_created_notification → notify_post_created() → Edge Function → FCM push to followers
          → trigger: trigger_posts_updated_at (no-op on insert, matters on update)
    → ChatBloc.add(RefreshChannelsEvent()) → channel list + notification badge recompute
Post now appears in: the channel's message list, the cross-org Explore feed, and (if it has media) wherever file_url is rendered.
Users can: view it (post_views insert → view_count++), react to it (post_reactions upsert), and admins/superadmins can edit title/content in place or change status to archive/fixate it.
```

---

## 4. Proposed Database Design

**Guiding rule applied throughout**: three tabs do **not** imply three tables. The existing `posts` table is extended with nullable, type-scoped columns — mirroring how this codebase already handled vehicles, market items, and shelter animals (§3.6). Only one genuinely new table is needed, because it represents a new *relationship* (who is interested in an event), not new *attributes* of a post.

### 4.1 Tables reused unchanged

`organizations`, `user_profiles`, `admin_organizations`, `post_views`, `post_reactions`, `notification_logs`, the `notify_post_created()` trigger, the `uploads` storage bucket. None of these need any change.

### 4.2 `posts` — modified (additive, nullable, backward-compatible)

```sql
-- 1. Widen the allowed post_type values
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_post_type_check;
ALTER TABLE posts ADD CONSTRAINT posts_post_type_check
    CHECK (post_type IN ('text', 'image', 'pdf', 'message', 'event', 'deal'));

-- 2. Treat 'event' and 'deal' like 'text'/'message' for the file-required rule
--    (a photo is optional on every post type, never mandatory)
ALTER TABLE posts DROP CONSTRAINT IF EXISTS file_required_for_media;
ALTER TABLE posts ADD CONSTRAINT file_required_for_media
    CHECK (
        post_type IN ('text', 'message', 'event', 'deal') OR
        (post_type IN ('image', 'pdf') AND file_url IS NOT NULL)
    );

-- 3. New nullable Deal columns
ALTER TABLE posts ADD COLUMN deal_offer_type   TEXT;          -- 'percent_off' | 'amount_off' | 'bogo' | 'freebie'
ALTER TABLE posts ADD COLUMN deal_amount       NUMERIC(10,2); -- meaning depends on deal_offer_type; NULL for bogo/freebie
ALTER TABLE posts ADD COLUMN deal_starts_at    DATE;
ALTER TABLE posts ADD COLUMN deal_ends_at      DATE;
ALTER TABLE posts ADD COLUMN promo_code        TEXT;

ALTER TABLE posts ADD CONSTRAINT deal_offer_type_check
    CHECK (deal_offer_type IS NULL OR deal_offer_type IN ('percent_off','amount_off','bogo','freebie'));

-- 4. New nullable Event columns
ALTER TABLE posts ADD COLUMN event_starts_at      TIMESTAMPTZ;
ALTER TABLE posts ADD COLUMN event_ends_at        TIMESTAMPTZ;
ALTER TABLE posts ADD COLUMN event_location_text  TEXT;

-- 5. Integrity: deal_* only set on deal posts, event_* only set on event posts
ALTER TABLE posts ADD CONSTRAINT deal_fields_require_deal_type CHECK (
    post_type = 'deal' OR (
        deal_offer_type IS NULL AND deal_amount IS NULL AND
        deal_starts_at IS NULL AND deal_ends_at IS NULL AND promo_code IS NULL
    )
);
ALTER TABLE posts ADD CONSTRAINT event_fields_require_event_type CHECK (
    post_type = 'event' OR (
        event_starts_at IS NULL AND event_ends_at IS NULL AND event_location_text IS NULL
    )
);
```

All six new columns are nullable with no default required — **every existing row in `posts` is valid without any backfill**, because `post_type` on existing rows is never `'deal'`/`'event'`, so the new "fields require type" constraints are trivially satisfied. **No data migration needed.**

`promo_code` is deliberately *not* named `deal_promo_code` to leave room for it to apply elsewhere later if ever needed, but functionally it is only meaningful for `post_type = 'deal'` under the constraint above — flagged here for naming-convention sign-off, not left silently inconsistent. (§ Open Questions.)

### 4.3 New table: `post_event_interests`

The one genuinely new table — it models a relationship (which users are interested in which event-post), not an attribute of a post, so it does not fit as columns on `posts`:

```sql
CREATE TABLE post_event_interests (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id    UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (post_id, user_id)
);

CREATE INDEX idx_post_event_interests_post ON post_event_interests(post_id);
CREATE INDEX idx_post_event_interests_user ON post_event_interests(user_id);

ALTER TABLE post_event_interests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can see interest counts" ON post_event_interests
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Users manage their own interest" ON post_event_interests
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users remove their own interest" ON post_event_interests
    FOR DELETE USING (auth.uid() = user_id);

-- Mirrors post_reaction_summary
CREATE VIEW post_interest_counts AS
SELECT post_id, COUNT(*) AS interested_count
FROM post_event_interests
GROUP BY post_id;
GRANT SELECT ON post_interest_counts TO authenticated;
```

This is a line-for-line structural copy of the existing `post_reactions` pattern (one row per user per post, RLS scoped to "see all, manage your own", a summary view). No new architectural concept is introduced.

**This table only covers the "tap Interested, see a count" half of the Event info box.** The "save it to their calendar and get a reminder" half is either a pure client-side action (adding a `.ics`/calendar entry via a device API, no server involvement) or requires a scheduled reminder job — this is a product decision, not something the schema can resolve on its own. See Open Question #3.

### 4.4 Explicitly rejected alternatives (so this isn't silently assumed later)

- **A separate `deals` table and a separate `events` table**, each FK'd 1:1 to `posts`. Rejected: it would require a join on every feed query that already reads `posts` directly, for no benefit over nullable columns, given the fields are few and mutually exclusive by `post_type`. Matches the user's explicit instruction not to default to one-table-per-tab.
- **A `post_channels` join table** for the Update tab's "channels you pick next": only needed if a *single* post must visually stay in sync across multiple channels (edit once, updates everywhere). The simpler, schema-free alternative — the client inserts one independent `posts` row per selected channel — reuses 100% of existing infrastructure (each row gets its own notification fan-out, its own view count, its own edit/delete lifecycle) and is the default recommendation in §5, pending confirmation of what "channels you pick next" is actually supposed to do (Open Question #1).

---

## 5. API and Backend Design

### 5.1 What can be reused as-is

- The generic `ApiRepository.create<T>('posts', data)` / `ApiService.create<T>` insert path — it has no knowledge of specific columns, so once the migration in §4.2 is applied, Deal and Event posts can be created through the **exact same call** `CreatePostScreen` already uses today, just with a larger `postData` map. No new endpoint is required for create.
- The generic `update<T>('posts', id, data)` path — same reasoning, for editing a Deal/Event post later.
- `uploadGenericFile()` for an optional attached photo on any tab.
- The `notify_post_created()` trigger — fires automatically on insert regardless of `post_type`.
- `post_views` / `batchInsertPostViews` — unaffected by post_type.

### 5.2 What needs to change

- **`ChatService.sendMessage()` signature** needs new optional parameters (`dealOfferType`, `dealAmount`, `dealStartsAt`, `dealEndsAt`, `promoCode`, `eventStartsAt`, `eventEndsAt`, `eventLocationText`), folded into the `postData` map alongside the existing fields. This is additive — existing callers that don't pass them are unaffected.
- **`SendMessageEvent`** (the `ChatBloc` event class) needs the same new optional fields threaded through from the UI.
- **`ChatMessage.fromJson`/model** needs the same new fields added so a Deal/Event post can be read back and rendered (today it silently has nowhere to put them).
- **New, small API surface for "Interested"**, directly parallel to the existing reaction methods:
  - `toggleEventInterest(postId, userId)` → upsert/delete a row in `post_event_interests` (same shape as `upsert_post_reaction`/`remove_post_reaction`, could be a single RPC `toggle_event_interest(post_id, user_id)` or two plain table calls through the generic repository — either is consistent with existing patterns).
  - `getEventInterestCount(postId)` / batch variant → read from the new `post_interest_counts` view, same shape as `getReactionSummaries`.
- **No change needed** to the generic `ApiService.create`/`update` methods themselves — they are table-agnostic.

### 5.3 Explicitly out of scope for "Create Post" but consequential

Rendering a Deal/Event post afterward (feed card styling, an "Interested" button, offer badges) touches `explore_feed_post_card.dart` and whatever renders messages in a channel — **not** part of the composer, but unavoidable follow-up work once a Deal/Event post can exist. Flagged, not designed here, since no reference image shows the resulting card.

---

## 6. Frontend Architecture

### 6.1 Component structure

Keep `CreatePostScreen` as the owning `StatefulWidget` (no new BLoC introduced — the existing screen is plain `StatefulWidget` state, and introducing a dedicated `CreatePostBloc` would be a bigger architectural change than this task calls for). Proposed decomposition, under `lib/modules/posts/`:

```
create_post_screen.dart          # app bar, POST TYPE pill selector, hosts the active form, bottom action bar (unchanged)
widgets/
  post_type_selector.dart        # the 3-pill Update/Event/Deal control
  update_post_form.dart          # Title + Content + "channels you pick next" caption (today's form, relabeled)
  event_post_form.dart           # Title + Date/Starts/Ends row + Location(+map button) + Content + static info box
  deal_post_form.dart            # Title + Offer chips + Amount/Starts/Ends row + Promo Code + Content
  offer_type_chips.dart          # the 4-chip % off / $ off / BOGO / Freebie selector, shared only by the Deal form
```

This mirrors an existing precedent in the codebase — `lib/modules/market/widgets/listing_form_fields.dart` already extracts shared form-field widgets out of a listing screen the same way. Each sub-form owns its own `TextEditingController`s/local state and exposes a single "current values" object upward (e.g. a small `DealPostData`/`EventPostData` value class) rather than the parent reaching into child state — kept intentionally simple, consistent with how `AttachmentData` already works as a plain value object passed up via a callback.

The attachment bar (paperclip → bottom sheet → image/PDF/link/paste) is unchanged and shared by all three tabs.

### 6.2 State/validation

- `CreatePostScreen` holds `_selectedPostType` (`'update' | 'event' | 'deal'`, mapped to the DB's `'text'`-or-`'message'` / `'event'` / `'deal'` at submit time — Update still needs the existing text-vs-message inference since the DB has no single `'update'` value).
- Each sub-form validates its own required fields on submit (Title always; Deal needs Offer+Amount(when applicable)+Starts+Ends; Event needs Date+Starts at minimum, pending Open Question #4 on Ends/Location).
- Date pickers: `showDatePicker`/`showTimePicker` (Flutter built-ins) — no existing date-picker widget was found elsewhere in the posts/market modules to reuse; this would be the first one in this part of the app apart from general Flutter date-pickers that may exist in unexamined admin screens.

### 6.3 Responsive layout

No existing desktop-specific breakpoint pattern was found anywhere in the files examined. Proposed default: keep the existing `SingleChildScrollView` + bottom action bar structure unchanged, and on windows wider than a phone, wrap the scroll content in a centered `ConstrainedBox(maxWidth: ~480)` so the form doesn't stretch edge-to-edge — a minimal, low-risk responsive treatment, not a redesign. This is explicitly a proposal pending confirmation (Open Question #6), since none of the three references show a wide-screen layout.

---

## 7. Implementation Plan

| Phase | Work | Depends on |
|---|---|---|
| **1. Database** | New migration: widen `post_type` check, update `file_required_for_media`, add Deal columns + check, add Event columns + check, create `post_event_interests` + RLS + `post_interest_counts` view. Apply to the **QA** Supabase project first (per the app's existing qa/prod split), verify, then apply the identical SQL to **production**. | Design sign-off in this doc |
| **2. Backend/API** | Extend `ChatMessage` model, `SendMessageEvent`, `ChatService.sendMessage()` with the new optional fields; add `toggleEventInterest`/`getEventInterestCount` to `ApiRepository`/`SupabaseApiService`, mirroring the reaction methods. | Phase 1 (columns must exist) |
| **3. Frontend** | Build `PostTypeSelector`, `UpdatePostForm`, `EventPostForm`, `DealPostForm`, `OfferTypeChips`; wire date/time pickers; wire per-tab validation; wire submit into the extended `sendMessage`/create path. | Phase 2 |
| **4. File upload integration** | Confirm attachment support is identical across tabs (paperclip bar appears unchanged in all three references); reuse `uploadGenericFile()` as-is — expected to need no new code, only wiring inside the new forms. | Can run alongside Phase 3 |
| **5. Testing & verification** | Unit tests for per-tab validation; manual QA: create one post of each type, confirm the DB row and its constraints, confirm the existing Update-only edit flow (`ExploreFeedPostCard`) still works unmodified, confirm the push-notification trigger still fires for all three types, confirm the Interested toggle/count round-trips. | All above |

Phase 1 must land and be verified on QA before Phase 2 code is written against it (the Dart code will reference the new columns by name). Phases 3 and 4 can overlap. Nothing in this plan touches `CreatePostScreenNoAnimation` — whether that screen is dead code, a fallback, or actually in use needs to be confirmed before deciding whether it also needs the new tabs (Open Question #7).
