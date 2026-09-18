defmodule YagyeCoreWeb.Controllers.Internal.SettlementBatchesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.Settlement
  alias YagyeCoreWeb.Controllers.Settlement.SettlementJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/settlement-batches
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    opts =
      [limit: params["limit"], starting_after: params["starting_after"]]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, page} <- Settlement.list_batches(merchant.id, opts) do
      Response.ok(conn, SettlementJSON.batch_list(page))
    end
  end

  # GET /internal/settlement-batches/:id
  def show(conn, %{"id" => id}) do
    case Settlement.get_batch(id) do
      nil -> {:error, :not_found}
      batch -> Response.ok(conn, SettlementJSON.batch_data(batch))
    end
  end
end
