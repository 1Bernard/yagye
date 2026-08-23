defmodule YagyeCore.Repo.Migrations.AddTraceIdToPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :trace_id, :string,
        comment:
          "OTel W3C trace-id at the moment of recording — ephemeral, the trace expires but this row does not"
    end
  end
end
