#!/usr/bin/env bash
set -euo pipefail

app_dir=${PIMCORE_APP_DIR:-/var/www/html}
bundles_dir=${PIMCORE_BUNDLES_DIR:-/var/www/bundles}
state_dir=/var/www/.aggro-dev
real_composer=/usr/local/bin/composer-real

mkdir -p "$state_dir"

packages_json="$(php /opt/aggro/generate-dev-composer.php "$app_dir" "$bundles_dir")"

mapfile -t packages < <(
    printf '%s' "$packages_json" | php -r '
        $packages = json_decode(stream_get_contents(STDIN), true, flags: JSON_THROW_ON_ERROR);
        foreach ($packages as $package) {
            echo $package, PHP_EOL;
        }
    '
)

if [[ ${#packages[@]} -eq 0 ]]; then
    printf '%s\n' 'No local bundle packages found.' >&2
    exit 1
fi

git_exclude="$app_dir/.git/info/exclude"
if [[ -d "$app_dir/.git" ]]; then
    touch "$git_exclude"
    for pattern in /composer.dev.json /composer.dev.lock; do
        grep -Fqx "$pattern" "$git_exclude" || printf '%s\n' "$pattern" >> "$git_exclude"
    done
fi

fingerprint="$(
    {
        cat "$app_dir/composer.json"
        cat "$app_dir/composer.lock"
        cat "$app_dir/composer.dev.json"

        for composer_file in "$bundles_dir"/*/composer.json; do
            [[ -f "$composer_file" ]] || continue
            printf '\n-- %s --\n' "$composer_file"
            cat "$composer_file"
        done
    } | sha256sum | cut -d' ' -f1
)"

state_file="$state_dir/pimcore-composer.sha256"
refresh=0

if [[ ! -f "$app_dir/composer.dev.lock" || ! -f "$state_file" ]]; then
    refresh=1
elif [[ "$(<"$state_file")" != "$fingerprint" ]]; then
    refresh=1
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

run_composer() {
    if [[ -n "$composer_auth" ]]; then
        (
            cd "$app_dir"
            COMPOSER=composer.dev.json \
            COMPOSER_HOME=/var/www/.composer \
            COMPOSER_AUTH="$composer_auth" \
                "$real_composer" "$@"
        )
    else
        (
            cd "$app_dir"
            COMPOSER=composer.dev.json \
            COMPOSER_HOME=/var/www/.composer \
                "$real_composer" "$@"
        )
    fi
}

if [[ "$refresh" -eq 1 ]]; then
    cp "$app_dir/composer.lock" "$app_dir/composer.dev.lock"

    printf '%s\n' 'Refreshing development Composer lock for local bundles...'
    run_composer update \
        "${packages[@]}" \
        --with-dependencies \
        --no-install \
        --no-scripts \
        --no-interaction

    printf '%s' "$fingerprint" > "$state_file"
fi

if [[ "${1:-}" == "--install" ]]; then
    printf '%s\n' 'Installing application dependencies with local bundle path repositories...'
    run_composer install --no-interaction --prefer-dist --no-scripts
fi
