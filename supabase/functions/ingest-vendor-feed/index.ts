// ---------------------------------------------------------------------------
// ingest-vendor-feed
//
// Called by the SFTP host (SFTPGo's event manager) the moment a vendor finishes
// uploading a file — on success only, so a half-written transfer never reaches
// here. Reads the CSV out of the vendor-feeds bucket, maps it, and upserts the
// dealership's inventory into vehicle_listings.
//
// This is the first server-side ingest in the project. Everything before it
// (LiftKit) is pulled live by the client, which is not an option for a feed
// that arrives as a file twice a day and has no API to query.
//
//   POST { "objectPath": "inbound/vauto/mvc_48213_20260906_1800.csv" }
//   header: x-feed-secret: <FEED_INGEST_SECRET>
// ---------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { parse } from "https://deno.land/std@0.224.0/csv/parse.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
import {
  mapRow,
  type MappedVehicle,
  normalizeRow,
  pickDealerRef,
  SkippedRow,
} from "./mapper.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-feed-secret",
};

const BUCKET = "vendor-feeds";

/// Postgres statements have limits and Edge Functions have memory limits; 500
/// rows per round trip keeps both comfortable for a 10 MB file.
const BATCH_SIZE = 500;

/// Marking absent vehicles as sold is only correct if each file is a COMPLETE
/// snapshot of that dealership's inventory. Until vAuto confirms that in
/// writing, this stays off: treating a delta file as a snapshot would flip a
/// dealer's entire inventory to sold on the first partial delivery.
const MARK_MISSING_AS_SOLD =
  Deno.env.get("FEED_MARK_MISSING_AS_SOLD") === "true";

interface IngestRequest {
  objectPath?: string;
  /// Optional override; normally derived from the path (inbound/<provider>/...).
  provider?: string;
}

interface SourceRow {
  source: string;
  provider: string;
  dealer_ref: string | null;
  is_active: boolean;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const secret = Deno.env.get("FEED_INGEST_SECRET");
  if (!secret || req.headers.get("x-feed-secret") !== secret) {
    // The SFTP host is the only caller; anything else is noise or probing.
    return json({ error: "Unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: IngestRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const objectPath = body.objectPath?.trim();
  if (!objectPath) return json({ error: "objectPath is required" }, 400);

  // inbound/vauto/mvc_48213_....csv -> "vauto"
  const provider = body.provider?.trim() || objectPath.split("/")[1];
  if (!provider) {
    return json({ error: `Cannot infer provider from "${objectPath}"` }, 400);
  }

  // A retried webhook must not re-run reconciliation against a file whose
  // contents are, by then, one delivery out of date.
  const { data: existing } = await supabase
    .from("feed_imports")
    .select("id")
    .eq("object_path", objectPath)
    .eq("status", "success")
    .limit(1);

  if (existing && existing.length > 0) {
    return json({ status: "already_imported", objectPath });
  }

  const startedAt = new Date().toISOString();

  try {
    const result = await ingest(supabase, provider, objectPath, startedAt);
    return json({ status: "ok", objectPath, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`ingest failed for ${objectPath}: ${message}`);

    // The failure itself is the thing an operator needs to see, so it is
    // recorded even though the import produced nothing.
    const fallbackSource = await anySourceFor(supabase, provider);
    if (fallbackSource) {
      await supabase.from("feed_imports").insert({
        source: fallbackSource,
        object_path: objectPath,
        status: "failed",
        error: message,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
      });
    }

    return json({ error: message }, 500);
  }
});

// ---------------------------------------------------------------------------

async function ingest(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  provider: string,
  objectPath: string,
  startedAt: string,
) {
  const { data: file, error: downloadError } = await supabase.storage
    .from(BUCKET)
    .download(objectPath);

  if (downloadError || !file) {
    throw new Error(
      `Could not read ${BUCKET}/${objectPath}: ${downloadError?.message ?? "not found"}`,
    );
  }

  const text = await file.text();
  const parsed = parse(text, { skipFirstRow: true }) as Record<
    string,
    string
  >[];

  if (parsed.length === 0) throw new Error("File contains no data rows");

  const rows = parsed.map(normalizeRow);

  // A file is normally one dealership, but grouping by the dealer column costs
  // nothing and means a combined file — should vAuto ever send one — is handled
  // correctly rather than attributed wholesale to the first dealer in it.
  const registry = await loadSources(supabase, provider);
  const groups = new Map<string, typeof rows>();
  const unknownDealers = new Set<string>();
  let skipped = 0;

  for (const row of rows) {
    const ref = pickDealerRef(row);
    const entry = resolveSource(registry, ref);
    if (!entry) {
      unknownDealers.add(ref || "(no dealer id column)");
      skipped++;
      continue;
    }
    const bucket = groups.get(entry.source) ?? [];
    bucket.push(row);
    groups.set(entry.source, bucket);
  }

  if (groups.size === 0) {
    throw new Error(
      `No onboarded dealership matched this file. Unknown dealer ids: ` +
        `${[...unknownDealers].join(", ")}. Add a dealer_sources row ` +
        `(provider='${provider}', dealer_ref=<id>) before re-running.`,
    );
  }

  const summary = {
    rowsRead: rows.length,
    rowsSkipped: skipped,
    vehiclesUpserted: 0,
    vehiclesMarkedSold: 0,
    dealers: [] as string[],
  };
  const notes: string[] = [];

  if (unknownDealers.size > 0) {
    notes.push(
      `skipped ${skipped} row(s) for un-onboarded dealer id(s): ` +
        `${[...unknownDealers].join(", ")}`,
    );
  }

  for (const [source, groupRows] of groups) {
    const outcome = await ingestDealer(
      supabase,
      source,
      groupRows,
      objectPath,
      startedAt,
    );
    summary.vehiclesUpserted += outcome.upserted;
    summary.vehiclesMarkedSold += outcome.markedSold;
    summary.rowsSkipped += outcome.skipped;
    summary.dealers.push(source);
    if (outcome.note) notes.push(`${source}: ${outcome.note}`);
  }

  return { ...summary, notes };
}

async function ingestDealer(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: string,
  rows: Record<string, string>[],
  objectPath: string,
  startedAt: string,
) {
  const { data: run } = await supabase
    .from("feed_imports")
    .insert({
      source,
      object_path: objectPath,
      dealer_ref: source.includes(":") ? source.split(":")[1] : null,
      status: "running",
      started_at: startedAt,
    })
    .select("id")
    .single();

  const runId = run?.id;
  const reasons: string[] = [];
  let skipped = 0;

  // Two de-duplication passes, both guarding real unique constraints:
  // vehicle_listings_external_id_unique and vehicle_listings_vin_unique. A file
  // that lists the same car twice would otherwise abort the whole batch.
  const byExternalId = new Map<string, MappedVehicle>();
  const seenVins = new Set<string>();

  for (const row of rows) {
    let vehicle: MappedVehicle;
    try {
      vehicle = mapRow(row, source);
    } catch (error) {
      if (error instanceof SkippedRow) {
        skipped++;
        reasons.push(error.message);
        continue;
      }
      throw error;
    }

    if (vehicle.vin) {
      if (seenVins.has(vehicle.vin)) {
        skipped++;
        reasons.push("duplicate VIN in file");
        continue;
      }
      seenVins.add(vehicle.vin);
    }
    // Last occurrence wins, matching how a re-sent row is meant to correct one
    // sent earlier in the same file.
    byExternalId.set(vehicle.external_id, vehicle);
  }

  const vehicles = [...byExternalId.values()];
  const touchedAt = new Date().toISOString();
  let upserted = 0;

  // A car is matched to its existing row by VIN, not by external_id. The
  // external_id carries the stock number, and dealers re-stock cars — a trade-in
  // re-listed as "TF134387A" after being "ST9920A". Keyed on external_id, that
  // is a brand-new row whose VIN collides with the old one on
  // vehicle_listings_vin_unique (source, vin), and the whole batch fails. Keyed
  // on VIN, the old row is updated in place and simply takes the new stock
  // number. Rows without a VIN have nothing better than the stock number.
  const withVin = vehicles.filter((v) => v.vin !== null);
  const withoutVin = vehicles.filter((v) => v.vin === null);
  const passes: [MappedVehicle[], string][] = [
    [withVin, "source,vin"],
    [withoutVin, "external_id"],
  ];

  for (const [group, onConflict] of passes) {
    for (let i = 0; i < group.length; i += BATCH_SIZE) {
      const batch = group
        .slice(i, i + BATCH_SIZE)
        // Set explicitly rather than relying on a trigger: the reconciliation
        // below uses updated_at as its watermark for "was in this file".
        .map((v) => ({ ...v, updated_at: touchedAt }));

      const { data, error } = await supabase
        .from("vehicle_listings")
        .upsert(batch, { onConflict })
        .select("id");

      if (error) {
        await finish(supabase, runId, "failed", {
          rows_read: rows.length,
          rows_skipped: skipped,
          vehicles_upserted: upserted,
          error: error.message,
        });
        throw new Error(`Upsert failed for ${source}: ${error.message}`);
      }
      upserted += data?.length ?? 0;
    }
  }

  let markedSold = 0;
  if (MARK_MISSING_AS_SOLD) {
    // Anything for this dealership the file did not touch is no longer in
    // their inventory. The watermark avoids sending thousands of ids back to
    // Postgres in a NOT IN list.
    const { data, error } = await supabase
      .from("vehicle_listings")
      .update({ is_sold: true, updated_at: new Date().toISOString() })
      .eq("source", source)
      .eq("is_sold", false)
      .lt("updated_at", touchedAt)
      .select("id");

    if (error) {
      await finish(supabase, runId, "failed", {
        rows_read: rows.length,
        rows_skipped: skipped,
        vehicles_upserted: upserted,
        error: `Reconciliation failed: ${error.message}`,
      });
      throw new Error(`Reconciliation failed for ${source}: ${error.message}`);
    }
    markedSold = data?.length ?? 0;
  }

  const note = summarizeReasons(reasons);
  await finish(supabase, runId, "success", {
    rows_read: rows.length,
    rows_skipped: skipped,
    vehicles_upserted: upserted,
    vehicles_marked_sold: markedSold,
    error: note,
  });

  return { upserted, markedSold, skipped, note };
}

// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function loadSources(supabase: any, provider: string) {
  const { data, error } = await supabase
    .from("dealer_sources")
    .select("source, provider, dealer_ref, is_active")
    .eq("provider", provider)
    .eq("is_active", true);

  if (error) throw new Error(`Could not load dealer_sources: ${error.message}`);
  if (!data || data.length === 0) {
    throw new Error(
      `No active dealer_sources row for provider '${provider}'. ` +
        `Onboard the dealership before its files can be ingested.`,
    );
  }
  return data as SourceRow[];
}

/// A single-dealership provider carries no dealer id in the file, so a lone
/// registry row with a NULL dealer_ref matches everything.
function resolveSource(registry: SourceRow[], ref: string): SourceRow | null {
  const trimmed = ref.trim();
  if (trimmed !== "") {
    // vAuto identifies a rooftop by a slug ("goodevw", "thecarstore"), not the
    // numeric id the spec sheet showed, so the comparison is case-insensitive:
    // a dealer_ref onboarded as "GoodeVW" must still match the file.
    const wanted = trimmed.toLowerCase();
    const match = registry.find((r) => r.dealer_ref?.trim().toLowerCase() === wanted);
    if (match) return match;
  }
  const wildcard = registry.filter((r) => r.dealer_ref === null);
  return wildcard.length === 1 ? wildcard[0] : null;
}

/// Used only to attach a failed run to something in feed_imports, which has a
/// NOT NULL FK on source. Best effort: a failure that happened before we could
/// identify the dealership still deserves a row.
// deno-lint-ignore no-explicit-any
async function anySourceFor(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  provider: string,
): Promise<string | null> {
  const { data } = await supabase
    .from("dealer_sources")
    .select("source")
    .eq("provider", provider)
    .limit(1)
    .maybeSingle();
  // No row at all means the FK would reject anything we invented here, so the
  // failure is logged and left unrecorded rather than swallowed by a bad insert.
  return data?.source ?? null;
}

// deno-lint-ignore no-explicit-any
async function finish(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  runId: string | undefined,
  status: "success" | "failed",
  fields: Record<string, unknown>,
) {
  if (!runId) return;
  await supabase
    .from("feed_imports")
    .update({ ...fields, status, finished_at: new Date().toISOString() })
    .eq("id", runId);
}

/// Turns 40 identical skip reasons into one line an operator will actually read.
function summarizeReasons(reasons: string[]): string | null {
  if (reasons.length === 0) return null;
  const counts = new Map<string, number>();
  for (const reason of reasons) {
    counts.set(reason, (counts.get(reason) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([reason, count]) => `${count}x ${reason}`)
    .join("; ");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
