defmodule YagyeCoreWeb.Controllers.Internal.KybController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Compliance
  alias YagyeCore.Merchants
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/kyb-status
  # Returns all KYB-relevant data in one call for portal step-completion checks.
  def show_kyb_status(conn, %{"merchant_code" => code}) do
    case resolve_merchant(code) do
      {:error, :not_found} ->
        Response.not_found(conn)

      {:ok, merchant} ->
        contact = Merchants.get_contact(merchant.id)
        addresses = merchant.id |> Merchants.list_addresses() |> Map.new(&{&1.address_type, &1})
        {:ok, documents} = Compliance.list_documents(code)
        controls = Settlement.get_settlement_controls(merchant.id)
        agreements = Compliance.list_service_agreements(merchant.id)

        Response.ok(conn, %{
          merchant: serialize_merchant(merchant),
          contact: contact && serialize_contact(contact),
          addresses: %{
            "office" => addresses |> Map.get("office") |> then(&(&1 && serialize_address(&1))),
            "registered" =>
              addresses |> Map.get("registered") |> then(&(&1 && serialize_address(&1)))
          },
          documents: Enum.map(documents, &serialize_document/1),
          settlement_controls: controls && serialize_controls(controls),
          service_agreements: Enum.map(agreements, &serialize_agreement/1)
        })
    end
  end

  # PATCH /internal/merchants/:merchant_code/kyb-profile
  def update_kyb_profile(conn, %{"merchant_code" => code} = params) do
    attrs =
      params
      |> Map.take(~w[business_type registration_type category tin])
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Merchants.update_merchant_profile(code, attrs) do
      {:ok, merchant} ->
        Response.ok(conn, %{merchant: serialize_merchant(merchant)})

      {:error, :not_found} ->
        Response.not_found(conn)

      {:error, %Ecto.Changeset{} = cs} ->
        Response.validation_error(conn, cs)
    end
  end

  # PUT /internal/merchants/:merchant_code/contacts
  def upsert_contact(conn, %{"merchant_code" => code} = params) do
    case resolve_merchant(code) do
      {:error, :not_found} ->
        Response.not_found(conn)

      {:ok, merchant} ->
        attrs =
          params
          |> Map.take(~w[general_email support_email disputes_email phone_number
                         whatsapp_number whatsapp_label website_url
                         twitter_handle facebook_username instagram_handle])
          |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

        case Merchants.upsert_contact(merchant.id, attrs) do
          {:ok, contact} -> Response.ok(conn, %{contact: serialize_contact(contact)})
          {:error, %Ecto.Changeset{} = cs} -> Response.validation_error(conn, cs)
        end
    end
  end

  # PUT /internal/merchants/:merchant_code/addresses/:address_type
  def upsert_address(conn, %{"merchant_code" => _code, "address_type" => type} = _params)
      when type not in ~w[office registered] do
    Response.unprocessable(
      conn,
      "invalid_address_type",
      "address_type must be office or registered"
    )
  end

  def upsert_address(conn, %{"merchant_code" => code, "address_type" => type} = params) do
    case resolve_merchant(code) do
      {:error, :not_found} ->
        Response.not_found(conn)

      {:ok, merchant} ->
        attrs =
          params
          |> Map.take(~w[country region city street_address gps_address complex_building])
          |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

        case Merchants.upsert_address(merchant.id, type, attrs) do
          {:ok, address} -> Response.ok(conn, %{address: serialize_address(address)})
          {:error, %Ecto.Changeset{} = cs} -> Response.validation_error(conn, cs)
        end
    end
  end

  # POST /internal/merchants/:merchant_code/documents
  def upload_document(conn, %{"merchant_code" => code} = params) do
    attrs = %{
      kind: params["kind"],
      label: params["label"],
      s3_key: params["s3_key"],
      checksum: params["checksum"],
      uploaded_by: params["uploaded_by"],
      required_for_business_types: params["required_for_business_types"] || []
    }

    case Compliance.upload_document(code, attrs) do
      {:ok, doc} -> Response.ok(conn, %{document: serialize_document(doc)})
      {:error, :not_found} -> Response.not_found(conn)
      {:error, %Ecto.Changeset{} = cs} -> Response.validation_error(conn, cs)
    end
  end

  # POST /internal/merchants/:merchant_code/service-agreements
  def accept_agreement(conn, %{"merchant_code" => code} = params) do
    attrs = %{
      agreement_version: params["agreement_version"],
      signatory_name: params["signatory_name"],
      signatory_email: params["signatory_email"],
      signatory_phone: params["signatory_phone"],
      signatory_job_title: params["signatory_job_title"],
      ip_address: params["ip_address"],
      user_agent: params["user_agent"]
    }

    case Compliance.accept_service_agreement(code, attrs) do
      {:ok, agreement} -> Response.ok(conn, %{service_agreement: serialize_agreement(agreement)})
      {:error, :not_found} -> Response.not_found(conn)
      {:error, %Ecto.Changeset{} = cs} -> Response.validation_error(conn, cs)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp serialize_merchant(m) do
    %{
      public_id: m.public_id,
      legal_name: m.legal_name,
      trading_name: m.trading_name,
      onboarding_state: m.onboarding_state,
      status: m.status,
      kyb_tier: m.kyb_tier,
      business_type: m.business_type,
      registration_type: m.registration_type,
      category: m.category,
      tin: m.tin
    }
  end

  defp serialize_contact(c) do
    %{
      id: c.id,
      general_email: c.general_email,
      support_email: c.support_email,
      disputes_email: c.disputes_email,
      phone_number: c.phone_number,
      whatsapp_number: c.whatsapp_number,
      whatsapp_label: c.whatsapp_label,
      website_url: c.website_url,
      twitter_handle: c.twitter_handle,
      facebook_username: c.facebook_username,
      instagram_handle: c.instagram_handle
    }
  end

  defp serialize_address(a) do
    %{
      id: a.id,
      address_type: a.address_type,
      country: a.country,
      region: a.region,
      city: a.city,
      street_address: a.street_address,
      gps_address: a.gps_address,
      complex_building: a.complex_building
    }
  end

  defp serialize_document(d) do
    %{
      id: d.id,
      kind: d.kind,
      label: d.label,
      status: d.status,
      required_for_business_types: d.required_for_business_types,
      s3_key: d.s3_key,
      uploaded_by: d.uploaded_by,
      reviewer_notes: d.reviewer_notes,
      reviewed_by: d.reviewed_by,
      reviewed_at: d.reviewed_at && DateTime.to_iso8601(d.reviewed_at),
      inserted_at: DateTime.to_iso8601(d.inserted_at)
    }
  end

  defp serialize_controls(c) do
    %{
      approval_threshold: c.approval_threshold,
      settlement_msisdn: c.settlement_msisdn,
      settlement_bank_code: c.settlement_bank_code,
      settlement_account_number: c.settlement_account_number,
      settlement_account_name: c.settlement_account_name
    }
  end

  defp serialize_agreement(a) do
    %{
      id: a.id,
      agreement_version: a.agreement_version,
      accepted_at: DateTime.to_iso8601(a.accepted_at),
      signatory_name: a.signatory_name,
      signatory_email: a.signatory_email,
      signatory_phone: a.signatory_phone,
      signatory_job_title: a.signatory_job_title,
      ip_address: a.ip_address
    }
  end
end
