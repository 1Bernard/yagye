defmodule YagyeCore.Compliance.Workers.ScreeningWorker do
  @moduledoc false
  use Oban.Worker, queue: :compliance, max_attempts: 5

  alias YagyeCore.Compliance.Schemas.{ScreeningProvider, ScreeningRequest, ScreeningSubject}
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id}}) do
    subject = Repo.get!(ScreeningSubject, subject_id)

    if subject.screening_status in ["confirmed_match_blocked", "suspended"] do
      :ok
    else
      with {:ok, provider} <- fetch_active_provider(),
           {:ok, adapter} <- resolve_adapter(provider) do
        run_screening(subject, provider, adapter)
      end
    end
  end

  defp run_screening(subject, provider, adapter) do
    request_attrs = %{
      subject_id: subject.id,
      provider_code: provider.code,
      trigger: "onboarding",
      lists_checked: provider.default_lists,
      status: "pending"
    }

    with {:ok, request} <-
           %ScreeningRequest{}
           |> ScreeningRequest.changeset(request_attrs)
           |> Repo.insert(),
         {:ok, result} <- adapter.screen(subject) do
      request
      |> ScreeningRequest.complete_changeset(%{
        status: "completed",
        search_ref: result.provider_search_ref,
        match_count: result.match_count,
        hit_count: 0,
        completed_at: DateTime.utc_now()
      })
      |> Repo.update!()

      subject
      |> ScreeningSubject.update_changeset(%{
        screening_status: "clean",
        last_screened_at: DateTime.utc_now(),
        next_screening_at: DateTime.add(DateTime.utc_now(), 365, :day)
      })
      |> Repo.update!()

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_active_provider do
    case Repo.get_by(ScreeningProvider, active: true) do
      nil -> {:error, :no_active_screening_provider}
      provider -> {:ok, provider}
    end
  end

  # Provider adapter modules are stored as fully-qualified string names
  # (e.g. "Elixir.YagyeCore.Compliance.Adapters.StubScreeningAdapter").
  # String.to_existing_atom/1 is safe here — all compiled modules are already
  # atoms in the VM at boot time.
  defp resolve_adapter(provider) do
    module = String.to_existing_atom(provider.adapter_module)
    {:ok, module}
  rescue
    ArgumentError ->
      {:error, {:unknown_adapter_module, provider.adapter_module}}
  end
end
