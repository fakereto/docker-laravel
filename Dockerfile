FROM fakereto/nginx-fpm:14-php-7.3
LABEL maintainer="Andres Vejar <andresvejar@neubox.net>"

ENV NJS_VERSION=1.14.0.0.2.0-1~stretch \
    NODE_VERSION=8.11.3 \
    NPM_CONFIG_LOGLEVEL=info \
    PATH="/composer/vendor/bin:$PATH" \
    COMPOSER_ALLOW_SUPERUSER=1

# add bitbucket and github to known hosts for ssh needs
WORKDIR /root/.ssh
RUN chmod 0600 /root/.ssh \
    && ssh-keyscan -t rsa bitbucket.org >> known_hosts \
    && ssh-keyscan -t rsa github.com >> known_hosts

# install node for running gulp at container entrypoint startup in dev
# copied from official node Dockerfile
# gpg keys listed at https://github.com/nodejs/node#release-team
RUN set -ex \
  && for key in \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    FD3A5288F042B6850C66B31F09FE44734EB7990E \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    56730D5401028683275BD23C23EFEFE93C4CFFFE \
    77984A986EBC2AA786BC0F66B01FBB92821C587A \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
  ; do \
    gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done

RUN curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && grep " node-v$NODE_VERSION-linux-x64.tar.gz\$" SHASUMS256.txt | sha256sum -c - \
  && ls -al \
  && tar -zxvf "node-v$NODE_VERSION-linux-x64.tar.gz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-x64.tar.gz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs

# we hardcode to develop so all tools are there for npm build
ENV NODE_ENV=develop
# install dependencies first, in a different location for easier app bind mounting for local development
WORKDIR /var/www
COPY ./src/package.json .
RUN npm install
# no need to cache clean in non-final build steps
ENV PATH=/var/www/node_modules/.bin:$PATH \
    NODE_PATH=/var/www/node_modules
WORKDIR /var/www/app

# Laravel App Config
# setup app config environment at runtime
# gets put into ./.env at startup
ENV APP_NAME=Laravel \
    APP_ENV=local \
    APP_DEBUG=true \
    APP_KEY=KEYGOESHERE \
    APP_LOG=errorlog \
    APP_URL=http://localhost \
    DB_CONNECTION=mysql \
    DB_HOST=mysql \
    DB_PORT=3306 \
    DB_DATABASE=homestead \
    DB_USERNAME=homestead \
    DB_PASSWORD=secret \
    CACHE_DRIVER=file \
    QUEUE_CONNECTION=sync \
    LOG_CHANNEL=stdout \
    LOG_SLACK_WEBHOOK_URL=NONE
# Many more ENV may be needed here, and updated in docker-phpfpm-entrypoint file
COPY ./config/app.conf ${NGINX_CONF_DIR}/sites-enabled/app.conf

# copy in app code as late as possible, as it changes the most
COPY docker-laravel-entrypoint.sh /var/www/
ENTRYPOINT ["/var/www/docker-laravel-entrypoint.sh"]

WORKDIR /var/www/app
COPY --chown=www-data:www-data ./src .

EXPOSE 80 443 9000 9001
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]