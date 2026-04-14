Rails.application.routes.draw do
  root "traces#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :traces, only: [:index, :show] do
    member do
      get :preview
      get :summary
    end
  end
  post "/reset", to: "traces#reset"
  resources :metrics, only: [:index, :show], param: :metric_name,
            constraints: { metric_name: /[^\/]+/ }, format: false

  get "/spans/:span_id/logs", to: "spans#logs", as: :span_logs

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
    post "/logs",    to: "api/v1/logs#create"
  end
end
