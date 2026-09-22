#!/usr/bin/env bash
set -euo pipefail

app_dir=/var/www/html
bundles_dir=/var/www/bundles

bundle_list() {
    if [[ -n ${DEV_BUNDLES:-} ]]; then
        printf '%s\n' "$DEV_BUNDLES" | tr ',' '\n'
    else
        cat /opt/aggro/templates/default-bundles.txt
    fi
}

while IFS= read -r repo || [[ -n "$repo" ]]; do
    repo="$(printf '%s' "$repo" | tr -d '\r' | xargs)"

    [[ -z "$repo" ]] && continue
    [[ "$repo" == \#* ]] && continue

    repo="${repo%.git}"
    bundle_dir="$bundles_dir/${repo##*/}"
    composer_file="$bundle_dir/composer.json"

    if [[ ! -f "$composer_file" ]]; then
        printf 'Cannot link %s: %s is missing\n' "$repo" "$composer_file" >&2
        exit 1
    fi

    package_name="$(
        php -r '
            $data = json_decode(file_get_contents($argv[1]), true);
            if (!is_array($data) || empty($data["name"])) {
                exit(1);
            }
            echo $data["name"];
        ' "$composer_file"
    )"

    target="$app_dir/vendor/$package_name"

    mkdir -p "$(dirname "$target")"

    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -e "$target" ]]; then
        rm -rf "$target"
    fi

    ln -s "$bundle_dir" "$target"
    printf 'Linked dev bundle: %s -> %s\n' "$package_name" "$bundle_dir"
done < <(bundle_list)
