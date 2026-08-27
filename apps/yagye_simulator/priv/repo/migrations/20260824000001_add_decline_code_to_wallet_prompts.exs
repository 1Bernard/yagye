defmodule Simulator.Repo.Migrations.AddDeclineCodeToWalletPrompts do
  use Ecto.Migration

  def change do
    alter table(:gw_wallet_prompts) do
      add :decline_code, :string
    end
  end
end
