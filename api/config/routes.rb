Rails.application.routes.draw do
  # Everything the SPA talks to is versioned. The version is in the path
  # rather than a header so a URL pasted into a terminal is complete.
  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :me, only: %i[show], controller: :me
    end
  end

  # Liveness probe. Returns 200 if the app boots, 500 otherwise.
  get "up" => "rails/health#show", as: :rails_health_check
end
