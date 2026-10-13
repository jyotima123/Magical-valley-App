---
title: SFTP Feed Droplet Runbook
eyebrow: Cars Section · Infrastructure
standfirst: Standing up the SFTP endpoint that receives vAuto's inventory files, from a blank Ubuntu droplet to a CSV landing in Supabase and being ingested — plus how to get back into everything afterwards.
meta:
  Owner: Alisson Damasceno
  Date: 2026-09-08
  Status: Working runbook
theme: light
---

## What you are building

Three moving parts, in this order:

1. **OpenSSH** moves off port 22 to 2222, and stays your admin door.
2. **SFTPGo** takes port 22 and becomes vAuto's door. It is a separate SSH server with its own user database — `vauto` is *not* a Linux account and cannot log into the box.
3. **An upload hook** fires the Supabase Edge Function the moment a file finishes landing.

Files never touch the droplet's disk. SFTPGo writes them straight into Supabase Storage over the S3 protocol, so the droplet stays disposable.

::: {.danger title="The one way to lock yourself out"}
Step 3 moves SSH to a new port. **Do not close your existing session until you have opened a second one on the new port.** If you do get locked out, DigitalOcean's **Recovery Console** (droplet page → Access → Launch Recovery Console) works regardless of SSH or firewall state. That is your escape hatch — know it exists before you need it.
:::

## Before you SSH: collect four values from Supabase

You need these to configure SFTPGo's storage backend. Get them first so you are not hunting mid-setup.

1. **Create the bucket.** Supabase dashboard → Storage → New bucket → name it `vendor-feeds`, and leave it **private** (public off). This project creates buckets by hand and adds policies in SQL — same pattern as `migrations/048_ads_storage_bucket.sql`, but inverted: this one gets no read policy at all.

2. **Create S3 access keys.** Project Settings → Storage → S3 access keys → New access key. You get an **access key ID** and a **secret** — the secret is shown once, so capture it now.

3. **Note the endpoint and region**, shown in the same Storage settings panel:
   - Endpoint: `https://<project-ref>.storage.supabase.co/storage/v1/s3`
   - Region: something like `us-east-1`

4. **Your project ref**, the subdomain in your Supabase URL. You need it again for the Edge Function URL.

::: {.warning title="This key is broader than the folder it writes to"}
The S3 credential grants access to Storage in that project, not just to `vendor-feeds/inbound/vauto/`. We restrict SFTPGo's `vauto` user to that prefix, but the underlying key is more powerful — so it lives only on the droplet and never in the repo.
:::

## Step 1 — First login and patching

```bash
ssh root@DROPLET_IP
```

If you made a dedicated key earlier, add `-i ~/.ssh/mvc_sftp`.

```bash
apt update && apt upgrade -y
apt install -y fail2ban unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
timedatectl set-timezone America/Boise
```

`unattended-upgrades` matters more than usual here: this box has a vendor connecting to it twice a day and you will not be logging in most weeks.

## Step 2 — Firewall, before you change any ports

Build this in the DigitalOcean control panel (Networking → Firewalls), not with `ufw`. A cloud firewall sits outside the droplet, so a bad rule cannot be fixed only from inside a session you have just lost.

Create a firewall, attach it to the droplet, inbound rules:

| Type | Port | Sources |
|---|---|---|
| SSH | 22 | All IPv4 — vAuto's SFTP, tightened later |
| Custom TCP | 2222 | All IPv4 — your admin SSH |

Leave outbound at the default allow-all; the droplet must reach Supabase.

::: {.tip title="Restricting admin SSH to your own IP"}
Stronger, and worth doing if your home IP is static: set port 2222's source to your address only. On a residential connection that changes, you will eventually lock yourself out — recoverable through the web console, but annoying. Key-only auth on a non-standard port with fail2ban is a reasonable posture if you would rather leave it open.
:::

## Step 3 — Move admin SSH to 2222

Set the port in `sshd_config`:

```bash
grep -E '^Port' /etc/ssh/sshd_config || echo 'Port 2222' >> /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
grep -E '^Port|^PasswordAuthentication|^PermitRootLogin' /etc/ssh/sshd_config
```

Ubuntu 24.04 ships SSH **socket-activated**, which means `systemd` holds the
listening port and `sshd_config`'s `Port` is ignored. Turn that off and run sshd
the ordinary way:

```bash
systemctl disable --now ssh.socket
systemctl daemon-reload
mkdir -p /run/sshd
sshd -t && echo "CONFIG OK"
systemctl enable --now ssh.service
systemctl restart ssh.service
ss -tlnp | grep 2222
```

You must see **two** listeners, and they must be owned by `sshd`:

```
LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=...))
LISTEN 0 128    [::]:2222    [::]:* users:(("sshd",pid=...))
```

::: {.danger title="Do not try to keep socket activation"}
The obvious-looking alternative — a `/etc/systemd/system/ssh.socket.d/override.conf`
containing `ListenStream=2222` — **silently binds IPv6 only**. `ss` shows a single
`[::]:2222` socket owned by `systemd`, `net.ipv6.bindv6only` reads `0` so it looks
like it should accept IPv4, and it does not. Every IPv4 connection is refused,
including from `127.0.0.1`, which sends you hunting through cloud firewall rules
that were never the problem. This cost two days on the first build.

The tell: if `ss -tlnp | grep 2222` shows the socket owned by **systemd** rather
than **sshd**, you are in this trap.
:::

Verify locally before trusting it:

```bash
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/2222' && echo "IPv4 OK"
```

**Now, in a new terminal and without closing this one:**

```bash
ssh -p 2222 root@DROPLET_IP
```

Only once that succeeds, close the original session. Port 22 is now free for SFTPGo.

::: {.tip title="You cannot actually lock yourself out here"}
The DigitalOcean web console does not go through sshd, so it stays available
whatever happens to the service. If you have no root password — which you will
not, having used key auth — reset it at droplet → Access → Reset Root Password.
That emails a temporary one and reboots the droplet.
:::

## Step 4 — Docker and SFTPGo

```bash
curl -fsSL https://get.docker.com | sh
mkdir -p /opt/sftpgo/data && cd /opt/sftpgo
chown -R 1000:1000 /opt/sftpgo/data
```

The container runs as UID 1000 and cannot bind privileged ports internally, so SFTP listens on 2022 inside and is published as 22 outside.

Write `/opt/sftpgo/docker-compose.yml`:

```yaml
services:
  sftpgo:
    image: drakkan/sftpgo:latest
    container_name: sftpgo
    restart: unless-stopped
    ports:
      - "22:2022"                 # vAuto's SFTP, public
      - "127.0.0.1:8080:8080"     # admin UI, tunnel only
    volumes:
      - ./data:/var/lib/sftpgo
    environment:
      # SFTPGo's built-in fail2ban equivalent.
      SFTPGO_COMMON__DEFENDER__ENABLED: "true"
      SFTPGO_COMMON__DEFENDER__THRESHOLD: "5"
      SFTPGO_COMMON__DEFENDER__BAN_TIME: "30"
      SFTPGO_COMMON__DEFENDER__BAN_TIME_INCREMENT: "50"
```

Then:

```bash
docker compose up -d
docker compose logs --tail 30
```

The admin UI is bound to `127.0.0.1` — never exposed to the internet. You reach it through a tunnel next.

::: {.note title="Pin the version once it works"}
`:latest` is fine for standing this up, but pin it afterwards — check the current tag on Docker Hub and change the image line, so a surprise upstream release cannot break the feed unattended.
:::

## Step 5 — Open the admin UI

From your Windows machine:

```bash
ssh -p 2222 -L 8080:localhost:8080 root@DROPLET_IP
```

Leave that running, then open **http://localhost:8080/web/admin**. The first visit asks you to create the SFTPGo admin account. Use a long unique password and store it in your password manager.

## Step 6 — The S3 spike, before anything else

This is the assumption the whole design rests on, and it takes ten minutes to prove or disprove. In the SFTPGo UI, create a throwaway user pointed at Supabase.

**Users → Add:**

| Field | Value |
|---|---|
| Username | `spike` |
| Password | anything — you will delete this user |
| Permissions | `*`, for this test only |
| Storage / Filesystem | **AWS S3** |
| Bucket | `vendor-feeds` |
| Region | your Supabase region |
| Access key / Secret | the Supabase S3 keys |
| Endpoint | `https://PROJECT_REF.storage.supabase.co/storage/v1/s3` |
| **Force path style** | **enabled** — Supabase requires it |
| Key prefix | `spike/` |

Then from your machine:

```bash
head -c 10000000 /dev/urandom > big.bin
sftp spike@DROPLET_IP
```

Inside the session: `put big.bin`, then `ls`, then `rename big.bin renamed.bin`, then `quit`.

Two things must work: the **upload** (SFTPGo streams via multipart) and the **rename** (implemented as S3 CopyObject plus delete). Confirm the file appears in Supabase Storage under `vendor-feeds/spike/`.

::: {.warning title="If rename or multipart fails"}
Fall back to the local-disk path: give `vauto` a normal filesystem home instead of the S3 backend, and have the upload hook in Step 9 run a small script that pushes the file to Supabase via the Storage REST API and then deletes the local copy. Everything downstream — the Edge Function, the ingest, the app — is unchanged. Only the droplet's internals differ, and 10 GB of disk holds a lot of 10 MB files.
:::

Delete the `spike` user when you are done.

## Step 7 — Create the real `vauto` user

Generate a password on the droplet and store it in your password manager:

```bash
openssl rand -base64 24
```

**Users → Add:**

| Field | Value |
|---|---|
| Username | `vauto` |
| Password | the generated string |
| Permissions on `/` | `list`, `upload`, `overwrite`, `rename`, `delete` — **not** `download` |
| Storage / Filesystem | AWS S3, same settings as the spike |
| Key prefix | `inbound/vauto/` |
| Max upload size | 100 MB, as a runaway guard |

::: {.tip title="Why download is denied"}
vAuto has no reason to read files back — they are the ones sending them. Denying `download` means a leaked credential cannot pull other dealerships' inventory back out of the bucket. It is unlikely to break their client, and it is a quick toggle if it does.
:::

The key prefix is what confines them: `vauto` sees a filesystem rooted at `inbound/vauto/` and can neither read nor write anything else in the bucket.

## Step 8 — Deploy the Edge Function

From your machine, in the repo:

```bash
openssl rand -hex 32          # print it, and keep it on your clipboard
supabase secrets set FEED_INGEST_SECRET=<that value>
supabase secrets set FEED_MARK_MISSING_AS_SOLD=false
supabase functions deploy ingest-vendor-feed --no-verify-jwt
```

`--no-verify-jwt` matters: without it Supabase demands an `Authorization` bearer token on every call, and SFTPGo is not a Supabase client. The function authenticates with the `x-feed-secret` header instead — not unauthenticated, just authenticated differently.

::: {.danger title="Do not generate the secret inline, and do not read it back with secrets list"}
`supabase secrets set FEED_INGEST_SECRET="$(openssl rand -hex 32)"` never shows you the value, and `supabase secrets list` does not give it back — that column is a **digest**, not the secret. Both are 64 hex characters, so the digest looks exactly like a real `openssl rand -hex 32` secret and pastes into SFTPGo without any visible sign that it is wrong. The function then rejects every upload with a 401 and the log shows nothing but `Unauthorized`.

Generate it in one command, read it with your eyes, paste it in two places: `supabase secrets set` and the SFTPGo header.
:::

Secrets take effect immediately — [you do not need to redeploy the function after changing one](https://supabase.com/docs/guides/functions/secrets).

Run the two migrations if you have not: `migrations/078_vehicle_source_registry.sql`, then `migrations/079_feed_imports.sql`.

Then onboard each dealership, using the dealer ID vAuto puts in the file — one
row per rooftop, not one per vendor:

```sql
INSERT INTO dealer_sources
  (source, organization_id, provider, kind, dealer_ref, display_name, is_active)
VALUES
  ('vauto:goodevw',     NULL, 'vauto', 'feed', 'goodevw',
   'Goode Motor Volkswagen Mazda', true),
  ('vauto:thecarstore', NULL, 'vauto', 'feed', 'thecarstore',
   'The Car Store', true);
```

`dealer_ref` is matched against the file's `DealerId` column, case-insensitively.
vAuto identifies a rooftop by a slug — `goodevw`, `thecarstore` — not by the
numeric id their spec sheet showed, and the filename carries the same slug.

::: {.note title="The organization can come later"}
`organization_id` is nullable so a feed can be ingested before anyone knows
which org answers for it. Vehicles import, browse and filter with it NULL; the
only thing that blocks is a buyer pressing contact, which raises
`No dealership is configured for this inventory yet`. Attach it whenever you
have it — the listings reach the org through `source`, so nothing is re-imported:

```sql
UPDATE dealer_sources SET organization_id = '<organizations.id>'
WHERE source = 'vauto:goodevw';
```
:::

Until that row exists the ingest rejects the file by design, rather than inventing a home for the vehicles.

## Step 9 — Wire the upload hook

SFTPGo keeps **actions** and **rules** in two separate lists, and the rule form only offers actions that already exist. So the Actions box on a new rule is empty until you have created one — build the action first, then the rule that fires it.

### 9a — Create the action

**Event Manager → Event Actions → Add**.

- **Name:** `ingest-vauto` — free text, and the name you will pick in 9b
- **Type:** `HTTP`
- **Endpoint:** `https://PROJECT_REF.supabase.co/functions/v1/ingest-vendor-feed`
- **Method:** `POST`
- **Headers:** `x-feed-secret` set to the secret from Step 8, and `Content-Type: application/json`
- **Body:**

```json
{"objectPath": "inbound/vauto{{.VirtualPath}}"}
```

`{{.VirtualPath}}` is the path inside the user's own root and begins with `/`, so this reconstructs the full bucket key the function expects.

::: {.warning title="Two placeholder syntaxes exist — check which one your build wants"}
The dot matters, and which form works depends on the SFTPGo generation:

| Build | Syntax |
|---|---|
| Current / Enterprise — [Go `text/template`](https://docs.sftpgo.com/enterprise/placeholders/) | `{{.VirtualPath}}` |
| OSS [v2.6](https://docs.sftpgo.com/2.6/eventmanager/) and earlier | `{{VirtualPath}}` |

Get it wrong and **nothing errors**: SFTPGo posts the placeholder through as literal text, and the function fails on a bucket key with `{{VirtualPath}}` still in it.

You can tell the two apart from the request size in the Supabase function log without touching SFTPGo. The unsubstituted body is 46 bytes; a real filename makes it ~59. So a `request.headers.content_length` of exactly **46** means the placeholder never expanded.
:::

### 9b — Create the rule

**Event Manager → Event Rules → Add**.

- **Trigger:** Filesystem event
- **Events:** `upload` only
- **Actions:** `ingest-vauto` now appears in the list — add it

Leave **Execute sync** unchecked. Sync makes SFTPGo hold the SFTP connection open until the action returns, so a large file would keep vAuto's client waiting through the entire ingest and risk a timeout on their side. Fire and forget is what you want: the outcome is recorded in `feed_imports` either way, which is where you look for it in Step 10.

The event only fires on a *successful* upload, which is what stops the function ever reading a half-written file.

## Step 10 — End to end

Two real vAuto exports live in `docs/sample_feeds/`:

| File | Rows | Shape |
|---|---|---|
| `mvc_goodevw_20260924_1544.csv` | 166 | New and used, 42 new cars, 5 certified, MSRP on 42 of them |
| `mvc_thecarstore_20260924_1544.csv` | 286 | All used, no MSRP column values, 6 cars with no photos |
| `mvc_48213_20260911_1800.csv` | 3 | Hand-built, the shape vAuto's spec sheet implied — keep it, it exercises the alias fallbacks nothing else covers |

Start with the smaller real one:

```bash
sftp vauto@RESERVED_IP
put docs/sample_feeds/mvc_goodevw_20260924_1544.csv
```

Then check in order:

::: {.note title="Rename the file on every retry"}
`feed_imports_one_success_per_object` is unique on `(object_path, source)` where `status = 'success'`, and the function short-circuits to `{"status":"already_imported"}` before doing any work. A second upload under the same name looks like silence. Bump the timestamp in the filename each time.
:::


1. The object appears in Supabase Storage under `vendor-feeds/inbound/vauto/`.
2. `feed_imports` has a row with `status = 'success'`, `rows_read = 166`, `rows_skipped = 0`, and `vehicles_marked_sold = 0`.
3. `vehicle_listings` has 166 rows with `source = 'vauto:goodevw'`.
4. The Cars tab shows them alongside LiftKit and community listings.

Then spot-check that the mapping landed, not just the rows:

```sql
select count(*) filter (where images is null)        as no_photos,      -- expect 0
       count(*) filter (where color is null)         as no_colour,      -- expect 0
       count(*) filter (where body not in ('Sedan','SUV','Pickup Truck','Hatchback',
                                           'Coupe','Convertible','Wagon','Minivan',
                                           'Van','Sports Car','Crossover'))
                                                     as unfilterable_body,  -- expect 0
       count(*) filter (where transmission not in ('Automatic','Manual','CVT','Semi-Auto / DCT'))
                                                     as unfilterable_gearbox -- expect 0
from vehicle_listings where source = 'vauto:goodevw';
```

Those four counts are the difference between "the import succeeded" and "the
cars are actually findable" — a feed whose vocabulary misses the filter chips
imports perfectly and then shows nothing under any filter.

```sql
select source, object_path, status, rows_read, rows_skipped,
       vehicles_upserted, vehicles_marked_sold, error, started_at
from feed_imports order by started_at desc limit 10;
```

If something failed, `error` is where the reason is — including a named error when the dealership is not onboarded.

## Step 11 — Reserved IP, and only then tell vAuto

Networking → Reserved IPs → assign to the droplet. **Give vAuto that address, never the droplet's own public IP.** Re-run the Step 10 test against the reserved IP to confirm it routes.

Once vAuto sends their egress addresses, edit the firewall so port 22's source is those addresses only, and the endpoint stops being reachable by the general internet.

## How to get back in

| What | How |
|---|---|
| Admin shell | `ssh -p 2222 root@RESERVED_IP` |
| SFTPGo admin UI | `ssh -p 2222 -L 8080:localhost:8080 root@IP`, then http://localhost:8080/web/admin |
| Test as vAuto | `sftp vauto@RESERVED_IP`, or WinSCP with protocol SFTP on port 22 |
| Locked out entirely | DigitalOcean → droplet → Access → Launch Recovery Console |
| Service logs | `cd /opt/sftpgo && docker compose logs -f` |
| Restart the stack | `cd /opt/sftpgo && docker compose restart` |
| Ingest logs | Supabase dashboard → Edge Functions → `ingest-vendor-feed` → Logs |
| Import history | `select * from feed_imports order by started_at desc;` |
| The raw files | Supabase Storage → `vendor-feeds` → `inbound/vauto/` |

## When something breaks

| Symptom | Look at |
|---|---|
| vAuto cannot connect | Firewall allows 22 from their IPs; `docker compose ps` shows the container up |
| File uploads but nothing imports | Is the Event Manager rule enabled? Check SFTPGo logs for the HTTP action's response code |
| Function returns 401 | `x-feed-secret` does not match `FEED_INGEST_SECRET` |
| "No onboarded dealership matched" | The `dealer_sources` row is missing or inactive; the error names the dealer ids it saw |
| Rows skipped | `feed_imports.error` summarises the reasons, e.g. `12x no stock number or VIN` |
| Vehicles vanished from the app | Check `vehicles_marked_sold`. If it is non-zero and vAuto sends deltas rather than snapshots, set `FEED_MARK_MISSING_AS_SOLD=false` at once and re-import the latest file |
