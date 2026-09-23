# Pimcore Dev Runtime

Remote development environment for Aggrosoft Pimcore bundles.

The runtime uses the real `aggrosoft/pimcore-app` repository as the host application and checks development bundles out separately below `/var/www/bundles`. A generated development Composer overlay registers those bundles as native Composer `path` repositories, so Composer itself installs them as symlinks into the host application's `vendor/aggrosoft` tree.

The result is a persistent remote Pimcore instance that can be opened directly through VS Code Remote SSH and used for PHP, integration and Pimcore Studio development.

## Workspace

```text
/var/www/
├── AGENTS.md                     # runtime-managed symlink
├── .aggro-dev/
│   ├── AGENTS.md                 # refreshed from the runtime on every start
│   └── AGENTS.local.md           # persistent optional local additions
├── html/                         # aggrosoft/pimcore-app
├── bundles/
│   ├── pimcore-data-bundle/
│   ├── pimcore-catalog-sources-bundle/
│   ├── pimcore-shirtnetwork-bundle/
│   ├── pimcore-shopware-bundle/
│   ├── pimcore-warexo-bundle/
│   └── pimcore-agent-bundle/
└── data -> /var/data
```

The workspace, database, OpenSearch data, RabbitMQ data and `/var/data` are backed by named volumes and survive normal container recreation.

### Agent instructions

`/var/www/AGENTS.md` is a symlink to the runtime-managed `/var/www/.aggro-dev/AGENTS.md`. The managed file is refreshed on every container start so changes in the runtime's development workflow reach existing instances after a redeploy.

Persistent instance-specific instructions belong in:

```text
/var/www/.aggro-dev/AGENTS.local.md
```

That file is created once and never overwritten by the runtime. The managed AGENTS file tells coding agents to read it in addition when it contains local instructions.

## Runtime image

GitHub Actions publishes:

```text
ghcr.io/aggrosoft/pimcore-dev-runtime:main
```

The image extends `pimcore/pimcore:php8.5-max-5.x` and adds only development plumbing:

- a `developer` user for VS Code/SSHPiper
- GitHub App Git authentication
- Node.js/npm for Studio frontend builds
- Chromium for browser smoke tests
- MariaDB client and netcat
- runtime scripts for workspace setup and bundle linking

Pimcore itself is not baked into the workspace. The configured host application repository is cloned into the persistent volume.

## Coolify

Use `compose.coolify.example.yaml` as the Coolify Compose template.

It starts MariaDB 10.11, Redis, RabbitMQ, OpenSearch 2, Mercure, a one-shot setup service, PHP-FPM, Pimcore workers and nginx.

The development PHP memory limit is set to `1G`. Pimcore/Symfony cache warmup in `APP_ENV=dev` with debug enabled can exceed the upstream image's 256 MiB default.

The setup is idempotent. Existing Git working copies are never pulled, reset or deleted automatically.

## GitHub and SSH

Use the same project-shared GitHub App and SSHPiper key variables as the Shopware development template:

```text
GITHUB_APP_CLIENT_ID
GITHUB_APP_INSTALLATION_ID
GITHUB_APP_PRIVATE_KEY
SSH_AUTHORIZED_KEYS_B64
```

For example:

```text
GITHUB_APP_CLIENT_ID={{project.GITHUB_APP_CLIENT_ID}}
GITHUB_APP_INSTALLATION_ID={{project.GITHUB_APP_INSTALLATION_ID}}
GITHUB_APP_PRIVATE_KEY={{project.GITHUB_APP_PRIVATE_KEY}}
SSH_AUTHORIZED_KEYS_B64={{project.SSH_AUTHORIZED_KEYS_B64}}
```

Keep the GitHub private key multiline.

The PHP container uses SSHPiper Docker-exec mode, so no separate SSH daemon is required in the image.

## Pimcore installation

The host repository defaults to:

```text
aggrosoft/pimcore-app
```

Override it with `PIMCORE_APP_REPOSITORY` only when necessary.

A fresh database requires `PIMCORE_PRODUCT_KEY`. Pimcore and package versions come from the host application's committed Composer lock file; there is intentionally no separate `PIMCORE_VERSION` setting.

## Development bundles

When `DEV_BUNDLES` is empty, these repositories are checked out:

```text
aggrosoft/pimcore-data-bundle
aggrosoft/pimcore-catalog-sources-bundle
aggrosoft/pimcore-shirtnetwork-bundle
aggrosoft/pimcore-shopware-bundle
aggrosoft/pimcore-warexo-bundle
aggrosoft/pimcore-agent-bundle
```

`DEV_BUNDLES` can override that list using one `owner/repo` per line.

### Composer path repositories

The committed host application files stay untouched:

```text
/var/www/html/composer.json
/var/www/html/composer.lock
```

The runtime generates:

```text
/var/www/html/composer.dev.json
/var/www/html/composer.dev.lock
```

The generated Composer file replaces the local Aggrosoft GitHub VCS repositories with a path repository pointing at:

```text
/var/www/bundles/*
```

Path packages force symlinking, use stable config-based lock references, and are exposed as `dev-main` even when a bundle checkout is currently on a feature branch.

Inside `/var/www/html`, the normal `composer` command automatically uses `composer.dev.json`. Inside an individual bundle repository, normal Composer behavior is unchanged.

Manual bundle linking is no longer required. To explicitly regenerate the development overlay and reinstall the host dependencies:

```bash
pimcore-dev-sync-composer --install
```

`pimcore-dev-link-bundles` remains available as a backwards-compatible alias.

If the committed host application's dependency definition itself must change, use `composer-real` intentionally against the source `composer.json`/`composer.lock`, then refresh the development overlay.

Bundle PHP development dependencies remain separate. From a bundle repository:

```bash
pimcore-dev-bundle-deps
composer quality
```

For bundles with frontend assets, use the bundle's own npm scripts. The current data bundle can be checked with:

```bash
cd assets
npm ci
npm run check-types
npm test
npm run build
npm run package-build
```

## Integration credentials

Use the same environment variable names as production, but point them exclusively at development/test accounts and endpoints.

The Coolify template passes through:

```text
WAREXO_BASE_URL
WAREXO_USERNAME
WAREXO_PASSWORD
WAREXO_CLIENT_ID

SHOPWARE_BASE_URL
SHOPWARE_CLIENT_ID
SHOPWARE_CLIENT_SECRET

SHIRTNETWORK_USERNAME
SHIRTNETWORK_PASSWORD
SHIRTNETWORK_SKU_SCHEME

NORTY_HUB_URL
NORTY_HUB_USER
NORTY_HUB_PASS

BEECHFIELD_HUB_URL
BEECHFIELD_HUB_USER
BEECHFIELD_HUB_PASS

MEDIA_AI_OPENAI_API_KEY
```

S3 variables are also available when an explicit development bucket is required. Leave them empty otherwise.

There are no production fallbacks in the runtime. Missing integration variables stay empty.

Values shared by all Pimcore development instances can be stored as Coolify project variables and referenced by each resource.

## CSV and source files

The persistent import/test directory is:

```text
/var/data
```

It is also visible in the VS Code workspace as:

```text
/var/www/data
```

CSV exports and other source files can therefore be copied into the environment manually without adding an upload service.

Example:

```text
/var/data/
├── lshop/
├── daiber/
├── atlantis/
└── tmp/
```

## Git behavior

The runtime only clones missing repositories.

It never automatically pulls, resets, cleans, stashes, switches branches, commits or pushes.

The default Git identity is:

```text
Aggrosoft Dev Server <dev-server@aggrosoft.de>
```

Override it with `GIT_USER_NAME` and `GIT_USER_EMAIL` if required.
