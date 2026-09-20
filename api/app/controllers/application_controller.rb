class ApplicationController < ActionController::API
  # ActionController::API omits cookies, since most APIs authenticate with a
  # bearer token. This one uses a signed, http-only session cookie: the
  # client is a same-origin SPA (docs/decisions.md 6), and a cookie no
  # script can read is a better place for a credential than anywhere
  # JavaScript can reach.
  #
  # The CSRF exposure that normally comes with cookie auth is handled by
  # SameSite=Lax on the cookie itself, which stops it being sent on
  # cross-site state-changing requests. See Authentication#start_new_session_for.
  include ActionController::Cookies

  include Authentication
end
