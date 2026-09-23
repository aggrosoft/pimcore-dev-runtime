#!/usr/bin/env bash
set -euo pipefail

export HOME=/var/www
umask 0002

install -d -o developer -g www-data -m 0775 \
    /var/www \
    /var/www/html \
    /var/www/bundles \
    /var/www/.aggro-dev \
    /var/www/.config \
    /var/www/.composer

if [[ -d /var/data ]]; then
    chown developer:www-data /var/data
    chmod 0775 /var/data
fi

agent_file=/var/www/.aggro-dev/AGENTS.md
agent_local_file=/var/www/.aggro-dev/AGENTS.local.md
agent_link=/var/www/AGENTS.md

# AGENTS.md is runtime-managed and refreshed on every container start so
# development instructions stay in sync with the runtime implementation.
install -o developer -g www-data -m 0664 \
    /opt/aggro/templates/AGENTS.md \
    "$agent_file"

# Local instance-specific additions survive runtime updates.
if [[ ! -e "$agent_local_file" ]]; then
    install -o developer -g www-data -m 0664 /dev/null "$agent_local_file"
fi

# Keep the workspace-level entry point deterministic even if an older instance
# created a regular file or a stale symlink here.
if [[ -e "$agent_link" || -L "$agent_link" ]]; then
    rm -f "$agent_link"
fi
ln -s "$agent_file" "$agent_link"

if [[ -d /var/data && ! -e /var/www/data && ! -L /var/www/data ]]; then
    ln -s /var/data /var/www/data
fi

if [[ ! -e /var/www/.bashrc ]]; then
    cat > /var/www/.bashrc <<'EOF'
umask 0002

export LS_OPTIONS='--color=auto'
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -lah'
alias l='ls $LS_OPTIONS -lA'

PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
EOF
    chown developer:www-data /var/www/.bashrc
    chmod 0664 /var/www/.bashrc
fi

git_user_name="${GIT_USER_NAME:-Aggrosoft Dev Server}"
git_user_email="${GIT_USER_EMAIL:-dev-server@aggrosoft.de}"

runuser -u developer -- env HOME=/var/www \
    git config --global user.name "$git_user_name"

runuser -u developer -- env HOME=/var/www \
    git config --global user.email "$git_user_email"

add_safe_directory() {
    local path="$1"

    if ! runuser -u developer -- env HOME=/var/www \
        git config --global --get-all safe.directory \
        | grep -Fxq "$path"; then

        runuser -u developer -- env HOME=/var/www \
            git config --global --add safe.directory "$path"
    fi
}

add_safe_directory /var/www/html
add_safe_directory '/var/www/bundles/*'

github_dir=/var/www/.config/aggro-github

if [[ -n ${GITHUB_APP_CLIENT_ID:-} \
    || -n ${GITHUB_APP_INSTALLATION_ID:-} \
    || -n ${GITHUB_APP_PRIVATE_KEY:-} ]]; then

    : "${GITHUB_APP_CLIENT_ID:?GitHub App configuration requires GITHUB_APP_CLIENT_ID}"
    : "${GITHUB_APP_INSTALLATION_ID:?GitHub App configuration requires GITHUB_APP_INSTALLATION_ID}"
    : "${GITHUB_APP_PRIVATE_KEY:?GitHub App configuration requires GITHUB_APP_PRIVATE_KEY}"

    install -d -o developer -g www-data -m 0700 "$github_dir"

    printf '%s\n' "$GITHUB_APP_CLIENT_ID" \
        | runuser -u developer -- tee "$github_dir/client-id" >/dev/null

    printf '%s\n' "$GITHUB_APP_INSTALLATION_ID" \
        | runuser -u developer -- tee "$github_dir/installation-id" >/dev/null

    printf '%s\n' "$GITHUB_APP_PRIVATE_KEY" \
        | runuser -u developer -- tee "$github_dir/private-key.pem" >/dev/null

    chmod 0600 \
        "$github_dir/client-id" \
        "$github_dir/installation-id" \
        "$github_dir/private-key.pem"

    runuser -u developer -- env HOME=/var/www \
        git config --global --unset-all credential.helper 2>/dev/null || true

    runuser -u developer -- env HOME=/var/www \
        git config --global --add \
        credential.helper \
        /opt/aggro/github-app-credential.sh
fi
