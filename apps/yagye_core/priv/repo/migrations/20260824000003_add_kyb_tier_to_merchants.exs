defmodule YagyeCore.Repo.Migrations.AddKybTierToMerchants do
  use Ecto.Migration

  def up do
    alter table(:merchants) do
      add :kyb_tier, :integer, null: false, default: 0
      add :reviewed_by, :string
      add :approved_by, :string
    end

    drop constraint(:merchants, :valid_onboarding_state)

    create constraint(:merchants, :valid_onboarding_state,
             check:
               "onboarding_state IN ('registered','basic_info_submitted','documents_submitted','under_review','approved','rejected','more_info_required')"
           )
  end

  def down do
    drop constraint(:merchants, :valid_onboarding_state)

    create constraint(:merchants, :valid_onboarding_state,
             check:
               "onboarding_state IN ('registered','details_submitted','under_review','approved','rejected','more_info_required')"
           )

    alter table(:merchants) do
      remove :kyb_tier
      remove :reviewed_by
      remove :approved_by
    end
  end
end
