require "rails_helper"

RSpec.describe "Api::V1::Me" do
  let(:password) { "compensation2026" }
  let!(:user) { create(:user, email_address: "hr@example.com", password: password) }

  def json = JSON.parse(response.body)

  def sign_in
    post "/api/v1/session", params: { email_address: "hr@example.com", password: password }
  end

  describe "GET /api/v1/me" do
    it "returns the signed-in user" do
      sign_in
      get "/api/v1/me"

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "email_address")).to eq("hr@example.com")
      expect(json.dig("user", "id")).to eq(user.id)
    end

    # CLAUDE.md testing rules: unauthenticated request -> 401.
    it "returns 401 when not signed in" do
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("unauthenticated")
    end

    it "returns 401 when the session record has been destroyed" do
      sign_in
      Session.delete_all

      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a forged session cookie" do
      sign_in
      # A value not signed by the application's secret.
      cookies[:session_id] = "999999"

      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end

    it "never exposes the password digest" do
      sign_in
      get "/api/v1/me"

      expect(response.body).not_to include("password_digest")
    end
  end
end
