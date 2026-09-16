import Ecto.Query

alias YagyeCore.Repo
alias YagyeCore.Compliance.Schemas.{BeneficialOwner, KybDocument, ScreeningSubject}
alias YagyeCore.Merchants.Schemas.Merchant

merchant_code = "MCH_DEMO_001"

case Repo.get_by(Merchant, public_id: merchant_code) do
  nil ->
    IO.puts("Merchant #{merchant_code} not found — run core seeds first.")

  m ->
    IO.puts("Seeding compliance data for #{m.public_id} (#{m.legal_name})")

    now  = DateTime.utc_now()
    ago5 = DateTime.add(now, -5 * 86_400, :second)
    ago3 = DateTime.add(now, -3 * 86_400, :second)
    ago2 = DateTime.add(now, -2 * 86_400, :second)
    ago1 = DateTime.add(now, -86_400,     :second)

    # ── Fixed demo UUIDs (so script is idempotent) ──────────────────────────
    pii_ref_1 = "d0000001-0001-7000-8000-000000000001"
    pii_ref_2 = "d0000002-0002-7000-8000-000000000002"
    pii_ref_3 = "d0000003-0003-7000-8000-000000000003"
    pii_refs  = [pii_ref_1, pii_ref_2, pii_ref_3]

    # Idempotent clear (FK order: BOs first, then subjects + vault)
    Repo.delete_all(from(b in BeneficialOwner, where: b.merchant_id == ^m.id))
    Repo.delete_all(from(d in KybDocument,     where: d.merchant_id == ^m.id))
    Repo.delete_all(from(s in ScreeningSubject, where: s.merchant_id == ^m.id))
    Enum.each(pii_refs, fn ref ->
      Ecto.Adapters.SQL.query!(Repo, "DELETE FROM pii_vault WHERE subject_ref = '#{ref}'::uuid", [])
    end)

    # ── 1. PII vault stubs (ciphertext is intentionally fake for dev) ────────
    # In prod these hold KMS-encrypted JSON with the individual's actual PII.
    Enum.each(pii_refs, fn ref ->
      Ecto.Adapters.SQL.query!(Repo, """
        INSERT INTO pii_vault (subject_ref, kms_key_id, ciphertext, subject_kind, inserted_at)
        VALUES ('#{ref}'::uuid, $1, $2, $3, $4)
        ON CONFLICT (subject_ref) DO NOTHING
        """,
        ["dev_kms_key_000", <<0::size(16)-unit(8)>>, "beneficial_owner",
         DateTime.add(now, -5 * 86_400, :second)]
      )
      IO.puts("  pii_vault: #{ref}")
    end)

    # ── 2. Screening subjects (one per UBO) ──────────────────────────────────
    subj_attrs = [
      %{merchant_id: m.id, subject_type: "beneficial_owner",
        subject_id: pii_ref_1, screening_status: "clean",
        enrolled_at: ago5, last_screened_at: ago1},
      %{merchant_id: m.id, subject_type: "beneficial_owner",
        subject_id: pii_ref_2, screening_status: "pending",
        enrolled_at: ago3},
      %{merchant_id: m.id, subject_type: "beneficial_owner",
        subject_id: pii_ref_3, screening_status: "potential_match",
        enrolled_at: ago3}
    ]

    Enum.each(subj_attrs, fn attrs ->
      case %ScreeningSubject{} |> ScreeningSubject.changeset(attrs) |> Repo.insert() do
        {:ok, s}     -> IO.puts("  ScreeningSubject: #{s.screening_status}")
        {:error, cs} -> IO.puts("  ScreeningSubject ERROR: #{inspect(cs.errors)}")
      end
    end)

    # ── 3. Beneficial owners referencing pii_vault.subject_ref ──────────────
    ubo_attrs = [
      %{merchant_id: m.id, subject_ref: pii_ref_1, role: "director",    ownership_bps: 4500},
      %{merchant_id: m.id, subject_ref: pii_ref_2, role: "both", ownership_bps: 3000},
      %{merchant_id: m.id, subject_ref: pii_ref_3, role: "ubo",         ownership_bps: 2500}
    ]

    Enum.each(ubo_attrs, fn attrs ->
      case %BeneficialOwner{} |> BeneficialOwner.changeset(attrs) |> Repo.insert() do
        {:ok, o}     -> IO.puts("  UBO: #{o.role} #{o.ownership_bps}bps")
        {:error, cs} -> IO.puts("  UBO ERROR: #{inspect(cs.errors)}")
      end
    end)

    # ── 4. KYB documents — two scanned, two pending scan ────────────────────
    doc_attrs = [
      %{merchant_id: m.id, kind: "incorporation",    s3_key: "dev/kfb/cert_incorp.pdf",
        checksum: "sha256:aabbcc001122", uploaded_by: "owner@kofibuilds.com",
        scanned_at: ago2},
      %{merchant_id: m.id, kind: "id",               s3_key: "dev/kfb/director_id.pdf",
        checksum: "sha256:ddeeff003344", uploaded_by: "owner@kofibuilds.com",
        scanned_at: ago2},
      %{merchant_id: m.id, kind: "proof_of_address",  s3_key: "dev/kfb/utility_bill.pdf",
        checksum: "sha256:112233445566", uploaded_by: "owner@kofibuilds.com"},
      %{merchant_id: m.id, kind: "bank_confirmation", s3_key: "dev/kfb/bank_letter.pdf",
        checksum: "sha256:778899aabbcc", uploaded_by: "owner@kofibuilds.com"}
    ]

    Enum.each(doc_attrs, fn attrs ->
      case %KybDocument{} |> KybDocument.changeset(attrs) |> Repo.insert() do
        {:ok, d}     -> IO.puts("  Doc: #{d.kind}")
        {:error, cs} -> IO.puts("  Doc ERROR: #{inspect(cs.errors)}")
      end
    end)

    IO.puts("\nDone.")
end
