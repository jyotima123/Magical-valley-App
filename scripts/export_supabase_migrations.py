#!/usr/bin/env python3
"""
Copy migrations/NNN[_name].sql into supabase/migrations/<timestamp>_<name>.sql
so the Supabase CLI (`supabase db push`) can apply them.

- Source files are never modified or deleted.
- Each copy gets a `SET search_path TO public, extensions;` header (needed for uuid_generate_v4()).
- Order: numeric prefix, then file name (so duplicate 045/062 get a stable order).
- Timestamps are synthetic (2025-01-01 00:00:00 + 1s per file) and deterministic,
  so re-running yields identical names. New files appended later get later stamps.

Usage:
    python scripts/export_supabase_migrations.py            # copy
    python scripts/export_supabase_migrations.py --dry-run  # just list
"""
from __future__ import annotations

import argparse
import re
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "migrations"
DST = ROOT / "supabase" / "migrations"
BASE = datetime(2025, 1, 1, 0, 0, 0)
# Supabase installs extensions (uuid-ossp, ...) in the "extensions" schema, which is
# not on the search_path when `supabase db push` runs. Prepend it to every file.
HEADER = "-- added by export_supabase_migrations.py\nSET search_path TO public, extensions;\n\n"
# Ad-hoc snippets that are not real migrations (e.g. 009 is markdown-quoted example
# calls with a placeholder UUID). Skipped on export.
SKIP = {"009.sql"}
# Per-file text fixes applied to the exported copy only (sources stay untouched).
# Stray paste artifacts that the SQL parser rejects.
FIXES = {
    # Postgres forbids subqueries in CHECK; move the uniqueness test into an immutable function
    "032.sql": [
        ("-- 1. Create the post_reactions table\nCREATE TABLE post_reactions (",
         "CREATE OR REPLACE FUNCTION emoji_array_is_unique(arr text[]) RETURNS boolean\n"
         "LANGUAGE sql IMMUTABLE AS $f$\n"
         "    SELECT coalesce(array_length(arr, 1), 0) = coalesce((SELECT count(DISTINCT e) FROM unnest(arr) AS e), 0)\n"
         "$f$;\n\n"
         "-- 1. Create the post_reactions table\nCREATE TABLE post_reactions ("),
        ("        array_length(emoji_reactions, 1) = \n        array_length(array(SELECT DISTINCT unnest(emoji_reactions)), 1)\n",
         "        emoji_array_is_unique(emoji_reactions)\n"),
        # set-returning unnest() inside aggregates is illegal; expand via LATERAL join instead
        ("    COUNT(pr.id) as total_users_reacted,\n"
         "    COUNT(unnest(pr.emoji_reactions)) as total_emoji_reactions,\n"
         "    array_agg(DISTINCT unnest(pr.emoji_reactions)) as unique_emojis_used\n"
         "FROM posts p\n"
         "LEFT JOIN post_reactions pr ON p.id = pr.post_id\n",
         "    COUNT(DISTINCT pr.id) as total_users_reacted,\n"
         "    COUNT(e.emoji) as total_emoji_reactions,\n"
         "    COALESCE(array_agg(DISTINCT e.emoji) FILTER (WHERE e.emoji IS NOT NULL), ARRAY[]::text[]) as unique_emojis_used\n"
         "FROM posts p\n"
         "LEFT JOIN post_reactions pr ON p.id = pr.post_id\n"
         "LEFT JOIN LATERAL unnest(pr.emoji_reactions) AS e(emoji) ON true\n"),
    ],
    "023.sql": [("handle_new_user();G", "handle_new_user();")],
    "066_organization_gps_and_photos.sql": [(" believe-- ====", "-- ====")],
    "082_first_run_hints.sql": [
        ("  supabase functions deploy ingest-vendor-feed  --project-ref jivehzyxobdggekoyrzh --no-verify-jwt",
         "-- (removed stray shell command: supabase functions deploy ingest-vendor-feed)"),
    ],
}
PATTERN = re.compile(r"^(\d+)(?:_(.+))?\.sql$")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    files = []
    for p in SRC.glob("*.sql"):
        if p.name in SKIP:
            print(f"skip (not a migration): {p.name}")
            continue
        m = PATTERN.match(p.name)
        if m:
            files.append((int(m.group(1)), p.name, p, m.group(2) or m.group(1)))
        else:
            print(f"skip (unrecognized name): {p.name}")
    files.sort(key=lambda t: (t[0], t[1]))

    if not args.dry_run:
        DST.mkdir(parents=True, exist_ok=True)

    for i, (_, _, path, slug) in enumerate(files):
        stamp = (BASE + timedelta(seconds=i)).strftime("%Y%m%d%H%M%S")
        target = DST / f"{stamp}_{slug}.sql"
        print(f"{path.name:70} -> {target.name}")
        if not args.dry_run:
            body = path.read_text(encoding="utf-8").replace(chr(13) + chr(10), chr(10))  # normalize CRLF
            for old, new in FIXES.get(path.name, []):
                if old not in body:
                    raise SystemExit(f"fix for {path.name} did not match: {old!r}")
                body = body.replace(old, new)
            with open(target, "w", encoding="utf-8", newline="\n") as f:
                f.write(HEADER + body)

    print(f"\n{len(files)} migrations {'would be ' if args.dry_run else ''}copied to {DST}")


if __name__ == "__main__":
    main()
