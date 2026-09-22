# Serves the React bundle.
#
# ActionDispatch::Static already serves anything that exists in public/, so
# this only ever runs for a path with no matching file — which is exactly
# what a client-side route is. Opening /employees/42 directly, or reloading
# it, has to return the same HTML shell and let React Router resolve the
# rest; without this the deep link 404s and only navigation from inside the
# app works.
#
# Inherits from ActionController::Base rather than ApplicationController so
# it carries no authentication. The shell is public; the data it then asks
# for is not, and every /api endpoint enforces that independently.
class SpaController < ActionController::Base
  INDEX = Rails.root.join("public", "index.html")

  def index
    if INDEX.exist?
      send_file INDEX, type: "text/html", disposition: "inline"
    else
      # In development the bundle is served by Vite on :5173 and is not
      # built into public/. Saying so beats a bare 404.
      render plain: <<~MESSAGE, status: :not_found
        No frontend bundle found at public/index.html.

        In development, use the Vite dev server on http://localhost:5173.
        To serve the built bundle from Rails instead, run:

            docker compose run --rm web npm run build
      MESSAGE
    end
  end
end
