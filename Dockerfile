#
# daloRADIUS Dockerfile
#

FROM php:7.4-apache
LABEL maintainer="Marius Bezuidenhout <marius.bezuidenhout@gmail.com>"

RUN apt-get update \
 && apt-get install --no-install-recommends --assume-yes --quiet \
        ca-certificates openssl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && ldconfig

RUN update-ca-certificates -f \
 && mkdir -p /tmp/pear/cache \
 && curl -O https://pear.php.net/go-pear.phar \
 && echo | php go-pear.phar \
 && rm go-pear.phar \
 && pear channel-update pear.php.net \
 && pear install -a -f DB \
 && pear install -a -f Mail \
 && pear install -a -f Mail_Mime

ENV DALO_VERSION 1.1-3

RUN curl -LO https://github.com/lirantal/daloradius/archive/"$DALO_VERSION".tar.gz \
 && tar -xzf "$DALO_VERSION".tar.gz \
 && rm "$DALO_VERSION".tar.gz \
 && mv daloradius-"$DALO_VERSION" /var/www/html/daloradius \
 && chown -R www-data:www-data /var/www/html/daloradius \
 && chmod 644 /var/www/html/daloradius/library/daloradius.conf.php

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 80 443
CMD ["apache2-foreground"]
