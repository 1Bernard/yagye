defmodule YagyeCore.Reserves.Workers.AutoActivateReserveWorker do
  @moduledoc false

  require Logger

  use Oban.Worker, queue: :reserves, max_attempts: 3

  alias YagyeCore.Reserves

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Reserves.pending_auto_activations()
    |> Enum.each(fn reserve ->
      case Reserves.auto_activate_policy(reserve) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to auto-activate reserve #{reserve.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
