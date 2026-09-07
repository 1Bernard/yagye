defmodule YagyeCore.Repo.Migrations.CreateP16CheckoutTables do
  use Ecto.Migration

  def change do
    # 1. payment_links
    create table(:payment_links, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :url_slug, :text, null: false
      add :kind, :text, null: false
      add :amount, :bigint
      add :currency, :string, size: 3, null: false
      add :description, :text, null: false
      add :image_url, :text
      add :allowed_methods, {:array, :text}, null: false, default: []
      add :collect_email, :boolean, null: false, default: false
      add :collect_phone, :boolean, null: false, default: false
      add :collect_name, :boolean, null: false, default: false
      add :reusable, :boolean, null: false, default: true
      add :max_uses, :integer
      add :use_count, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
      add :expires_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:payment_links, [:public_id])
    create unique_index(:payment_links, [:url_slug])
    create index(:payment_links, [:merchant_id, :mode, :active])

    # 2. checkout_templates
    create table(:checkout_templates, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :name, :text, null: false
      add :status, :text, null: false, default: "draft"
      add :theme, :map, null: false, default: %{}
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:checkout_templates, [:public_id])
    create index(:checkout_templates, [:merchant_id, :mode])

    create unique_index(:checkout_templates, [:merchant_id, :mode],
             where: "status = 'published'",
             name: :checkout_templates_one_published_per_merchant_mode
           )

    # 3. merchant_checkout_configs (PK = merchant_id, 1-1 with merchants)
    create table(:merchant_checkout_configs, primary_key: false) do
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :display_name, :text, null: false
      add :logo_url, :text
      add :brand_colour, :string, size: 7
      add :support_email, :text
      add :support_phone, :text
      add :website_url, :text
      add :terms_url, :text
      add :privacy_url, :text
      add :refund_policy_url, :text
      add :default_locale, :text, null: false, default: "en"
      add :updated_at, :utc_datetime_usec, null: false
    end

    # 4. checkout_sessions
    create table(:checkout_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :url_token_hash, :text, null: false
      add :state, :text, null: false, default: "open"
      add :subtotal_amount, :bigint, null: false
      add :tax_amount, :bigint, null: false, default: 0
      add :shipping_amount, :bigint, null: false, default: 0
      add :discount_amount, :bigint, null: false, default: 0
      add :total_amount, :bigint, null: false
      add :currency, :string, size: 3, null: false
      add :merchant_reference, :text, null: false
      add :description, :text
      add :collect_email, :boolean, null: false, default: false
      add :collect_phone, :boolean, null: false, default: false
      add :collect_name, :boolean, null: false, default: false
      add :customer_subject_ref, :uuid
      add :allowed_methods, {:array, :text}, null: false, default: []
      add :locale, :text, null: false, default: "en"
      add :success_url, :text, null: false
      add :cancel_url, :text, null: false
      add :template_id, references(:checkout_templates, type: :uuid, on_delete: :nilify_all)
      add :payment_link_id, references(:payment_links, type: :uuid, on_delete: :restrict)
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict)
      add :metadata, :map, null: false, default: %{}
      add :expires_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:checkout_sessions, [:public_id])
    create unique_index(:checkout_sessions, [:url_token_hash])
    create index(:checkout_sessions, [:merchant_id, :state])
    create index(:checkout_sessions, [:payment_link_id])
    create index(:checkout_sessions, [:expires_at], where: "state = 'open'")

    # 5. checkout_line_items
    create table(:checkout_line_items, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :session_id, references(:checkout_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false
      add :kind, :text, null: false
      add :description, :text, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_amount, :bigint, null: false
      add :total_amount, :bigint, null: false
      add :image_url, :text
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:checkout_line_items, [:session_id, :position])

    # 6. checkout_events (append-only funnel telemetry — no updated_at)
    create table(:checkout_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :session_id, references(:checkout_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :event_type, :text, null: false
      add :method_selected, :text
      add :payload, :map, null: false, default: %{}
      add :ip_hash, :text
      add :user_agent_hash, :text
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:checkout_events, [:session_id, :occurred_at])

    # 7. checkout_template_components (cascade delete with template)
    create table(:checkout_template_components, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :template_id, references(:checkout_templates, type: :uuid, on_delete: :delete_all),
        null: false

      add :component_type, :text, null: false
      add :position, :integer, null: false
      add :visible, :boolean, null: false, default: true
      add :config, :map, null: false, default: %{}
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:checkout_template_components, [:template_id, :position])

    # 8. payment_captures
    create table(:payment_captures, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false

      add :attempt_id, references(:payment_attempts, type: :uuid, on_delete: :restrict),
        null: false

      add :sequence, :integer, null: false
      add :amount, :bigint, null: false
      add :currency, :string, size: 3, null: false
      add :is_final, :boolean, null: false, default: false
      add :state, :text, null: false, default: "requested"
      add :provider_reference, :text
      add :arn, :text
      add :failure_code, :text
      add :idempotency_token, :text, null: false
      add :captured_at, :utc_datetime_usec
      timestamps(inserted_at: :inserted_at)
    end

    create unique_index(:payment_captures, [:public_id])
    create unique_index(:payment_captures, [:payment_id, :sequence])
    create index(:payment_captures, [:attempt_id])

    # 9. payment_card_details (PK = payment_id, 1-1)
    create table(:payment_card_details, primary_key: false) do
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :brand, :text
      add :last4, :string, size: 4
      add :bin, :string, size: 8
      add :funding, :text
      add :card_category, :text
      add :issuer_name, :text
      add :issuer_country, :string, size: 2
      add :exp_month, :integer
      add :exp_year, :integer
      add :provider_token, :text
      add :network_token_used, :boolean
      add :cardholder_name_subject_ref, :uuid
      add :avs_result, :text
      add :cvv_result, :text
      add :auth_code, :text
      add :rrn, :text
      add :arn, :text
      add :network_transaction_id, :text
      add :initiated_by, :text
      add :stored_credential, :text
      add :mit_type, :text
    end

    # 10. payment_three_ds (PK = payment_id, 1-1)
    create table(:payment_three_ds, primary_key: false) do
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :version, :text
      add :flow, :text
      add :status, :string, size: 1
      add :eci, :string, size: 2
      add :cavv, :text
      add :ds_transaction_id, :text
      add :acs_transaction_id, :text
      add :liability_shift, :boolean
      add :exemption_applied, :text
      add :challenge_started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    # 11. payment_mobile_money_details (PK = payment_id, 1-1)
    create table(:payment_mobile_money_details, primary_key: false) do
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :network, :text, null: false
      add :network_source, :text, null: false
      add :msisdn_subject_ref, :uuid
      add :msisdn_masked, :text, null: false
      add :msisdn_hash, :text, null: false
      add :account_name_returned, :text
      add :name_match_score, :decimal, precision: 4, scale: 3
      add :charge_bearer, :text, null: false
      add :levy_amount, :bigint
      add :prompt_sent_at, :utc_datetime_usec
      add :prompt_expires_at, :utc_datetime_usec
      add :approved_at, :utc_datetime_usec
      add :network_reference, :text
      add :financial_transaction_id, :text
    end

    create index(:payment_mobile_money_details, [:msisdn_hash])

    # 12. payment_bank_transfer_details (PK = payment_id, 1-1)
    create table(:payment_bank_transfer_details, primary_key: false) do
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :virtual_account_number, :text
      add :bank_code, :text
      add :expected_by, :utc_datetime_usec
      add :received_at, :utc_datetime_usec
    end

    # 13. card_declines (PK = attempt_id, 1-1)
    create table(:card_declines, primary_key: false) do
      add :attempt_id, references(:payment_attempts, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :raw_code, :text, null: false
      add :canonical_code, :text, null: false
      add :hardness, :text, null: false
      add :retryable, :boolean, null: false
      add :retry_after, :interval
      add :origin, :text, null: false
      add :customer_message_key, :text, null: false
    end

    # ── Post-table alterations ──────────────────────────────────────────────────

    # Invoice → payment_links FK (deferred from P13 Step 0 until payment_links existed)
    alter table(:invoices) do
      modify :payment_link_id, references(:payment_links, type: :uuid, on_delete: :restrict),
        from: :uuid,
        null: true
    end

    # payment_attempts routing audit columns (routing_configurations landed at P14)
    alter table(:payment_attempts) do
      add :routing_configuration_id,
          references(:routing_configurations, type: :uuid, on_delete: :nilify_all)

      add :routing_node_id, :text
    end
  end
end
