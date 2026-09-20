module Api
  module V1
    # Who am I? The SPA calls this on boot to decide between the login page
    # and the dashboard, which is why it is a separate endpoint rather than
    # something folded into the session response.
    class MeController < BaseController
      def show
        render json: { user: UserResource.new(Current.user).to_h }
      end
    end
  end
end
