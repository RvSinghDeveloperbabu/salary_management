module Api
  module V1
    # Everything needed to populate every filter in the UI, in one call.
    #
    # Separate endpoints per list would mean four round trips before the
    # directory can render its filter bar. These are small, rarely-changing
    # lists; sending them together is strictly cheaper.
    class ReferenceController < BaseController
      def show
        render json: {
          departments: DepartmentResource.new(Department.alphabetical).to_h,
          job_levels: JobLevelResource.new(JobLevel.in_rank_order).to_h,
          countries: countries,
          currencies: Rates.table.keys.sort,
          statuses: Employee::STATUSES,
          employment_types: Employee::EMPLOYMENT_TYPES,
          change_reasons: Salary::CHANGE_REASONS,
          sortable: EmployeeSearch::SORTABLE.keys
        }
      end

      private

      # Derived from the employees actually on file rather than a hard-coded
      # list, so the filter never offers a country with nobody in it.
      def countries
        Employee.distinct.order(:country_code).pluck(:country_code)
      end
    end
  end
end
