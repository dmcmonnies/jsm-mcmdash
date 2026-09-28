# Configuration

This page covers storage, secrets, Worker bindings, and health checks for Setup
Manager HUD. For a first-time Deploy Button setup, start with
[Getting Started](getting-started.md).

---

## D1 Database (Required)

Setup Manager HUD stores webhook events in [Cloudflare D1](https://developers.cloudflare.com/d1/). Without this, webhook and API responses return a configuration error and the dashboard shows a storage warning.

### Option A: Deploy Button

Most Deploy Button users should not manually create a D1 database. Cloudflare
reads `wrangler.toml` and can provision the D1 binding declared there:

```toml
[[d1_databases]]
binding = "DB"
database_name = "setupmanagerhud-events"
database_id = "setupmanagerhud-events"
```

The deploy script applies migrations with the binding name:

```bash
npx wrangler d1 migrations apply DB --remote
```

During Deploy Button setup, Cloudflare may ask for `WEBHOOK_TOKEN`. Enter a long random value, save it somewhere secure, and use that exact same value in Setup Manager. Do not leave it blank. After deployment, verify the Worker has a D1 binding named `DB` and that `WEBHOOK_TOKEN` is set before sending real Setup Manager webhooks.

Only use the manual D1 steps below if your health check shows D1 as missing,
not configured, or in error.

### Option B: Cloudflare Dashboard

Use this when you need to create or rebind D1 in the Cloudflare dashboard. You
can create and bind the database in the browser, but migrations still require a
local clone with Wrangler.

**1. Create the database:**

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com)
2. Go to **Workers & Pages -> D1 SQL Database** in the left sidebar
3. Click **Create database**
4. Name it `setupmanagerhud-events`
5. Click **Add**

**2. Bind it to your Worker:**

1. Go to **Workers & Pages** -> click your Worker
2. Go to **Settings -> Bindings**
3. Click **Add binding** -> **D1 Database**
4. Variable name: `DB` (must be exactly this)
5. Select your database from the dropdown
6. Click **Save** and **Deploy**

> [!NOTE]
> Dashboard bindings can be removed if you later redeploy from GitHub with a `wrangler.toml` D1 section that points somewhere else. For persistent GitHub/CLI deploys, use the CLI method and commit your database ID to your fork.

**3. Apply the migration:**

If you created the database in the dashboard, apply the migration from a local clone:

```bash
npx wrangler d1 migrations apply DB --remote
```

### Option C: CLI with Wrangler

Bindings persist across redeploys when configured in `wrangler.toml`.

```bash
# Create the database
npx wrangler d1 create setupmanagerhud-events
# Copy the database_id from the output
```

Edit `wrangler.toml` and replace the Deploy Button placeholder ID with the UUID from `wrangler d1 create`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "setupmanagerhud-events"
database_id = "paste-your-d1-database-id-here"
```

Apply migrations:

```bash
npx wrangler d1 migrations apply DB --remote
```

Redeploy:

```bash
npm run deploy
```

---

## Environment Variables

### Secrets (via Wrangler CLI)

Secrets are encrypted and never exposed in logs or code.

| Secret | Purpose | Required |
|--------|---------|----------|
| `WEBHOOK_TOKEN` | Shared token for webhook authentication | Yes |

Set a secret:

```bash
npx wrangler secret put WEBHOOK_TOKEN
# Paste your token when prompted
```

Use a non-empty value you know and have saved. Cloudflare hides Worker secrets after they are saved, so if you lose the value, generate a new token and update both the Worker secret and Setup Manager.

List secrets:

```bash
npx wrangler secret list
```

Delete a secret:

```bash
npx wrangler secret delete WEBHOOK_TOKEN
```

See [Security](security.md) for complete webhook token setup instructions.

### Variables (via wrangler.toml)

Non-sensitive configuration stored in `wrangler.toml`.

| Variable | Purpose | Default |
|----------|---------|---------|
| `CF_ACCESS_AUD` | Cloudflare Access audience tag | (not set) |
| `CF_ACCESS_TEAM_DOMAIN` | Cloudflare Access team domain | (not set) |
| `APP_TITLE` | Custom dashboard title | `Setup Manager HUD` |
| `LOGO_URL` | Custom logo URL | (not set) |

```toml
[vars]
CF_ACCESS_AUD = "your-audience-tag"
CF_ACCESS_TEAM_DOMAIN = "your-team.cloudflareaccess.com"
```

> [!IMPORTANT]
> If `CF_ACCESS_AUD` and `CF_ACCESS_TEAM_DOMAIN` are not set, the Worker skips JWT validation. The dashboard works but doesn't verify that requests came through Cloudflare Access.

Set these only after creating a Cloudflare Access application for the dashboard. See [Security - Optional: Verify Cloudflare Access JWTs](security.md#optional-verify-cloudflare-access-jwts-in-the-worker) for why this is recommended, where to find the values, and how to redeploy from a local clone or GitHub Actions.

### Local Development (.dev.vars)

For local development with `npm run dev`, create a `.dev.vars` file:

```
WEBHOOK_TOKEN=local-test-token
```

See `.dev.vars.example` for a template. This file is gitignored.

---

## wrangler.toml Reference

The `wrangler.toml` file configures your Worker deployment. Key sections:

### Basic Settings

```toml
name = "setupmanagerhud"
main = "src/index.ts"
compatibility_date = "2024-12-01"
compatibility_flags = ["nodejs_compat"]
```

- `name`: Your Worker name (becomes the subdomain)
- `main`: Entry point file
- `compatibility_date`: Cloudflare runtime version
- `compatibility_flags`: Enable Node.js compatibility

### D1 Database Binding

```toml
[[d1_databases]]
binding = "DB"
database_name = "setupmanagerhud-events"
database_id = "setupmanagerhud-events"
```

Deploy Button installs can use the placeholder-style `database_id` above during Cloudflare provisioning. Manual CLI/GitHub deploys should replace `database_id` with the D1 UUID from `npx wrangler d1 create setupmanagerhud-events`.

`binding = "DB"` is the Worker variable name used by the code. Keep it exactly
`DB`. `database_name` is the Cloudflare D1 database name, and admins sometimes
change it during setup.

### Durable Object Binding

```toml
[[durable_objects.bindings]]
name = "DASHBOARD_ROOM"
class_name = "DashboardRoom"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["DashboardRoom"]
```

The Durable Object handles WebSocket connections. This is pre-configured and shouldn't need changes.

### Static Assets

```toml
[assets]
directory = "./public"
```

The starter copies the dashboard assets from `@motionbug/setupmanagerhud-core`
into `public/` during `npm run build` or `npm run sync`. The `public/` folder is
gitignored because it is regenerated from the package.

### Environment Variables

```toml
[vars]
CF_ACCESS_AUD = "your-audience-tag"
CF_ACCESS_TEAM_DOMAIN = "your-team.cloudflareaccess.com"
```

---

## Health Check

Verify your configuration via the health endpoint:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
```

Response:

```json
{
  "status": "healthy",
  "timestamp": 1735689600000,
  "d1": "connected",
  "durable_objects": "connected",
  "connections": 0
}
```

The endpoint returns **HTTP 200** when healthy and **HTTP 503** when degraded.

| Field | Healthy Value | Problem Value |
|-------|--------------|---------------|
| `status` | `healthy` | `degraded` |
| `d1` | `connected` | `not configured` or `error` |
| `durable_objects` | `connected` | `not configured` or `error` |

If any field shows a problem value, see [Troubleshooting](troubleshooting.md).

---

## Advanced: API Event Filters

`GET /api/events` returns an array of stored events. The endpoint supports server-side filtering for larger deployments.

| Parameter | Values |
|-----------|--------|
| `limit` | `1` to `1000` |
| `offset` | `0` or higher |
| `eventType` | `started`, `finished`, `failed` |
| `failedOnly` | `true` |
| `macOSVersion` | partial version text |
| `model` | partial model name |
| `serial` | partial serial number |
| `search` | searches serial, model, computer name, macOS version, and user ID |
| `timeRange` | `hour`, `day`, `week` |

Example:

```bash
curl "https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/events?eventType=failed&timeRange=week&limit=50"
```

### Dashboard Record Visibility

The dashboard uses record visibility endpoints for the Active and Disabled
views:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/records` | Return active records |
| `GET /api/records?state=hidden` | Return disabled records |
| `POST /api/records/visibility` | Hide or show a record |

Visibility changes use a JSON body:

```json
{"eventId":"paste-event-id-here","hidden":true}
```

Set `hidden` to `true` to move a row out of Active, or `false` to enable it
again. Disabled records stay stored in D1; they are hidden from the Active
record list, not deleted.

Do not build new dashboard behavior around old URL shapes such as
`/api/events/:id/archive` or `/api/events/:id/disabled`. Those routes caused
content blockers to treat dashboard actions like tracking/event-collection
requests and should not be reintroduced.
