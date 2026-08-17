# Schema — Physical Data Models

DBML source files for the three Yagye databases.

| File | Service | Tables | Database |
|------|---------|--------|----------|
| [yagye-core.dbml](yagye-core.dbml) | `yagye_core` (Elixir/Phoenix) | ~66 | `yagye_core_dev` / `yagye_core_prod` |
| [yagye-portal.dbml](yagye-portal.dbml) | `yagye_portal` (Rails 8) | ~20 | `yagye_portal_dev` / `yagye_portal_prod` |
| [gateway-simulator.dbml](gateway-simulator.dbml) | `gateway_simulator` (Elixir/Phoenix) | ~13 | `gateway_simulator_dev` |

Render any file at [dbdiagram.io](https://dbdiagram.io/d) by pasting its contents.

## Status

These files are the **design specification** for Phase 0. They will become
generated output once `mix yagye.schema.export` is implemented (Step 8):
at that point the migrations become the source of truth and these files are
regenerated from `pg_catalog + COMMENT ON`.

Until Step 8 is complete: **edit the DBML, then write the migration to match**.
After Step 8: **edit the migration, then regenerate the DBML**.

## Migration checklist

The following constraints are documented in the DBML but cannot be expressed
in DBML syntax. Every relevant migration must include them explicitly —
search for `MIGRATION REQUIRED` in the DBML files.

| Table | Constraint | Type |
|-------|-----------|------|
| `ledger_postings` | SUM(debits) = SUM(credits) per entry | Deferred trigger |
| `pricing_plans` | `(effective_from, effective_to)` non-overlapping per plan name | Exclusion constraint |
| `payments` | `refunded_amount <= captured_amount` | CHECK |
| `data_subject_requests` | `controller IN ('yagye', 'merchant')` | CHECK |
| `impersonation_sessions` | `read_only = true` | CHECK |
| `payment_card_details` | `cardholder_name_subject_ref → pii_vault` | FK |
| `payment_mobile_money_details` | `msisdn_subject_ref → pii_vault` | FK |
| `momo_name_enquiries` | `returned_name_subject_ref → pii_vault` | FK |
| `checkout_sessions` | `customer_subject_ref → pii_vault` | FK |

## Key conventions (from the core schema header)

- **Internal PK**: `uuid` (UUIDv7, generated in the application)
- **Public id**: prefixed ULID, `TEXT UNIQUE` — `pay_` `mch_` `stl_` `brk_` `rfd_` `pot_` `cks_`
- **Money**: `BIGINT` minor units + `CHAR(3)` ISO-4217, adjacent columns, never `NUMERIC`
- **Tenancy**: every money-bearing table carries `merchant_id` AND `mode`
- **Time**: `occurred_at` = domain time, `recorded_at` = system time (bitemporal)
- **Append-only**: `ledger_entries`, `ledger_postings`, `payment_events`, `*_state_events`
- **PII**: lives behind `subject_ref` in `pii_vault` — crypto-shredding resolves right-to-erasure vs financial retention
