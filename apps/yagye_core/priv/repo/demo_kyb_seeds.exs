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
      %{merchant_id: m.id, subject_ref: pii_ref_1, role: "director", ownership_bps: 4500,
        subject_name: "Kofi Agyeman",  subject_dob: "1978-03-12"},
      %{merchant_id: m.id, subject_ref: pii_ref_2, role: "both",     ownership_bps: 3000,
        subject_name: "Abena Mensah",  subject_dob: "1985-07-24"},
      %{merchant_id: m.id, subject_ref: pii_ref_3, role: "ubo",      ownership_bps: 2500,
        subject_name: "Kwame Owusu",   subject_dob: "1990-11-05"}
    ]

    Enum.each(ubo_attrs, fn attrs ->
      case %BeneficialOwner{} |> BeneficialOwner.changeset(attrs) |> Repo.insert() do
        {:ok, o}     -> IO.puts("  UBO: #{o.role} #{o.ownership_bps}bps")
        {:error, cs} -> IO.puts("  UBO ERROR: #{inspect(cs.errors)}")
      end
    end)

    # ── 4. KYB documents — uploaded to Floci S3 with real presigned keys ─────
    # Each document is inserted first (to get its generated ID), then a
    # placeholder PDF stub is PUT to Floci at the canonical S3 key, and the
    # record is updated to status=uploaded with a real SHA-256 checksum.
    # The stub content is a valid but minimal PDF (10 bytes is enough for a dev demo).
    placeholder_pdf = """
    %PDF-1.4
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
    3 0 obj<</Type/Page/MediaBox[0 0 612 792]>>endobj
    xref
    0 4
    0000000000 65535 f
    trailer<</Size 4/Root 1 0 R>>
    startxref
    9
    %%EOF
    """

    placeholder_checksum = :crypto.hash(:sha256, placeholder_pdf) |> Base.encode16(case: :lower)

    doc_attrs = [
      %{kind: "incorporation",       label: "Certificate of Incorporation", scanned_at: ago2},
      %{kind: "id",                  label: "Director ID",                  scanned_at: ago2},
      %{kind: "proof_of_address",    label: "Utility Bill"},
      %{kind: "bank_confirmation",   label: "Bank Confirmation Letter"}
    ]

    Enum.each(doc_attrs, fn attrs ->
      # Insert with pending_upload to get the generated UUID
      base_attrs = Map.merge(attrs, %{
        merchant_id:  m.id,
        s3_key:       "pending",
        checksum:     "pending",
        uploaded_by:  "seed:demo",
        status:       "pending_upload"
      })

      case %KybDocument{} |> KybDocument.changeset(base_attrs) |> Repo.insert() do
        {:error, cs} ->
          IO.puts("  Doc ERROR (#{attrs.kind}): #{inspect(cs.errors)}")

        {:ok, doc} ->
          # Build the canonical S3 key now that we have the doc ID
          s3_key = "kyb/#{m.id}/#{doc.kind}/#{doc.id}"

          # Upload the placeholder PDF to Floci
          upload_result =
            ExAws.S3.put_object(
              Application.get_env(:yagye_core, :document_store, [])
              |> Keyword.get(:bucket, "yagye-kyb-documents"),
              s3_key,
              placeholder_pdf,
              content_type: "application/pdf"
            )
            |> ExAws.request()

          case upload_result do
            {:ok, _} ->
              # Update to uploaded status with the real key and checksum
              doc
              |> KybDocument.upload_changeset(%{
                s3_key:   s3_key,
                checksum: placeholder_checksum,
                status:   "uploaded"
              })
              |> Repo.update!()

              IO.puts("  Doc: #{doc.kind} → #{s3_key}")

            {:error, reason} ->
              IO.puts("  Doc S3 ERROR (#{attrs.kind}): #{inspect(reason)} — keeping pending_upload")
          end
      end
    end)

    IO.puts("\nDone.")
end
