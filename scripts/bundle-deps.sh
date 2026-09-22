#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:-$PWD}"
bundle_dir="$(readlink -f "$bundle_dir")"

case "$bundle_dir" in
    /var/www/bundles/*) ;;
    *)
        printf 'Bundle must be below /var/www/bundles: %s\n' "$bundle_dir" >&2
        exit 1
        ;;
esac

if [[ ! -f "$bundle_dir/composer.json" ]]; then
    printf 'No composer.json in %s\n' "$bundle_dir" >&2
    exit 1
fi

tracked_lock=0

if git -C "$bundle_dir" ls-files --error-unmatch composer.lock >/dev/null 2>&1; then
    tracked_lock=1
fi

composer_auth=

if [[ -s /var/www/.config/aggro-github/client-id ]]; then
    token="$(/opt/aggro/github-app-credential.sh --token)"
    composer_auth="$(
        php -r '
            echo json_encode([
                "github-oauth" => ["github.com" => $argv[1]],
            ], JSON_UNESCAPED_SLASHES);
        ' "$token"
    )"
fi

if [[ -n "$composer_auth" ]]; then
    COMPOSER_HOME=/var/www/.composer \
    COMPOSER_AUTH="$composer_auth" \
        composer --working-dir="$bundle_dir" install --no-interaction --prefer-dist
else
    COMPOSER_HOME=/var/www/.composer \
        composer --working-dir="$bundle_dir" install --no-interaction --prefer-dist
fi

if [[ "$tracked_lock" -eq 0 && -f "$bundle_dir/composer.lock" ]]; then
    rm "$bundle_dir/composer.lock"
fi
