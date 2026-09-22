Rails.application.routes.draw do
  # Everything the SPA talks to is versioned. The version is in the path
  # rather than a header so a URL pasted into a terminal is complete.
  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :me, only: %i[show], controller: :me
      resource :reference, only: %i[show], controller: :reference

      # Flat rather than a resource: these are questions, not records.
      get "analytics/overview", to: "analytics#overview"
      get "analytics/distribution", to: "analytics#distribution"
      get "analytics/payroll_trend", to: "analytics#payroll_trend"
      get "analytics/outliers", to: "analytics#outliers"

      resources :employees, only: %i[index show create update] do
        # Nested, because a salary has no meaning apart from its employee
        # and nothing lists or edits salaries directly. Append-only, so
        # create is the entire interface.
        resources :salaries, only: %i[create]
      end
    end
  end

  # Liveness probe. Returns 200 if the app boots, 500 otherwise.
  get "up" => "rails/health#show", as: :rails_health_check

  # The SPA. Declared last so it can never shadow an API route: an unknown
  # /api path must return a JSON 404, not the HTML shell, or a broken
  # request looks to the client like a successful page load.
  root to: "spa#index"
  get "*path", to: "spa#index", constraints: ->(request) {
    !request.path.start_with?("/api/") && !request.xhr?
  }
end
