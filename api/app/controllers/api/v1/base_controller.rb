module Api
  module V1
    # Every API controller inherits from this. It exists to make error
    # responses uniform: a client should never have to guess the shape of a
    # failure, and a failure should never leak a stack trace or a SQL
    # fragment to a browser holding salary data.
    #
    #   { "error": { "code": ..., "message": ..., "details": { ... } } }
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
      rescue_from ActionController::ParameterMissing, with: :bad_request
      rescue_from InvalidQueryParameter, with: :invalid_parameter
      rescue_from Salaries::RecordChange::Error, with: :unprocessable_service_error

      private

      def render_error(code:, message:, status:, details: nil)
        payload = { code: code, message: message }
        payload[:details] = details if details.present?

        render json: { error: payload }, status: status
      end

      def not_found(exception)
        render_error(
          code: "not_found",
          message: exception.model ? "#{exception.model} not found" : "Not found",
          status: :not_found
        )
      end

      # Validation failures carry per-attribute detail, because the SPA
      # renders them next to the field that caused them.
      def unprocessable(exception)
        render_error(
          code: "validation_failed",
          message: exception.record.errors.full_messages.to_sentence,
          status: :unprocessable_content,
          details: exception.record.errors.to_hash
        )
      end

      def bad_request(exception)
        render_error(
          code: "bad_request",
          message: exception.message,
          status: :bad_request
        )
      end

      # 400 rather than 422: an unknown sort key is a malformed request, not
      # a well-formed one that failed a business rule. CLAUDE.md requires
      # this to be rejected rather than passed to the database.
      def invalid_parameter(exception)
        render_error(
          code: "invalid_parameter",
          message: exception.message,
          status: :bad_request,
          details: exception.details
        )
      end

      def unprocessable_service_error(exception)
        render_error(
          code: "unprocessable",
          message: exception.message,
          status: :unprocessable_content
        )
      end
    end
  end
end
