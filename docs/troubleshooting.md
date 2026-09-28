# Troubleshooting

Common issues and their solutions. Each section follows the format: Problem, Cause, Solution.

Examples use this placeholder dashboard URL:

```text
https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev
```

---

## Webhook Issues

### Webhooks return 401 Unauthorized

**Problem:** Setup Manager devices receive 401 errors when posting to `/webhook`.

**Cause:** The token in your Setup Manager plist doesn't match the `WEBHOOK_TOKEN` configured on your Worker, or the device is not sending an `Authorization` header.

**Solution:**

1. Verify your Worker has a secret set:
   ```bash
   npx wrangler secret list
   # Should show: WEBHOOK_TOKEN
   ```

2. If missing, set it:
   ```bash
   npx wrangler secret put WEBHOOK_TOKEN
   ```

3. Verify your plist `token` value matches **exactly** (including any trailing whitespace)

4. Redeploy the configuration profile to your devices

5. Test manually:
   ```bash
   curl -X POST https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook \
     -H "Authorization: Bearer your-token-here" \
     -H "Content-Type: application/json" \
     -d '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"2025-01-01T00:00:00Z","started":"2025-01-01T00:00:00Z","modelName":"Test Mac","modelIdentifier":"Mac15,3","macOSBuild":"24A335","macOSVersion":"15.0","serialNumber":"TEST001","setupManagerVersion":"2.0.0"}'
   ```

Setup Manager sends the token as a raw `Authorization: <token>` header. Curl
examples use `Authorization: Bearer <token>` because the Worker accepts both
forms for manual testing.

See [Security](security.md) for complete webhook token setup.

---

### Webhooks return 403 Forbidden

**Problem:** All webhook POSTs are blocked with 403 errors.

**Cause:** Cloudflare Access is protecting the `/webhook` path without a bypass policy.

**Solution:**

1. In Cloudflare Zero Trust, go to **Access -> Applications**
2. Open your Setup Manager HUD application
3. Go to the **Policies** tab
4. Add a new policy:
   - Policy name: `Bypass webhook`
   - Action: `Bypass`
   - Include: `Everyone`
   - Path: `/webhook`
5. **Drag this policy ABOVE the Allow policy** (Bypass policies must be evaluated first)
6. Save

Test:
```bash
curl -X POST https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"2025-01-01T00:00:00Z","started":"2025-01-01T00:00:00Z","modelName":"Test Mac","modelIdentifier":"Mac15,3","macOSBuild":"24A335","macOSVersion":"15.0","serialNumber":"TEST001","setupManagerVersion":"2.0.0"}'
# Should return 200, not 403
```

---

### Webhooks return 503 Service Unavailable

**Problem:** Webhook POSTs return a 503 configuration error.

**Cause:** D1 database is not bound to the Worker, migrations have not been applied, or the binding name is incorrect.

**Solution:**

1. Check health endpoint:
   ```bash
   curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
   ```

2. If `d1` shows `not configured` or `error`:
   - Verify D1 database exists in Cloudflare dashboard
   - Verify binding variable name is exactly `DB`
   - Verify migrations have been applied
   - Rebind via dashboard or `wrangler.toml`

See [Configuration - D1 Database](configuration.md#d1-database-required) for setup steps.

---

## WebSocket Issues

### Dashboard shows "Disconnected" or events don't appear in real-time

**Problem:** Dashboard connects but shows "Disconnected" status, or new events don't appear without refreshing.

**Cause:** WebSocket connection failed or was blocked.

**Solution:**

1. Check the browser console for WebSocket errors:
   - Chrome: **View -> Developer -> JavaScript Console**
   - Safari: enable the Develop menu, then open **Develop -> Show JavaScript Console**

2. If using Cloudflare Access, verify the Access cookie is valid:
   - Open dashboard in browser (should prompt for login)
   - After login, WebSocket should connect

3. Check if a proxy or firewall is blocking WebSocket connections:
   ```bash
   # Test WebSocket upgrade
   curl -i -N \
     -H "Connection: Upgrade" \
     -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" \
     -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/ws
   # Should return 101 Switching Protocols
   ```

4. If on corporate network, try from a different network to isolate the issue

---

### Events appear briefly then disappear

**Problem:** Events show up in the dashboard, then vanish after a few seconds.

**Cause:** Dashboard is receiving events from the WebSocket but failing to persist them in component state.

**Solution:**

1. Open the browser JavaScript console and look for errors
2. Hard refresh: Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac)
3. Clear browser cache and local storage for the domain
4. Try a different browser to isolate browser-specific issues

---

## D1 Database Issues

### Health check shows "d1": "not configured"

**Problem:** The `/api/health` endpoint shows D1 as not configured.

**Cause:** D1 database binding is missing from the Worker.

**Solution:**

1. Verify D1 database exists:
   ```bash
   npx wrangler d1 list
   ```

2. Verify binding in `wrangler.toml`:
   ```toml
   [[d1_databases]]
   binding = "DB"
   database_name = "setupmanagerhud-events"
   database_id = "your-d1-database-id"
   ```

3. Redeploy:
   ```bash
   npm run deploy
   ```

4. Or rebind via dashboard (see [Configuration - D1 Database](configuration.md#d1-database-required))

---

### Health check shows "d1": "error"

**Problem:** D1 is bound but returning errors.

**Cause:** Database ID mismatch, database was deleted, or migrations have not been applied.

**Solution:**

1. List databases and verify ID:
   ```bash
   npx wrangler d1 list
   ```

2. Compare with `wrangler.toml` - IDs must match exactly

3. Apply migrations:
   ```bash
   npx wrangler d1 migrations apply DB --remote
   ```

4. If the database was deleted, create a new one and update the binding

---

### Dashboard shows a storage warning

**Problem:** The dashboard loads but shows "Storage configuration needs attention."

**Cause:** `/api/health` reports D1 or Durable Objects as degraded.

**Solution:**

1. Open the health endpoint after authenticating through Cloudflare Access:
   ```bash
   curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
   ```

2. Verify `"d1": "connected"`.

3. Verify `"durable_objects": "connected"`.

4. If D1 is degraded, recheck the `DB` binding and apply migrations with `--remote`.

5. If Durable Objects are degraded, verify the `DASHBOARD_ROOM` binding and migration in `wrangler.toml`.

---

### Storage warning says D1 is connected and Durable Objects are error

**Problem:** The dashboard says D1 is connected, but Durable Objects are in error.

**Cause:** The D1 database is working, but the Worker cannot create or reach the
`DASHBOARD_ROOM` Durable Object. This usually means the Durable Object binding
or migration is missing from the deployed Worker configuration.

**Solution:**

1. Verify `wrangler.toml` contains both Durable Object sections:
   ```toml
   [[durable_objects.bindings]]
   name = "DASHBOARD_ROOM"
   class_name = "DashboardRoom"

   [[migrations]]
   tag = "v1"
   new_sqlite_classes = ["DashboardRoom"]
   ```

2. Confirm Cloudflare deployed from the repository and commit you expect.

3. If using Cloudflare Git integration, push a commit and wait for a successful
   Cloudflare deployment.

4. If using GitHub Actions, remember that this starter validates on push but
   deploys only when you manually run **Actions -> Deploy to Cloudflare Workers
   -> Run workflow**.

5. If deploying from your Mac, run:
   ```bash
   npm run build
   npx wrangler deploy
   ```

6. Recheck health:
   ```bash
   curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
   ```

---

## Cloudflare Access Issues

### Dashboard redirects to login loop

**Problem:** Accessing the dashboard redirects to Cloudflare Access login, but after logging in, redirects back to login again.

**Cause:** JWT validation in the Worker is failing, possibly due to misconfigured `CF_ACCESS_AUD` or `CF_ACCESS_TEAM_DOMAIN`.

**Solution:**

1. Verify `wrangler.toml` has correct values:
   ```toml
   [vars]
   CF_ACCESS_AUD = "your-audience-tag"
   CF_ACCESS_TEAM_DOMAIN = "your-team.cloudflareaccess.com"
   ```

2. Find your Audience tag:
   - Zero Trust dashboard -> Access -> Applications
   - Click your application -> Overview tab
   - Copy the "Application Audience (AUD) Tag"

3. Find your Team domain:
   - Zero Trust dashboard -> Settings -> Custom Pages
   - Your team domain is shown at the top

4. Redeploy after updating:
   ```bash
   npm run deploy
   ```

5. If you test with `curl`, expect unauthenticated dashboard/API requests to return `302` from Cloudflare Access or `403` from the Worker. A `403` response should still include the standard security headers.

---

### Dashboard accessible without login (unprotected)

**Problem:** Dashboard loads without prompting for Cloudflare Access login.

**Cause:** Cloudflare Access is optional. If you expected a login prompt, the Access application is not configured, or `CF_ACCESS_*` variables are not set for Worker-side JWT validation.

**Solution:**

1. Verify Access application exists:
   - Zero Trust dashboard -> Access -> Applications
   - Should see your application listed

2. Verify `wrangler.toml` has both variables set (not empty):
   ```toml
   [vars]
   CF_ACCESS_AUD = "..."  # Not empty
   CF_ACCESS_TEAM_DOMAIN = "..."  # Not empty
   ```

3. Redeploy if variables were missing

See [Security - Cloudflare Access](security.md#cloudflare-access-optional-dashboard-authentication) for complete setup.

---

## General Issues

### Events not appearing on dashboard

**Problem:** Webhooks return 200 but events don't show on dashboard.

**Cause:** Multiple possible causes - use this checklist.

**Solution:**

1. **Check WebSocket connection:** Dashboard should show "Connected" status

2. **Check D1 storage:** Health endpoint should show `"d1": "connected"`

3. **Check browser console:** Look for JavaScript errors

4. **Check event payload:** Ensure webhooks have all required fields:
   - `name`, `event`, `timestamp`, `started` (for started events)
   - `name`, `event`, `timestamp`, `started`, `finished` (for finished events)

5. **Test with curl:** Send a test event and watch the dashboard:
   ```bash
   curl -X POST https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook \
     -H "Authorization: Bearer your-token-here" \
     -H "Content-Type: application/json" \
     -d '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"2025-01-01T00:00:00Z","started":"2025-01-01T00:00:00Z","modelName":"Test Mac","modelIdentifier":"Mac15,3","macOSBuild":"24A335","macOSVersion":"15.0","serialNumber":"TEST001","setupManagerVersion":"2.0.0"}'
   ```

---

### Disable or Enable fails

**Problem:** Clicking **Disable** or **Enable** shows an error toast, or the
browser console reports that a dashboard request was blocked.

**Cause:** Older dashboard bundles used blocker-sensitive URLs such as
`/api/events/.../archive` or `/api/events/.../disabled`. Core `1.2.5` moved
dashboard visibility changes to neutral records endpoints.

**Solution:**

1. Confirm the live Worker is running `1.2.5` or newer:
   ```bash
   curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/config
   ```

2. Hard refresh the dashboard:
   - Chrome, Edge, or Firefox on Mac: **Command-Shift-R**
   - Safari: **Option-Command-R**, or use **Develop -> Empty Caches**

3. If the browser console still shows `/api/events/.../archive` or
   `/api/events/.../disabled`, the browser is using an old cached dashboard
   bundle. Clear site data for the Worker domain and reload.

4. If `/api/config` still reports an older version, finish the upgrade and wait
   for Cloudflare to deploy the pushed commit. See [Upgrading](upgrading.md).

Disabled rows are hidden from the Active record list; they are not deleted from
D1 and can be enabled again from the Disabled view.

---

### Need sample data for testing

Use the CSV-based test sender from the repository root:

```bash
WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
WEBHOOK_TOKEN=your-token-here \
scripts/send-test-events.sh
```

The sample device CSV is [examples/test-devices.csv](../examples/test-devices.csv).
You can edit serial numbers, macOS versions, hardware models, and computer
names before running the script. Its columns are:

```csv
serial,macos_version,model_name,model_identifier,computer_name
```

The sample application CSV is
[examples/test-applications.csv](../examples/test-applications.csv). Edit it to
change the application names used as enrollment actions. It is a simple `name`
column. The default apps are Microsoft Outlook, Google Chrome, Microsoft Teams,
Zoom, SAP Privileges, Jamf Trust, and Jamf Protect.

To validate the CSV files and event count without posting data:

```bash
DRY_RUN=1 \
WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
WEBHOOK_TOKEN=your-token-here \
scripts/send-test-events.sh
```

Useful options include `DAYS`, `ENROLLMENTS_PER_DEVICE`, `FAILURE_RATE`, and
`FAILED_APPLICATION`. Failed enrollments mark only `FAILED_APPLICATION` as
failed and use slow network throughput.

---

### Need more help?

- Check the [GitHub Issues](https://github.com/motionbug/setupmanagerhud-starter/issues) for similar problems
- Open a new issue with your error details, health check output, and relevant logs
