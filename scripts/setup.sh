#!/usr/bin/env bash
set -euo pipefail

export HOME=/var/www
export COMPOSER_HOME=/var/www/.composer
umask 0002

app_dir=/var/www/html
bundles_dir=/var/www/bundles

run_dev() {
    runuser -u developer -- env \
        HOME=/var/www \
        COMPOSER_HOME=/var/www/.composer \
        "$@"
}

composer_auth() {
    if [[ ! -s /var/www/.config/aggro-github/client-id ]]; then
        return 0
    fi

    local token
    token="$(/opt/aggro/github-app-credential.sh --token)"

    php -r '
        echo json_encode([
            "github-oauth" => ["github.com" => $argv[1]],
        ], JSON_UNESCAPED_SLASHES);
    ' "$token"
}

run_composer() {
    local auth
    auth="$(composer_auth)"

    if [[ -n "$auth" ]]; then
        run_dev env COMPOSER_AUTH="$auth" composer "$@"
    else
        run_dev composer "$@"
    fi
}

bundle_list() {
    if [[ -n ${DEV_BUNDLES:-} ]]; then
        printf '%s\n' "$DEV_BUNDLES" | tr ',' '\n'
    else
        cat /opt/aggro/templates/default-bundles.txt
    fi
}

normalize_repo() {
    local repo
    repo="$(printf '%s' "$1" | tr -d '\r' | xargs)"
    repo="${repo%.git}"

    if [[ ! "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
        printf 'Invalid GitHub repository: %s\n' "$repo" >&2
        return 1
    fi

    printf '%s' "$repo"
}

clone_repo() {
    local repo target url origin
    repo="$(normalize_repo "$1")"
    target="$2"
    url="https://github.com/$repo.git"

    if [[ -d "$target/.git" ]]; then
        origin="$(run_dev git -C "$target" remote get-url origin 2>/dev/null || true)"

        if [[ "$origin" != "$url" && "$origin" != "git@github.com:$repo.git" ]]; then
            printf 'Existing repository at %s has unexpected origin: %s\n' \
                "$target" "$origin" >&2
            return 1
        fi

        printf 'Repository already present: %s -> %s\n' "$repo" "$target"
        return
    fi

    if [[ -e "$target" && -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        printf 'Cannot clone %s: target is not empty: %s\n' "$repo" "$target" >&2
        return 1
    fi

    printf 'Cloning repository: %s -> %s\n' "$repo" "$target"
    run_dev git clone "$url" "$target"
}

is_pimcore_installed() {
    php -r '
        $url = getenv("DATABASE_URL");

        if (!$url) {
            fwrite(STDERR, "DATABASE_URL is missing\n");
            exit(2);
        }

        $parts = parse_url($url);

        if ($parts === false) {
            fwrite(STDERR, "Could not parse DATABASE_URL\n");
            exit(2);
        }

        $database = ltrim($parts["path"] ?? "", "/");
        $host = $parts["host"] ?? "db";
        $port = $parts["port"] ?? 3306;
        $user = urldecode($parts["user"] ?? "");
        $password = urldecode($parts["pass"] ?? "");

        $pdo = new PDO(
            sprintf(
                "mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4",
                $host,
                $port,
                $database
            ),
            $user,
            $password,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );

        $statement = $pdo->prepare(
            "SELECT COUNT(*)
             FROM information_schema.tables
             WHERE table_schema = ?
               AND table_name = ?"
        );

        $statement->execute([$database, "users"]);

        exit(((int) $statement->fetchColumn()) > 0 ? 0 : 1);
    '
}

run_console() {
    (
        cd "$app_dir"
        run_dev php bin/console "$@"
    )
}

bundle_installed() {
    local bundle="$1"

    (
        cd "$app_dir"
        run_dev env APP_DEBUG=0 php bin/console pimcore:bundle:list --json
    ) | BUNDLE_NAME="$bundle" php -r '
        $bundle = getenv("BUNDLE_NAME");
        $rows = json_decode(stream_get_contents(STDIN), true);

        if (!is_array($rows)) {
            fwrite(STDERR, "Could not parse pimcore:bundle:list output\n");
            exit(2);
        }

        foreach ($rows as $row) {
            if (($row["Bundle"] ?? null) === $bundle) {
                exit(!empty($row["Installed"]) ? 0 : 1);
            }
        }

        fwrite(STDERR, sprintf("Bundle %s is not registered\n", $bundle));
        exit(2);
    '
}

install_bundle() {
    local bundle="$1"

    if bundle_installed "$bundle"; then
        printf 'Bundle already installed: %s\n' "$bundle"
        return
    fi

    printf 'Installing bundle: %s\n' "$bundle"
    run_console pimcore:bundle:install "$bundle" --no-interaction
}

printf '%s\n' '==> Initializing development workspace'

app_repo="$(normalize_repo "${PIMCORE_APP_REPOSITORY:-aggrosoft/pimcore-app}")"
clone_repo "$app_repo" "$app_dir"

while IFS= read -r raw_repo || [[ -n "$raw_repo" ]]; do
    raw_repo="$(printf '%s' "$raw_repo" | tr -d '\r' | xargs)"

    [[ -z "$raw_repo" ]] && continue
    [[ "$raw_repo" == \#* ]] && continue

    repo="$(normalize_repo "$raw_repo")"
    clone_repo "$repo" "$bundles_dir/${repo##*/}"

    run_composer config --global \
        "repositories.${repo##*/}" \
        vcs \
        "https://github.com/$repo.git"
done < <(bundle_list)

printf '%s\n' '==> Installing Pimcore application dependencies'
run_composer --working-dir="$app_dir" install \
    --no-interaction \
    --prefer-dist \
    --no-scripts

printf '%s\n' '==> Linking editable development bundles'
/opt/aggro/link-bundles.sh

run_composer --working-dir="$app_dir" dump-autoload \
    --no-interaction \
    --no-scripts

install -d -o developer -g www-data -m 0775 \
    "$app_dir/var" \
    "$app_dir/public/var"

chmod -R g+rwX "$app_dir/var" "$app_dir/public/var"

if is_pimcore_installed; then
    printf '%s\n' '==> Pimcore core already installed'
else
    : "${PIMCORE_PRODUCT_KEY:?PIMCORE_PRODUCT_KEY is required for the initial Pimcore installation}"

    printf '%s\n' '==> Installing Pimcore core into fresh database'

    (
        cd "$app_dir"
        run_dev env \
            PIMCORE_APP_BUNDLES=0 \
            vendor/bin/pimcore-install \
            --install-profile='App\Installer\SkeletonProfile' \
            --no-interaction
    )
fi

printf '%s\n' '==> Warming development container'
run_console cache:warmup

printf '%s\n' '==> Running Doctrine migrations'
run_console doctrine:migrations:migrate --no-interaction

printf '%s\n' '==> Installing application bundles'
install_bundle PimcoreDataHubBundle
install_bundle PimcoreDataImporterBundle
install_bundle AggrosoftPimcoreDataBundle
install_bundle AggrosoftPimcoreWarexoBundle
install_bundle AggrosoftPimcoreShopwareBundle
install_bundle AggrosoftPimcoreShirtnetworkBundle
install_bundle AggrosoftPimcoreAgentBundle

printf '%s\n' '==> Running remaining migrations'
run_console doctrine:migrations:migrate --no-interaction

printf '%s\n' '==> Applying idempotent application model upgrades'
run_console app:pim:install-object-model --no-interaction
run_console app:shopware:install-object-model --no-interaction
run_console app:shirtnetwork:install-object-model --no-interaction

printf '%s\n' '==> Installing assets and rebuilding Pimcore classes'
run_console assets:install public --no-interaction
run_console pimcore:deployment:classes-rebuild --no-interaction

printf '%s\n' '==> Rebuilding development caches'
run_console pimcore:cache:clear
run_console cache:clear --no-warmup
run_console cache:warmup

chgrp -R www-data "$app_dir/var" "$app_dir/public/var"
chmod -R g+rwX "$app_dir/var" "$app_dir/public/var"

printf '%s\n' '==> Pimcore development environment is ready'
