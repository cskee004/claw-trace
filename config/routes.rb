Rails.application.routes.draw do
  root "traces#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :traces, only: [:index, :show] do
    collection { post :seed }
  end

  namespace :api do
    namespace :v1 do
      post "auth/token", to: "auth#token"
      post "telemetry",  to: "telemetry#create"
      post "keys",       to: "keys#create"
    end
  end
end
