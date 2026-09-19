defmodule YagyeCoreWeb.Controllers.Internal.ComplianceController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Compliance
  alias YagyeCoreWeb.Controllers.Compliance.ComplianceJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def list_beneficial_owners(conn, %{"merchant_id" => merchant_id}) do
    with {:ok, owners} <- Compliance.list_beneficial_owners(merchant_id) do
      Response.ok(conn, ComplianceJSON.beneficial_owners_list_data(owners))
    end
  end

  def add_beneficial_owner(conn, %{"merchant_id" => merchant_id} = params) do
    attrs = %{
      "subject_ref" => params["subject_ref"],
      "role" => params["role"],
      "ownership_bps" => params["ownership_bps"]
    }

    with {:ok, owner} <- Compliance.add_beneficial_owner(merchant_id, attrs) do
      Response.ok(conn, ComplianceJSON.beneficial_owner_data(owner))
    end
  end

  def list_documents(conn, %{"merchant_id" => merchant_id}) do
    with {:ok, docs} <- Compliance.list_documents(merchant_id) do
      Response.ok(conn, ComplianceJSON.documents_list_data(docs))
    end
  end

  def screening_status(conn, %{"merchant_id" => merchant_id}) do
    with {:ok, status} <- Compliance.screening_status(merchant_id) do
      Response.ok(conn, ComplianceJSON.screening_status_data(status))
    end
  end
end
