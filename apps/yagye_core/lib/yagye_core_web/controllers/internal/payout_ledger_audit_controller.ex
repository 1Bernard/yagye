defmodule YagyeCoreWeb.Controllers.Internal.PayoutLedgerAuditController do
  @moduledoc """
  Internal endpoint for ops: paid payouts missing a payout_completed ledger entry.
  """

  use YagyeCoreWeb, :controller

  alias YagyeCore.Payouts

  action_fallback YagyeCoreWeb.FallbackController

  def index(conn, params) do
    opts = [
      mode: params["mode"],
      limit: String.to_integer(params["limit"] || "100")
    ]

    gaps = Payouts.list_ledger_gaps(opts)

    json(conn, %{
      data: Enum.map(gaps, &serialize/1),
      count: length(gaps)
    })
  end

  defp serialize(payout) do
    %{
      id: payout.public_id,
      payout_code: payout.public_id,
      merchant_id: payout.merchant_id,
      amount: payout.amount,
      currency: payout.currency,
      mode: payout.mode,
      state: payout.state,
      destination_type: payout.destination_type,
      provider_reference: payout.provider_reference,
      completed_at: payout.completed_at && DateTime.to_iso8601(payout.completed_at),
      inserted_at: payout.inserted_at && DateTime.to_iso8601(payout.inserted_at)
    }
  end
end
