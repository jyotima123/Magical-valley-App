---
title: vAuto Export Feed Setup
eyebrow: Cars Section · Vendor Onboarding
standfirst: Our answers to vAuto's new-export-vendor form, the questions we need answered back before the feed can go live, and the endpoint that receives the files.
meta:
  Owner: Alisson Damasceno
  Date: 2026-09-07
  Status: Ready to send
theme: light
---

## What vAuto is asking for

vAuto is an inventory management platform used by dealerships. When a dealer authorises an export, vAuto pushes that dealer's inventory to a destination on a schedule — the same way they feed AutoTrader or Cars.com. Their form is asking where to push ours.

So the direction is **vAuto → us**. We host an SFTP endpoint, they connect twice a day and drop a CSV per dealership, and our ingest picks it up from there. Nobody at either company touches a file by hand.

::: {.info title="One decision drives the rest"}
Every answer below is a commitment we then build against — the delimiter, the filename, one file per dealer. They are cheap to choose now and expensive to change once vAuto has provisioned the feed, because changing them means a support ticket on their side.
:::

## The answer sheet

Copy this back to vAuto. Bracketed values are filled in once the server is up.

| Their question | Our answer |
|---|---|
| FTP/SFTP site URL | `sftp://[RESERVED_IP]` — **SFTP** (SSH File Transfer Protocol) on **port 22**. Please do not use plain FTP. |
| User | `vauto` |
| Password | `[generated — sent separately, not in this email]` |
| Schedule and frequency | Twice daily: **6:00 AM and 6:00 PM Mountain Time**. If only one run per day is supported, 6:00 AM MT. |
| File type | `.csv` |
| Delimiter | Comma, with RFC 4180 double-quote qualification. UTF-8, header row included. |
| Multi-value delimiter | Pipe — the vertical bar \| — for fields holding several values (features, options, photo URLs). |
| File naming | `mvc_<yourDealerId>_<YYYYMMDD>_<HHmm>.csv`, e.g. `mvc_48213_20260907_1800.csv`. Please include the timestamp so one run never overwrites another. |
| File specifics | **One file per dealership**, all delivered through the **same** `vauto` credentials. Please also carry the dealer ID as a column inside the file. |
| File specs | Please send your **standard export** first — we will map from it and come back with anything missing. Required fields listed below; field order does not matter to us as long as the header row is present. |
| Company name for dealer requests | **Magic Valley Central** |

### Fields we need

Stock number · VIN · year · make · model · trim · condition (new/used/certified) · certified flag · mileage · list price · advertised or discounted price · body type · exterior colour · interior colour · transmission · fuel type · drivetrain · doors · engine · cylinders · description · options/features · photo URLs · dealer ID · dealer name · last-modified timestamp.

::: {.tip title="Your standard export is probably fine as-is"}
Our importer matches column names leniently — `Stock Number`, `stock_number` and `StockNumber` all resolve to the same field — so in most cases no custom build is needed on vAuto's side.
:::

## Questions we need answered back

These change what we build, so they go in the same reply.

1. **Is each file a complete snapshot of that dealership's current inventory, or only what changed since the last run?**
2. **Are sold or removed vehicles included with a status flag, or do they simply stop appearing?**
3. **Are photo URLs permanent?** We cache images indefinitely on the assumption that a given URL's content never changes.
4. **Can the file be uploaded under a temporary name and renamed to `.csv` on completion?**
5. **What source IP addresses will you connect from?** We would like to allowlist them.
6. **Character encoding and line endings** — we assume UTF-8; please confirm.

::: {.warning title="Question 1 is the one that matters"}
Snapshot and delta feeds need opposite handling. If each file is a full snapshot, a vehicle that stops appearing has left the lot and should disappear from the app. If we assume that about a delta feed, the first partial delivery marks a dealer's **entire** inventory as sold.

The reconciliation step ships switched off (`FEED_MARK_MISSING_AS_SOLD=false`) and stays off until vAuto confirms snapshot semantics in writing.
:::

## Where the files land

```
vAuto  --SFTP(22)-->  DigitalOcean droplet         Supabase (already on Pro)
                      SFTPGo, chrooted    ──S3──>  vendor-feeds/inbound/vauto/
                             │                              │
                             └── upload-success hook ───────┘
                                          │
                                          v
                              Edge Function ingest-vendor-feed
                                          │
                                          v
                              vehicle_listings (source='vauto:<dealerId>')
```

The droplet runs [SFTPGo](https://github.com/drakkan/sftpgo), which can use S3-compatible object storage as a user's filesystem. Bytes vAuto writes go straight into the Supabase Storage we already pay for — no local disk, no sync job, no second copy to reconcile, and nothing lost if the droplet is rebuilt.

| Item | Monthly |
|---|---|
| DigitalOcean droplet, 1 GB / 1 vCPU, US region | ~$6 |
| Reserved IP (free while attached) | $0 |
| Supabase Storage — ~600 MB/yr against a 100 GB allowance | $0 |
| **Total** | **~$6** |

::: {.note title="Why a server at all"}
SFTP needs a long-lived listener on a TCP port. Supabase has no SFTP front end, and no serverless platform — Edge Functions, Cloudflare, Vercel — can accept a raw SFTP connection. A small VM is the floor. Managed SFTP services start around $10–25/mo for the same one endpoint.
:::

### Use a Reserved IP, not the droplet's own

We are giving vAuto a bare IP address rather than a hostname, so that address is effectively permanent — changing it later means a support ticket with them. A DigitalOcean **Reserved IP** can be remapped to a different droplet in seconds, which restores the freedom a DNS record would have given us, at no cost while it is attached.

## One dealership per source key

vAuto delivers a separate file for each dealership it exports for, and each of those dealerships is a different business with a different inbox. So a dealership — not the vendor — is the unit in `dealer_sources`:

```sql
INSERT INTO dealer_sources
  (source, organization_id, provider, kind, dealer_ref, display_name, is_active)
VALUES
  ('vauto:48213', '<organizations.id>', 'vauto', 'feed', '48213',
   'Smith Chevrolet', true);
```

Collapsing them into one `vauto` source would route every dealer's buyer messages into a single organization's inbox, and would make "mark everything absent from this file as sold" erase every *other* dealership's inventory on each import.

Until that row exists, the ingest function rejects that dealer's file with a named error rather than inventing a home for the vehicles. Onboarding the next dealership — or the next vendor entirely — is an INSERT, not a migration.
