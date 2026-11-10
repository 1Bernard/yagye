defmodule YagyeCore.Repo.Migrations.SeedMccFromPaymentLinkBranding do
  use Ecto.Migration

  # One-time backfill: populate merchant_checkout_configs brand_colour / logo_url
  # from legacy payment_links.checkout_layout JSONB for merchants who had branding
  # stored per-link before the MCC-first refactor.
  #
  # - For merchants with no MCC row: inserts one seeded from their most-recently-
  #   updated link that carries branding.
  # - For merchants with an existing MCC row: fills only NULL/empty brand_colour
  #   and logo_url; never overwrites values already set.
  # - display_name on new rows falls back to 'Merchant' if no business_name in link.
  #
  # Safe to re-run (ON CONFLICT DO UPDATE with COALESCE guards).

  def up do
    execute("""
    INSERT INTO merchant_checkout_configs
      (merchant_id, display_name, brand_colour, logo_url, updated_at)
    SELECT DISTINCT ON (pl.merchant_id)
      pl.merchant_id,
      COALESCE(NULLIF(TRIM(pl.checkout_layout->>'business_name'), ''), 'Merchant'),
      NULLIF(TRIM(pl.checkout_layout->>'brand_color'), ''),
      NULLIF(TRIM(pl.checkout_layout->>'logo_url'), ''),
      NOW()
    FROM payment_links pl
    WHERE pl.checkout_layout IS NOT NULL
      AND (
        NULLIF(TRIM(pl.checkout_layout->>'brand_color'), '') IS NOT NULL
        OR NULLIF(TRIM(pl.checkout_layout->>'logo_url'), '') IS NOT NULL
        OR NULLIF(TRIM(pl.checkout_layout->>'business_name'), '') IS NOT NULL
      )
    ORDER BY pl.merchant_id, pl.updated_at DESC
    ON CONFLICT (merchant_id) DO UPDATE SET
      brand_colour = COALESCE(
        NULLIF(merchant_checkout_configs.brand_colour, ''),
        EXCLUDED.brand_colour
      ),
      logo_url = COALESCE(
        NULLIF(merchant_checkout_configs.logo_url, ''),
        EXCLUDED.logo_url
      ),
      updated_at = NOW()
    WHERE EXCLUDED.brand_colour IS NOT NULL OR EXCLUDED.logo_url IS NOT NULL
    """)
  end

  def down, do: :ok
end
