#!/usr/bin/env bash
# Runs once when the postgres volume is first created.
# Creates all app databases so a clean `docker compose up` gives every app a DB.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
  SELECT 'CREATE DATABASE yagye_core_dev'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yagye_core_dev')\gexec
  SELECT 'CREATE DATABASE yagye_core_test'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yagye_core_test')\gexec
  SELECT 'CREATE DATABASE gateway_simulator_dev'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gateway_simulator_dev')\gexec
  SELECT 'CREATE DATABASE gateway_simulator_test'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gateway_simulator_test')\gexec
  SELECT 'CREATE DATABASE yagye_portal_dev'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yagye_portal_dev')\gexec
  SELECT 'CREATE DATABASE yagye_portal_test'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yagye_portal_test')\gexec
EOSQL
