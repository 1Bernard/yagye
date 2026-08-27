defmodule YagyeCore.Compliance.Workers.ScreeningWorkerTest do
  use YagyeCore.DataCase, async: true

  import Ecto.Query

  alias YagyeCore.Compliance
  alias YagyeCore.Compliance.Schemas.{ScreeningProvider, ScreeningRequest, ScreeningSubject}
  alias YagyeCore.Compliance.Workers.ScreeningWorker
  alias YagyeCore.Fixtures
  alias YagyeCore.Repo

  setup do
    merchant = Fixtures.merchant_fixture()
    subject_ref = Fixtures.pii_vault_fixture()

    {:ok, owner} =
      Compliance.add_beneficial_owner(merchant.public_id, %{
        subject_ref: subject_ref,
        role: "ubo",
        ownership_bps: 5000
      })

    subject =
      Repo.get_by!(ScreeningSubject, subject_type: "beneficial_owner", subject_id: owner.id)

    %{merchant: merchant, owner: owner, subject: subject}
  end

  describe "perform/1 — stub provider" do
    test "resolves provider from DB and marks subject clean", %{subject: subject} do
      assert :ok = perform_job(ScreeningWorker, %{subject_id: subject.id})

      updated = Repo.get!(ScreeningSubject, subject.id)
      assert updated.screening_status == "clean"
      assert updated.last_screened_at != nil
      assert updated.next_screening_at != nil
    end

    test "creates an immutable screening_request audit row", %{subject: subject} do
      assert :ok = perform_job(ScreeningWorker, %{subject_id: subject.id})

      request =
        Repo.one(from r in ScreeningRequest, where: r.subject_id == ^subject.id)

      assert request != nil
      assert request.provider_code == "stub"
      assert request.trigger == "onboarding"
      assert request.status == "completed"
      assert request.search_ref =~ "stub-"

      assert request.lists_checked ==
               ~w[pep sanctions_ofac sanctions_eu sanctions_un sanctions_uk_hmt]
    end

    test "is a no-op when subject is confirmed_match_blocked", %{subject: subject} do
      subject
      |> ScreeningSubject.update_changeset(%{screening_status: "confirmed_match_blocked"})
      |> Repo.update!()

      assert :ok = perform_job(ScreeningWorker, %{subject_id: subject.id})

      # Status must not change
      updated = Repo.get!(ScreeningSubject, subject.id)
      assert updated.screening_status == "confirmed_match_blocked"

      assert Repo.aggregate(
               from(r in ScreeningRequest, where: r.subject_id == ^subject.id),
               :count
             ) == 0
    end

    test "returns error when no active provider exists", %{subject: subject} do
      Repo.update_all(ScreeningProvider, set: [active: false])

      assert {:error, :no_active_screening_provider} =
               perform_job(ScreeningWorker, %{subject_id: subject.id})
    end

    test "returns error when adapter_module is not a known atom", %{subject: subject} do
      Repo.update_all(ScreeningProvider,
        set: [adapter_module: "Elixir.NonExistent.Adapter"]
      )

      assert {:error, {:unknown_adapter_module, "Elixir.NonExistent.Adapter"}} =
               perform_job(ScreeningWorker, %{subject_id: subject.id})
    end
  end
end
