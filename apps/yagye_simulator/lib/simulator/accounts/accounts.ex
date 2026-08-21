defmodule Simulator.Accounts do
  @moduledoc false

  import Ecto.Query

  alias Simulator.Accounts.Schemas.{Account, ApiKey}
  alias Simulator.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_account(attrs) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  def issue_api_key(account_id, raw_key, label) do
    %ApiKey{}
    |> ApiKey.changeset(%{
      account_id: account_id,
      key_hash: hash_key(raw_key),
      label: label
    })
    |> Repo.insert()
  end

  # Returns {:ok, account} or {:error, :invalid_key}.
  # Preloads default_scenario so OutcomeEngine can use it without an extra query.
  def authenticate(raw_key) do
    hash = hash_key(raw_key)

    result =
      from(k in ApiKey,
        where: k.key_hash == ^hash and k.active == true and is_nil(k.revoked_at),
        join: a in Account,
        on: a.id == k.account_id,
        left_join: s in assoc(a, :default_scenario),
        preload: [account: {a, default_scenario: s}],
        limit: 1
      )
      |> Repo.one()

    case result do
      nil -> {:error, :invalid_key}
      api_key -> {:ok, api_key.account}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp hash_key(raw_key) do
    :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
  end
end
