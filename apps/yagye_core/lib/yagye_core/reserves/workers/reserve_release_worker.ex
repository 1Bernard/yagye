defmodule YagyeCore.Reserves.Workers.ReserveReleaseWorker do
  @moduledoc false

  use Oban.Worker, queue: :reserves, max_attempts: 3

  alias YagyeCore.Reserves

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Reserves.release_due_holds() do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        {:ok, %{released: count}}

      {:error, {:partial_release, released, failed}} ->
        {:error, "partial release: #{released} released, #{failed} failed"}
    end
  end
end
