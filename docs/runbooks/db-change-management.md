# Database Change Management Policy

**Last updated:** 2026-10-18

This document defines what counts as a database change, what approval it
requires, and how to apply it safely. It applies to both `yagye_core_dev`
(Core) and `yagye_portal_development` (Portal) in all environments.

---

## Categories of change

### Category A — Schema migrations (Ecto / Rails)

Ecto migrations (`priv/repo/migrations/*.exs`) and Rails migrations
(`db/migrate/*.rb`) are the only approved mechanism for schema changes.

**Rules:**
- All migrations must be reviewed in a pull request before merging
- Migrations must be backwards-compatible: a migration that removes a column
  or changes a column type must not be deployed while the old application code
  still references that column (deploy code first, then migrate)
- Never run a migration directly in production without first running it in
  staging and verifying the result
- Never write raw `ALTER TABLE` / `DROP COLUMN` statements outside a migration
  file — they are untracked and unrepeatable

**Review checklist for migrations:**
- [ ] Does this migration take an exclusive lock? (e.g. `ADD COLUMN NOT NULL` without a default on a large table)
- [ ] Is the migration reversible? (Ecto: does `down/0` work correctly?)
- [ ] Does it require downtime? If yes, schedule a maintenance window.
- [ ] Does it touch a table referenced by the Portal? (Changes to `merchant_applications`, `merchants`, `payments` require Portal consumer ACL review)

**Lock-safe patterns for large tables:**

```elixir
# UNSAFE on a large table — takes ACCESS EXCLUSIVE lock:
alter table(:payments) do
  add :new_column, :text, null: false, default: ""
end

# SAFE — add nullable first, then backfill, then add constraint:
alter table(:payments) do
  add :new_column, :text
end

# In a separate migration after backfill:
execute "ALTER TABLE payments ALTER COLUMN new_column SET NOT NULL"
# Uses a table scan + rewrite but no exclusive lock on PostgreSQL 12+
```

---

### Category B — Server parameter changes (`postgresql.conf` / `ALTER SYSTEM`)

Server parameters control PostgreSQL's runtime behaviour. Some take effect
immediately (`pg_reload_conf()`); others require a full restart.

**Approval required before any parameter change:**
- Engineering lead review (written, in Slack or GitHub comment)
- For parameters requiring a restart: CTO awareness (this is a financial system)

**Parameters that require a restart (cannot change without downtime):**
- `max_connections`
- `shared_buffers`
- `wal_level`
- `max_wal_senders`
- `listen_addresses`

**Parameters that reload without restart:**
- `work_mem`
- `maintenance_work_mem`
- `autovacuum_*`
- `checkpoint_completion_target`
- `max_wal_size`
- `log_*`

**How to apply a reloadable change safely:**

```bash
# 1. Apply the change
docker exec yagye-core-db psql -U postgres -c "
  ALTER SYSTEM SET checkpoint_completion_target = '0.9';
  ALTER SYSTEM SET max_wal_size = '2GB';
"

# 2. Reload (no downtime)
docker exec yagye-core-db psql -U postgres -c "SELECT pg_reload_conf();"

# 3. Verify the change took effect
docker exec yagye-core-db psql -U postgres -c "
  SHOW checkpoint_completion_target;
  SHOW max_wal_size;
"

# 4. Record the change in the ops log (Slack #ops-log channel or GitHub issue)
```

**How to apply a restart-required change:**

```bash
# 1. Get engineering lead + CTO awareness
# 2. Schedule during lowest-traffic window
# 3. Apply and restart:

docker exec yagye-core-db psql -U postgres -c "
  ALTER SYSTEM SET max_connections = '200';
"
docker compose -f infra/docker/docker-compose.yml restart core-db

# 4. Verify:
docker exec yagye-core-db psql -U postgres -c "SHOW max_connections;"

# 5. Confirm application reconnects successfully:
docker logs yagye-core --tail 20 | grep -E "connected|error"
```

**What NEVER to do:**
- `ALTER SYSTEM SET max_connections = 500` without review — this risks OOM
  if connection count * `work_mem` exceeds available RAM
- Editing `postgresql.conf` inside the Docker container directly — changes
  are lost on container rebuild; use `ALTER SYSTEM` (writes to
  `postgresql.auto.conf`) or the Docker environment variable

---

### Category C — Index changes

Adding or removing indexes is a schema change but with distinct operational
considerations.

**Adding an index on a large table:**

```sql
-- UNSAFE — takes ShareLock, blocks all writes:
CREATE INDEX idx_payments_merchant_state ON payments(merchant_id, state);

-- SAFE — runs without blocking writes:
CREATE INDEX CONCURRENTLY idx_payments_merchant_state ON payments(merchant_id, state);
```

Always use `CONCURRENTLY` in production. The downside: it takes longer and
cannot run inside a transaction block. In an Ecto migration:

```elixir
def change do
  create index(:payments, [:merchant_id, :state], concurrently: true)
end
```

**Removing an index:**

```sql
-- Safe — DROP INDEX does not lock the table for reads or writes:
DROP INDEX CONCURRENTLY idx_payments_old;
```

**Review checklist for index changes:**
- [ ] Is `CONCURRENTLY` used for creation on tables with > 10,000 rows?
- [ ] Does the new index duplicate an existing one? (Check with `\d tablename` in psql)
- [ ] Will the query planner actually use this index? (Verify with `EXPLAIN ANALYZE`)

---

### Category D — Data changes (UPDATE / DELETE / INSERT in production)

Direct data changes in production are **exceptional** and require the highest
level of approval. They bypass all application-layer validation and state
machine checks.

**Approval required:**
- Engineering lead + Finance lead for any change touching financial tables
  (payments, ledger_postings, settlements, fee_records)
- CTO for any change that modifies amounts or states

**Procedure:**

```bash
# 1. Write the SQL and share it in #ops-log for review — do not run it yet
# 2. Test the exact SQL on staging with production-representative data
# 3. Wrap in a transaction and dry-run with ROLLBACK:

docker exec yagye-core-db psql -U postgres -d yagye_core_dev << 'EOF'
BEGIN;
  -- Your change here
  UPDATE payments SET state = 'failed' WHERE id = 'uuid-here';
  -- Verify the result:
  SELECT id, state FROM payments WHERE id = 'uuid-here';
  -- If correct:
  -- COMMIT;
  -- If wrong:
ROLLBACK;
EOF

# 4. After approval, run with COMMIT (not ROLLBACK)
# 5. Record the change in the audit log with:
#    - Who approved it
#    - What was changed
#    - Why it was necessary
#    - The exact SQL run
#    - The timestamp
```

**Financial tables — additional rule:**
The double-entry ledger must remain balanced after any data change.
After any modification to `ledger_postings`:

```sql
SELECT SUM(CASE WHEN direction='debit' THEN amount ELSE -amount END) AS net
FROM ledger_postings;
-- Must equal 0. Non-zero = corrupted ledger. Escalate immediately.
```

---

## Change log

All database changes — schema migrations, parameter changes, index changes,
and data changes — must be logged. Minimum entry:

```
Date: 2026-10-18
Env: staging / production
Type: parameter change
Change: SET checkpoint_completion_target = '0.9'
Approved by: [name]
Reason: I/O pressure observed in Grafana (PostgresCheckpointSpreadLow alert)
Result: pg_bgwriter checkpoint timed% improved from 72% to 94% after reload
```

Log location: Slack `#ops-log` channel (pinned thread "DB Change Log") or
the `ops/db-changes.md` file in this repository.

---

## See also

- `docs/runbooks/database-recovery.md` — what to do when things go wrong
- `docs/architecture/engineering-concepts.md §31` — why these decisions were made
- `docs/architecture/engineering-concepts.md §18` — settlement and SoD constraints
