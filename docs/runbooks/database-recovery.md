# Database Recovery Runbook

**Last updated:** 2026-10-18

Procedures for PostgreSQL failure scenarios. Each entry covers: how to
confirm the situation, immediate actions, recovery steps, and post-recovery
verification. Read `common-incidents.md` for application-layer incidents.

---

## 1. PostgreSQL Process Crash

**Symptoms:** All database connections refused. `pg_isready` returns
`no response`. All Oban workers failing with `DBConnection.ConnectionError`.

**Confirm:**
```bash
pg_isready -h localhost -p 5432
# "no response" or "connection refused"

docker logs yagye-core-db --tail 50
# Look for: FATAL, PANIC, or "database system was interrupted"
```

**Recovery — automatic restart (most crashes):**
PostgreSQL restores from its WAL automatically on restart. Docker Compose
restarts the container if `restart: unless-stopped` is set (it is).

```bash
# Confirm the container is restarting:
docker ps | grep core-db

# If not restarting automatically:
docker compose -f infra/docker/docker-compose.yml restart core-db
docker compose -f infra/docker/docker-compose.yml restart portal-db

# Watch logs until "database system is ready to accept connections":
docker logs -f yagye-core-db
```

**Recovery — corruption (PANIC in logs, WAL replay failure):**
If PostgreSQL cannot replay WAL on startup, the data directory may be
corrupt. Do NOT attempt to repair the live data directory.

```bash
# 1. Stop the container — do not delete the volume
docker compose stop core-db

# 2. Identify the most recent pg_basebackup or snapshot
#    In production: S3 path is s3://yagye-backups/core-db/<timestamp>/
#    In dev: restore from the last known-good Docker volume snapshot

# 3. Proceed to §3 (Point-in-Time Recovery) for production,
#    or restore from a dev snapshot for local development.
```

**Post-recovery verification:**
```sql
-- Connect and verify the ledger invariant holds
SELECT
  SUM(CASE WHEN direction = 'debit' THEN amount ELSE -amount END) AS net
FROM ledger_postings;
-- Must equal 0. Any non-zero value indicates corrupt ledger entries.

-- Check payment state machine consistency
SELECT state, COUNT(*) FROM payments GROUP BY state ORDER BY state;
-- "dispatching" with very old inserted_at indicates payments stuck in transit
```

---

## 2. Disk Full

**Symptoms:** `PostgresDiskUsageCritical` alert fires. All writes failing
with `could not write to file`. Logs show `No space left on device`.

**Immediate mitigation — buy time:**

```bash
# 1. Identify what's consuming disk
docker exec yagye-core-db du -sh /var/lib/postgresql/data/* | sort -rh | head -20

# 2. Most likely culprit: WAL accumulation (pg_wal/)
#    Safe to remove: WAL segments older than the oldest replication slot
#    DO NOT manually delete WAL — use pg_archivecleanup or wait for checkpoint

# 3. Find and drop temporary / bloated tables
docker exec yagye-core-db psql -U postgres -d yagye_core_dev -c "
  SELECT relname, pg_size_pretty(pg_total_relation_size(oid))
  FROM pg_class WHERE relkind = 'r'
  ORDER BY pg_total_relation_size(oid) DESC LIMIT 10;
"
```

**Proper fix:**
1. Provision additional disk capacity (AWS EBS volume resize, or Docker volume increase)
2. Run `VACUUM FULL` on the highest-bloat table (causes an exclusive lock —
   schedule during low-traffic window)
3. Investigate autovacuum configuration — high dead-tuple ratio means
   autovacuum is not keeping up (see §5)

**Do not:**
- Delete `pg_wal` files manually
- Run `DROP TABLE` on any domain table — RESTRICT FKs will prevent this anyway
- Expand `max_wal_size` without also expanding disk

---

## 3. Point-in-Time Recovery (PITR)

Use this procedure when: data was corrupted by a bad migration, a runaway
script deleted or mutated financial records, or a crash left the DB in an
inconsistent state that WAL replay cannot fix.

**Prerequisites:** WAL archiving must have been running continuously.
Verify the last archive timestamp before proceeding.

```bash
# In production, check S3 for the WAL archive:
aws s3 ls s3://yagye-backups/core-db/wal/ | tail -5
# Most recent timestamp should be < 5 minutes ago

# If WAL archiving is broken (no recent files), PITR is not possible.
# Fall back to restoring from the most recent full backup (§3b).
```

**PITR procedure:**

```bash
# 1. Identify the target recovery time
#    Use git log, Oban job history, or application logs to find
#    the last known-good timestamp (e.g. before a bad migration ran)
TARGET_TIME="2026-10-18 14:30:00 UTC"

# 2. Stop the application — prevent new writes during recovery
docker compose stop yagye-core yagye-portal

# 3. Stop the database (do not delete the volume — keep it for forensics)
docker compose stop core-db

# 4. Create a recovery instance from the base backup
#    In production: copy from s3://yagye-backups/core-db/<latest-basebackup>/
#    into a new volume, then configure recovery.conf (PostgreSQL 12+: recovery
#    parameters go in postgresql.conf or postgresql.auto.conf)

# Add to postgresql.conf on the recovery instance:
cat >> /var/lib/postgresql/data/postgresql.conf << EOF
restore_command = 'aws s3 cp s3://yagye-backups/core-db/wal/%f %p'
recovery_target_time = '${TARGET_TIME}'
recovery_target_action = 'promote'
EOF

# Create recovery signal file (PostgreSQL 12+):
touch /var/lib/postgresql/data/recovery.signal

# 5. Start the recovery instance and monitor logs:
docker compose up core-db
docker logs -f yagye-core-db
# Watch for: "recovery stopping before commit of transaction"
# then: "database system is ready to accept read-only connections"
# then (after promote): "database system is ready to accept connections"

# 6. Verify financial integrity (see post-recovery check in §1)

# 7. Restart the application
docker compose up yagye-core yagye-portal
```

**§3b — Restore from full backup (no WAL archiving):**

```bash
# Last resort — restores to backup timestamp only, not a specific point in time
# All transactions after the backup timestamp are lost

# 1. Copy base backup from S3
aws s3 sync s3://yagye-backups/core-db/<timestamp>/ /var/lib/postgresql/data/

# 2. Remove any recovery.signal file (plain restore, not PITR)
rm -f /var/lib/postgresql/data/recovery.signal

# 3. Start and verify (same as §1 post-recovery)
```

---

## 4. Replica Promotion

Use when: the primary PostgreSQL instance is unrecoverable and a replica
exists. Promotes the replica to primary.

**Confirm the replica is up and its lag:**
```bash
docker exec yagye-core-db-replica psql -U postgres -c "
  SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
"
# Low lag = minimal data loss. High lag = transactions may be lost.
```

**Promote:**
```bash
# PostgreSQL 12+ — touch the trigger file:
docker exec yagye-core-db-replica touch /var/lib/postgresql/data/failover.signal
# Or use pg_promote():
docker exec yagye-core-db-replica psql -U postgres -c "SELECT pg_promote();"

# Confirm promotion:
docker exec yagye-core-db-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
# Must return: f (false — no longer in recovery mode)
```

**Update application config:**
```bash
# Update DATABASE_URL in Core and Portal to point to the promoted replica's host
# Restart both applications
docker compose restart yagye-core yagye-portal
```

**Post-promotion:**
- The old primary must NOT be reconnected to the cluster without a full
  pg_rewind — reconnecting it as a peer causes a split-brain
- File an incident report documenting the data loss window (time between
  last replica sync and the primary failure)
- Provision a new replica from the promoted primary within 24 hours

---

## 5. Autovacuum Blocked / Table Bloat

**Symptoms:** `PostgresDeadTuplesHigh` alert. Queries slowing over time.
`pg_stat_user_tables.last_autovacuum` is NULL or very old.

**Diagnose:**
```sql
-- Find tables with high dead-tuple ratio
SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
  last_autovacuum,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_pct DESC;

-- Check if autovacuum is blocked by a long transaction
SELECT pid, now() - xact_start AS duration, query, state
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY xact_start;
```

**Fix — kill blocking transaction (if safe):**
```sql
-- Verify the blocking query is safe to terminate
SELECT query FROM pg_stat_activity WHERE pid = <blocking_pid>;

-- Terminate it
SELECT pg_terminate_backend(<blocking_pid>);
```

**Fix — manual VACUUM (if autovacuum is too slow):**
```sql
-- VACUUM without FULL reclaims space without an exclusive lock (safe on live DB)
VACUUM VERBOSE ledger_postings;
VACUUM VERBOSE payments;
VACUUM VERBOSE outbox_messages;

-- VACUUM FULL reclaims more space but requires exclusive lock (schedule offline)
-- Only use during a maintenance window
VACUUM FULL VERBOSE ledger_postings;
```

**Long-term fix:**
- Increase `autovacuum_vacuum_scale_factor` from 0.2 to 0.05 for high-write tables
- Add per-table autovacuum settings for `payments`, `ledger_postings`, `outbox_messages`
- Review whether `outbox_messages` rows older than 7 days are being swept

---

## 6. Backup Validation

Run this procedure monthly (or after any infrastructure change) to confirm
backups are usable. **A backup that has never been restored is not a backup.**

```bash
# 1. Restore the most recent backup to a scratch instance
docker run -d \
  --name pg-backup-test \
  -e POSTGRES_PASSWORD=postgres \
  postgres:16

# Copy latest backup into it:
aws s3 sync s3://yagye-backups/core-db/<latest>/ /tmp/pg-backup-restore/
docker cp /tmp/pg-backup-restore/. pg-backup-test:/var/lib/postgresql/data/
docker restart pg-backup-test

# 2. Connect and run integrity checks
docker exec pg-backup-test psql -U postgres -d yagye_core_dev -c "
  -- Ledger sum-zero check
  SELECT SUM(CASE WHEN direction='debit' THEN amount ELSE -amount END) AS net
  FROM ledger_postings;

  -- Payment count sanity (should be > 0 in production)
  SELECT COUNT(*) FROM payments;

  -- No orphaned outbox messages older than 7 days
  SELECT COUNT(*) FROM outbox_messages
  WHERE published_at IS NULL AND inserted_at < NOW() - INTERVAL '7 days';
"

# 3. Record the result in the backup validation log
echo "$(date -u) backup validated: $(docker exec pg-backup-test psql -U postgres -d yagye_core_dev -t -c 'SELECT COUNT(*) FROM payments')" >> /var/log/yagye/backup-validations.log

# 4. Clean up
docker rm -f pg-backup-test
```

---

## 7. Emergency Contacts and Escalation

| Situation | First responder | Escalation |
|---|---|---|
| Disk full | On-call engineer | Platform lead within 15 min |
| DB crash with data loss | On-call engineer | CTO + Finance lead within 5 min |
| Replica promotion | Platform lead | CTO sign-off required |
| PITR restore | Platform lead + Finance lead | CTO sign-off required |
| Backup validation failure | On-call engineer | Platform lead within 1 hour |

**Before any PITR or promotion in production:**
1. Notify Finance lead — they must review the data-loss window
2. Get CTO sign-off — this is a regulated financial system; data loss may require disclosure
3. Document everything in the incident log before, during, and after

---

## See also

- `docs/runbooks/common-incidents.md` — application-layer incidents
- `docs/architecture/engineering-concepts.md §31` — database architecture decisions
- `docs/architecture/diagrams/outbox-projection-pipeline.md` — what data flows through the DB
