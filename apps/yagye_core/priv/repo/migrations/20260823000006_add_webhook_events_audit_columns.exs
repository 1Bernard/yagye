defmodule YagyeCore.Repo.Migrations.AddWebhookEventsAuditColumns do
  use Ecto.Migration

  def change do
    alter table(:webhook_events) do
      # PSP/orchestration compliance: stamp signature verification result at ingestion
      # even though the controller rejects invalid ones before DB insert. Auditors and
      # forensics need to see the verification result in the inbox, not just infer it
      # from "the row exists". Defaults true — every row inserted today was verified.
      add :signature_valid, :boolean, null: false, default: true

      # Orchestration-layer retry tracking: incremented each time the provider retries
      # delivery of this event_id. Feeds stuck-event detection
      # (state = pending AND attempt_count > N) and rate-limiting of aggressive providers.
      add :attempt_count, :integer, null: false, default: 1
    end
  end
end
