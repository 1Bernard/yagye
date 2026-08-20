defmodule YagyeCore.Compliance do
  @moduledoc false

  alias YagyeCore.Compliance.Commands.{
    DispositionScreeningHit,
    SubmitBeneficialOwner,
    SubmitKybDocument,
    SubmitOnboardingDetails
  }

  alias YagyeCore.Compliance.Events.{
    BeneficialOwnerAdded,
    KybDocumentUploaded,
    OnboardingDetailsSubmitted,
    ScreeningHitDispositioned,
    ScreeningHitRaised
  }

  alias YagyeCore.Compliance.Schemas.{BeneficialOwner, KybDocument, ScreeningHit}
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def submit_onboarding(merchant_id, attrs) do
    dispatch(%SubmitOnboardingDetails{
      merchant_id: merchant_id,
      business_type: Map.get(attrs, :business_type, attrs["business_type"]),
      website_url: Map.get(attrs, :website_url, attrs["website_url"]),
      expected_monthly_volume_minor:
        Map.get(
          attrs,
          :expected_monthly_volume_minor,
          attrs["expected_monthly_volume_minor"]
        ),
      expected_monthly_volume_currency:
        Map.get(
          attrs,
          :expected_monthly_volume_currency,
          attrs["expected_monthly_volume_currency"]
        )
    })
  end

  def add_beneficial_owner(merchant_id, attrs) do
    dispatch(%SubmitBeneficialOwner{
      merchant_id: merchant_id,
      subject_ref: Map.get(attrs, :subject_ref, attrs["subject_ref"]),
      role: Map.get(attrs, :role, attrs["role"]),
      ownership_bps: Map.get(attrs, :ownership_bps, attrs["ownership_bps"])
    })
  end

  def upload_document(merchant_id, attrs) do
    dispatch(%SubmitKybDocument{
      merchant_id: merchant_id,
      kind: Map.get(attrs, :kind, attrs["kind"]),
      s3_key: Map.get(attrs, :s3_key, attrs["s3_key"]),
      checksum: Map.get(attrs, :checksum, attrs["checksum"]),
      uploaded_by: Map.get(attrs, :uploaded_by, attrs["uploaded_by"])
    })
  end

  def disposition_hit(screening_hit_id, attrs) do
    dispatch(%DispositionScreeningHit{
      screening_hit_id: screening_hit_id,
      merchant_id: Map.get(attrs, :merchant_id, attrs["merchant_id"]),
      status: Map.get(attrs, :status, attrs["status"]),
      disposition_reason: Map.get(attrs, :disposition_reason, attrs["disposition_reason"]),
      dispositioned_by: Map.get(attrs, :dispositioned_by, attrs["dispositioned_by"])
    })
  end

  # Internal — used by compliance tooling, not the merchant-facing API.
  def raise_screening_hit(attrs) do
    hit =
      %ScreeningHit{}
      |> ScreeningHit.changeset(attrs)

    Repo.transaction(fn ->
      case Repo.insert(hit) do
        {:ok, hit} ->
          event = %ScreeningHitRaised{
            screening_hit_id: hit.id,
            merchant_id: hit.merchant_id,
            subject_type: hit.subject_type,
            subject_id: hit.subject_id,
            list_type: hit.list_type,
            list_source: hit.list_source,
            matched_name: hit.matched_name,
            match_score: hit.match_score,
            occurred_at: DateTime.utc_now()
          }

          # P7: outbox
          {hit, event}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # ── Dispatch ─────────────────────────────────────────────────────────────────

  defp dispatch(%SubmitOnboardingDetails{} = cmd) do
    onboarding_meta = %{
      business_type: cmd.business_type,
      website_url: cmd.website_url,
      expected_monthly_volume_minor: cmd.expected_monthly_volume_minor,
      expected_monthly_volume_currency: cmd.expected_monthly_volume_currency
    }

    Repo.transaction(fn ->
      with {:ok, merchant} <- fetch_submittable(cmd.merchant_id),
           merged_meta = Map.merge(merchant.metadata || %{}, %{onboarding: onboarding_meta}),
           {:ok, merchant} <-
             merchant
             |> Ecto.Changeset.change(
               onboarding_state: "details_submitted",
               metadata: merged_meta
             )
             |> Repo.update() do
        event = %OnboardingDetailsSubmitted{
          merchant_id: merchant.id,
          business_type: cmd.business_type,
          website_url: cmd.website_url,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {merchant, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%SubmitBeneficialOwner{} = cmd) do
    Repo.transaction(fn ->
      with {:ok, merchant} <- resolve_merchant(cmd.merchant_id),
           attrs = %{
             merchant_id: merchant.id,
             subject_ref: cmd.subject_ref,
             role: cmd.role,
             ownership_bps: cmd.ownership_bps
           },
           {:ok, owner} <- %BeneficialOwner{} |> BeneficialOwner.changeset(attrs) |> Repo.insert() do
        event = %BeneficialOwnerAdded{
          beneficial_owner_id: owner.id,
          merchant_id: owner.merchant_id,
          subject_ref: owner.subject_ref,
          role: owner.role,
          ownership_bps: owner.ownership_bps,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {owner, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%SubmitKybDocument{} = cmd) do
    Repo.transaction(fn ->
      with {:ok, merchant} <- resolve_merchant(cmd.merchant_id),
           attrs = %{
             merchant_id: merchant.id,
             kind: cmd.kind,
             s3_key: cmd.s3_key,
             checksum: cmd.checksum,
             uploaded_by: cmd.uploaded_by
           },
           {:ok, doc} <- %KybDocument{} |> KybDocument.changeset(attrs) |> Repo.insert() do
        event = %KybDocumentUploaded{
          document_id: doc.id,
          merchant_id: doc.merchant_id,
          kind: doc.kind,
          s3_key: doc.s3_key,
          uploaded_by: doc.uploaded_by,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {doc, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%DispositionScreeningHit{} = cmd) do
    Repo.transaction(fn ->
      with {:ok, hit} <- fetch_open_hit(cmd.screening_hit_id, cmd.merchant_id),
           {:ok, hit} <-
             hit
             |> ScreeningHit.disposition_changeset(%{
               status: cmd.status,
               disposition_reason: cmd.disposition_reason,
               dispositioned_by: cmd.dispositioned_by,
               dispositioned_at: DateTime.utc_now()
             })
             |> Repo.update() do
        event = %ScreeningHitDispositioned{
          screening_hit_id: hit.id,
          merchant_id: hit.merchant_id,
          status: hit.status,
          disposition_reason: hit.disposition_reason,
          dispositioned_by: hit.dispositioned_by,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {hit, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp fetch_submittable(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      %Merchant{onboarding_state: state} = m when state in ["registered", "details_submitted"] ->
        {:ok, m}

      %Merchant{} ->
        {:error, :invalid_onboarding_state}

      nil ->
        {:error, :not_found}
    end
  end

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp fetch_open_hit(hit_id, merchant_id) do
    case Repo.get_by(ScreeningHit, id: hit_id, merchant_id: merchant_id, status: "open") do
      nil -> {:error, :not_found}
      hit -> {:ok, hit}
    end
  end
end
