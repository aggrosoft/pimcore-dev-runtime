#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'pimcore-dev-link-bundles is kept for compatibility; Composer path repositories now manage the bundle symlinks.'
exec /opt/aggro/sync-app-composer.sh --install
