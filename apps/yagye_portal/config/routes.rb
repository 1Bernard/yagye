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

  get "up" => "rails/health#show", as: :rails_health_check

  # Stub routes so sidebar nav helpers resolve
  get "payments", to: "payments#index", as: :payments
  get "disputes",   to: "application#not_implemented", as: :disputes
  get "merchants",  to: "application#not_implemented", as: :merchants
  get "kyb-reviews",  to: "application#not_implemented", as: :kyb_reviews
  get "api-keys",   to: "application#not_implemented", as: :api_keys
  get "settings",   to: "application#not_implemented", as: :settings
  get "help",       to: "application#not_implemented", as: :help
end
