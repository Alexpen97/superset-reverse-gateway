#!/bin/bash
set -euo pipefail

# Creates dedicated databases + roles for Superset and Keycloak.
# Runs once via /docker-entrypoint-initdb.d on first Postgres boot.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER ${SUPERSET_DB_USER} WITH PASSWORD '${SUPERSET_DB_PASSWORD}';
    CREATE DATABASE ${SUPERSET_DB} OWNER ${SUPERSET_DB_USER};
    GRANT ALL PRIVILEGES ON DATABASE ${SUPERSET_DB} TO ${SUPERSET_DB_USER};

    CREATE USER ${KEYCLOAK_DB_USER} WITH PASSWORD '${KEYCLOAK_DB_PASSWORD}';
    CREATE DATABASE ${KEYCLOAK_DB} OWNER ${KEYCLOAK_DB_USER};
    GRANT ALL PRIVILEGES ON DATABASE ${KEYCLOAK_DB} TO ${KEYCLOAK_DB_USER};
EOSQL

# Postgres 15+ requires schema privileges on the public schema
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$SUPERSET_DB" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${SUPERSET_DB_USER};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$KEYCLOAK_DB" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${KEYCLOAK_DB_USER};
EOSQL
