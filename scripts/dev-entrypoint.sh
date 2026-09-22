#!/usr/bin/env bash
set -euo pipefail

umask 0002

/opt/aggro/dev-shell-init.sh

if [[ $# -eq 0 ]]; then
    set -- php-fpm
fi

exec "$@"
