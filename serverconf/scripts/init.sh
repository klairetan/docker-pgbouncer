#!/usr/bin/env bash

set -e

source /build/scripts/functions.sh

rm -rf /etc/stunnel/stunnel-pgbouncer.conf
rm -rf /etc/pgbouncer/pgbouncer.ini
rm -rf /etc/pgbouncer/users.txt

mkdir -p /etc/stunnel/
mkdir -p /etc/pgbouncer/

generatePgBouncerDefaultConfig
generateStunnelDefaultConfig

URLS=( $(env | cut -d = -f 1 | grep "^POSTGRES_URL_") )
for URL in "${URLS[@]}"; do
  generateDatabaseConfig ${!URL} ${DB_LOCAL_PORT:-6432}
  DB_LOCAL_PORT=$((${DB_LOCAL_PORT:-6432} + 1))
done

chmod go-rwx /etc/pgbouncer/*
chmod go-rwx /etc/stunnel/*
chmod 600 /etc/stunnel/stunnel.pem
chown -R postgres:postgres /etc/pgbouncer
chown root:postgres /var/log/postgresql
chmod 1775 /var/log/postgresql
chmod 640 /etc/pgbouncer/users.txt

exec /usr/bin/supervisord -n
