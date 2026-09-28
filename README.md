# Setup Manager HUD

Real-time webhook dashboard for [Setup Manager](https://github.com/jamf/setup-manager).

## Quick Start

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/Jamf-Concepts/setupmanagerhud-starter)

### 1. Generate A Webhook Token

Run this on your Mac before you open the Deploy Button:

```bash
openssl rand -hex 24
```

Save this token. You need the exact same value in Cloudflare and Setup Manager.
Cloudflare hides Worker secrets after they are saved.

### 2. Deploy To Cloudflare

When the Deploy Button opens Cloudflare, paste your generated token into the
required `WEBHOOK_TOKEN` secret field. This is the shared token that Setup
Manager must send with every webhook request.

The template includes `.dev.vars.example` so Cloudflare's Deploy Button shows
`WEBHOOK_TOKEN` during setup. `wrangler.toml` also declares this as a required
secret, so manual deploys fail clearly if the token has not been configured.

### 3. Save These Values

After Cloudflare deploys the Worker, save:

- `WEBHOOK_TOKEN`: the token you generated
- Dashboard URL: the Worker URL Cloudflare gives you
- Webhook URL: the same Worker URL with `/webhook` at the end

Example:

```text
Dashboard URL: https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev
Webhook URL:   https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/webhook
```

Then check health:

```text
https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
```

The dashboard is ready when D1 and Durable Objects both show connected.

### 4. Configure Setup Manager

Add the webhook URL and token to your Setup Manager configuration plist. See
[Getting Started](docs/getting-started.md) for the full setup flow and
[Security](docs/security.md) for the complete plist example.

Cloudflare Access is optional. It protects people viewing the dashboard, but it
does not replace the required `WEBHOOK_TOKEN` for Setup Manager webhooks.

## Dashboard Views

The dashboard opens in the **Active** view. Use **Disabled** for test, demo, or
noise enrollments that you want to hide from the main operational dashboard.
Disabled rows stay stored in D1 and can be enabled again later.

## Upgrading

When the dashboard shows that an update is available, update the Git repository
created for your deployment and push the change so Cloudflare rebuilds it. See
[Upgrading Setup Manager HUD](docs/upgrading.md) for the step-by-step guide.

## Local Development

```bash
npm install
npm run sync
npm run dev
```

## Documentation

- [Getting Started](docs/getting-started.md)
- [Docs index](docs/README.md)
- [Configuration](docs/configuration.md)
- [Security](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Upgrading](docs/upgrading.md)

## License

[MIT](LICENSE)
