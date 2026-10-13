---
title: Cars Inventory Provider Integration
eyebrow: Cars Section · Partner Integration Guide
standfirst: What a new inventory API provider needs to know before we connect their vehicle feed — the data shape, the filters it has to fit, the credentials we need, and how buyer contact works once cars are live.
meta:
  Owner: Alisson Damasceno
  Date: 2026-08-28
  Status: Draft for provider onboarding
theme: light
---

## What we're connecting

Our app has a **Cars** section where users browse vehicle inventory, filter and search it, and get in touch about a specific car. This document is the generic playbook for adding a provider.

Two things happen once a provider is connected:

1. **We display their inventory** inside our Cars section, styled and filterable exactly like every other listing.
2. **Users can message about any car**, and those conversations go to the provider's organization rather than to one person — see [Messaging and notifications](#messaging-and-notifications).

::: callout What "integration" means here
The provider does not need to build anything new. They expose (or already have) a machine-readable inventory feed; we read it, normalize it into our vocabulary, and everything else — search, filters, messaging, notifications — already works.
:::

## How we pull in inventory

There are two supported shapes for getting a provider's cars into the app. Which one applies depends on what the provider can offer.

:::: split
::: panel Live API pull
We call the provider's API directly, on a short cache (today: **10 minutes**), and render whatever comes back. Nothing is stored beyond that cache.

- Freshest possible data — price drops and sold vehicles disappear quickly
- Provider's API must be reasonably fast and tolerate polling
- Every screen open is a live read, so rate limits matter
:::

::: panel Feed + stored copy
We ingest a feed (pull or the provider pushes) and keep our own copy of each vehicle.

- Works for slower or batch-oriented providers (nightly export, SFTP drop, webhook)
- We control freshness independent of the provider's own uptime
- Delimited files are fine here — CSV does not have to become JSON
- Stored rows *are* the inventory, and are what the Cars list renders
:::
::::

::: note Why a stored copy exists even for a live pull
This applies to **live API pull** providers only. For a delivered feed, the stored rows are the real thing — browsable, filterable, and refreshed by each delivery — not the limited copy described here.

The moment a buyer sends the *first* message about a live-feed vehicle, we materialize a private copy of that vehicle into our own database (a "shadow row"). This is what a conversation is *about* — it lets the chat history keep showing what was being discussed even after the car sells or drops out of the provider's feed. It is refreshed on every subsequent contact, is never shown in the browsable Cars list (which always renders the live feed instead), and is not editable by anyone in our app.
:::

## Data we need

Fields fall into a few groups. **Required** means the card and detail screen have nothing sensible to show without it; everything else degrades gracefully (the field or its section is simply hidden).

### Identity and status

| Field | Type | Required | Notes |
|---|---|:-:|---|
| Stock number | string | Yes | Provider's inventory/stock id. Must be unique within that provider's feed (not globally — our own listings and every other provider share the app, so uniqueness is scoped per source). |
| VIN | string | Recommended | 17-character VIN. Used for de-duplication and shown to serious buyers. |
| Year | integer | Yes | |
| Make | string | Yes | Free text, matched loosely against our brand list for filtering — see [Filters and enums](#filters-and-enums-we-support). |
| Model | string | Yes | Free text, same treatment as make. |
| Trim | string | No | |
| Condition / status | enum | Yes | Must map to `New`, `Pre-Owned`, or `Certified Pre-Owned`. A separate "certified" flag, if the provider has one, promotes a used car to `Certified Pre-Owned` on our side. |
| Sold / no-longer-available flag | boolean | Recommended | If the provider can tell us a vehicle is sold rather than just omitting it from the feed, we keep it visible (marked "Sold") instead of it silently vanishing mid-conversation. |

### Pricing

| Field | Type | Required | Notes |
|---|---|:-:|---|
| List price | decimal | Yes* | *A missing or zero price is treated as "Call for price" rather than free — dealer feeds routinely omit price on fresh trade-ins, so this is tolerated, not an error. |
| Advertised / discounted price | decimal | No | Shown struck-through against the list price when lower. If the provider only has one price, send it as the list price and omit this. |

Currency is assumed USD; tell us if a feed needs another currency before we connect it.

### Specifications

| Field | Type | Required | Notes |
|---|---|:-:|---|
| Mileage | integer | Yes | |
| Body / vehicle type | string | Recommended | Normalized into our body-type filter — see enums below. |
| Color (exterior) | string | Recommended | A normalized color bucket if the provider has one, else a free-text color name; we bucket it ourselves as a fallback. |
| Interior color | string | No | |
| Transmission type | string | Recommended | Normalized to `Automatic` / `Manual` / `CVT` / `Semi-Auto / DCT`. |
| Transmission — speed / description | string | No | Free text, e.g. "8-Speed Automatic". |
| Fuel type | string | Recommended | Normalized — see enums below. |
| Drivetrain | string | No | Normalized to `FWD` / `RWD` / `AWD` / `4WD / 4x4`. |
| Engine name / size | string | No | Free text (e.g. "3.5L V6"). |
| Cylinders | string/int | No | |
| Doors | string/int | No | |

### Media

| Field | Type | Required | Notes |
|---|---|:-:|---|
| Photos | array of URLs (or comma-separated) | Yes | First photo is used as the card thumbnail everywhere (search results, message previews, notifications). Photos are cached indefinitely on our side under the assumption that a photo URL's *content* never changes once published — if the provider recycles a URL for different bytes, tell us. |
| Videos | array of URLs (or comma-separated) | No | |

### Descriptive / marketing

| Field | Type | Required | Notes |
|---|---|:-:|---|
| Description | string (HTML tolerated) | No | HTML tags are stripped for plain-text display; basic entities are unescaped. |
| Curated / key features | array of strings | No | A short, buyer-facing highlight list (e.g. "Apple CarPlay", "Heated Seats"). |
| Full option/feature list | array of strings | No | Longer OEM-style option strings. Used for filter matching (see [Filters and enums](#filters-and-enums-we-support)), not necessarily displayed in full. |
| Packages | array of strings or objects with a name | No | |
| Add-ons / options description | string | No | |
| Location | string | No | Lot or dealership location, free text. |

### Fields we deliberately do not use

We do **not** ingest or display a vehicle detail page URL, dealer phone number, or dealer email from a provider feed. See [No outbound links to the provider](#no-outbound-links-to-the-provider) for why.

## Filters and enums we support

Our search screen lets users filter on the categories below. A provider's raw values are normalized into these exact vocabularies on ingestion (this is our responsibility, not the provider's — we map their wording to ours the same way we already do for the connected provider). Values outside a known vocabulary are generally kept as free text and still work for full-text/keyword matching, they just won't populate a filter chip.

| Filter | Current values |
|---|---|
| Body type | `Sedan`, `SUV`, `Pickup Truck`, `Hatchback`, `Coupe`, `Convertible`, `Wagon`, `Minivan`, `Van`, `Sports Car`, `Crossover` |
| Fuel type | `Gasoline`, `Diesel`, `Hybrid`, `Plug-in Hybrid`, `Electric`, `Flex Fuel`, `Hydrogen` |
| Transmission | `Automatic`, `Manual`, `CVT`, `Semi-Auto / DCT` |
| Drivetrain | `FWD`, `RWD`, `AWD`, `4WD / 4x4` |
| Engine size | `Under 1.5L`, `1.5L – 2.0L`, `2.0L – 2.5L`, `2.5L – 3.0L`, `3.0L – 4.0L`, `4.0L+`, `Electric Motor` |
| Steering | `Hydraulic`, `Electric (EPS)`, `Electro-Hydraulic` |
| Doors | `2`, `3`, `4`, `5+` |
| Condition / status | `New`, `Pre-Owned`, `Certified Pre-Owned` |
| Colors | `Black`, `White`, `Silver`, `Gray`, `Red`, `Blue`, `Navy`, `Green`, `Brown`, `Beige`, `Gold`, `Orange`, `Yellow`, `Purple`, `Maroon` |
| Make / model | An open list of ~50 brands, each with its current model lineup |
| Sort options | `Most Relevant`, `Newest Listing`, `Lowest Price`, `Highest Price`, `Lowest Mileage`, `Newest Year`, `Oldest Year` |

::: note Features and conditions are matched, not enumerated
"Feature" chips (e.g. Sunroof, Navigation, Backup Camera) and "condition" chips (e.g. Single Owner, Accident Free, Active Manufacturer Warranty) are matched against the vehicle's free-text fields — description, options, packages, add-ons — rather than against a strict enum. A provider does not need to map into these; sending a reasonably complete options/feature list is enough for these filters to work.
:::

::: warn New filter values
If a provider's data doesn't fit an existing vocabulary well (a body type or fuel type we don't have yet), tell us during onboarding — extending a filter list is a small change on our side, but we'd rather add it deliberately than have a whole provider's inventory fall outside every filter chip.
:::

## What we need from the provider

::: request Typical inventory pull (illustrative shape)
status: 200 OK
vars:
  API_KEY: Provider API key. Issued per provider, sent on every request, never logged.
---
```bash
curl https://api.example-provider.com/v1/vehicles?page=1&limit=100 \
  -H "X-API-Key: {{API_KEY}}"
```

```json
{
  "success": true,
  "vehicles": [
    {
      "stock": "PG205293",
      "vin": "1FTFW1E5XPFA12345",
      "year": "2023",
      "make": "Ford",
      "model": "F-150",
      "trim": "Lariat",
      "type": "Truck",
      "status": "Used",
      "certified": false,
      "mileage": "18342",
      "color": { "simple": "Blue", "name": "Antimatter Blue" },
      "transmission": { "type": "Automatic", "speed": "10-Speed" },
      "engine": { "name": "3.5L V6", "cylinders": "6" },
      "fuel": "Gas",
      "drivetrain": "4WD",
      "doors": "4",
      "pricing": { "original": "48500.00", "final": "45900.00" },
      "description": { "short": "One owner, clean history." },
      "key_features": ["Apple CarPlay / Android Auto", "Backup Camera"],
      "features": ["..."],
      "photos": ["https://cdn.example-provider.com/PG205293/1.jpg"],
      "videos": []
    }
  ],
  "meta": { "has_more": false }
}
```
:::

This is illustrative, not a spec — it mirrors the shape of the provider we already have connected. A new provider's actual field names will differ; what matters is that every field in [Data we need](#data-we-need) is present somewhere in the payload.

A **live API pull** must answer in JSON — it is parsed in the app itself, and we do not ship an XML or CSV parser to the client. A **delivered feed** has no such restriction: a delimited file dropped on our SFTP endpoint is parsed server-side at ingest, so CSV is a first-class option there and no provider needs to rebuild their export to suit us. See [Delivering a feed by SFTP](#delivering-a-feed-by-sftp).

### Access requirements (live API pull)

| Requirement | What we need |
|---|---|
| Authentication | An API key (or equivalent bearer token) issued to us specifically, sent on every request. We store it hashed/at rest and never log it. |
| Pagination | A page/limit (or cursor) scheme, with a reliable "more pages" signal — either a `has_more` flag in the body or a response header. |
| Rate limit | The provider's request-per-minute ceiling, so we can size our polling/cache interval to stay under it. |
| Response format | JSON. |
| Sandbox / test environment | Preferred but not required — lets us validate field mapping before going live against production inventory. |
| Contact for schema questions | A technical contact who can answer "what does this field mean" and "what are the possible values here" during onboarding. |

## Delivering a feed by SFTP

For providers who export files rather than serve an API, we host an SFTP endpoint and you push to it. Nothing has to be built on your side beyond pointing an existing export at us.

::: tip What you get from us
A host address, a username, and a password (or a public key, if you prefer key auth). The account is chrooted to its own directory and cannot see any other provider's files.
:::

| Setting | What we ask for | Why |
|---|---|---|
| Protocol | **SFTP** (SSH File Transfer, port 22). Not plain FTP. | Plain FTP sends the password in the clear. |
| Frequency | Whatever suits your export — once or twice a day is typical. Tell us the times so we can tell a dealer when their inventory refreshes. | |
| Format | CSV, UTF-8, header row included, RFC 4180 quoting. | |
| Field delimiter | Comma. | |
| Multi-value delimiter | Pipe (`|`), for features, options and photo URLs. | Keeps a value containing a comma from silently splitting into two. |
| File naming | Include the dealer id and a timestamp, e.g. `mvc_<dealerId>_<YYYYMMDD>_<HHmm>.csv`. | A timestamp stops one run overwriting another and gives us an audit trail. |
| One file per dealership | Preferred. A combined file is accepted if the dealer id is a column. | A bad file for one dealer then cannot disturb the others. |
| Partial writes | Upload under a temporary name and rename to `.csv` when complete, if your tooling supports it. | Stops us reading a half-written file. |
| Source IPs | The addresses you will connect from, so we can allowlist them. | |

::: warning Snapshot or delta — tell us which
We need to know whether each file is a **complete snapshot** of that dealership's current inventory or only **what changed** since the last run.

If it is a snapshot, a vehicle that stops appearing is treated as sold and leaves the app. If we assume that wrongly about a delta feed, the first partial delivery marks a dealer's entire inventory as sold. We leave this behaviour switched off until a provider confirms it in writing.
:::

Field names are matched leniently — `Stock Number`, `stock_number` and `StockNumber` are all understood — so in most cases your standard export can be sent as-is and we map from it. Send a sample file first and we will come back with anything missing.

## Messaging and notifications

Once a provider's inventory is live, buyer contact works the same way for their cars as it does for every other listing in the app — no extra integration work needed on the provider's side.

::: plain
- **Private, per-buyer conversations.** Any signed-in user can start a conversation about any car. Each buyer gets their own private thread — buyers cannot see each other's messages about the same vehicle.
- **Shared with the whole organization.** A conversation about a provider's vehicle is not owned by one staff member. It's routed to the provider's **organization**, and every user the organization has designated as an **admin** can see and answer it. Adding or removing an admin takes effect immediately — no messages are lost and no departed staffer keeps access.
- **Real-time chat.** Messages deliver live while both sides are in the conversation.
- **Push notifications.** Whoever isn't actively looking at the conversation gets a push notification — the buyer when an admin replies, every current admin (other than whoever just answered) when a buyer writes in.
- **Text, questions, and attachments.** A message can be plain text or carry an image or PDF attachment, so a buyer can ask a question and attach a photo (e.g. "does it still have this scratch?") in the same thread.
:::

### How routing works

- One connected feed maps to exactly one organization. Every vehicle from that feed is answered by that organization's current admins.
- A buyer never needs to know or choose which staff member to talk to — starting a conversation from any of the provider's listings reaches the same shared inbox.
- If a provider represents multiple independently-staffed locations that should **not** share an inbox, tell us during onboarding — today one feed maps to one organization, so multiple locations need either separate feeds or a single shared inbox across locations.

## Onboarding checklist

::: questions
1. Can the feed return JSON? If not, what would it take to add a JSON output option?
2. What is the request rate limit, and is pagination cursor-based or page/limit-based?
3. Is there a sandbox/test environment with representative (not just placeholder) inventory?
4. What are the possible values for condition/status, body/type, transmission, fuel, and drivetrain in the provider's own vocabulary? (Needed so we can build the mapping to our enums.)
5. Can the feed report a vehicle as sold/unavailable, or does a sold car simply disappear from the feed?
6. Do photo URLs ever change to point at different image bytes, or are they stable once published?
7. Which organization in our system should receive this provider's buyer messages, and who should be an admin on it?
8. Is there more than one independently-staffed location behind this feed?
:::
