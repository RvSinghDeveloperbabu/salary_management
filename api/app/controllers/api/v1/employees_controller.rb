module Api
  module V1
    class EmployeesController < BaseController
      # Thin by design (CLAUDE.md "Code structure"): authenticate, permit
      # params, call one object, render. The filtering and the sort
      # allow-list live in EmployeeSearch, not here.
      def index
        result = EmployeeSearch.new(search_params).call

        render json: {
          employees: EmployeeResource.new(result.records, params: { rates: rates }).to_h,
          pagination: {
            page: result.page,
            per_page: result.per_page,
            total_count: result.total_count,
            total_pages: result.total_pages
          }
        }
      end

      def show
        employee = Employee
          .preload(:department, :manager, :current_salary, :salaries, job_level: :pay_bands)
          .find(params[:id])

        render json: {
          employee: EmployeeDetailResource.new(employee, params: { rates: rates }).to_h
        }
      end

      def create
        employee = Employee.new(employee_params)
        employee.save!

        AuditEvent.create!(
          actor_id: Current.user&.id,
          subject: employee,
          action: "employee_created",
          metadata: { employee_code: employee.employee_code }
        )

        render json: { employee: EmployeeDetailResource.new(employee, params: { rates: rates }).to_h },
          status: :created
      end

      def update
        employee = Employee.find(params[:id])
        employee.assign_attributes(employee_params)
        changed = employee.changed
        employee.save!

        AuditEvent.create!(
          actor_id: Current.user&.id,
          subject: employee,
          action: "employee_updated",
          metadata: { changed: changed }
        )

        render json: { employee: EmployeeDetailResource.new(employee, params: { rates: rates }).to_h }
      end

      private

      def search_params
        params.permit(:q, :department_id, :job_level_id, :country_code, :status,
                      :employment_type, :sort, :direction, :page, :per_page)
      end

      # employee_code and current_salary_id are deliberately absent.
      #
      # employee_code is the identifier other systems quote, so letting a
      # request reassign it would silently repoint every external reference.
      # current_salary_id is maintained inside Salaries::RecordChange's
      # transaction; setting it directly would let the denormalised pointer
      # disagree with the salary history, and every analytics figure is
      # derived from one or the other.
      #
      # Pay is changed through POST /employees/:id/salaries, never here.
      def employee_params
        params.require(:employee).permit(
          :first_name, :last_name, :email, :country_code,
          :department_id, :job_level_id, :manager_id,
          :employment_type, :status, :hired_on, :terminated_on
        )
      end

      # One query per request, shared by every row rather than looked up per
      # employee (CLAUDE.md non-negotiable 5).
      def rates
        @rates ||= Rates.table
      end
    end
  end
end
