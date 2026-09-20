require "rails_helper"

RSpec.describe "Api::V1::Sessions" do
  let(:password) { "compensation2026" }
  let!(:user) { create(:user, email_address: "hr@example.com", password: password) }

  def json = JSON.parse(response.body)

  describe "POST /api/v1/session" do
    it "signs in with correct credentials" do
      post "/api/v1/session", params: { email_address: "hr@example.com", password: password }

      expect(response).to have_http_status(:created)
      expect(json.dig("user", "email_address")).to eq("hr@example.com")
    end

    it "sets an http-only session cookie" do
      post "/api/v1/session", params: { email_address: "hr@example.com", password: password }

      # Rack 3 emits these lowercase, so match without regard to case.
      cookie = Array(response.headers["Set-Cookie"]).join("\n")
      expect(cookie).to include("session_id")
      expect(cookie).to match(/httponly/i)
      expect(cookie).to match(/samesite=lax/i)
    end

    it "creates a session record carrying the request metadata" do
      expect {
        post "/api/v1/session",
          params: { email_address: "hr@example.com", password: password },
          headers: { "User-Agent" => "RSpec" }
      }.to change(Session, :count).by(1)

      expect(Session.last.user).to eq(user)
      expect(Session.last.user_agent).to eq("RSpec")
    end

    it "is case insensitive about the email address" do
      post "/api/v1/session", params: { email_address: "HR@Example.COM", password: password }

      expect(response).to have_http_status(:created)
    end

    it "rejects a wrong password with 401" do
      post "/api/v1/session", params: { email_address: "hr@example.com", password: "wrong-password" }

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_credentials")
    end

    it "creates no session on a failed attempt" do
      expect {
        post "/api/v1/session", params: { email_address: "hr@example.com", password: "wrong" }
      }.not_to change(Session, :count)
    end

    # Distinguishing the two would confirm to an attacker that an address
    # belongs to a real user of a compensation system.
    it "gives the same response for an unknown address as for a wrong password" do
      post "/api/v1/session", params: { email_address: "nobody@example.com", password: password }
      unknown_address = [ response.status, json ]

      post "/api/v1/session", params: { email_address: "hr@example.com", password: "wrong" }
      wrong_password = [ response.status, json ]

      expect(unknown_address).to eq(wrong_password)
    end

    it "handles missing parameters without raising" do
      post "/api/v1/session", params: {}

      expect(response).to have_http_status(:unauthorized)
    end

    it "never returns the password digest" do
      post "/api/v1/session", params: { email_address: "hr@example.com", password: password }

      expect(response.body).not_to include("password_digest")
      expect(response.body).not_to include(user.password_digest)
    end
  end

  describe "DELETE /api/v1/session" do
    before do
      post "/api/v1/session", params: { email_address: "hr@example.com", password: password }
    end

    it "signs out" do
      delete "/api/v1/session"

      expect(response).to have_http_status(:no_content)
    end

    it "destroys the session record, so the cookie cannot be replayed" do
      expect { delete "/api/v1/session" }.to change(Session, :count).by(-1)
    end

    it "leaves protected endpoints inaccessible afterwards" do
      delete "/api/v1/session"
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end

    it "requires authentication to sign out" do
      delete "/api/v1/session"
      delete "/api/v1/session"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "rate limiting" do
    # This only proves anything because config/environments/test.rb uses a
    # real cache store. Rails 8 captures the rate-limit store when the class
    # is defined, so swapping Rails.cache inside the example is too late.
    it "blocks repeated failed sign-in attempts with 429" do
      11.times do
        post "/api/v1/session", params: { email_address: "hr@example.com", password: "wrong" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(json.dig("error", "code")).to eq("rate_limited")
    end
  end
end
