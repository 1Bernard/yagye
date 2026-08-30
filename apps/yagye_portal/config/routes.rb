Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions:  "users/sessions",
    passwords: "users/passwords"
  }

  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end

  devise_scope :user do
    get  "users/otp-challenge", to: "users/sessions#otp_challenge", as: :users_otp_challenge
    post "users/otp-challenge", to: "users/sessions#verify_otp",    as: :users_verify_otp
    root "users/sessions#new"
  end

  get  "up" => "rails/health#show", as: :rails_health_check
  get  "locale", to: "locale#set",         as: :locale
  post "portal/mode", to: "portal/mode#update", as: :portal_mode

  # ── Payments domain ──────────────────────────────────────────────────────
  scope module: "payments" do
    get "payments",       to: "transactions#index", as: :payments
    get "payments/:id",   to: "transactions#show",  as: :payment
    get   "disputes",       to: "disputes#index",     as: :disputes
    get   "disputes/:id",   to: "disputes#show",      as: :dispute
    patch "disputes/:id",   to: "disputes#update"
  end

  # ── Merchants domain (ops — policy-gated) ────────────────────────────────
  scope module: "merchants" do
    get "merchants",      to: "merchants#index",    as: :merchants
    get "merchants/:id",  to: "merchants#show",     as: :merchant
  end

  # ── Compliance domain (ops — policy-gated) ───────────────────────────────
  scope module: "compliance" do
    get  "kyb-reviews",               to: "kyb_reviews#index",   as: :kyb_reviews
    get  "kyb-reviews/:id",           to: "kyb_reviews#show",    as: :kyb_review
    post "kyb-reviews/:id/approve",   to: "kyb_reviews#approve", as: :approve_kyb_review
    post "kyb-reviews/:id/reject",    to: "kyb_reviews#reject",  as: :reject_kyb_review

    get  "compliance/approvals",          to: "approvals#index",   as: :compliance_approvals
    post "compliance/approvals/:id/approve", to: "approvals#approve", as: :compliance_approve_approval
    post "compliance/approvals/:id/reject",  to: "approvals#reject",  as: :compliance_reject_approval
  end

  # ── Developers domain ────────────────────────────────────────────────────
  scope module: "developers" do
    get "developers",                  to: "api_keys#index",              as: :developers
    get "developers/deliveries",       to: "webhook_deliveries#index",    as: :developers_deliveries
    get "developers/deliveries/:id",   to: "webhook_deliveries#show",     as: :developers_delivery
  end

  # ── Payments — refund ────────────────────────────────────────────────────
  scope module: "payments" do
    post "payments/:id/refund", to: "transactions#refund", as: :payment_refund
  end

  # ── Developers — write actions ───────────────────────────────────────────
  scope module: "developers" do
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
    get  "team/users/:id",              to: "users#show",       as: :team_user
    post "team/users",                  to: "users#create",     as: :team_invite_user
    post "team/users/:id/suspend",      to: "users#suspend",    as: :suspend_team_user
    post "team/users/:id/roles",        to: "users#assign_role", as: :assign_team_user_role
    get  "team/roles",                  to: "roles#index",      as: :team_roles
  end

  # ── Account domain ───────────────────────────────────────────────────────
  scope module: "account" do
    get   "settings",                   to: "settings#index",           as: :settings
    patch "settings/profile",           to: "settings#update_profile",  as: :settings_profile
    patch "settings/password",          to: "settings#update_password", as: :settings_password
    get   "help",                       to: "help#index",               as: :help

    post   "settings/allowlists/ip",         to: "allowlists#create_ip",      as: :settings_add_ip
    delete "settings/allowlists/ip/:id",     to: "allowlists#destroy_ip",     as: :settings_remove_ip
    post   "settings/allowlists/msisdn",     to: "allowlists#create_msisdn",  as: :settings_add_msisdn
    delete "settings/allowlists/msisdn/:id", to: "allowlists#destroy_msisdn", as: :settings_remove_msisdn
  end
end
