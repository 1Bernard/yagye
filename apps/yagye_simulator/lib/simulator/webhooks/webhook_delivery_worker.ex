defmodule Simulator.Webhooks.WebhookDeliveryWorker do
  @moduledoc false

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  import Ecto.Query

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Charges.Schemas.{Charge, WalletPrompt}
  alias Simulator.Repo
  alias Simulator.Webhooks.Schemas.WebhookNotification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "charge_ref" => charge_ref}}) do
    account = Repo.get!(Account, account_id)
    charge = Repo.get_by!(Charge, charge_ref: charge_ref)
    prompt = Repo.one!(from p in WalletPrompt, where: p.charge_id == ^charge.id, limit: 1)

    notification = WebhookNotification.build(charge, prompt)
    payload = Jason.encode!(notification)
    signature = sign(payload, account.webhook_secret)

    case Req.post(account.webhook_url,
           body: payload,
           headers: [
             {"content-type", "application/json"},
             {"x-webhook-signature", "sha256=#{signature}"},
             {"x-webhook-event-id", notification.event_id}
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, "unexpected status #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end
end
