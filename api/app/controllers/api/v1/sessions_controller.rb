module Api
  module V1
    class SessionsController < BaseController
      allow_unauthenticated_access only: %i[create]

      # Brute-force protection. The generated controller redirects on
      # breach; an API returns 429 with the same envelope as every other
      # error. Salary data justifies the ceiling being low.
      rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
        render json: {
          error: {
            code: "rate_limited",
            message: "Too many sign-in attempts. Try again shortly."
          }
        }, status: :too_many_requests
      }

      def create
        user = User.authenticate_by(
          email_address: params[:email_address].to_s,
          password: params[:password].to_s
        )

        # One message for both a wrong address and a wrong password. Saying
        # which was wrong tells an attacker whether an address is a real
        # user of a compensation system.
        if user.nil?
          return render_error(
            code: "invalid_credentials",
            message: "Incorrect email address or password.",
            status: :unauthorized
          )
        end

        start_new_session_for(user)

        render json: { user: UserResource.new(user).to_h }, status: :created
      end

      def destroy
        terminate_session

        head :no_content
      end
    end
  end
end
