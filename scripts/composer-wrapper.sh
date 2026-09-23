#!/usr/bin/env bash
set -euo pipefail

real_composer=/usr/local/bin/composer-real
app_dir=/var/www/html
dev_composer="$app_dir/composer.dev.json"

if [[ -n ${COMPOSER:-} || ! -f "$dev_composer" ]]; then
    exec "$real_composer" "$@"
fi

workdir="$(pwd -P)"
args=("$@")

for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
        -d|--working-dir)
            if (( i + 1 < ${#args[@]} )); then
                workdir="$(realpath -m "${args[$((i + 1))]}")"
            fi
            ;;
        --working-dir=*)
            workdir="$(realpath -m "${args[$i]#--working-dir=}")"
            ;;
    esac
done

composer_root="$workdir"
while [[ "$composer_root" != "/" && ! -f "$composer_root/composer.json" ]]; do
    composer_root="$(dirname "$composer_root")"
done

if [[ "$composer_root" == "$app_dir" ]]; then
    /opt/aggro/sync-app-composer.sh

    export COMPOSER=composer.dev.json
    exec "$real_composer" "$@"
fi

exec "$real_composer" "$@"
