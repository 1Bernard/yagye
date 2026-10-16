defmodule YagyeCore.Disputes.Workers.DisputeEscalationWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Disputes
  alias YagyeCore.Disputes.Schemas.Dispute
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    overdue =
      Repo.all(
        from d in Dispute,
          where:
            d.stage == "evidence_required" and
              not is_nil(d.evidence_due_at) and
              d.evidence_due_at < ^now
      )

    results =
      Enum.map(overdue, fn dispute ->
        case Disputes.auto_escalate(dispute) do
          {:ok, _} ->
            Logger.info("[DisputeEscalationWorker] escalated dispute #{dispute.public_id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "[DisputeEscalationWorker] failed to escalate dispute #{dispute.public_id}",
              reason: inspect(reason)
            )

            {:error, dispute.public_id, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, {:escalation_errors, length(errors)}}
    end
  end
end
