require "rails_helper"

RSpec.describe "SPA shell" do
  let(:index) { Rails.root.join("public", "index.html") }

  context "when the bundle has been built" do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(SpaController::INDEX).to receive(:exist?).and_return(true)
      allow_any_instance_of(SpaController).to receive(:send_file) do |controller|
        controller.render html: "<!doctype html><html><body>bundle</body></html>".html_safe
      end
    end

    it "serves the shell at the root" do
      get "/"

      expect(response).to have_http_status(:ok)
    end

    # Opening /employees/42 directly, or reloading it, must return the shell
    # so React Router can resolve the path. Without the catch-all only
    # navigation from inside the app works, and every bookmark 404s.
    it "serves the shell for a client-side route" do
      get "/employees/42"

      expect(response).to have_http_status(:ok)
    end

    it "serves the shell for a nested client-side route" do
      get "/outliers"

      expect(response).to have_http_status(:ok)
    end
  end

  # The catch-all is declared last precisely so it cannot swallow API
  # traffic. An unknown /api path returning the HTML shell would look to a
  # client like a successful page load rather than a broken request.
  describe "API routes are never shadowed by the shell" do
    it "still returns JSON 401 for an unauthenticated API request" do
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
    end

    # Rails renders its own debug page for an unrouted path in test, so the
    # assertion is that the request was *not* absorbed by the catch-all —
    # it must not come back 200 with the SPA shell.
    it "does not serve the shell for an unknown API path" do
      get "/api/v1/nonexistent"

      expect(response).to have_http_status(:not_found)
      # The shell always carries React's mount point; Rails' own error page
      # does not. The catch-all returning 200 here would be the failure.
      expect(response.body).not_to include(%(id="root"))
    end
  end

  context "when the bundle has not been built" do
    before { allow(SpaController::INDEX).to receive(:exist?).and_return(false) }

    # Requested via a deep link rather than "/": the static middleware
    # serves a real public/index.html before routing ever happens, so the
    # controller is only reached for paths with no matching file.
    it "explains how to build it rather than returning a bare 404" do
      get "/employees/42"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("npm run build")
    end
  end
end
