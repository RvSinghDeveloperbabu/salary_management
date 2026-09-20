module Api
  module V1
    # The only HTTP route into the salaries table. It does no work itself:
    # the three writes a raise entails have to happen atomically, and that
    # belongs in a service, not spread across a controller action.
    class SalariesController < BaseController
      def create
        employee = Employee.find(params[:employee_id])

        result = Salaries::RecordChange.new(
          employee: employee,
          amount_cents: salary_params[:amount_cents],
          currency: salary_params[:currency],
          effective_from: salary_params[:effective_from],
          change_reason: salary_params[:change_reason],
          recorded_by: Current.user
        ).call

        render json: {
          salary: SalaryResource.new(result.salary, params: { rates: Rates.table }).to_h,
          previous_salary_id: result.previous&.id
        }, status: :created
      end

      private

      def salary_params
        params.require(:salary).permit(:amount_cents, :currency, :effective_from, :change_reason)
      end
    end
  end
end
