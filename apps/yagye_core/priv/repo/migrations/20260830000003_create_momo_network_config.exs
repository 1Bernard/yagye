defmodule YagyeCore.Repo.Migrations.CreateMomoNetworkConfig do
  use Ecto.Migration

  def change do
    # ── momo_network_config ────────────────────────────────────────────────────
    # Static configuration per mobile money network.
    # PK is network name (text), not UUID — one row per network, never re-keyed.
    create table(:momo_network_config, primary_key: false) do
      add :network, :text, primary_key: true, null: false
      add :display_name, :text, null: false
      # NOT authoritative — number portability means a prefix doesn't determine network
      add :msisdn_prefixes, {:array, :text}, null: false
      add :prompt_timeout_seconds, :integer, null: false
      # primary|advisory — advisory means polling is the main path, callback is optimisation
      add :callback_reliability, :text, null: false
      add :poll_interval_seconds, :integer, null: false
      add :supports_name_enquiry, :boolean, null: false, default: false
      add :supports_reversal, :boolean, null: false, default: false
      # decline from CUSTOMER KYC tier; nothing to do with merchant
      add :customer_daily_limit, :bigint
    end

    create constraint(:momo_network_config, :valid_callback_reliability,
             check: "callback_reliability IN ('primary','advisory')"
           )

    create constraint(:momo_network_config, :positive_prompt_timeout,
             check: "prompt_timeout_seconds > 0"
           )

    create constraint(:momo_network_config, :positive_poll_interval,
             check: "poll_interval_seconds > 0"
           )

    # Seed the three West African networks present in the simulator
    execute(
      """
      INSERT INTO momo_network_config
        (network, display_name, msisdn_prefixes, prompt_timeout_seconds,
         callback_reliability, poll_interval_seconds, supports_name_enquiry, supports_reversal)
      VALUES
        ('MTN', 'MTN Mobile Money', ARRAY['024','054','055','059'],
         90, 'primary', 10, true, true),
        ('VODAFONE', 'Vodafone Cash', ARRAY['020','050'],
         120, 'advisory', 15, false, false),
        ('AIRTELTIGO', 'AirtelTigo Money', ARRAY['026','027','056','057'],
         90, 'primary', 10, false, true)
      ON CONFLICT (network) DO NOTHING
      """,
      "DELETE FROM momo_network_config WHERE network IN ('MTN','VODAFONE','AIRTELTIGO')"
    )
  end
end
