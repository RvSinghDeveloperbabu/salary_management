# Signs in through the real endpoint rather than stubbing the concern, so
# request specs exercise the actual cookie round trip.
module AuthenticationHelpers
  def sign_in(user = nil)
    user ||= create(:user, password: "compensation2026", password_confirmation: "compensation2026")

    post "/api/v1/session",
      params: { email_address: user.email_address, password: "compensation2026" }

    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
