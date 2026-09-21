defmodule YagyeCore.Repo.Migrations.ExpandKybDocumentKindConstraint do
  use Ecto.Migration

  def up do
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

  def down do
    execute("ALTER TABLE kyb_documents DROP CONSTRAINT valid_kind")

    execute("""
    ALTER TABLE kyb_documents
    ADD CONSTRAINT valid_kind CHECK (kind IN (
      'incorporation', 'id', 'proof_of_address', 'bank_confirmation'
    ))
    """)
  end
end
