Rails.application.routes.draw do
  root "traces#index"

  get "up" => "rails/health#show", as: :rails_health_check

  get "/dashboard", to: "dashboard#index", as: :dashboard
  get "/dashboard/error_rate_chart",    to: "dashboard#error_rate_chart",    as: :error_rate_chart_dashboard_index
  get "/dashboard/traces_volume_chart", to: "dashboard#traces_volume_chart", as: :traces_volume_chart_dashboard_index

  resources :agents, only: [:index, :show], param: :agent_id,
            constraints: { agent_id: /[^\/]+/ }, format: false do
    member do
      post   :set_budget
      delete :delete_budget
    end
  end

  resources :logs, only: [:index]

  resource :settings, only: [:show, :update] do
    post :prune_logs,         on: :member
    post :prune_traces,       on: :member
    post :delete_all_traces,  on: :member
    post :prune_metrics,      on: :member
    post :delete_all_metrics, on: :member
    post :delete_all_logs,    on: :member
  end

  resources :traces, only: [:index, :show] do
    member do
      get :preview
      get :summary
      get :waterfall
      get :span_chart
      get :tool_calls_chart
      get :logs
    end
  end
  post "/reset", to: "traces#reset"
  resources :metrics, only: [:index, :show], param: :metric_name,
            constraints: { metric_name: /[^\/]+/ }, format: false do
    collection do
      get :tool_calls_chart
    end
    member do
      get :chart
    end
  end

  scope "/v1" do
    post "/traces",  to: "api/v1/otlp#create"
    post "/metrics", to: "api/v1/metrics#create"
    post "/logs",    to: "api/v1/logs#create"
  end
end
