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
end
