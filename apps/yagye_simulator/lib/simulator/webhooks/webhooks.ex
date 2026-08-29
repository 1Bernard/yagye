defmodule Simulator.Webhooks do
  @moduledoc false

  alias Simulator.Webhooks.WebhookDeliveryWorker

  def enqueue_delivery(account_id, charge_ref, opts \\ []) do
    %{account_id: account_id, charge_ref: charge_ref}
    |> WebhookDeliveryWorker.new(opts)
    |> Oban.insert()
  end
end
