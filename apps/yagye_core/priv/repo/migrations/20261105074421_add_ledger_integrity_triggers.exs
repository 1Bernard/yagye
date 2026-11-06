defmodule YagyeCore.Repo.Migrations.AddLedgerIntegrityTriggers do
  use Ecto.Migration

  def up do
    # ── 1. Deferred Constraint Trigger: Invariant SUM(debits) == SUM(credits) ──
    # Enforces double-entry balance per entry_id across all postings at COMMIT time.
    execute("""
    CREATE OR REPLACE FUNCTION verify_ledger_entry_balanced()
    RETURNS TRIGGER AS $$
    DECLARE
      v_debit_sum  NUMERIC;
      v_credit_sum NUMERIC;
      v_entry_id   UUID;
    BEGIN
      v_entry_id := COALESCE(NEW.entry_id, OLD.entry_id);

      SELECT
        COALESCE(SUM(CASE WHEN direction = 'debit'  THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0)
      INTO v_debit_sum, v_credit_sum
      FROM ledger_postings
      WHERE entry_id = v_entry_id;

      IF v_debit_sum <> v_credit_sum THEN
        RAISE EXCEPTION 'Ledger entry % is unbalanced: debit sum (%) <> credit sum (%)',
          v_entry_id, v_debit_sum, v_credit_sum
          USING ERRCODE = '23514'; -- check_violation
      END IF;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER trg_verify_ledger_postings_balanced
    AFTER INSERT OR UPDATE OR DELETE ON ledger_postings
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION verify_ledger_entry_balanced();
    """)

    # ── 2. Immutability Trigger: Prohibit UPDATE and DELETE on Ledger ──────────
    # Ledger entries and postings are append-only. Corrections must be made via
    # new correcting entries, never by mutating existing rows.
    execute("""
    CREATE OR REPLACE FUNCTION prevent_ledger_mutation()
    RETURNS TRIGGER AS $$
    BEGIN
      RAISE EXCEPTION 'Ledger records are strictly append-only and immutable. UPDATE/DELETE prohibited on %',
        TG_TABLE_NAME
        USING ERRCODE = '55000'; -- object_not_in_prerequisite_state
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_prevent_ledger_entries_mutation
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION prevent_ledger_mutation();
    """)

    execute("""
    CREATE TRIGGER trg_prevent_ledger_postings_mutation
    BEFORE UPDATE OR DELETE ON ledger_postings
    FOR EACH ROW
    EXECUTE FUNCTION prevent_ledger_mutation();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS trg_prevent_ledger_postings_mutation ON ledger_postings;")
    execute("DROP TRIGGER IF EXISTS trg_prevent_ledger_entries_mutation ON ledger_entries;")
    execute("DROP FUNCTION IF EXISTS prevent_ledger_mutation();")

    execute("DROP TRIGGER IF EXISTS trg_verify_ledger_postings_balanced ON ledger_postings;")
    execute("DROP FUNCTION IF EXISTS verify_ledger_entry_balanced();")
  end
end
