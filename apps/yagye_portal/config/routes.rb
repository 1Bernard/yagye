Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions" }

  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end

  devise_scope :user do
    get  "users/otp-challenge", to: "users/sessions#otp_challenge", as: :users_otp_challenge
    post "users/otp-challenge", to: "users/sessions#verify_otp",    as: :users_verify_otp
    root "devise/sessions#new"
  end

  get  "up" => "rails/health#show", as: :rails_health_check
  get  "locale", to: "locale#set",         as: :locale
  post "portal/mode", to: "portal/mode#update", as: :portal_mode

  # ── Payments domain ──────────────────────────────────────────────────────
  scope module: "payments" do
    get "payments",       to: "transactions#index", as: :payments
    get "payments/:id",   to: "transactions#show",  as: :payment
    get "disputes",       to: "disputes#index",     as: :disputes
    get "disputes/:id",   to: "disputes#show",      as: :dispute
  end

  # ── Merchants domain (ops — policy-gated) ────────────────────────────────
  scope module: "merchants" do
    get "merchants",      to: "merchants#index",    as: :merchants
    get "merchants/:id",  to: "merchants#show",     as: :merchant
  end

  # ── Compliance domain (ops — policy-gated) ───────────────────────────────
  scope module: "compliance" do
    get "kyb-reviews",      to: "kyb_reviews#index", as: :kyb_reviews
    get "kyb-reviews/:id",  to: "kyb_reviews#show",  as: :kyb_review
  end

  # ── Developers domain ────────────────────────────────────────────────────
  scope module: "developers" do
    get "developers",                  to: "api_keys#index",              as: :developers
    get "developers/deliveries",       to: "webhook_deliveries#index",    as: :developers_deliveries
    get "developers/deliveries/:id",   to: "webhook_deliveries#show",     as: :developers_delivery
  end

  # ── Team domain ──────────────────────────────────────────────────────────
  scope module: "team" do
    get "team",             to: "users#index",   as: :team
    get "team/users",       to: "users#index",   as: :team_users
    get "team/users/:id",   to: "users#show",    as: :team_user
    get "team/roles",       to: "roles#index",   as: :team_roles
  end

  # ── Account domain ───────────────────────────────────────────────────────
  scope module: "account" do
    get "settings",       to: "settings#index",  as: :settings
    get "help",           to: "help#index",       as: :help
  end
end
