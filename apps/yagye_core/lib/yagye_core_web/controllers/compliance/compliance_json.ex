defmodule YagyeCoreWeb.Controllers.Compliance.ComplianceJSON do
  @moduledoc false

  alias YagyeCore.Compliance.Schemas.{BeneficialOwner, KybDocument}

  def onboarding_data(merchant) do
    %{
      id: merchant.public_id,
      object: "merchant",
      onboarding_state: merchant.onboarding_state,
      metadata: merchant.metadata
    }
  end

  def beneficial_owner_data(%BeneficialOwner{} = o) do
    %{
      id: o.id,
      object: "beneficial_owner",
      merchant_id: o.merchant_id,
      subject_ref: o.subject_ref,
      role: o.role,
      ownership_bps: o.ownership_bps,
      inserted_at: o.inserted_at
    }
  end

  def document_data(%KybDocument{} = d) do
    %{
      id: d.id,
      object: "kyb_document",
      merchant_id: d.merchant_id,
      kind: d.kind,
      checksum: d.checksum,
      inserted_at: d.inserted_at
    }
  end
end
