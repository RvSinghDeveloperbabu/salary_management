# Raised when a request parameter fails an allow-list check — an unknown
# sort key, a bad sort direction, an unrecognised group_by.
#
# Deliberately not an ArgumentError: this is a client mistake that must
# surface as 400, and conflating it with a programming error would either
# hide real bugs or turn them into 400s.
#
# CLAUDE.md non-negotiable 4: Rails quotes values, not identifiers, so an
# allow-list is the only thing between a sort parameter and arbitrary SQL.
class InvalidQueryParameter < StandardError
  attr_reader :parameter, :allowed

  def initialize(parameter:, value:, allowed:)
    @parameter = parameter
    @allowed = allowed

    super("#{value.inspect} is not a permitted value for #{parameter}. " \
          "Permitted: #{allowed.to_a.join(', ')}.")
  end

  def details
    { parameter => [ "must be one of: #{allowed.to_a.join(', ')}" ] }
  end
end
