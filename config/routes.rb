Rails.application.routes.draw do
  root "traces#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :traces, only: [:index, :show]
  resources :metrics, only: [:index, :show], param: :metric_name,
            constraints: { metric_name: /[^\/]+/ }, format: false

  namespace :api do
    namespace :v1 do
      post "auth/token", to: "auth#token"
      post "telemetry",  to: "telemetry#create"
      post "keys",       to: "keys#create"
    end
  end

  scope "/v1" do
    post "/traces",  to: "api/v1/otlp#create"
    post "/metrics", to: "api/v1/metrics#create"
  end
end
