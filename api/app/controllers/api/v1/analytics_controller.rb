module Api
  module V1
    # The endpoints that answer the six questions in docs/requirements.md.
    #
    # CLAUDE.md is explicit that this is the differentiator: a CRUD table is
    # the baseline, and being able to answer "how does the organisation pay
    # people" is the product.
    class AnalyticsController < BaseController
      # Question 1: what do we spend in total, and how does it split?
      def overview
        snapshot = CompensationSnapshot.new(filters)
        summary = Stats::Distribution.of(snapshot.amounts)

        render json: {
          currency: Rates::BASE_CURRENCY,
          as_of: Rates::SNAPSHOT_DATE,
          headcount: snapshot.headcount,
          total_annual_cents: summary.sum,
          salary: summary.to_h,
          splits: {
            department: split_for(snapshot, "department"),
            country: split_for(snapshot, "country"),
            job_level: split_for(snapshot, "job_level")
          }
        }
      end

      # Questions 2 and 6: the median and spread at each level, and how the
      # same level differs between departments.
      def distribution
        group_by = params[:group_by].presence || "department"
        snapshot = CompensationSnapshot.new(filters)

        groups = snapshot.grouped_amounts(group_by).map do |label, amounts|
          Stats::Distribution.of(amounts).to_h.merge(group: label)
        end

        render json: {
          currency: Rates::BASE_CURRENCY,
          as_of: Rates::SNAPSHOT_DATE,
          group_by: group_by,
          groups: groups
        }
      end

      # Question 4: how has total payroll moved over the last 24 months?
      #
      # Converted at a single fixed rate, so the line shows compensation
      # decisions rather than currency movement. See docs/decisions.md 5.
      def payroll_trend
        points = PayrollTimeline.new(
          months: params[:months] || PayrollTimeline::DEFAULT_MONTHS,
          filters: filters
        ).call

        render json: {
          currency: Rates::BASE_CURRENCY,
          as_of: Rates::SNAPSHOT_DATE,
          points: points.map(&:to_h)
        }
      end

      private

      def filters
        params.permit(:department_id, :job_level_id, :country_code, :status)
      end

      # Totals and medians per group. Enough for a bar chart without a
      # second round trip, and it is the same single query either way.
      def split_for(snapshot, group_by)
        snapshot.grouped_amounts(group_by).map do |label, amounts|
          summary = Stats::Distribution.of(amounts)

          {
            group: label,
            headcount: summary.count,
            total_annual_cents: summary.sum,
            median_cents: summary.p50
          }
        end
      end
    end
  end
end
