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
    hostname="${APACHE_HOSTNAME:-localhost}"
    a2dissite 000-default
    cat > /etc/apache2/sites-available/${hostname}.conf <<EOL
    <VirtualHost *:80>
        ServerName ${hostname}
        ServerAdmin webmaster@localhost
	    DocumentRoot /var/www/daloradius
        ErrorLog \${APACHE_LOG_DIR}/error.log
	    CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
EOL
    a2ensite ${hostname}

    : ${HTTPS_ENABLED:=false}
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
                DocumentRoot /var/www/daloradius
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

envs=(
    RADIUS_DB_HOST
    RADIUS_DB_USER
    RADIUS_DB_PASSWORD
    RADIUS_DB_NAME
    RADIUS_DB_PORT
)
haveConfig=
for e in "${envs[@]}"; do
    file_env "$e"
    if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
        haveConfig=1
    fi
done

if [ "$haveConfig" ]; then
    : "${RADIUS_DB_HOST:=mysql}"
    : "${RADIUS_DB_USER:=root}"
    : "${RADIUS_DB_PASSWORD:=}"
    : "${RADIUS_DB_NAME:=freeradius}"
    : "${RADIUS_DB_PORT:=3306}"

    # Ensure that line ends are unix
    sed -ri -e 's/\r$//' /var/www/daloradius/library/daloradius.conf.php

    sed_escape_lhs() {
        echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
    }
    sed_escape_rhs() {
        echo "$@" | sed -e 's/[\/&]/\\&/g'
    }
    php_escape() {
        local escaped="$(php -r 'var_export(('"$2"') $argv[1]);' -- "$1")"
        if [ "$2" = 'string' ] && [ "${escaped:0:1}" = "'" ]; then
            escaped="${escaped//$'\n'/"' + \"\\n\" + '"}"
        fi
        echo "$escaped"
    }
    set_config() {
        key="$1"
        value="$2"
        var_type="${3:-string}"
        start="\[(['\\\"])$(sed_escape_lhs "$key")\2\]\s*="
        end=";"
        if [ "${key:0:1}" = '$' ]; then
            start="^(\s*)$(sed_escape_lhs "$key")\s*="
            end=";"
        fi
        sed -ri -e "s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/" /var/www/daloradius/library/daloradius.conf.php
    }
    set_config 'CONFIG_DB_HOST' "$RADIUS_DB_HOST"
    set_config 'CONFIG_DB_USER' "$RADIUS_DB_USER"
    set_config 'CONFIG_DB_PASS' "$RADIUS_DB_PASSWORD"
    set_config 'CONFIG_DB_NAME' "$RADIUS_DB_NAME"
    set_config 'CONFIG_DB_PORT' "$RADIUS_DB_PORT"
fi

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- apache2-foreground "$@"
fi

exec "$@"
