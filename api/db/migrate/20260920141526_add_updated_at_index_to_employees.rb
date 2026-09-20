# Analytics responses are cached against a watermark: the most recent write
# across salaries and employees. Both maxima are read on every analytics
# request, including cache hits, so both need an index or the saving is
# partly given back as a table scan.
#
# salaries.updated_at was indexed when that table was created.
class AddUpdatedAtIndexToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_index :employees, :updated_at
  end
end
