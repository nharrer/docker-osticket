# syntax=docker/dockerfile:1.3

FROM php:8.1-fpm-alpine3.16
RUN set -ex; \
    \
    export CFLAGS="-Os"; \
    export CPPFLAGS="${CFLAGS}"; \
    export LDFLAGS="-Wl,--strip-all"; \
    \
    # Runtime dependencies
    apk add --no-cache \
        c-client \
        icu \
        libintl \
        libpng \
        libzip \
        msmtp \
        nginx \
        openldap \
        runit \
    ; \
    \
    # Build dependencies
    apk add --no-cache --virtual .build-deps \
        ${PHPIZE_DEPS} \
        gettext-dev \
        icu-dev \
        imap-dev \
        libpng-dev \
        libzip-dev \
        openldap-dev \
    ; \
    \
    # Install PHP extensions
    docker-php-ext-configure imap --with-imap-ssl; \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        gettext \
        imap \
        intl \
        ldap \
        mysqli \
        sockets \
        zip \
    ; \
    pecl install apcu; \
    docker-php-ext-enable \
        apcu \
        opcache \
    ; \
    \
    # Create msmtp log
    touch /var/log/msmtp.log; \
    chown www-data:www-data /var/log/msmtp.log; \
    \
    # Create data dir
    mkdir /var/lib/osticket; \
    \
    # Clean up
    apk del .build-deps; \
    rm -rf /tmp/pear /var/cache/apk/*
# DO NOT FORGET TO CHECK THE LANGUAGE PACK DOWNLOAD URL BELOW
# DO NOT FORGET TO UPDATE "image-version" FILE
ENV OSTICKET_VERSION=1.18 \
    OSTICKET_SHA256SUM=c0c3ef4220b8709e1dbe12503294d412390e91d638e8c6d57ab8d8403c5753e1
RUN --mount=type=bind,source=utils/verify-plugin.php,target=/tmp/verify-plugin.php,readonly \
    \
    set -ex; \
    \
    wget -q -O osTicket.zip https://github.com/osTicket/osTicket/releases/download/\
v${OSTICKET_VERSION}/osTicket-v${OSTICKET_VERSION}.zip; \
    echo "${OSTICKET_SHA256SUM}  osTicket.zip" | sha256sum -c; \
    unzip osTicket.zip 'upload/*'; \
    rm osTicket.zip; \
    mkdir /usr/local/src; \
    mv upload /usr/local/src/osticket; \
    # Hard link the sources to the public directory
    cp -al /usr/local/src/osticket/. /var/www/html; \
    # Hide setup
    rm -r /var/www/html/setup; \
    \
    cd /var/www/html; \
    \
    for lang in bg bn bs ca cs da de el es_AR es_ES es_MX et eu fa fi fr gl he hi hr hu id is it \
        ja ka km ko lt lv mk mn ms nl no pl pt_BR pt_PT ro ru sk sl sq sr sr_CS sv_SE sw th tr uk \
        ur_IN ur_PK vi zh_CN zh_TW; do \
        # Language packs from https://s3.amazonaws.com/downloads.osticket.com/lang/1.17.x/ (used by
        # the official osTicket Downloads page) cannot be authenticated. See:
        # https://github.com/osTicket/osTicket/issues/6377
        wget -q -O /var/www/html/include/i18n/${lang}.phar \
            https://s3.amazonaws.com/downloads.osticket.com/lang/1.14.x/${lang}.phar; \
        php /tmp/verify-plugin.php "/var/www/html/include/i18n/${lang}.phar"; \
    done
RUN set -ex; \
    \
    for plugin in audit auth-2fa auth-ldap auth-oauth2 auth-passthru auth-password-policy \
        storage-fs storage-s3; do \
        wget -q -O /var/www/html/include/plugins/${plugin}.phar \
            https://s3.amazonaws.com/downloads.osticket.com/plugin/${plugin}.phar; \
    done; \
    # This checks `.phar` integrity (authenticity check is not supported - see
    # https://github.com/osTicket/osTicket/issues/6376).
    for phar in /var/www/html/include/plugins/*.phar; do \
        # The following PHP code throws an exception and returns non-zero if .phar can't be loaded
        # (e.g. due to a checksum mismatch)
        php -r "new Phar(\"${phar}\");"; \
    done
ENV OSTICKET_SLACK_VERSION=de1d9a276a64520eea6e6368e609a0f4c4829d96 \
    OSTICKET_SLACK_SHA256SUM=8d06500fd5b8a589a5f7103c242160086ca1696a5b93d0e3767119a54059532b
RUN set -ex; \
    \
    wget -q -O osTicket-slack-plugin.tar.gz https://github.com/devinsolutions/\
osTicket-slack-plugin/archive/${OSTICKET_SLACK_VERSION}.tar.gz; \
    echo "${OSTICKET_SLACK_SHA256SUM}  osTicket-slack-plugin.tar.gz" | sha256sum -c; \
    tar -xzf osTicket-slack-plugin.tar.gz -C /var/www/html/include/plugins --strip-components 1 \
        osTicket-slack-plugin-${OSTICKET_SLACK_VERSION}/slack; \
    rm osTicket-slack-plugin.tar.gz
COPY root /
CMD ["start"]
STOPSIGNAL SIGTERM
EXPOSE 80
HEALTHCHECK CMD curl -fIsS http://localhost/ || exit 1
