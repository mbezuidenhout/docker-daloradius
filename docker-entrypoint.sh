#!/bin/bash
set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

if [[ "$1" == apache2* ]]; then
    : ${HTTPS_ENABLED:=false}
    hostname="${APACHE_HOSTNAME:-localhost}"
    if [[ $HTTPS_ENABLED != "false" ]]; then
        if [ ! -e /etc/apache2/ssl/${hostname}.crt ] || [ ! -e /etc/apache2/ssl/${hostname}.key ]; then
            # if the certificates don't exist then make them
            mkdir -p /etc/apache2/ssl
            openssl req -days 356 -x509 -out /etc/apache2/ssl/${hostname}.crt -keyout /etc/apache2/ssl/${hostname}.key \
                -newkey rsa:2048 -nodes -sha256 \
                -subj '/CN='${hostname} -extensions EXT -config <( \
            printf "[dn]\nCN=${hostname}\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:${hostname}\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
        fi

        cat > /etc/apache2/sites-available/${hostname}-ssl.conf <<EOL
        <IfModule mod_ssl.c>
            <VirtualHost *:443>
                ServerName ${hostname}
                DocumentRoot /var/www/html
                ErrorLog \${APACHE_LOG_DIR}/error.log
                CustomLog \${APACHE_LOG_DIR}/access.log combined
                SSLEngine on
                SSLCertificateFile /etc/apache2/ssl/${hostname}.crt
                SSLCertificateKeyFile /etc/apache2/ssl/${hostname}.key
            </VirtualHost>
        </IfModule>
EOL
        a2enmod ssl
        a2ensite ${hostname}-ssl
    fi
fi

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- apache2-foreground "$@"
fi

exec "$@"
