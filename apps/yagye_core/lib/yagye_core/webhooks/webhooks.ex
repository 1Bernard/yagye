defmodule YagyeCore.Webhooks do
  @moduledoc false

  alias Ecto.Changeset
  alias YagyeCore.Repo
  alias YagyeCore.Webhooks.Schemas.WebhookEvent
  alias YagyeCore.Webhooks.Workers.WebhookProcessorWorker

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Receives and persists an inbound webhook. Idempotent on (provider_code, event_id).

  On first receipt: inserts a pending WebhookEvent and enqueues a
  WebhookProcessorWorker in the same transaction so delivery is atomic.

  On duplicate receipt: returns {:error, :already_received}.
  """
  def receive_webhook(provider_code, event_id, event_type, raw_body, opts \\ []) do
    changeset =
      WebhookEvent.changeset(%WebhookEvent{}, %{
        provider_code: provider_code,
        event_id: event_id,
        event_type: event_type,
        raw_body: raw_body,
        signature_valid: Keyword.get(opts, :signature_valid, true),
        attempt_count: Keyword.get(opts, :attempt_count, 1)
      })

    Repo.transaction(fn -> insert_and_enqueue(changeset) end)
    |> case do
      {:ok, webhook} -> {:ok, webhook}
      {:error, :already_received} -> {:error, :already_received}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_and_enqueue(changeset) do
    case Repo.insert(changeset) do
      {:ok, webhook} ->
        WebhookProcessorWorker.new(%{webhook_event_id: webhook.id}) |> Oban.insert!()
        webhook

      {:error, %Changeset{} = cs} ->
        Repo.rollback(rollback_reason(cs))
    end
  end

  defp rollback_reason(cs) do
    if unique_conflict?(cs), do: :already_received, else: cs
  end

  def mark_processed(%WebhookEvent{} = webhook) do
    webhook
    |> WebhookEvent.changeset(%{state: "processed", processed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def mark_failed(%WebhookEvent{} = webhook, error) do
    webhook
    |> WebhookEvent.changeset(%{state: "failed", error: error})
    |> Repo.update()
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp unique_conflict?(%Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_, opts}} -> opts[:constraint] == :unique end)
  end
end
