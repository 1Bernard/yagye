defmodule YagyeCore.Outbox.Workers.OutboxCleanupWorker do
  @moduledoc false

  use Oban.Worker, queue: :events, max_attempts: 3

  import Ecto.Query

  alias YagyeCore.Repo

  @retention_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days * 86_400, :second)

    {deleted, _} =
      from(m in "outbox_messages",
        where: not is_nil(m.published_at) and m.published_at < ^cutoff
      )
      |> Repo.delete_all()

    {:ok, %{deleted: deleted}}
  end
end
