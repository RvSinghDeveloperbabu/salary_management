module Api
  module V1
    # The endpoints that answer the six questions in docs/requirements.md.
    #
    # CLAUDE.md is explicit that this is the differentiator: a CRUD table is
    # the baseline, and being able to answer "how does the organisation pay
    # people" is the product.
    #
    # Every response is cached against a data watermark rather than a clock.
    # See AnalyticsCaching.
    class AnalyticsController < BaseController
      include AnalyticsCaching

      # Question 1: what do we spend in total, and how does it split?
      def overview
        render json: cached_analytics("overview", **cache_filters) { build_overview }
      end

      # Questions 2 and 6: the median and spread at each level, and how the
      # same level differs between departments.
      def distribution
        group_by = params[:group_by].presence || "department"

        payload = cached_analytics("distribution", group_by: group_by, **cache_filters) do
          build_distribution(group_by)
        end

        render json: payload
      end

      # Question 4: how has total payroll moved over the last 24 months?
      #
      # Converted at a single fixed rate, so the line shows compensation
      # decisions rather than currency movement. See docs/decisions.md 5.
      def payroll_trend
        months = params[:months] || PayrollTimeline::DEFAULT_MONTHS

        payload = cached_analytics("payroll_trend", months: months, **cache_filters) do
          build_payroll_trend(months)
        end

        render json: payload
      end

      # Questions 3 and 5: who is paid outside their band, and who has not
      # had a change in over 18 months.
      def outliers
        render json: cached_analytics("outliers", **cache_filters) { build_outliers }
      end

      private

      def build_overview
        snapshot = CompensationSnapshot.new(filters)
        summary = Stats::Distribution.of(snapshot.amounts)

        {
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

      def build_distribution(group_by)
        snapshot = CompensationSnapshot.new(filters)

        {
          currency: Rates::BASE_CURRENCY,
          as_of: Rates::SNAPSHOT_DATE,
          group_by: group_by,
          groups: snapshot.grouped_amounts(group_by).map do |label, amounts|
            Stats::Distribution.of(amounts).to_h.merge(group: label)
          end
        }
      end

      def build_payroll_trend(months)
        {
          currency: Rates::BASE_CURRENCY,
          as_of: Rates::SNAPSHOT_DATE,
          points: PayrollTimeline.new(months: months, filters: filters).call.map(&:to_h)
        }
      end

      def build_outliers
        findings = BandOutliers.new(filters)

        {
          currency_note: "Amounts are in local currency; bands are defined per country.",
          stale_after_months: BandOutliers::STALE_MONTHS,
          below_band: findings.below_band.map(&:to_h),
          above_band: findings.above_band.map(&:to_h),
          stale: findings.stale.map(&:to_h),
          counts: {
            below_band: findings.below_band.size,
            above_band: findings.above_band.size,
            stale: findings.stale.size
          }
        }
      end

      def filters
        params.permit(:department_id, :job_level_id, :country_code, :status)
      end

      # The filters, as plain symbols, so two requests differing only in
      # filter do not share a cache entry.
      def cache_filters
        filters.to_h.symbolize_keys
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
