Rails.application.routes.draw do
  root "traces#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :traces, only: [:index, :show]

  namespace :api do
    namespace :v1 do
      post "auth/token", to: "auth#token"
      post "telemetry",  to: "telemetry#create"
      post "keys",       to: "keys#create"
    end
  end

  scope "/v1" do
    post "/traces", to: "api/v1/otlp#create"
  end
end
