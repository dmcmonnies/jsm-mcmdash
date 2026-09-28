# Upgrading Setup Manager HUD

This guide is for Mac admins who deployed Setup Manager HUD with the Cloudflare
Deploy Button.

When the dashboard shows an update is available, the dashboard cannot update
itself. It is a Cloudflare Worker built from a Git repository. To upgrade it,
you update that repository, push the change to GitHub, and Cloudflare builds a
new Worker from the pushed commit.

There are three possible deployment routes:

- Cloudflare Git integration: push to the connected GitHub repo and Cloudflare deploys.
- GitHub Actions: push validates, then manually run the deploy workflow.
- Wrangler: deploy directly from your Mac when Git deployment is not connected.

## What You Need

- The GitHub repository created for your dashboard deployment
- Git installed on your Mac
- Node.js 22 or newer installed on your Mac
- Access to push changes to that GitHub repository
- A Cloudflare Git deployment connected to that repository, or Wrangler access for manual deploys

You do not need to change your `WEBHOOK_TOKEN` for a normal upgrade.

Check your Node.js version:

```bash
node --version
```

The version should start with `v22` or be newer.

If you use `nvm`, switch to Node.js 22 from the repository folder:

```bash
nvm install 22
nvm use 22
```

## Find Your Dashboard Repository

Use the repository that Cloudflare created or connected when you used the
Deploy Button. This is usually not the original starter template repository.

If you are not sure which repository is connected:

1. Open the Cloudflare dashboard.
2. Go to **Workers & Pages**.
3. Open your Setup Manager HUD Worker.
4. Check the build or deployment settings for the connected Git repository.

Clone that repository to your Mac:

```bash
git clone https://github.com/YOUR-ORG/YOUR-DASHBOARD-REPO.git
cd YOUR-DASHBOARD-REPO
```

If you already cloned it earlier:

```bash
cd YOUR-DASHBOARD-REPO
git pull
```

## Check the Current Live Version

Replace the URL with your dashboard URL:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/config
```

You may see something like:

```json
{"version":"1.2.4","latestVersion":"1.2.5","updateAvailable":true}
```

That means the live Worker is running `1.2.4`, and `1.2.5` is available.

## Back Up Your D1 Database

Before upgrading, export a backup of the remote D1 database that stores your
dashboard history. This gives you a copy of your setup events before package
updates or database migrations run.

The default starter database name is `setupmanagerhud-events`, but your
database may have a different name.

Check the database name in `wrangler.toml`:

```bash
grep -A5 '\[\[d1_databases\]\]' wrangler.toml
```

Look for this line:

```toml
database_name = "setupmanagerhud-events"
```

You can also find the database name in Cloudflare:

1. Open `dash.cloudflare.com`
2. Select your account
3. Go to **Workers & Pages**
4. Go to **D1 SQL Database**
5. Find the database used by this dashboard

The Worker binding is usually named `DB`, but the backup command needs the D1
database name, not the binding name.

Create a backup folder and export the remote database:

```bash
mkdir -p backups

npx wrangler d1 export YOUR_DATABASE_NAME \
  --remote \
  --output backups/YOUR_DATABASE_NAME-$(date +%Y%m%d-%H%M%S).sql
```

For the default starter database name, that command is:

```bash
npx wrangler d1 export setupmanagerhud-events \
  --remote \
  --output backups/setupmanagerhud-events-$(date +%Y%m%d-%H%M%S).sql
```

Confirm the backup file was created:

```bash
ls -lh backups
```

Do not commit database backups. They may contain device history, serial
numbers, user names, or other setup details. Keep the SQL file as a recovery
copy in case you need to rebuild or restore D1 after a failed upgrade.

## Upgrade the Repository

From inside your dashboard repository:

```bash
npm install
npm install @motionbug/setupmanagerhud-core@latest
npm run build
```

`npm run build` runs the sync step. Sync removes and regenerates `public/` and
`migrations/` from the installed core package, which prevents old hashed
dashboard bundles from being left behind after an upgrade.

The important files are:

- `package.json`
- `package-lock.json`

Those files tell Cloudflare which version to install during the next build.

Check the installed package version:

```bash
node -p "require('./package-lock.json').packages['node_modules/@motionbug/setupmanagerhud-core']?.version"
```

It should print the new version number.

## Commit and Push

Check what changed:

```bash
git status --short
```

Stage and commit the package update:

```bash
git add package.json package-lock.json
git commit -m "Upgrade Setup Manager HUD core"
git push
```

If Cloudflare is connected directly to this GitHub repo, it should
automatically build and deploy the new Worker after you push. This can take a
few minutes.

If you are using the GitHub Actions workflow included with this starter, a push
to `main` validates the build but does not deploy. Go to **Actions -> Deploy to
Cloudflare Workers -> Run workflow** to deploy after the validation passes.

## Confirm Cloudflare Rebuilt It

In Cloudflare, open your Worker and check the latest deployment. Confirm that it
used the commit you just pushed.

You can also check from Terminal:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/config
```

After a successful upgrade, `version` and `latestVersion` should match:

```json
{"version":"1.2.5","latestVersion":"1.2.5","updateAvailable":false}
```

If your browser still shows the old version, hard refresh the dashboard page.

## Manual Wrangler Deploy

Most admins should use the Git push method above. Use Wrangler only if your
Cloudflare project is not rebuilding from Git or you intentionally want to
deploy from your Mac.

First sign in:

```bash
npx wrangler login
npx wrangler whoami
```

Check that `wrangler.toml` points at the correct Worker:

```bash
grep '^name = ' wrangler.toml
```

The name should match your dashboard Worker. For example:

```toml
name = "jamfnationlive"
```

Then deploy:

```bash
npm run build
npx wrangler d1 migrations apply DB --remote
npx wrangler deploy
```

Check the live version again:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/config
```

## Troubleshooting

### Cloudflare Rebuilt, But The Dashboard Still Shows The Old Version

Check the lockfile version:

```bash
node -p "require('./package-lock.json').packages['node_modules/@motionbug/setupmanagerhud-core']?.version"
```

If this prints the old version, run:

```bash
npm install @motionbug/setupmanagerhud-core@latest
git add package.json package-lock.json
git commit -m "Upgrade Setup Manager HUD core"
git push
```

### `package.json` Looks Updated, But Cloudflare Still Installs The Old Version

Make sure `package-lock.json` was committed. Cloudflare uses the lockfile during
install, so `package.json` alone is not enough.

### The Wrong Worker Was Updated

Check `wrangler.toml`:

```bash
grep '^name = ' wrangler.toml
```

If the name does not match your dashboard Worker, Cloudflare or Wrangler may be
deploying to the wrong Worker.

### D1 Or Durable Object Warnings Appear After Deploy

Check health:

```bash
curl https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/api/health
```

You want to see:

```json
{"status":"healthy","d1":"connected","durable_objects":"connected"}
```

If D1 migrations are pending, run:

```bash
npx wrangler d1 migrations apply DB --remote
```

Then redeploy or wait for Cloudflare's next successful build.
