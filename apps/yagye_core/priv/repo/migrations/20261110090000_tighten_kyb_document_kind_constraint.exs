defmodule YagyeCore.Repo.Migrations.TightenKybDocumentKindConstraint do
  use Ecto.Migration

  # Removes redundant document kinds:
  #   - 'incorporation'    → duplicate of 'certificate_of_incorporation'
  #   - 'bank_confirmation'→ redundant; bank_statement proves account exists
  #   - 'utility_bill'    → never surfaced in merchant UI; subsumed by 'proof_of_address'
  #
  # 'proof_of_address' is retained for ops-side compliance recording
  # (utility bill fallback). Merchant-facing UI uses 'bank_statement' for both.

  def up do
    execute("ALTER TABLE kyb_documents DROP CONSTRAINT valid_kind")

    execute("""
    ALTER TABLE kyb_documents
    ADD CONSTRAINT valid_kind CHECK (kind IN (
      'id', 'form_a', 'certificate_of_incorporation', 'business_registration',
      'tax_clearance', 'bank_statement', 'proof_of_address'
    ))
    """)
  end

  def down do
    execute("ALTER TABLE kyb_documents DROP CONSTRAINT valid_kind")

    execute("""
    ALTER TABLE kyb_documents
    ADD CONSTRAINT valid_kind CHECK (kind IN (
      'incorporation', 'id', 'proof_of_address', 'bank_confirmation',
      'form_a', 'certificate_of_incorporation', 'business_registration',
      'tax_clearance', 'utility_bill', 'bank_statement'
    ))
    """)
  end
end
