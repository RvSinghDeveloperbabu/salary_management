class PayBandResource
  include Alba::Resource

  # Cents, not decimals. The client formats; the wire carries integers, so
  # no float ever represents money (CLAUDE.md non-negotiable 1).
  attributes :id, :country_code, :currency, :min_cents, :mid_cents, :max_cents
end
