class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      # user_id is nullable — the log must survive anonymisation (GDPR erasure
      # replaces email/name but we keep the FK null rather than hard-delete)
      t.references :user, type: :uuid, foreign_key: true, null: true, index: true

      # denormalised — survives user anonymisation; matches users.email at write time
      t.text :user_code, null: false

      t.text :merchant_code  # null for internal-staff actions with no merchant context

      # dot-namespaced action key: "payments.refund_requested",
      # "kyb.disposition_approved", "team.user_invited"
      t.text :action, null: false

      t.text :resource_type, null: false
      t.text :resource_code  # the PK / code of the affected record (nullable for list actions)

      # ALL THREE outcomes are logged — a failed attempt is as important as a success
      t.text :outcome, null: false  # attempted | succeeded | failed

      t.text :reason  # rejection reasons, suspension reasons, etc.

      # Joins this row to yagye_core payment_events and the OTel distributed trace.
      # Populated from X-Request-ID / traceparent header via CorrelationId middleware.
      t.text :correlation_id, null: false, default: ""

      t.text :ip
      t.text :user_agent_hash  # SHA-256 of User-Agent; not stored raw (PII)

      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false, precision: 6
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :merchant_code
    add_index :audit_logs, :correlation_id
    add_index :audit_logs, :created_at
  end
end
