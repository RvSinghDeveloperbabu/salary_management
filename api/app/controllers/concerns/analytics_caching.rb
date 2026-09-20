# Caches analytics responses against a data watermark rather than a clock.
#
# Time-based expiry is the wrong tool here. Compensation data changes rarely
# and unpredictably: a five-minute TTL either serves a stale payroll total
# after a raise is recorded, or throws away a perfectly good answer every
# five minutes because nothing happened. Keying on the most recent write
# means the cache is exact — it is invalidated by a change and by nothing
# else.
module AnalyticsCaching
  extend ActiveSupport::Concern

  # docs/architecture.md specifies the watermark as Salary.maximum(:updated_at)
  # alone. That is not sufficient: terminating an employee, moving them
  # between departments or changing their country all move headcount and
  # payroll totals without touching a salary row, so the dashboard would
  # keep serving the old figure until somebody happened to record a raise.
  # Both tables are watermarked.
  WATERMARK_SOURCES = [ Salary, Employee ].freeze

  private

  def cached_analytics(name, **key_parts)
    Rails.cache.fetch(analytics_cache_key(name, **key_parts)) { yield }
  end

  def analytics_cache_key(name, **key_parts)
    [
      "analytics",
      name,
      watermark,
      key_parts.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    ].join("/")
  end

  # Max id as well as max updated_at. updated_at alone misses an insert that
  # lands in the same microsecond as the previous write, and max id alone
  # misses every update. Together they catch both, and both columns are
  # indexed so the pair costs two index lookups.
  #
  # "empty" rather than nil for an empty table: "no salaries yet" is a
  # distinct cache state from "salaries exist", and must not collide.
  def watermark
    WATERMARK_SOURCES.map { |model|
      # Both maxima in one round trip. Two separate .maximum calls would be
      # two queries per table on every request, including cache hits, which
      # is a cost paid to save a cost.
      latest, highest_id = model.pick(Arel.sql("MAX(updated_at)"), Arel.sql("MAX(id)"))

      "#{latest || 'empty'}:#{highest_id || 0}"
    }.join("-")
  end
end
