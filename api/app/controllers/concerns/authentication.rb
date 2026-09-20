# Session authentication, adapted from `bin/rails generate authentication`
# for an API.
#
# The generated version redirects to a login page on failure, which an API
# client cannot follow. Everything here is the generated logic with the
# browser assumptions replaced: 401 with a JSON body instead of a redirect,
# and no return_to handling, because the SPA owns navigation.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session.present?
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    return if cookies.signed[:session_id].blank?

    Session.find_by(id: cookies.signed[:session_id])
  end

  # Salary data is among the most sensitive an organisation holds. An
  # unauthenticated request gets 401 and nothing else — no hint about
  # whether the resource exists.
  def request_authentication
    render json: {
      error: {
        code: "unauthenticated",
        message: "You must be signed in to access this resource."
      }
    }, status: :unauthorized
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip
    ).tap do |session|
      Current.session = session

      # httponly so no script can read it, and SameSite=Lax so it is not
      # sent on cross-site requests. The SPA is served same-origin
      # (docs/decisions.md 6), so Lax is sufficient and Strict would break
      # nothing but buys nothing either.
      cookies.signed.permanent[:session_id] = {
        value: session.id,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
    end
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
    Current.session = nil
  end
end
