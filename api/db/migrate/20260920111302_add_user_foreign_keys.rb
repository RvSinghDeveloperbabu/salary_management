# salaries.recorded_by_id and audit_events.actor_id were created as bare
# bigints because the users table did not exist yet. It does now, so the
# references become real.
#
# Both stay nullable: seeded history has no human author, and an audit event
# must survive the deletion of the user who caused it — on_delete: :nullify
# rather than :cascade, because destroying the trail is the opposite of
# what it is for.
class AddUserForeignKeys < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :salaries, :users, column: :recorded_by_id, on_delete: :nullify
    add_foreign_key :audit_events, :users, column: :actor_id, on_delete: :nullify
  end
end
