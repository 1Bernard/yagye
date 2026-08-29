defmodule YagyeCore.Repo.Migrations.RenameApiRequestsCorrelationIdToTraceId do
  use Ecto.Migration

  def change do
    # Drop the never-populated nullable trace_id column first so we can
    # rename correlation_id (the actual HTTP request ID) into its place.
    drop index(:api_requests, [:correlation_id])
    drop_if_exists index(:api_requests, [:trace_id])
    alter table(:api_requests), do: remove(:trace_id, :text)
    rename table(:api_requests), :correlation_id, to: :trace_id
    create index(:api_requests, [:trace_id])
  end
end
