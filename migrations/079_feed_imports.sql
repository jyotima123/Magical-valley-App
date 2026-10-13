-- ============================================================================
-- 079: Audit log for ingested inventory files
--
-- A kind='feed' provider delivers a file and walks away. Nobody is watching the
-- moment it lands, so without a record there is no way to answer the only
-- questions that matter when a dealer calls: did the 6 PM file arrive, how many
-- vehicles were in it, and why did 40 cars disappear from the app last night.
--
-- One row per attempt, written by the ingest Edge Function under the service
-- role. Retries are allowed; a given file can only succeed once.
--
-- Applies on top of 078.
-- ============================================================================

CREATE TABLE IF NOT EXISTS feed_imports (
    id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    source               text        NOT NULL REFERENCES dealer_sources(source),

    -- Storage object this run read, e.g. inbound/vauto/mvc_48213_20260906_1800.csv.
    -- The file itself is kept in the bucket, so this doubles as a pointer back
    -- to the exact bytes that produced the numbers below.
    object_path          text        NOT NULL,

    -- The provider's own dealer identifier, as carried by the file. Text, not a
    -- FK: it is their namespace, and we may see a dealer here before we have
    -- ever heard of them.
    dealer_ref           text,

    status               text        NOT NULL DEFAULT 'running',

    rows_read            integer     NOT NULL DEFAULT 0,
    rows_skipped         integer     NOT NULL DEFAULT 0,
    vehicles_upserted    integer     NOT NULL DEFAULT 0,
    vehicles_marked_sold integer     NOT NULL DEFAULT 0,

    -- Populated on failure, and on success when rows were skipped: the operator
    -- needs to see "12 rows had no VIN or stock number" without opening the CSV.
    error                text,

    started_at           timestamptz NOT NULL DEFAULT now(),
    finished_at          timestamptz,

    CONSTRAINT feed_imports_status_check
      CHECK (status IN ('running', 'success', 'failed')),

    -- A finished run has an end; a running one does not yet.
    CONSTRAINT feed_imports_finished_when_done CHECK (
      (status = 'running' AND finished_at IS NULL) OR
      (status <> 'running' AND finished_at IS NOT NULL)
    )
);

-- "What happened to this provider lately", the query every operator runs.
CREATE INDEX IF NOT EXISTS idx_feed_imports_source_started
  ON feed_imports (source, started_at DESC);

-- Idempotency guard. SFTPGo can fire its upload hook more than once for the
-- same object (a retried webhook, a resumed transfer), and re-importing a file
-- would re-run the mark-as-sold reconciliation against stale contents. A file
-- may be retried as often as needed while it keeps failing, but may succeed
-- exactly once per dealership.
--
-- Scoped by source, not by object alone: a combined file covering several
-- dealerships writes one row per dealership, and all of them are legitimately
-- successful imports of the same object.
CREATE UNIQUE INDEX IF NOT EXISTS feed_imports_one_success_per_object
  ON feed_imports (object_path, source)
  WHERE status = 'success';

ALTER TABLE feed_imports ENABLE ROW LEVEL SECURITY;

-- Operator-facing only. The ingest function writes as the service role, which
-- bypasses RLS, so there is deliberately no INSERT/UPDATE policy here: nothing
-- holding a user's JWT has any business writing an import record.
DROP POLICY IF EXISTS "Admins can view feed imports" ON feed_imports;
CREATE POLICY "Admins can view feed imports"
    ON feed_imports FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
        )
    );

COMMENT ON TABLE feed_imports IS
  'One row per attempt to ingest a delivered inventory file. Written by the '
  'ingest-vendor-feed Edge Function under the service role; readable by admins.';

COMMENT ON COLUMN feed_imports.vehicles_marked_sold IS
  'Vehicles present in this provider''s previous file but absent from this one, '
  'flipped to is_sold. Only meaningful when the provider sends full snapshots — '
  'a delta feed must never populate this.';
