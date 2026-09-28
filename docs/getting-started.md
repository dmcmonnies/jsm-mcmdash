# Getting Started

This guide is the happy path for Mac admins deploying Setup Manager HUD with
the Cloudflare Deploy Button.

Setup Manager HUD has two separate security layers:

- `WEBHOOK_TOKEN` is required. Setup Manager uses it when posting webhook events.
- Cloudflare Access is optional. It protects people viewing the dashboard.

Cloudflare Access does not replace `WEBHOOK_TOKEN`.

## What You Need

- A Cloudflare account
- A GitHub account that can create the dashboard repository
- Setup Manager ready to receive a webhook configuration
- A Mac with Terminal for generating the token and running test commands

## 1. Generate The Webhook Token

Run this on your Mac:

```bash
openssl rand -hex 24
```

Save the value somewhere secure before continuing. You will paste the same
token into Cloudflare and into your Setup Manager webhook plist.

## 2. Deploy To Cloudflare

Open the Deploy Button from the main README:

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/Jamf-Concepts/setupmanagerhud-starter)

During the Cloudflare setup flow:

1. Sign in to Cloudflare if prompted.
2. Connect or select your GitHub account if prompted.
3. Let Cloudflare create or connect the dashboard repository.
4. Choose the Worker name you want to use.
5. Paste your generated token into the required `WEBHOOK_TOKEN` field.
6. Start the deployment.

The Deploy Button uses `.dev.vars.example` so Cloudflare knows to ask for
`WEBHOOK_TOKEN`. Do not leave this value blank.

## 3. Save The Dashboard Values

After Cloudflare finishes deploying, save these values:

| Value | Example |
|-------|---------|
| Dashboard URL | `https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev` |
| Webhook URL | `https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook` |
| Webhook token | The value from `openssl rand -hex 24` |

Use the Worker URL Cloudflare gives you. Your Worker name may not be
`setupmanagerhud`.

## 4. Check Health

Open the health endpoint in a browser or run:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
```

Healthy storage looks like this:

```json
{"status":"healthy","d1":"connected","durable_objects":"connected"}
```

If D1 or Durable Objects are not connected, see
[Troubleshooting](troubleshooting.md#dashboard-shows-a-storage-warning).

## 5. Configure Setup Manager

Add the webhook URL and token to each webhook in your Setup Manager
configuration plist:

```xml
<key>webhooks</key>
<dict>
  <key>started</key>
  <dict>
    <key>url</key>
    <string>https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook</string>
    <key>token</key>
    <string>paste-your-secret-here</string>
  </dict>
  <key>finished</key>
  <dict>
    <key>url</key>
    <string>https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook</string>
    <key>token</key>
    <string>paste-your-secret-here</string>
  </dict>
</dict>
```

The `token` value must exactly match the `WEBHOOK_TOKEN` value saved in
Cloudflare.

## 6. Send A Test Event

Before relying on live Setup Manager enrollments, send one test event:

```bash
curl -X POST https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"2025-01-01T00:00:00Z","started":"2025-01-01T00:00:00Z","modelName":"Test Mac","modelIdentifier":"Mac15,3","macOSBuild":"24A335","macOSVersion":"15.0","serialNumber":"TEST001","setupManagerVersion":"2.0.0"}'
```

- `200 OK` means the token matched and the Worker accepted the event.
- `401 Unauthorized` means the token is missing or does not match.
- `503 Service Unavailable` usually means D1 is missing, unbound, or not migrated.

Setup Manager sends the token as a raw `Authorization: <token>` header. The
curl example uses `Authorization: Bearer <token>` because the Worker accepts
both forms for easier manual testing.

Refresh the dashboard and confirm the test event appears.

For a larger demo dataset, use the included CSV-based test sender:

```bash
WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
WEBHOOK_TOKEN=your-token-here \
scripts/send-test-events.sh
```

Edit [examples/test-devices.csv](../examples/test-devices.csv) for computers.
It uses these columns:

```csv
serial,macos_version,model_name,model_identifier,computer_name
```

The sample file includes Mac serials, macOS versions, hardware models, model
identifiers, and computer names.

Edit [examples/test-applications.csv](../examples/test-applications.csv) for
application names. It is a simple `name` column. The default list is:

```csv
name
Microsoft Outlook
Google Chrome
Microsoft Teams
Zoom
SAP Privileges
Jamf Trust
Jamf Protect
```

The script sends started and finished events across the last 7 days. By
default, failed enrollments fail `Microsoft Outlook` only when network
throughput is slow.

Useful options:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DRY_RUN` | Validate CSV files and event count without posting | `0` |
| `DAYS` | Spread generated events across this many days | `7` |
| `ENROLLMENTS_PER_DEVICE` | Number of enrollments to create per device | `7` |
| `FAILURE_RATE` | Approximate percent of enrollments to fail | `5` |
| `FAILED_APPLICATION` | Application marked failed when an enrollment fails | `Microsoft Outlook` |

To change the failed app, set `FAILED_APPLICATION`:

```bash
FAILED_APPLICATION="Zoom" \
WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
WEBHOOK_TOKEN=your-token-here \
scripts/send-test-events.sh
```

To check the count without sending events:

```bash
DRY_RUN=1 \
WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
WEBHOOK_TOKEN=your-token-here \
scripts/send-test-events.sh
```

## 7. Manage Test Enrollments

The dashboard has two record views:

- **Active** is the normal working view for live enrollment monitoring.
- **Disabled** shows enrollments you intentionally hid from Active.

If you ran a curl test or the CSV demo sender and want to clear that noise
before watching real Setup Manager enrollments, click **Disable** on those test
rows. Disabled enrollments are not deleted; they remain stored in D1 for
history and can be enabled again from the Disabled view.

Disabled rows are hidden from the Active record list. Aggregate dashboard
totals may still include stored history.

## 8. Optional: Protect Dashboard Viewing

The dashboard can be public or protected with Cloudflare Access.

Cloudflare Access protects humans opening the dashboard, API, and WebSocket.
Setup Manager devices still post to `/webhook`, and that route must continue to
use `WEBHOOK_TOKEN`.

See [Security](security.md#cloudflare-access-optional-dashboard-authentication)
for the Cloudflare Access setup steps.
