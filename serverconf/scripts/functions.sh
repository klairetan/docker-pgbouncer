#!/usr/bin/env bash

set -e

function generatePgBouncerDefaultConfig()
{
  POOL_MODE=${PGBOUNCER_POOL_MODE:-session}
  SERVER_RESET_QUERY=${PGBOUNCER_SERVER_RESET_QUERY}

  # if the SERVER_RESET_QUERY and pool mode is session, pgbouncer recommends DISCARD ALL be the default
  # http://pgbouncer.projects.pgfoundry.org/doc/faq.html#_what_should_my_server_reset_query_be
  if [ -z "${SERVER_RESET_QUERY}" ] &&  [ "$POOL_MODE" == "session" ]; then
      SERVER_RESET_QUERY="DISCARD ALL;"
  fi

  cat >> /etc/pgbouncer/pgbouncer.ini << EOFEOF
[pgbouncer]
listen_addr     = localhost
listen_port     = 6000
auth_type       = md5
auth_file       = /etc/pgbouncer/users.txt
unix_socket_dir = /tmp
; When server connection is released back to pool:
;   session      - after client disconnects
;   transaction  - after transaction finishes
;   statement    - after statement finishes
pool_mode                 = ${POOL_MODE}
server_reset_query        = ${SERVER_RESET_QUERY}
max_client_conn           = ${PGBOUNCER_MAX_CLIENT_CONN:-100}
default_pool_size         = ${PGBOUNCER_DEFAULT_POOL_SIZE:-1}
reserve_pool_size         = ${PGBOUNCER_RESERVE_POOL_SIZE:-1}
reserve_pool_timeout      = ${PGBOUNCER_RESERVE_POOL_TIMEOUT:-5.0}
log_connections           = ${PGBOUNCER_LOG_CONNECTIONS:-1}
log_disconnections        = ${PGBOUNCER_LOG_DISCONNECTIONS:-1}
log_pooler_errors         = ${PGBOUNCER_LOG_POOLER_ERRORS:-1}
stats_period              = ${PGBOUNCER_STATS_PERIOD:-60}
ignore_startup_parameters = extra_float_digits

[databases]
EOFEOF
}

function generateStunnelDefaultConfig()
{
  cat >> /etc/stunnel/stunnel-pgbouncer.conf << EOFEOF
foreground = yes

sslVersion = TLSv1

options = SINGLE_ECDH_USE
options = SINGLE_DH_USE
options = NO_SSLv2
options = NO_SSLv3

ciphers = HIGH:!ADH:!AECDH:!LOW:!EXP:!MD5:!3DES:!SRP:!PSK:@STRENGTH

socket = r:TCP_NODELAY=1

[ingress]
protocol = pgsql
accept = 0.0.0.0:5432
connect = 127.0.0.1:6000
retry = no
retry = ${PGBOUNCER_CONNECTION_RETRY:-"no"}
cert = /etc/stunnel/stunnel.pem

EOFEOF
}

function generateDatabaseConfig()
{
  DB=$(echo "$1" | perl -lne 'print "$1 $2 $3 $4 $5 $6 $7" if /^postgres:\/\/([^:]+):([^@]+)@(.*?):(.*?)\/(.*?)(\\?.*)?$/')
  DB_URI=( $DB )
  DB_USER=${DB_URI[0]}
  DB_PASS=${DB_URI[1]}
  DB_HOST=${DB_URI[2]}
  DB_PORT=${DB_URI[3]}
  DB_NAME=${DB_URI[4]}
  DB_MD5_PASS="md5"`echo -n ${DB_PASS}${DB_USER} | md5sum | awk '{print $1}'`

  echo "Setting ${DB_NAME} database config var"

  cat >> /etc/stunnel/stunnel-pgbouncer.conf << EOFEOF
[egress_$DB_NAME]
client = yes
protocol = pgsql
accept  = 127.0.0.1:${DB_LOCAL_PORT:-6432}
connect = $DB_HOST:$DB_PORT
retry = ${PGBOUNCER_CONNECTION_RETRY:-"no"}

EOFEOF

  cat >> /etc/pgbouncer/users.txt << EOFEOF
"$DB_USER" "$DB_MD5_PASS"
EOFEOF

  cat >> /etc/pgbouncer/pgbouncer.ini << EOFEOF
$DB_NAME= host=127.0.0.1 port=${DB_LOCAL_PORT:-6432}
EOFEOF
}