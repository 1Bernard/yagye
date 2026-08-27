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

  def beneficial_owners_list_data(owners) do
    %{
      object: "list",
      data: Enum.map(owners, &beneficial_owner_data/1),
      count: length(owners)
    }
  end

  def document_data(%KybDocument{} = d) do
    %{
      id: d.id,
      object: "kyb_document",
      merchant_id: d.merchant_id,
      kind: d.kind,
      checksum: d.checksum,
      scanned_at: d.scanned_at,
      inserted_at: d.inserted_at
    }
  end

  def documents_list_data(docs) do
    %{
      object: "list",
      data: Enum.map(docs, &document_data/1),
      count: length(docs)
    }
  end

  def screening_status_data(%{subjects: subjects, open_hits: open_hits}) do
    %{
      object: "screening_status",
      subjects: Enum.map(subjects, &screening_subject_data/1),
      open_hits: Enum.map(open_hits, &screening_hit_data/1)
    }
  end

  defp screening_subject_data(s) do
    %{
      id: s.id,
      object: "screening_subject",
      subject_type: s.subject_type,
      subject_id: s.subject_id,
      screening_status: s.screening_status,
      enrolled_at: s.enrolled_at,
      last_screened_at: s.last_screened_at,
      next_screening_at: s.next_screening_at,
      screening_frequency_days: s.screening_frequency_days
    }
  end

  defp screening_hit_data(h) do
    %{
      id: h.id,
      object: "screening_hit",
      subject_type: h.subject_type,
      subject_id: h.subject_id,
      list_type: h.list_type,
      list_source: h.list_source,
      matched_name: h.matched_name,
      match_score: h.match_score,
      status: h.status,
      inserted_at: h.inserted_at
    }
  end
end
