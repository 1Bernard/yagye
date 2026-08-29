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

    # Transition charge to its terminal state before delivery so that
    # query_charge always reflects the resolved outcome, regardless of
    # whether the webhook reaches yagye_core.
    charge = transition_charge(charge, account, prompt)

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

  # Already transitioned on a prior attempt — return as-is so the notification
  # reuses the auth_code/decline_code that was stored on the first run.
  defp transition_charge(%Charge{state: state} = charge, _account, _prompt)
       when state != "PENDING_AUTH",
       do: charge

  defp transition_charge(charge, account, %WalletPrompt{prompt_state: "APPROVED"}) do
    now = DateTime.utc_now()
    auth_code = ("AUTH" <> :crypto.strong_rand_bytes(4)) |> Base.encode16()
    rrn = ("RRN" <> String.slice(account.id, 0, 8)) |> String.upcase()

    charge
    |> Charge.transition_changeset("AUTHORISED", %{
      auth_code: auth_code,
      rrn: rrn,
      authorised_amount_minor: charge.amount_minor,
      captured_amount_minor: charge.amount_minor,
      authorised_at: now
    })
    |> Repo.update!()
  end

  defp transition_charge(charge, _account, %WalletPrompt{prompt_state: state, decline_code: code}) do
    decline_code =
      case state do
        "DECLINED" -> code || "DECLINED_BY_CUSTOMER"
        "EXPIRED" -> "PROMPT_EXPIRED"
        _ -> "UNKNOWN"
      end

    charge
    |> Charge.transition_changeset("DECLINED", %{decline_code: decline_code})
    |> Repo.update!()
  end

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end
end
