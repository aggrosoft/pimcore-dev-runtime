FROM pimcore/pimcore:php8.5-max-5.x

LABEL org.opencontainers.image.title="Pimcore Dev Runtime" \
      org.opencontainers.image.description="Remote development runtime for Aggrosoft Pimcore bundles" \
      org.opencontainers.image.source="https://github.com/aggrosoft/pimcore-dev-runtime"

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        chromium \
        curl \
        netcat-openbsd \
        sudo \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    useradd \
        --uid 1000 \
        --gid www-data \
        --home-dir /var/www \
        --no-create-home \
        --shell /bin/bash \
        developer; \
    printf 'developer ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/developer; \
    chmod 0440 /etc/sudoers.d/developer

COPY --chmod=0755 scripts/ /opt/aggro/
COPY templates/ /opt/aggro/templates/

RUN ln -s /opt/aggro/link-bundles.sh /usr/local/bin/pimcore-dev-link-bundles \
    && ln -s /opt/aggro/bundle-deps.sh /usr/local/bin/pimcore-dev-bundle-deps

ENV HOME=/var/www

ENTRYPOINT ["/opt/aggro/dev-entrypoint.sh"]
CMD ["php-fpm"]
