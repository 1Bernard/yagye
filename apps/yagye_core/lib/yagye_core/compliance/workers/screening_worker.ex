defmodule YagyeCore.Compliance.Workers.ScreeningWorker do
  @moduledoc false
  use Oban.Worker, queue: :compliance, max_attempts: 5

  alias YagyeCore.Compliance.Adapters.StubScreeningAdapter
  alias YagyeCore.Compliance.Schemas.{ScreeningRequest, ScreeningSubject}
  alias YagyeCore.Repo

  @stub_lists ~w[pep sanctions_ofac sanctions_eu sanctions_un sanctions_uk_hmt]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id}}) do
    subject = Repo.get!(ScreeningSubject, subject_id)

    if subject.screening_status in ["confirmed_match_blocked", "suspended"] do
      :ok
    else
      run_screening(subject)
    end
  end

  defp run_screening(subject) do
    request_attrs = %{
      subject_id: subject.id,
      provider_code: "stub",
      trigger: "onboarding",
      lists_checked: @stub_lists,
      status: "pending"
    }

    with {:ok, request} <-
           %ScreeningRequest{}
           |> ScreeningRequest.changeset(request_attrs)
           |> Repo.insert(),
         {:ok, result} <- StubScreeningAdapter.screen(subject) do
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
      {:error, reason} ->
        {:error, reason}
    end
  end
end
