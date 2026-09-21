Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions:  "users/sessions",
    passwords: "users/passwords"
  }

  authenticated :user do
    root "dashboard#index", as: :authenticated_root
    get "dashboard/provider-split", to: "dashboard#provider_split_breakdown", as: :dashboard_provider_split
  end

  devise_scope :user do
    get  "users/otp-challenge", to: "users/sessions#otp_challenge", as: :users_otp_challenge
    post "users/otp-challenge", to: "users/sessions#verify_otp",    as: :users_verify_otp
    root "users/sessions#new"

    # SSO / SAML
    get  "auth/sso/check",    to: "users/sso#check",    as: :sso_check
    get  "auth/sso/initiate", to: "users/sso#initiate", as: :sso_initiate
    post "auth/saml/callback", to: "users/sso#callback", as: :sso_callback
  end

  get  "up" => "rails/health#show", as: :rails_health_check
  get  "locale", to: "locale#set",         as: :locale
  post "portal/mode", to: "portal/mode#update", as: :portal_mode

  # ── Payments domain ──────────────────────────────────────────────────────
  scope module: "payments" do
    get "payments",          to: "transactions#index",  as: :payments
    get "payments/filter",   to: "transactions#filter", as: :filter_payments
    get "payments/:id",      to: "transactions#show",   as: :payment
    get   "disputes",          to: "disputes#index",  as: :disputes
    get   "disputes/filter",   to: "disputes#filter", as: :filter_disputes
    get   "disputes/:id",      to: "disputes#show",   as: :dispute
    patch "disputes/:id",   to: "disputes#update"

    get "customers",        to: "customers#index", as: :customers
    get "customers/:id",    to: "customers#show",  as: :customer

    get "settlement-batches",     to: "settlement_batches#index", as: :settlement_batches
    get "settlement-batches/:id", to: "settlement_batches#show",  as: :settlement_batch

    get "reserves", to: "reserves#index", as: :reserves
  end

  # ── Merchants domain (ops — policy-gated) ────────────────────────────────
  scope module: "merchants" do
    get   "merchants",                              to: "merchants#index",              as: :merchants
    get   "merchants/filter",                       to: "merchants#filter",             as: :filter_merchants
    get   "merchants/:id",                         to: "merchants#show",               as: :merchant
    patch "merchants/:id",                         to: "merchants#update"
    post  "merchants/:id/kyb-approve",             to: "merchants#kyb_approve",        as: :kyb_approve_merchant
    get   "merchants/:id/settlement-controls",     to: "settlement_controls#show",     as: :merchant_settlement_controls
    patch "merchants/:id/settlement-controls",     to: "settlement_controls#update"
  end

  # ── Compliance domain (ops — policy-gated) ───────────────────────────────
  scope module: "compliance" do
    get  "kyb-reviews",               to: "kyb_reviews#index",   as: :kyb_reviews
    get  "kyb-reviews/filter",        to: "kyb_reviews#filter",  as: :filter_kyb_reviews
    get  "kyb-reviews/:id",           to: "kyb_reviews#show",    as: :kyb_review
    post "kyb-reviews/:id/approve",   to: "kyb_reviews#approve", as: :approve_kyb_review
    post "kyb-reviews/:id/reject",    to: "kyb_reviews#reject",  as: :reject_kyb_review
    post "kyb-reviews/:id/assign",    to: "kyb_reviews#assign",  as: :assign_kyb_review
    post "kyb-reviews/:id/add-ubo",   to: "kyb_reviews#add_ubo", as: :add_ubo_kyb_review

    get  "compliance/approvals",          to: "approvals#index",   as: :compliance_approvals
    post "compliance/approvals/:id/approve", to: "approvals#approve", as: :compliance_approve_approval
    post "compliance/approvals/:id/reject",  to: "approvals#reject",  as: :compliance_reject_approval
  end

  # ── Developers domain ────────────────────────────────────────────────────
  scope module: "developers" do
    get "developers",                          to: "api_keys#index",              as: :developers
    get "developers/keys/new",                 to: "api_keys#new",                as: :new_developers_key
    get "developers/webhooks/new",             to: "webhooks#new",                as: :new_developers_webhook
    get "developers/deliveries",               to: "webhook_deliveries#index",    as: :developers_deliveries
    get "developers/deliveries/:id",           to: "webhook_deliveries#show",     as: :developers_delivery
    get "developers/routing-rules",            to: "routing_rules#index",         as: :developers_routing_rules
    get "developers/routing-rules/new",        to: "routing_rules#new",           as: :new_developers_routing_rule
    get "developers/routing-rules/:id/edit",   to: "routing_rules#edit",          as: :edit_developers_routing_rule
  end

  # ── Payments — refund ────────────────────────────────────────────────────
  scope module: "payments" do
    get  "payouts",                          to: "payouts#index",                   as: :payouts
    get  "payouts/filter",                   to: "payouts#filter",                  as: :filter_payouts
    get  "payouts/:id",                     to: "payouts#show",                    as: :payout
    get  "payout-requests",                 to: "payout_requests#index",           as: :payout_requests
    get  "payout-requests/new",             to: "payout_requests#new",             as: :new_payout_request
    post "payout-requests",                 to: "payout_requests#create"
    get  "payout-requests/:id",             to: "payout_requests#show",            as: :payout_request
    post "payout-requests/:id/approve",     to: "payout_requests#approve",         as: :approve_payout_request
    post "payout-requests/:id/reject",      to: "payout_requests#reject",          as: :reject_payout_request
    get  "reconciliation",                                  to: "reconciliation#index",              as: :reconciliation
    get  "reconciliation/filter",                           to: "reconciliation#filter",             as: :filter_reconciliation
    get  "reconciliation/:id",                             to: "reconciliation#show",               as: :reconciliation_break
    post "reconciliation/:id/propose-adjustment",          to: "reconciliation#propose_adjustment", as: :reconciliation_propose_adjustment
    get  "settlements",                            to: "settlements#index",             as: :settlements
    get  "settlements/filter",                     to: "settlements#filter",            as: :filter_settlements
    get  "settlements/:id",                        to: "settlements#show",              as: :settlement
    post "settlements/:id/approve-dispatch",       to: "settlement_dispatches#approve", as: :approve_dispatch_settlement
    post "settlements/:id/reject-dispatch",        to: "settlement_dispatches#reject",  as: :reject_dispatch_settlement
  end

  scope module: "payments" do
    post "payments/:id/refund", to: "transactions#refund", as: :payment_refund
  end

  # ── Developers — write actions ───────────────────────────────────────────
  scope module: "developers" do
    post  "developers/routing-rules",                    to: "routing_rules#create"
    patch "developers/routing-rules/:id",                to: "routing_rules#update",  as: :developers_routing_rule
    post  "developers/routing-rules/:id/publish",        to: "routing_rules#publish", as: :publish_developers_routing_rule
    post   "developers/keys",                    to: "api_keys#create",   as: :developers_keys
    delete "developers/keys/:key_id",            to: "api_keys#destroy",  as: :developers_key
    post   "developers/webhooks",                to: "webhooks#create",   as: :developers_webhooks
    delete "developers/webhooks/:endpoint_id",   to: "webhooks#destroy",  as: :developers_webhook
    post   "developers/webhooks/:endpoint_id/test", to: "webhooks#test",  as: :test_developers_webhook
  end

  # ── Team domain ──────────────────────────────────────────────────────────
  scope module: "team" do
    get  "team",                        to: "users#index",      as: :team
    get  "team/users",                  to: "users#index",      as: :team_users
    get  "team/users/filter",            to: "users#filter",     as: :filter_team_users
    get  "team/users/new",              to: "users#new",        as: :new_team_user
    get  "team/users/:id",              to: "users#show",       as: :team_user
    get  "team/users/:id/edit-roles",   to: "users#edit_roles", as: :edit_roles_team_user
    post "team/users",                  to: "users#create",     as: :team_invite_user
    post "team/users/:id/suspend",      to: "users#suspend",     as: :suspend_team_user
    post "team/users/:id/roles",        to: "users#assign_role", as: :assign_team_user_role
    put  "team/users/:id/roles",        to: "users#set_roles",   as: :set_team_user_roles
    get  "team/role-requests",              to: "role_requests#index",   as: :team_role_requests
    post "team/role-requests/:id/approve", to: "role_requests#approve", as: :approve_team_role_request
    post "team/role-requests/:id/reject",  to: "role_requests#reject",  as: :reject_team_role_request
    get    "team/roles",          to: "roles#index",   as: :team_roles
    get    "team/roles/new",      to: "roles#new",     as: :new_team_role
    post   "team/roles",          to: "roles#create"
    get    "team/roles/:key/edit", to: "roles#edit",   as: :edit_team_role
    patch  "team/roles/:key",     to: "roles#update",  as: :team_role
    delete "team/roles/:key",     to: "roles#destroy"
  end

  # ── Onboarding / KYB self-serve (merchant users only) ───────────────────
  scope module: "onboarding" do
    get   "verify",                    to: "verify#index",             as: :verify
    get   "verify/:step",              to: "verify#show",              as: :verify_step
    patch "verify/profile",            to: "verify#update_profile",    as: :update_kyb_profile
    patch "verify/contact",            to: "verify#update_contact",    as: :update_kyb_contact
    patch "verify/settlement",         to: "verify#update_settlement", as: :update_kyb_settlement
    post  "verify/documents",          to: "verify#upload_document",   as: :upload_kyb_document
    post  "verify/agreement",          to: "verify#submit_agreement",  as: :submit_kyb_agreement
    get   "onboarding/kyb-banner",     to: "verify#banner",            as: :kyb_banner
  end

  # ── Account domain ───────────────────────────────────────────────────────
  scope module: "account" do
    get   "onboarding/kyc",             to: "kyc#index",                as: :kyc_onboarding
    get   "settings",                   to: "settings#index",           as: :settings
    get   "settings/pricing",           to: "pricing#index",            as: :settings_pricing
    get   "settings/fee-invoices",      to: "pricing#fee_invoices",     as: :settings_fee_invoices
    patch "settings/profile",           to: "settings#update_profile",  as: :settings_profile
    patch "settings/password",          to: "settings#update_password", as: :settings_password
    get   "help",                       to: "help#index",               as: :help

    post   "settings/allowlists/ip",         to: "allowlists#create_ip",      as: :settings_add_ip
    delete "settings/allowlists/ip/:id",     to: "allowlists#destroy_ip",     as: :settings_remove_ip
    post   "settings/allowlists/msisdn",     to: "allowlists#create_msisdn",  as: :settings_add_msisdn
    delete "settings/allowlists/msisdn/:id", to: "allowlists#destroy_msisdn", as: :settings_remove_msisdn

    get    "settings/totp/new",              to: "totp#new",           as: :settings_totp_new
    post   "settings/totp",                  to: "totp#create",        as: :settings_totp
    delete "settings/totp",                  to: "totp#destroy",       as: :settings_totp_delete
    get    "settings/totp/recovery-codes",   to: "totp#recovery_codes", as: :settings_totp_recovery_codes

    post   "settings/passkeys/register-challenge", to: "passkeys#register_challenge", as: :settings_passkey_register_challenge
    post   "settings/passkeys",                    to: "passkeys#create",             as: :settings_passkeys
    delete "settings/passkeys/:id",                to: "passkeys#destroy",            as: :settings_remove_passkey
  end

  devise_scope :user do
    post "users/passkey-challenge", to: "users/passkey_sessions#challenge",    as: :users_passkey_challenge
    post "users/passkey-auth",      to: "users/passkey_sessions#authenticate", as: :users_passkey_auth
  end

  # ── Checkout / Payment links (P16) ──────────────────────────────────────────
  scope module: "checkout" do
    get  "payment-links",                    to: "payment_links#index",      as: :payment_links
    get  "payment-links/filter",             to: "payment_links#filter",     as: :filter_payment_links
    get  "payment-links/new",                to: "payment_links#new",        as: :new_payment_link
    post "payment-links",                    to: "payment_links#create"
    get  "payment-links/:id",                to: "payment_links#show",       as: :payment_link
    get  "payment-links/:id/layout",         to: "payment_links#layout",     as: :payment_link_layout
    patch "payment-links/:id/layout",        to: "payment_links#update_layout"
    post "payment-links/:id/deactivate",     to: "payment_links#deactivate", as: :deactivate_payment_link
  end

  # ── Invoices (P13) ───────────────────────────────────────────────────────────
  scope module: "checkout" do
    get   "invoices",              to: "invoices#index",  as: :invoices
    get   "invoices/new",          to: "invoices#new",    as: :new_invoice
    post  "invoices",              to: "invoices#create"
    get   "invoices/:id/edit",     to: "invoices#edit",   as: :edit_invoice
    patch "invoices/:id",          to: "invoices#update"
    get   "invoices/:id",          to: "invoices#show",   as: :invoice
    post  "invoices/:id/issue",    to: "invoices#issue",  as: :issue_invoice
    post  "invoices/:id/void",      to: "invoices#void",      as: :void_invoice
    get   "invoices/:id/duplicate", to: "invoices#duplicate", as: :duplicate_invoice
  end

  # ── Checkout Sessions (P16) ───────────────────────────────────────────────────
  scope module: "checkout" do
    get "checkout-sessions",      to: "checkout_sessions#index", as: :checkout_sessions
    get "checkout-sessions/:id",  to: "checkout_sessions#show",  as: :checkout_session
  end

  # Ops-only SSO configuration CRUD (top-level controller, settings URL namespace)
  resources "settings/sso",
            controller: "sso_configurations",
            only:       %i[new create edit update destroy],
            as:         :settings_sso
end
