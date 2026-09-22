#!/usr/bin/env bash
set -euo pipefail

github_dir=/var/www/.config/aggro-github
client_id_file="$github_dir/client-id"
installation_id_file="$github_dir/installation-id"
private_key="$github_dir/private-key.pem"
token_file="$github_dir/installation-token"

get_token() {
    if [[ ! -s "$client_id_file" || ! -s "$installation_id_file" || ! -s "$private_key" ]]; then
        printf '%s\n' 'GitHub App credentials are not initialized.' >&2
        return 1
    fi

    local client_id installation_id now token token_mtime
    client_id="$(<"$client_id_file")"
    installation_id="$(<"$installation_id_file")"
    now="$(date +%s)"
    token=

    if [[ -s "$token_file" ]]; then
        token_mtime="$(stat -c %Y "$token_file" 2>/dev/null || printf '0')"

        if (( now - token_mtime < 3000 )); then
            token="$(<"$token_file")"
        fi
    fi

    if [[ -z "$token" ]]; then
        b64url() {
            openssl base64 -A | tr '+/' '-_' | tr -d '='
        }

        local header payload unsigned signature jwt response

        header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
        payload="$(
            printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
                "$((now - 60))" \
                "$((now + 540))" \
                "$client_id" \
                | b64url
        )"

        unsigned="$header.$payload"
        signature="$(
            printf '%s' "$unsigned" \
                | openssl dgst -sha256 -sign "$private_key" -binary \
                | b64url
        )"
        jwt="$unsigned.$signature"

        response="$(
            curl -fsS \
                --request POST \
                --url "https://api.github.com/app/installations/$installation_id/access_tokens" \
                --header 'Accept: application/vnd.github+json' \
                --header "Authorization: Bearer $jwt" \
                --header 'X-GitHub-Api-Version: 2022-11-28'
        )"

        token="$(
            printf '%s' "$response" \
                | php -r '
                    $data = json_decode(stream_get_contents(STDIN), true);
                    if (!is_array($data) || empty($data["token"])) {
                        fwrite(STDERR, "GitHub did not return an installation token\n");
                        exit(1);
                    }
                    echo $data["token"];
                '
        )"

        umask 077
        printf '%s' "$token" > "$token_file"
    fi

    printf '%s' "$token"
}

if [[ "${1:-}" == "--token" ]]; then
    get_token
    printf '\n'
    exit 0
fi

[[ "${1:-}" == "get" ]] || exit 0

protocol=
host=

while IFS='=' read -r key value; do
    case "$key" in
        protocol) protocol="$value" ;;
        host) host="$value" ;;
    esac
done

[[ "$protocol" == "https" ]] || exit 0
[[ "$host" == "github.com" ]] || exit 0

token="$(get_token)"

printf 'username=x-access-token\n'
printf 'password=%s\n\n' "$token"
