-- ============================================================================
-- Migration 082: First-run hint dialogs served from the database
-- ============================================================================
-- The single-page hint dialogs (AppDialog, see docs/dialog_types.md) used to
-- have their heading and subheading hard-coded in each screen, and the app
-- remembered only whether a hint had been shown. Now the text lives here, one
-- row per hint, so it can be changed without shipping a build.
--
-- The app stores, per hint, the content_updated_at of the version the user
-- last saw. When a screen opens it fetches its row; if content_updated_at is
-- newer than what was stored, the dialog is shown again with the new text.
-- So: editing heading or subheading re-shows that hint to everyone once.
--
-- content_updated_at is bumped only when heading or subheading change, so
-- toggling is_active (or any future column) does not re-show anything. To
-- deliberately re-show unchanged text, set content_updated_at = now().
--
-- The icon stays in the app: Flutter tree-shakes icon fonts, so an icon
-- chosen at runtime from a database value would not render in release builds.
--
-- Applies on top of 081.
-- ============================================================================

CREATE TABLE IF NOT EXISTS first_run_hints (
    key                 text PRIMARY KEY,
    heading             text NOT NULL,
    subheading          text,
    is_active           boolean NOT NULL DEFAULT true,
    content_updated_at  timestamptz NOT NULL DEFAULT now(),
    created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE first_run_hints IS
    'Text of the one-time hint dialogs, keyed by the FirstRunKeys constant in '
    'the app. A newer content_updated_at re-shows the hint to users who saw an '
    'older version.';

COMMENT ON COLUMN first_run_hints.content_updated_at IS
    'Bumped by trigger when heading or subheading change. The app compares it '
    'with the timestamp it stored when the user last saw this hint.';

-- Keys match FirstRunKeys in lib/services/first_run_service.dart.
-- DO NOTHING so a re-run never undoes copy edited in production.
INSERT INTO first_run_hints (key, heading, subheading) VALUES
    ('chat_follow_hint',
     'Explore and follow channels',
     'Use the Explore tab to follow channels and see their posts here.'),
    ('profile_settings_hint',
     'Manage your profile',
     'Here you can edit your profile picture and name, view organizations you follow, and manage your account settings.'),
    ('edit_user_hint',
     'Change your display name',
     'Use this screen to update your name and profile picture.'),
    ('create_organization_hint',
     'Create a Channel',
     'Fill in the Channel name, upload a logo, and select categories. You will be automatically assigned as the admin.'),
    ('create_post_hint',
     'Create a post',
     'Add a title and content, or attach images, PDFs, links, or paste content. Use the attachment button to add media.'),
    ('market_hint',
     'Welcome to the Market',
     'Browse listings by category, message sellers directly in the app, and tap + to list something of your own.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION first_run_hints_bump_content_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.heading IS DISTINCT FROM OLD.heading
       OR NEW.subheading IS DISTINCT FROM OLD.subheading THEN
        NEW.content_updated_at = now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS first_run_hints_content_updated_at ON first_run_hints;
CREATE TRIGGER first_run_hints_content_updated_at
    BEFORE UPDATE ON first_run_hints
    FOR EACH ROW EXECUTE FUNCTION first_run_hints_bump_content_updated_at();

ALTER TABLE first_run_hints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view first run hints"
    ON first_run_hints;
CREATE POLICY "Authenticated users can view first run hints"
    ON first_run_hints FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Superadmins manage first run hints"
    ON first_run_hints;
CREATE POLICY "Superadmins manage first run hints"
    ON first_run_hints FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );

-- Example: change the Market hint; everyone sees it again on their next visit.
-- UPDATE first_run_hints
-- SET subheading = 'New copy here.'
-- WHERE key = 'market_hint';
  supabase functions deploy ingest-vendor-feed  --project-ref jivehzyxobdggekoyrzh --no-verify-jwt