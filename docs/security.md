# Security

> [!WARNING]
> **Webhook tokens are required for every usable deployment.**
> Without a token, anyone who discovers your Worker URL can POST fake enrollment events to your dashboard.

## Webhook Token Setup (Required)

You must configure **both sides** for webhook authentication to work:
1. **Worker Side:** Set `WEBHOOK_TOKEN` as a Cloudflare Worker secret
2. **Setup Manager Side:** Add `token` key to your webhook plist

If these values don't match, webhooks return **401 Unauthorized**.

### 1. Worker Side (Cloudflare)

First, generate a secure random token:

```bash
openssl rand -hex 24
```

Save this value — you'll need it for both the Worker and Setup Manager configuration.

#### Option A: Cloudflare Dashboard (recommended for Deploy Button users)

If the **Deploy to Cloudflare** setup screen asks for `WEBHOOK_TOKEN`, paste your generated token there during setup. Do not leave it blank. Save the value before continuing because Cloudflare secrets are hidden after they are saved.

If you skipped it during Deploy Button setup, add it manually:

1. Go to [Workers & Pages](https://dash.cloudflare.com/?to=/:account/workers-and-pages) in the Cloudflare dashboard
2. Click on your Worker (e.g., `setupmanagerhud`)
3. Go to **Settings** → **Variables and Secrets**
4. Click **Add** under the Secrets section
5. Name: `WEBHOOK_TOKEN`
6. Type: **Secret** (not Text — secrets are encrypted and hidden after save)
7. Value: paste your generated token
8. Click **Save and Deploy**

#### Option B: Wrangler CLI

If you cloned the repo locally:

```bash
npx wrangler secret put WEBHOOK_TOKEN
# Paste your token when prompted
```

The secret is stored securely by Cloudflare and never exposed in logs or code.

### 2. Setup Manager Side (plist)

Add the `token` key to **each** webhook in your Setup Manager configuration plist:

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

> [!IMPORTANT]
> The token value must be **identical** to what you set in `WEBHOOK_TOKEN`. Setup Manager sends this as a raw `Authorization: <token>` request header. The Worker also accepts `Authorization: Bearer <token>` for curl and other tools.
> A blank `WEBHOOK_TOKEN` is not valid. If you do not know the saved value, generate a new token, update the Worker secret, and update Setup Manager with the same new value.

### Verifying Token Setup

Test your configuration with curl:

```bash
curl -X POST https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"2025-01-01T00:00:00Z","started":"2025-01-01T00:00:00Z","modelName":"Test Mac","modelIdentifier":"Mac15,3","macOSBuild":"24A335","macOSVersion":"15.0","serialNumber":"TEST001","setupManagerVersion":"2.0.0"}'
```

- **200 OK** = Token matches, webhook accepted
- **401 Unauthorized** = Token mismatch or missing

Setup Manager sends the token as a raw `Authorization: <token>` header. The
curl examples use `Authorization: Bearer <token>` because the Worker accepts
both forms for easier manual testing.

> **Note:** Setup Manager also supports Basic Auth (`username` + `password` keys instead of `token`), but this Worker validates the `token` key through the `Authorization` header. Use the `token` key for compatibility.

---

## Cloudflare Access (Optional Dashboard Authentication)

Cloudflare Access is optional. Enable it when you want only authorized users to view enrollment data in the dashboard. It sits at Cloudflare's edge - before dashboard requests reach your Worker.

```
User -> Cloudflare Access (optional login gate) -> Dashboard (Worker)
Device -> POST /webhook (bypasses Access) -> Worker -> D1
```

> [!IMPORTANT]
> **Choose your login method first.** One-time PIN is the fastest setup: Cloudflare emails a code to users allowed by your Access policy. You can also connect an existing identity provider such as GitHub, Google Workspace, Microsoft Entra ID, Okta, JumpCloud, SAML, or OIDC. The steps below use One-time PIN because it requires the least setup, but Setup Manager HUD works with any Cloudflare Access identity provider.

### Quick Setup

1. **Enable Zero Trust:** Go to [dash.cloudflare.com](https://dash.cloudflare.com), choose a team name, select Free plan
2. **Choose a login method:** Go to **Zero Trust -> Integrations -> Identity providers**
   - For the quickest setup, choose **Add new identity provider -> One-time PIN**.
   - For existing organization login, add your provider, such as GitHub, Google, Microsoft, Okta, SAML, or OIDC.
   - If your provider already appears under **Your identity providers**, you can use the existing provider.
3. **Create application:** Go to **Zero Trust -> Access -> Applications -> Add an application -> Self-hosted**
   - Name: `Setup Manager HUD`
   - Domain: `YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev`
4. **Create Allow policy:** Include your email address or domain
5. **Create Bypass policy for webhook:**
   - Policy name: `Bypass webhook`
   - Action: `Bypass`
   - Include: `Everyone`
   - Path: `/webhook`
   - **Position this ABOVE the Allow policy**

### Optional: Verify Cloudflare Access JWTs in the Worker

If you enable Cloudflare Access, it protects the dashboard at the edge. JWT validation adds a second optional check inside the Worker: dashboard, API, and WebSocket requests must include a valid Cloudflare Access token before the Worker serves data. If the token is missing or invalid, the Worker returns `403` and keeps the normal security headers, including CSP and HSTS.

This is useful for production because it makes the Worker reject dashboard traffic that did not come through your Access application. It does **not** apply to `/webhook`; that route must bypass Access so Setup Manager devices can post events, and it is protected separately by `WEBHOOK_TOKEN`.

#### Find the Access values

After creating the Access application:

1. Open [Cloudflare Zero Trust](https://dash.cloudflare.com)
2. Go to **Access -> Applications**
3. Open your Setup Manager HUD application
4. Copy the **Application Audience (AUD) Tag** for `CF_ACCESS_AUD`
5. Find your team domain in **Settings -> Custom Pages** or your Zero Trust URL, for example `your-team.cloudflareaccess.com`

#### Update wrangler.toml

Add these values to `wrangler.toml`:

```toml
[vars]
CF_ACCESS_AUD = "paste-your-audience-tag-here"
CF_ACCESS_TEAM_DOMAIN = "your-team.cloudflareaccess.com"
```

#### Understand where this file lives

If you used the **Deploy to Cloudflare** button, Cloudflare created a copy of this project in your GitHub account and deployed from that repository. `wrangler.toml` is in that GitHub repository.

You have two common ways to update it:

**Option A: edit locally and deploy with Wrangler**

```bash
git clone https://github.com/YOUR-USERNAME/setupmanagerhud.git
cd setupmanagerhud
npm install
npx wrangler login
# edit wrangler.toml and add CF_ACCESS_AUD / CF_ACCESS_TEAM_DOMAIN
npm run deploy
```

If you want your GitHub repo to keep this configuration too, commit and push the `wrangler.toml` change:

```bash
git add wrangler.toml
git commit -m "Enable Cloudflare Access JWT validation"
git push
```

**Option B: edit in GitHub and deploy with GitHub Actions**

1. Open your copied `setupmanagerhud` repository in GitHub
2. Edit `wrangler.toml` and add the `[vars]` values
3. Commit the change
4. Make sure GitHub Actions are enabled for the repository
5. Confirm the repository secrets exist:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
6. Go to **Actions -> Deploy to Cloudflare Workers -> Run workflow**

> [!TIP]
> Deploying locally with `npm run deploy` updates Cloudflare immediately, but it does not update GitHub unless you also commit and push. Editing in GitHub keeps the repository as the source of truth, but the Worker is updated only after the deploy workflow runs.

### Route Summary

When optional Cloudflare Access is enabled:

| Route | Authentication | Who |
|-------|---------------|-----|
| `/` (dashboard) | Cloudflare Access | Authorized users only |
| `/ws` (WebSocket) | Cloudflare Access | Authorized users only |
| `/api/*` | Cloudflare Access | Authorized users only |
| `/webhook` | Bypassed by Access, protected by `WEBHOOK_TOKEN` | Setup Manager devices only |

Without Cloudflare Access, the dashboard routes are public to anyone who knows the Worker URL. `/webhook` still requires `WEBHOOK_TOKEN` either way.

---

## Rate Limiting (Optional)

Add a Cloudflare WAF rate limiting rule to prevent webhook flooding:

1. Cloudflare dashboard -> Security -> WAF -> Rate limiting rules
2. Create rule:
   - Match: URI Path equals `/webhook`
   - Rate: 30 requests per minute per IP (adjust for fleet size)
   - Action: Block for 1 minute

| Fleet Size | Concurrent Enrollments | Suggested Rate |
|------------|----------------------|----------------|
| Small (1-10 devices) | 1-10 | 30 req/min |
| Medium (10-50 devices) | 10-50 | 120 req/min |
| Large (50+ from one IP) | 50+ | 300 req/min |

> **Calculation:** Each device sends 2 webhooks per enrollment (started + finished). A rate of 30 req/min supports ~15 concurrent enrollments from a single IP. If devices share a NAT gateway, use a higher limit based on expected concurrent enrollment count.
