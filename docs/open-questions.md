# Create Post Redesign — Open Questions

These need your confirmation before any implementation starts. None of them were guessed at or silently resolved in the technical analysis or the proposed decisions — where the analysis had to assume something to keep moving, it says so and points back here.

1. **"Shows in the Home feed of the channels you pick next" (Update tab).** Today a post belongs to exactly one channel/organization (`posts.organization_id`, single FK). This caption describes a multi-channel selection step that doesn't exist anywhere in the current app — the existing `SelectOrganizationScreen` is single-select and is used for something else (starting a DM). Three things need answers:
   - Does this multi-channel step apply only to the Update tab, or to Deal/Event too?
   - When a post goes to multiple channels, should it behave as N independent posts (one row per channel — my default recommendation, since it needs zero schema change and each channel gets its own notification/view-count/edit lifecycle), or as one logical post that must stay in sync across channels if edited later (which would need a new join table)?
   - Is the channel-picker screen itself part of this task, or an already-planned/separate piece of work I shouldn't design here?

2. **Event "Location" field + map icon.** The field is a plain text box, not a search/autocomplete widget, and the map icon's behavior isn't shown mid-interaction in a static mock. My analysis assumes it just opens the typed address in a maps app (no geocoding, no lat/lng stored) — consistent with how organizations already store a plain `maps_url` rather than coordinates (migration `067_organization_maps_url.sql`). Please confirm whether that's right, or whether real geocoding/autocomplete is actually wanted.

3. **Event "Interested" → "get a reminder."** The composer screen itself only needs a static info box (confirmed from the image — there's no Interested button in the composer). But making the promise in that box true requires a decision outside the composer:
   - Is "save to calendar + reminder" a purely local/device action (e.g. generate an `.ics` file or use a calendar-integration package when the user taps Interested on the published post), with no server involvement?
   - Or does the server need to schedule and send a push notification close to the event's start time? That would require a new scheduled job/Edge Function, which is a meaningfully bigger piece of backend work than anything else in this redesign, and isn't described or shown anywhere in the three references.

4. **Which Event fields are actually required.** All three sample screenshots have every field pre-filled, so there's no way to tell which fields show a red "required" state if left empty. Specifically: is `Ends` optional (some events might be open-ended), and is `Location` optional (some events might be "online" or TBD)? Same question applies to Deal's `Starts`/`Ends`/`Amount`.

5. **Deal "Amount" when Offer is "Buy 1 get 1" or "Freebie."** The reference image only shows the "% off" state with `Amount` = "20%". For the other two offer types, should the `Amount` field be hidden, disabled/greyed, or left as free text with no enforced meaning? Please confirm which.

6. **Desktop/tablet layout.** All three references are phone-width mockups. No existing screen examined this session has a desktop-specific layout to pattern-match against. The technical analysis proposes a minimal centered-max-width treatment on wide screens as a safe default — confirm that's acceptable, or provide a desktop reference if one exists.

7. **`CreatePostScreenNoAnimation` — is it live?** The codebase contains two composer screens. I could not find a navigation call to either `CreatePostScreen` or `CreatePostScreenNoAnimation` in the files examined this session, so I can't yet confirm which screen (or both) is actually reachable in the running app, or where the "+" / "new post" entry point lives. Before touching any screen I need to know: is `CreatePostScreenNoAnimation` dead code, a fallback for something (e.g. reduced-motion), or does it also need the new tabs? Pointing me at its call site (or confirming there isn't one) will settle this quickly.

8. **`promo_code` column naming/scope.** Proposed as a plain `posts.promo_code` column (not `deal_promo_code`), since a `CHECK` constraint already restricts it to `post_type = 'deal'` rows only. Flagging the name for your sign-off rather than assuming it.

9. **Editing an existing Deal/Event post.** Is editing meant to reuse this same tabbed `CreatePostScreen` pre-filled with the post's current values (consistent with how Update-type posts are currently edited inline via `ExploreFeedPostCard`), or is edit explicitly out of scope for this piece of work? The three references only show the creation flow.

10. **Feed/card rendering for Deal and Event posts.** Not part of the composer itself, but a direct consequence of being able to create these post types: `explore_feed_post_card.dart` and wherever channel messages render will need new branches to actually display an offer badge, a date/location line, and an Interested button/count. No reference image shows this. Should this be scoped into the same piece of work, or tracked separately once the composer ships?
