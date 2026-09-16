defmodule Simulator.Disbursements do
  @moduledoc """
  Creates and manages disbursements for the simulator.

  In simulation mode all disbursements settle immediately — `create_disbursement/2`
  returns a record with state PAID and a `paid_at` timestamp.
  """

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Disbursements.Schemas.Disbursement
  alias Simulator.Repo

  @doc """
  Creates a disbursement for `account` and immediately marks it PAID.

  Returns `{:ok, %Disbursement{}}`.
  """
  def create_disbursement(%Account{} = account, attrs) do
    now = DateTime.utc_now()
    ref = "DISB_" <> Uniq.UUID.uuid7()

    %Disbursement{}
    |> Disbursement.changeset(
      Map.merge(attrs, %{
        account_id: account.id,
        disbursement_ref: ref,
        state: "PAID",
        paid_at: now
      })
    )
    |> Repo.insert()
  end
end
