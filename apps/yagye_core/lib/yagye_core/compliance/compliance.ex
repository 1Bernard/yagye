defmodule YagyeCore.Compliance do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi

  alias YagyeCore.Compliance.Commands.{
    DispositionScreeningHit,
    SubmitBeneficialOwner,
    SubmitKybDocument,
    SubmitOnboardingDetails
  }

  alias YagyeCore.Compliance.Schemas.{
    BeneficialOwner,
    KybDocument,
    ScreeningHit,
    ScreeningSubject
  }

  alias YagyeCore.Compliance.Workers.ScreeningWorker
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  # Merchant-facing path: stores business metadata AND transitions onboarding_state to basic_info_submitted.
  # For state-only transitions (ops tooling), use Merchants.submit_basic_info/2 instead.
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

  def list_beneficial_owners(merchant_id) do
    with {:ok, merchant} <- resolve_merchant(merchant_id) do
      owners =
        from(b in BeneficialOwner,
          where: b.merchant_id == ^merchant.id,
          order_by: [asc: b.inserted_at]
        )
        |> Repo.all()

      {:ok, owners}
    end
  end

  def list_documents(merchant_id) do
    with {:ok, merchant} <- resolve_merchant(merchant_id) do
      docs =
        from(d in KybDocument,
          where: d.merchant_id == ^merchant.id,
          order_by: [asc: d.inserted_at]
        )
        |> Repo.all()

      {:ok, docs}
    end
  end

  # Returns the merchant's screening subjects and any open hits across them.
  def screening_status(merchant_id) do
    with {:ok, merchant} <- resolve_merchant(merchant_id) do
      subjects =
        from(s in ScreeningSubject,
          where: s.merchant_id == ^merchant.id,
          order_by: [asc: s.enrolled_at]
        )
        |> Repo.all()

      open_hits =
        from(h in ScreeningHit,
          where: h.merchant_id == ^merchant.id and h.status == "open",
          order_by: [desc: h.inserted_at]
        )
        |> Repo.all()

      {:ok, %{subjects: subjects, open_hits: open_hits}}
    end
  end

  # Internal — used by compliance tooling, not the merchant-facing API.
  def raise_screening_hit(attrs) do
    changeset = ScreeningHit.changeset(%ScreeningHit{}, attrs)

    Multi.new()
    |> Multi.insert(:hit, changeset)
    |> Multi.insert(:outbox, fn %{hit: hit} ->
      Outbox.build_changeset(hit, "compliance.screening_hit_raised", %{
        screening_hit_id: hit.id,
        merchant_id: hit.merchant_id,
        subject_type: hit.subject_type,
        list_type: hit.list_type,
        match_score: hit.match_score
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{hit: hit}} -> {:ok, hit}
      {:error, :hit, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # Returns true when all beneficial owners with ownership >= 25% have a
  # non-pending, non-blocked screening status. Called by Merchants.approve/2.
  def ubo_threshold_cleared?(merchant_id) do
    qualifying_ids =
      from(b in BeneficialOwner,
        where: b.merchant_id == ^merchant_id and b.ownership_bps >= 2500,
        select: b.id
      )
      |> Repo.all()

    if qualifying_ids == [] do
      true
    else
      unscreened_count =
        from(s in ScreeningSubject,
          where:
            s.subject_type == "beneficial_owner" and
              s.subject_id in ^qualifying_ids and
              s.screening_status not in ["clean", "cleared", "confirmed_pep"],
          select: count(s.id)
        )
        |> Repo.one()

      unscreened_count == 0
    end
  end

  # ── Dispatch ─────────────────────────────────────────────────────────────────

  defp dispatch(%SubmitOnboardingDetails{} = cmd) do
    onboarding_meta = %{
      business_type: cmd.business_type,
      website_url: cmd.website_url,
      expected_monthly_volume_minor: cmd.expected_monthly_volume_minor,
      expected_monthly_volume_currency: cmd.expected_monthly_volume_currency
    }

    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      fetch_submittable(cmd.merchant_id)
    end)
    |> Multi.run(:updated, fn _repo, %{merchant: merchant} ->
      merged_meta = Map.merge(merchant.metadata || %{}, %{onboarding: onboarding_meta})

      merchant
      |> Ecto.Changeset.change(onboarding_state: "basic_info_submitted", metadata: merged_meta)
      |> Repo.update()
    end)
    |> Multi.insert(:outbox, fn %{updated: merchant} ->
      Outbox.build_changeset(merchant, "compliance.onboarding_submitted", %{
        merchant_id: merchant.id,
        business_type: cmd.business_type,
        website_url: cmd.website_url
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{updated: merchant}} -> {:ok, merchant}
      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp dispatch(%SubmitBeneficialOwner{} = cmd) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      resolve_merchant(cmd.merchant_id)
    end)
    |> Multi.run(:owner, fn _repo, %{merchant: merchant} ->
      attrs = %{
        merchant_id: merchant.id,
        subject_ref: cmd.subject_ref,
        role: cmd.role,
        ownership_bps: cmd.ownership_bps
      }

      %BeneficialOwner{} |> BeneficialOwner.changeset(attrs) |> Repo.insert()
    end)
    |> Multi.run(:subject, fn _repo, %{merchant: merchant, owner: owner} ->
      attrs = %{
        merchant_id: merchant.id,
        subject_type: "beneficial_owner",
        subject_id: owner.id,
        screening_status: "pending",
        enrolled_at: now,
        next_screening_at: now,
        screening_frequency_days: 365
      }

      %ScreeningSubject{} |> ScreeningSubject.changeset(attrs) |> Repo.insert()
    end)
    |> Multi.insert(:outbox, fn %{owner: owner} ->
      Outbox.build_changeset(owner, "compliance.beneficial_owner_added", %{
        beneficial_owner_id: owner.id,
        merchant_id: owner.merchant_id,
        role: owner.role,
        ownership_bps: owner.ownership_bps
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{owner: owner, subject: subject}} ->
        Oban.insert(ScreeningWorker.new(%{subject_id: subject.id}))
        {:ok, owner}

      {:error, _step, %Ecto.Changeset{} = cs, _} ->
        {:error, cs}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp dispatch(%SubmitKybDocument{} = cmd) do
    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      resolve_merchant(cmd.merchant_id)
    end)
    |> Multi.run(:doc, fn _repo, %{merchant: merchant} ->
      s3_key = cmd.s3_key || "kyb/pending/#{merchant.id}/#{cmd.kind}/#{Uniq.UUID.uuid7()}"

      attrs = %{
        merchant_id: merchant.id,
        kind: cmd.kind,
        s3_key: s3_key,
        checksum: cmd.checksum,
        uploaded_by: cmd.uploaded_by
      }

      %KybDocument{} |> KybDocument.changeset(attrs) |> Repo.insert()
    end)
    |> Multi.insert(:outbox, fn %{doc: doc} ->
      Outbox.build_changeset(doc, "compliance.kyb_document_uploaded", %{
        document_id: doc.id,
        merchant_id: doc.merchant_id,
        kind: doc.kind
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{doc: doc}} -> {:ok, doc}
      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp dispatch(%DispositionScreeningHit{} = cmd) do
    Multi.new()
    |> Multi.run(:hit, fn _repo, _changes ->
      fetch_open_hit(cmd.screening_hit_id, cmd.merchant_id)
    end)
    |> Multi.run(:updated, fn _repo, %{hit: hit} ->
      hit
      |> ScreeningHit.disposition_changeset(%{
        status: cmd.status,
        disposition_reason: cmd.disposition_reason,
        dispositioned_by: cmd.dispositioned_by,
        dispositioned_at: DateTime.utc_now()
      })
      |> Repo.update()
    end)
    |> Multi.insert(:outbox, fn %{updated: hit} ->
      Outbox.build_changeset(hit, "compliance.screening_hit_dispositioned", %{
        screening_hit_id: hit.id,
        merchant_id: hit.merchant_id,
        status: hit.status,
        disposition_reason: hit.disposition_reason
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{updated: hit}} -> {:ok, hit}
      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp fetch_submittable(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      %Merchant{onboarding_state: state} = m
      when state in ["registered", "basic_info_submitted"] ->
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
